///|
/// The input was formatted, or validated successfully.
pub let exit_success : Int = 0

///|
/// The input could not be read, or is not valid JSON.
pub let exit_input_error : Int = 1

///|
/// The command line itself was wrong.
pub let exit_usage_error : Int = 2

///|
/// The input was fine, but the AI review could not be produced.
pub let exit_ai_error : Int = 3

///|
/// Everything one run produced: the text destined for each output stream, and
/// the code the process should end with.
pub(all) struct RunResult {
  out : String
  err : String
  code : Int
}

///|
/// A run that stopped early, with `message` on standard error and an empty
/// standard output.
fn failure(message : String, code : Int) -> RunResult {
  { out: "", err: message + "\n", code, }
}

///|
/// The `error:` marker every failure message opens with, in red when colour is
/// on and plain when it is not.
///
/// The argument error is the one message that does not use this: it is built
/// from an argument list that did not parse, so whether `--no-color` was among
/// those arguments is unknown, and the safe answer for an unknown is no colour.
fn error_prefix() -> String {
  red("error:") + " "
}

///|
/// How an input is named: the path it was named by, or the stream it was read
/// from when no file was given.
///
/// A run that reports a failure as it happens has the name at hand; one that
/// summarises at the end has only what it kept, so the name is decided here,
/// once, rather than at each place that needs it.
fn input_label(input : String?) -> String {
  match input {
    Some(path) => path
    None => "<stdin>"
  }
}

///|
/// Read the JSON text, from `--file` when given and from standard input
/// otherwise.
async fn read_input(input : String?) -> Result[String, String] {
  match input {
    Some(path) =>
      match read_file(path) {
        Ok(text) => Ok(text)
        Err(message) => Err("cannot read " + path + ": " + message)
      }
    None =>
      match read_stdin() {
        Ok(text) => Ok(text)
        Err(message) => Err("cannot read standard input: " + message)
      }
  }
}

///|
/// Reject the command lines that do not describe a run, before any input is
/// read.
///
/// Each of them pairs a request that only makes sense for one document with a
/// command line that names more than one, and the answer is to refuse rather
/// than to answer for the first of them and quietly drop the rest.
fn validate_options(options : CliOptions) -> Result[Unit, String] {
  // Each undoes the other, so asking for both is not a pair of changes but a
  // question about which one was meant.
  if options.flatten && options.unflatten {
    return Err(
      "--flatten and --unflatten are inverses, so only one of them can be given",
    )
  }
  // One says the run ends at the first failure and the other says it does not,
  // so asking for both is not two requests but a question about which was meant.
  if options.fail_fast && options.continue_on_error {
    return Err(
      "--fail-fast stops at the first failure and --continue-on-error carries on past it, so the two cannot be given together",
    )
  }
  // Each of the three answers what the document should hold, so two of them is
  // not two rewrites but a question about which shape was wanted. Unlike the
  // removals and reshapings, these do not compose: --select drops what
  // --sort-by would have sorted and --sort-by reorders what --unique would have
  // deduplicated against, so there is no order to put them in that would make
  // asking for two of them mean anything in particular.
  let transforms : Array[String] = []
  if options.select != None {
    transforms.push("--select")
  }
  if options.sort_by != None {
    transforms.push("--sort-by")
  }
  if options.unique != None {
    transforms.push("--unique")
  }
  if transforms.length() > 1 {
    return Err(
      transforms.join(" and ") +
      " each rewrite the document, so at most one of them can be given",
    )
  }
  // The root name of a generated type is written into the type, so it has to be
  // a name MoonBit declares types under. Whether a name is one is a question
  // about the language rather than about the document, which is why the answer
  // comes from `emit.mbt` and not from here; what is decided here is that a name
  // that cannot be written into a type is a mistake in the command line rather
  // than a document that cannot be emitted.
  match options.emit_moonbit {
    Some(name) =>
      match type_name_problem(name) {
        Some(reason) =>
          return Err(
            "--emit-moonbit takes the name of the root type, and " + reason,
          )
        None => ()
      }
    None => ()
  }
  // Each of these replaces the document with an answer of its own, and no run
  // asks for two of them: a generated type is not a list of paths, and neither
  // is a review of the document. `--keys-only` is among them because it is the
  // other form of `--paths` everywhere else the pair is read.
  if options.emit_moonbit != None {
    let replaced : String? = if options.ai {
      Some("--ai")
    } else if options.json_out != None {
      Some("--json-out")
    } else if options.paths {
      Some("--paths")
    } else if options.keys_only {
      Some("--keys-only")
    } else {
      None
    }
    match replaced {
      Some(other) =>
        return Err(
          other +
          " and --emit-moonbit each replace the document with an answer of their own, so only one of them can be given",
        )
      None => ()
    }
  }
  // The dependency tree is a reading of a module manifest, and a statistics
  // file is a reading of a JSON document; the two questions have nothing to do
  // with each other, and a run that asks both is answered by neither.
  if options.moon_deps && options.json_out != None {
    return Err(
      "--json-out describes a JSON document, and --moon-deps reads a module manifest: the two cannot be combined",
    )
  }
  if options.moon_deps && options.jsonl {
    return Err(
      "--moon-deps reads one module manifest, and --jsonl reads many documents: the two cannot be combined",
    )
  }
  if options.files.length() > 1 && options.json_out != None {
    return Err(
      "--json-out describes a single document, but " +
      options.files.length().to_string() +
      " files were given",
    )
  }
  if options.jsonl {
    // Each of these asks about a document as a whole: a statistics file to
    // write, a review to ask for, or a summary of the structure to print. A
    // JSON Lines input is many documents, and none of those answers survives
    // being repeated once per record with nothing to say which record it
    // belongs to.
    let refused = if options.json_out != None {
      Some("--json-out")
    } else if options.ai {
      Some("--ai")
    } else if options.stats {
      Some("--stats")
    } else if options.paths {
      Some("--paths")
    } else if options.keys_only {
      Some("--keys-only")
    } else if options.emit_moonbit != None {
      Some("--emit-moonbit")
    } else {
      None
    }
    match refused {
      Some(option) =>
        return Err(
          option +
          " describes a single document, and --jsonl reads many: the two cannot be combined",
        )
      None => ()
    }
  }
  Ok(())
}

///|
/// The rewrite the command line asked for, if it asked for one.
///
/// At most one of the three can be set — `validate_options` refuses the rest —
/// so this is a choice rather than a sequence, and the option carries its own
/// argument: the field list, the path to sort by, or the path to compare. The
/// `None` that comes back is a run that left the document as it found it.
fn transform_document(
  options : CliOptions,
  json : @pjson.Json,
) -> Result[@pjson.Json, String] {
  match (options.select, options.sort_by, options.unique) {
    (Some(fields), _, _) => select(json, split_fields(fields))
    (_, Some(path), _) => sort_by(json, path)
    // Deduplicating is the one rewrite that compares values against each other,
    // and what it compares is the item as the run would print it — so the
    // tidying the run asked for is applied first. With --sort-keys, two objects
    // whose members were written in different orders are one item; with
    // --trim-strings so are " a" and "a". Both are asked for again at the end
    // of the pipeline, which is where they always were: --sort-keys is defined
    // as the order the keys are printed in, so it has to be the last thing that
    // happens. Applying one of them twice changes nothing — sorting keys twice
    // is sorting them once — and what changes here is only what "the same item"
    // was taken to mean.
    (_, _, Some(path)) => unique(tidy_document(options, json), Some(path))
    _ => Ok(json)
  }
}

///|
/// The tidying the command line asked for: the whitespace around every string,
/// and the order of every object's keys.
///
/// This is the last thing done to a document before it is printed, and it is
/// also done before `--unique` compares its items, since what that compares is
/// an item as the run would print it. Both steps are idempotent and neither
/// looks at what the other changes, so the second pass a `--unique` run makes
/// cannot tell that it is the second.
fn tidy_document(options : CliOptions, json : @pjson.Json) -> @pjson.Json {
  let trimmed = if options.trim_strings { trim_strings(json) } else { json }
  if options.sort_keys {
    sort_keys(trimmed)
  } else {
    trimmed
  }
}

///|
/// Split the comma-separated list given to `--select` into field names.
///
/// Nothing is trimmed: a space around a name is part of the name, since a JSON
/// key may contain one, and a document whose member is called `"a"` is not a
/// document whose member is called `" a"`. The list is a list of names rather
/// than a list of things to be tidied up.
fn split_fields(list : String) -> Array[String] {
  let fields : Array[String] = []
  for field in list.split(",") {
    fields.push(field.to_owned())
  }
  fields
}

///|
/// Apply the changes that alter the document rather than its layout.
///
/// These happen before anything is printed, so the review, the statistics file
/// and the path list all see the result. The order is: keep and reorder what is
/// wanted, drop what is not, reshape the keys, then tidy the values and the
/// order they are printed in.
///
/// Every one of them rebuilds the containers rather than editing them, so the
/// tree handed in is left as it was found. The order of the last two does not
/// matter: neither looks at what the other changes, one moving keys and the
/// other rewriting values.
///
/// Selecting, sorting and deduplicating come first because they decide what the
/// document holds, and everything after them is about the shape of what is
/// left: `--select name,age --prune-null` drops the null members that survived
/// the selection rather than the ones it was about to drop anyway. They also
/// come first among themselves because only one of them can be asked for.
///
/// Removing comes next because what is gone cannot then be in the way: a
/// document whose null member sits beside a dotted key it would collide with
/// flattens once the member has been dropped, and one that is entirely empty
/// has nothing left to reshape. The two removals are ordered between
/// themselves for the same reason — `{"a":{"b":null}}` is `{}` once the null is
/// gone and the member holding it is left empty, but `{"a":{}}` if the emptying
/// is asked for first.
///
/// Two steps can fail, and only for a document that has no form to be had: the
/// reshaping, and the rewrite, which needs a document of the shape it rewrites.
fn prepare_document(
  options : CliOptions,
  json : @pjson.Json,
) -> Result[@pjson.Json, String] {
  let json = match transform_document(options, json) {
    Ok(json) => json
    Err(message) => return Err(message)
  }
  let pruned = if options.prune_null { prune_null(json) } else { json }
  let json = if options.prune_empty { prune_empty(pruned) } else { pruned }
  let shaped = if options.flatten {
    flatten(json)
  } else if options.unflatten {
    unflatten(json)
  } else {
    Ok(json)
  }
  match shaped {
    Err(message) => Err(message)
    Ok(shaped) => Ok(tidy_document(options, shaped))
  }
}

///|
/// The word for the change a command line asked of the document.
///
/// Only read when that change failed, and then only for the sentence that says
/// so: `cannot be flattened` names what was refused, where `conflicting keys`
/// on its own would leave the reader guessing what it was about to do. The
/// rewrites are named the same way, in the same sentence: `cannot be sorted`
/// says which of the run's requests the document could not answer, and the line
/// under it says why.
fn shape_verb(options : CliOptions) -> String {
  if options.select != None {
    "selected from"
  } else if options.sort_by != None {
    "sorted"
  } else if options.unique != None {
    "deduplicated"
  } else if options.flatten {
    "flattened"
  } else {
    "unflattened"
  }
}

///|
/// The report for a document the requested reshaping cannot be done to.
fn shape_failure(
  options : CliOptions,
  source : String,
  message : String,
) -> RunResult {
  failure(
    error_prefix() +
    source +
    " cannot be " +
    shape_verb(options) +
    "\n" +
    message,
    exit_input_error,
  )
}

///|
/// Render a document in the layout the options ask for.
///
/// `--compact` wants a document with no line breaks in it at all, which is what
/// `--indent` exists to place, so the width is simply not consulted.
fn format_document(options : CliOptions, json : @pjson.Json) -> String {
  if options.compact {
    format_compact(json)
  } else {
    format(json, options.indent)
  }
}

///|
/// Run the tool over `args` and collect everything it produced.
///
/// Several `--file` arguments mean several documents, each handled by
/// `run_document`. They are read `max_parallel_inputs` at a time and answered in
/// the order they were named: a file that fails is reported on standard error
/// and the ones after it are still processed, so one bad input does not hide the
/// state of the rest. The run ends with the first non-zero code any of them
/// produced — the earliest failure is the one worth naming, and the other
/// failures are already on standard error beside it.
///
/// `--fail-fast` gives up that reading for the opposite one and stops at the
/// first input that fails, and `--continue-on-error` keeps it and adds the
/// roll-call at the end. The default is neither: every input is read and every
/// failure is reported as it happens, which is what the two flags are each half
/// of, one way round or the other.
pub async fn run(
  args : Array[String],
  analyze~ : async (String, String, String, String) -> Result[String, String],
) -> RunResult {
  let options = match CliOptions::parse(args) {
    Ok(options) => options
    Err(message) =>
      return failure(
        "error: " +
        message +
        "\nrun 'moonjson-toolkit --help' to see the available options",
        exit_usage_error,
      )
  }
  // Colour is settled here, once everything that decides it is known: it takes
  // a terminal and an absence of `--no-color`. The argument error above is
  // deliberately left out of it — an argument list that failed to parse is
  // exactly the one whose `--no-color` cannot be read, so the only safe answer
  // is no colour, which is what the default already is.
  set_color_enabled(!options.no_color && is_tty())
  // `--help` and `--version` both answer without reading any input. When both
  // are asked for, the usage text wins: it is the longer answer and the one
  // that tells you the other flag exists.
  if options.help {
    return { out: usage() + "\n", err: "", code: exit_success, }
  }
  if options.version {
    return { out: version_line() + "\n", err: "", code: exit_success, }
  }
  // Checked before any input is read, so a command line that names several
  // documents and then asks a question about one of them costs nothing to
  // answer.
  match validate_options(options) {
    Ok(_) => ()
    Err(message) =>
      return failure(
        error_prefix() +
        message +
        "\nrun 'moonjson-toolkit --help' to see the available options",
        exit_usage_error,
      )
  }
  let inputs : Array[String?] = if options.files.length() == 0 {
    // No file named is not no input: standard input is the document.
    [None]
  } else {
    options.files.map(fn(path) { Some(path) })
  }
  // Every input is read and handled before any of it is printed, so the
  // printing below is only ever a walk over the answers in the order they were
  // asked for.
  let outcomes = run_batch(options, inputs, analyze)
  // A heading is only worth printing when there is more than one document to
  // tell apart, which is why a single file reads exactly as it always has.
  let many = inputs.length() > 1
  let out = StringBuilder()
  let err = StringBuilder()
  let mut code = exit_success
  let mut passed = 0
  // The inputs that failed, in the order they were read, each with what it
  // failed with. Every run keeps them, and only `--continue-on-error` prints
  // them: a run that stops at the first failure is the one that keeps the
  // fewest, and a run that never fails keeps none.
  let failures : Array[(String, String)] = []
  for outcome in outcomes {
    if many && outcome.out != "" {
      out.write_string("==> " + outcome.source + " <==\n")
    }
    out.write_string(outcome.out)
    err.write_string(outcome.err)
    if outcome.code == exit_success {
      passed = passed + 1
    } else {
      failures.push((outcome.source, outcome.err))
      if code == exit_success {
        code = outcome.code
      }
      // Nothing after the first failure is printed: `--fail-fast` asks for the
      // run to end where the trouble is rather than at the end of the list.
      // The walk stops here rather than trusting the batch to have stopped
      // everything in time — an input behind the failure can have been read
      // before the cancellation reached it, and finishing it is not a reason to
      // print it after the failure that ended the run.
      if options.fail_fast {
        break
      }
    }
  }
  if options.continue_on_error && failures.length() > 0 {
    append_summary(out, passed, failures)
  }
  { out: out.to_string(), err: err.to_string(), code, }
}

///|
/// How many inputs a batch reads at once.
///
/// Four: enough that the wait for one input's bytes to arrive is spent on
/// another input's, and few enough that a run over a long list of files does
/// not hold all of them open at the same time.
let max_parallel_inputs : Int = 4

///|
/// Read and handle every input, at most `max_parallel_inputs` of them at a
/// time, and answer with one outcome per input in the order they were named.
///
/// The work runs concurrently and the answers are collected in order: each task
/// writes into the slot it was given, so the order the inputs finish in — which
/// is not the order they were asked for, and is not the same from one run to
/// the next — never reaches the reader. Nothing is printed here either, for the
/// same reason: a task that printed as it went would put the documents in
/// whatever order the machine happened to finish them in. A slot left empty is
/// an input the run gave up on, which only `--fail-fast` produces.
///
/// The permit is taken before the task is spawned rather than inside it, which
/// is what makes the limit the number of inputs *in flight* rather than the
/// number of tasks that exist: an input with no permit yet is one that has not
/// been started at all. This is the shape `moonbitlang/async` uses for its own
/// `all`, down to the deferred release.
async fn run_batch(
  options : CliOptions,
  inputs : Array[String?],
  analyze : async (String, String, String, String) -> Result[String, String],
) -> Array[InputOutcome] {
  let slots : Array[InputOutcome?] = []
  for _ in inputs {
    slots.push(None)
  }
  let permits = @semaphore.Semaphore(max_parallel_inputs)
  // The tasks that have been started, by the index of the input each is
  // reading. Only `--fail-fast` ever looks at them, and it looks only at the
  // ones behind the input that failed.
  let started : Array[@async.Task[Unit]] = []
  // A failure is noticed by the task that failed and acted on by the loop that
  // starts tasks, so it has to be said somewhere both can see.
  let stopped : @ref.Ref[Bool] = @ref.new(false)
  @async.with_task_group(group => {
    for index, input in inputs {
      permits.acquire()
      if stopped.val {
        // A failure was reported while this input was waiting for a turn. It is
        // not started, and neither is anything behind it.
        permits.release()
        break
      }
      let task : @async.Task[Unit] = group.spawn(() => {
        // Released however this task ends, cancellation included: the permit
        // was taken for the task, not for the work it managed to do.
        defer permits.release()
        let outcome = handle_input(options, input, analyze)
        slots[index] = Some(outcome)
        if options.fail_fast && outcome.code != exit_success {
          stopped.val = true
          // The inputs behind the one that failed are cancelled rather than
          // waited for. The ones in front of it are left alone: they were
          // already under way when the run stopped, and stopping at the first
          // failure means the run has everything up to it to show, not that it
          // throws away what it has already read.
          for later = index + 1; later < started.length(); later = later + 1 {
            started[later].cancel()
          }
        }
      })
      started.push(task)
    }
  })
  // The slots are compacted rather than printed as they are, because a run that
  // stopped early leaves holes in them: an input that was cancelled has nothing
  // to say and is passed over, and what is left keeps the order it was named in.
  let outcomes : Array[InputOutcome] = []
  for slot in slots {
    match slot {
      Some(outcome) => outcomes.push(outcome)
      None => ()
    }
  }
  outcomes
}

///|
/// Everything one input of a batch contributed: what it printed, what it failed
/// with, and the code the run would end with if it were the only input.
priv struct InputOutcome {
  source : String
  out : String
  err : String
  code : Int
}

///|
/// Read one input and handle it, in whichever way the command line asked for.
///
/// An input that cannot be read is answered like one that was read and could
/// not be handled: a message on standard error, nothing on standard output, and
/// the code that goes with it. The two differ only in the message, which is why
/// neither of them is a special case here.
async fn handle_input(
  options : CliOptions,
  input : String?,
  analyze : async (String, String, String, String) -> Result[String, String],
) -> InputOutcome {
  let source = input_label(input)
  let text = match read_input(input) {
    Ok(text) => text
    Err(message) =>
      return {
        source,
        out: "",
        err: error_prefix() + message + "\n",
        code: exit_input_error,
      }
  }
  let result = if options.jsonl {
    run_jsonl(options, source, text)
  } else {
    run_document(options, source, text, analyze)
  }
  { source, out: result.out, err: result.err, code: result.code, }
}

///|
/// The roll-call a `--continue-on-error` run ends with: how many inputs passed,
/// how many failed, and what each failure said.
///
/// A blank line sets it apart from the documents above it, and each failure is
/// named once with its message indented under it, the way a diagnostic underlines
/// the line it is about. The messages are the ones the run already reported as it
/// went: the two streams are read apart from one another, so the summary repeats
/// them where the run ends rather than leaving the reader to pair a report with
/// the input it belongs to.
fn append_summary(
  out : StringBuilder,
  passed : Int,
  failures : Array[(String, String)],
) -> Unit {
  out.write_string(
    "\nSummary: " +
    passed.to_string() +
    " passed, " +
    failures.length().to_string() +
    " failed\n",
  )
  for failure in failures {
    let (source, message) = failure
    out.write_string("  failed: " + source + "\n")
    for line in message.split("\n") {
      let text = line.to_owned()
      if text != "" {
        out.write_string("    " + text + "\n")
      }
    }
  }
}

///|
/// Handle one document, from its text to everything the run prints for it.
///
/// Every step that can fail — parsing, the AI review, writing the statistics
/// file — runs before a single byte for this document reaches `out`, so a
/// failure never leaves a half-written document on standard output. `-v`
/// suppresses only the formatted document itself; `--json-out` and `--ai` still
/// run.
async fn run_document(
  options : CliOptions,
  source : String,
  text : String,
  analyze : async (String, String, String, String) -> Result[String, String],
) -> RunResult {
  // `--moon-deps` asks a question about a module manifest rather than about a
  // document, so it stands in front of the parse below and answers on its own.
  // Under `--ai` it stands aside: a review describes the document, so a run
  // that asks for one is asking about the document after all.
  if options.moon_deps && !options.ai {
    return run_moon_deps(source, text)
  }
  let json = match parse_with_diagnostic(text, options.max_depth) {
    Ok(json) => json
    Err(diagnostic) =>
      return failure(
        error_prefix() + source + " is not valid JSON\n" + diagnostic.render(),
        exit_input_error,
      )
  }
  render_document(options, source, json, analyze)
}

///|
/// Everything one parsed document produces, from the options to the text.
///
/// Split from `run_document` so that a parse failure is the only thing that has
/// to happen before this point: from here on the document is known to be good.
async fn render_document(
  options : CliOptions,
  source : String,
  json : @pjson.Json,
  analyze : async (String, String, String, String) -> Result[String, String],
) -> RunResult {
  let prepared = match prepare_document(options, json) {
    Ok(prepared) => prepared
    Err(message) => return shape_failure(options, source, message)
  }
  let formatted = format_document(options, prepared)
  // The review is asked for before anything is printed, so that a failure here
  // leaves standard output empty rather than trailing a document that the
  // caller may be piping somewhere.
  let review = if options.ai {
    // The three settings the request is made of are settled here rather than
    // inside `analyze`, which is handed nothing but strings: the command line
    // is read by this layer, and the environment is read here too and handed
    // in, so that the resolvers themselves decide only the precedence. They
    // are resolved only under `--ai`, so a run without it neither reads nor
    // needs any of them — a missing key is not an error for a document that
    // was never going to be reviewed.
    let model = resolve_model(options.model, non_empty_env(model_variable))
    let endpoint = resolve_endpoint(
      options.ai_base_url,
      non_empty_env(endpoint_variable),
    )
    let api_key = match
      resolve_api_key(
        non_empty_env(api_key_variable),
        non_empty_env(fallback_api_key_variable),
      ) {
      Ok(key) => key
      Err(message) => return failure("error: " + message, exit_ai_error)
    }
    match analyze(formatted, endpoint, model, api_key) {
      Ok(report) => Some(report)
      Err(message) => return failure("error: " + message, exit_ai_error)
    }
  } else {
    None
  }
  let mut err = ""
  match options.json_out {
    Some(path) =>
      match write_stats_file(path, prepared) {
        Ok(_) => err = "statistics written to " + path + "\n"
        Err(message) =>
          return failure(
            error_prefix() + "cannot write " + path + ": " + message,
            exit_input_error,
          )
      }
    None => ()
  }
  // `--stats` and `--json-out` are two answers to the same question, so asking
  // for both is not an error but a tie, and the file is the more useful of the
  // two: it is the one that can be kept, charted and compared. The summary on
  // standard output is what is given up.
  let show_stats = options.stats && options.json_out == None
  // Nothing below can fail, so this is where standard output starts.
  let out = StringBuilder()
  if options.validate {
    // `-v` replaces the document with a one-line verdict, nothing else.
    out.write_string(source + ": valid JSON\n")
  } else if options.paths || options.keys_only {
    // The two name lists are alternatives to the document rather than additions
    // to it, and `--paths` is the longer of the pair, so it is the one that
    // answers when both are asked for.
    let names = if options.paths {
      collect_paths(prepared)
    } else {
      collect_key_paths(prepared)
    }
    for name in names {
      out.write_string(name)
      out.write_string("\n")
    }
  } else if options.emit_moonbit != None {
    // The type is read off the prepared document rather than off the parsed one,
    // so that the run has one answer to what this document holds: the fields are
    // the members the reader would have seen, in the order they would have been
    // printed in. The generated text carries the newline that ends it, so none
    // is added here.
    match options.emit_moonbit {
      Some(name) => out.write_string(emit_moonbit(prepared, name))
      // Unreachable: the branch above is the same test.
      None => ()
    }
  } else if show_stats {
    // Counted over the prepared document, which is the one the run has been
    // asked to produce and the one the reader is looking at. Sorting and
    // trimming cannot tell the difference — neither moves a value or changes
    // its type — while pruning and flattening can, and a summary that kept
    // counting members the document no longer has would be describing
    // something the reader cannot see. It is also the value `--json-out` is
    // given, so the two reports say the same thing when both are asked for.
    out.write_string(JsonStats::of(prepared).to_text())
    out.write_string("\n")
  } else {
    out.write_string(formatted)
    out.write_string("\n")
  }
  match review {
    Some(report) => {
      out.write_string("\n")
      out.write_string("AI quality report\n")
      out.write_string("-----------------\n")
      out.write_string(report)
      out.write_string("\n")
    }
    None => ()
  }
  { out: out.to_string(), err, code: exit_success, }
}

///|
/// Handle one JSON Lines input: every record is rendered onto a line of its
/// own, and every record that is not valid JSON is reported on standard error.
///
/// A bad record does not stop the run, unless `--fail-fast` asks it to. Each
/// line of the input stands alone by definition, so the ones that can be read
/// are printed whether or not the others could be, and a mistake on the fourth
/// line does not cost the reader the fifth. The code is the first non-zero one
/// any record produced, so a run with a single bad record ends 1 however many
/// good ones followed it.
///
/// `-v` asks for no document output at all, so a run where every record parsed
/// is answered with the one verdict line it prints for a single document, and a
/// run where one did not is answered by that record's report alone.
fn run_jsonl(options : CliOptions, source : String, text : String) -> RunResult {
  let out = StringBuilder()
  let err = StringBuilder()
  let mut code = exit_success
  for record in parse_jsonl_with_depth(text, options.max_depth) {
    match record {
      Ok(json) =>
        match prepare_document(options, json) {
          Ok(prepared) =>
            if !options.validate {
              out.write_string(format_document(options, prepared))
              out.write_string("\n")
            }
          Err(message) => {
            // As with a record that does not parse, one that cannot be reshaped
            // is reported and the rest are still printed, and the run ends 1.
            let report = shape_failure(options, source, message)
            err.write_string(report.err)
            if code == exit_success {
              code = report.code
            }
            if options.fail_fast {
              break
            }
          }
        }
      Err(diagnostic) => {
        err.write_string(
          error_prefix() +
          source +
          " is not valid JSON\n" +
          diagnostic.render() +
          "\n",
        )
        if code == exit_success {
          code = exit_input_error
        }
        if options.fail_fast {
          break
        }
      }
    }
  }
  if options.validate && code == exit_success {
    out.write_string(source + ": valid JSON\n")
  }
  { out: out.to_string(), err: err.to_string(), code, }
}
