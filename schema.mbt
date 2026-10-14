///|
/// Validate the supported JSON Schema Draft 2020-12 subset.
/// Compilation rejects unsupported features before any data is checked.

///|
/// One place where a schema and something else disagree.
///
/// `path` names where the trouble is and `message` says what it is, in a
/// sentence about the value at that path: a report is the two joined with a
/// colon, one error to a line. The message never names the path itself, so the
/// same error reads the same wherever it is found.
pub(all) struct SchemaError {
  path : String
  message : String
}

///|
/// Compile first, then return data violations. Only Ok([]) means a match.
pub fn validate_schema(
  json : @pjson.Json,
  schema : @pjson.Json,
) -> Result[Array[SchemaError], SchemaValidationFailure] {
  match compile_schema(schema) {
    Ok(compiled) =>
      match validate_compiled_schema(json, compiled) {
        Ok(errors) => Ok(errors)
        Err(error) => Err(EvaluationFailed(error))
      }
    Err(problems) => Err(SchemaProblems(problems))
  }
}

///|
/// Validate data against an opaque schema that has passed compilation.
pub fn validate_compiled_schema(
  json : @pjson.Json,
  compiled : CompiledSchema,
) -> Result[Array[SchemaError], SchemaEvaluationError] {
  evaluate_schema_with_limits(
    json, compiled, schema_evaluation_depth_limit, schema_evaluation_visit_limit,
  )
}

///|
/// A schema error as one line: where it is and what it is.
///
/// The root has the empty path, which would leave nothing in front of the
/// colon, so it is named instead: a report is read line by line and a line that
/// starts with a colon says nothing about where it is about.
pub fn render_schema_error(error : SchemaError) -> String {
  (if error.path == "" { "(root)" } else { error.path }) + ": " + error.message
}

///|
/// Every keyword in `schema` that this tool cannot read.
///
/// Read before a document is: what is being checked is that the schema is one
/// this tool knows how to apply, and a schema that is not is answered with the
/// place to fix rather than with a document that was never compared to it.
pub fn schema_problems(schema : @pjson.Json) -> Array[SchemaProblem] {
  precheck_schema(schema, Map([]))
}

///|
/// Check one value against one schema, adding every disagreement to `errors`.
///
/// A keyword says what it is about as much as what it wants: `required` is about
/// an object, `minLength` about a string, `items` about an array. A value of
/// another kind is left alone by it — there is no member that could be missing
/// from a number — and it is `type` that says a number is the wrong kind of value
/// to find here.
fn check_value(
  value : @pjson.Json,
  schema : @pjson.Json,
  path : String,
  errors : Array[SchemaError],
  ctx : SchemaEvaluationContext,
) -> Unit {
  match schema {
    Object(members~) =>
      for entry in members {
        if ctx.failure != None {
          break
        }
        let (keyword, wanted) = entry
        match keyword {
          "$ref" => {
            let id = ctx.compiled.references[pointer_child(
                ctx.schema_pointer,
                "$ref",
              )]
            evaluate_schema_node(
              value,
              ctx.compiled.nodes[id].pointer,
              ctx.instance_pointer,
              path,
              errors,
              ctx,
            )
          }
          "type" => check_type(value, wanted, path, errors)
          "required" => check_required(value, wanted, path, errors)
          "properties" => check_properties(value, wanted, path, errors, ctx)
          "patternProperties" =>
            check_pattern_properties(value, wanted, path, errors, ctx)
          "minProperties" =>
            check_property_count(value, wanted, path, errors, true)
          "maxProperties" =>
            check_property_count(value, wanted, path, errors, false)
          "items" => check_items(value, wanted, members, path, errors, ctx)
          "prefixItems" => check_prefix_items(value, wanted, path, errors, ctx)
          "minItems" => check_array_length(value, wanted, path, errors, true)
          "maxItems" => check_array_length(value, wanted, path, errors, false)
          "uniqueItems" => check_unique_items(value, wanted, path, errors)
          "contains" => check_contains(value, members, path, errors, ctx)
          "enum" => check_enum(value, wanted, path, errors)
          "const" => check_const(value, wanted, path, errors)
          "allOf" | "anyOf" | "oneOf" =>
            check_combination(value, wanted, keyword, path, errors, ctx)
          "not" =>
            match branch_errors(value, ["not"], path, ctx) {
              Ok(violations) =>
                if violations.is_empty() {
                  errors.push({
                    path,
                    message: "it matches the schema forbidden by not",
                  })
                }
              Err(_) => () // The shared context propagates this execution failure.
            }
          "additionalProperties" =>
            check_additional_properties(
              value, wanted, members, path, errors, ctx,
            )
          "minimum" =>
            check_bound(value, wanted, path, errors, InclusiveMinimum)
          "maximum" =>
            check_bound(value, wanted, path, errors, InclusiveMaximum)
          "exclusiveMinimum" =>
            check_bound(value, wanted, path, errors, ExclusiveMinimum)
          "exclusiveMaximum" =>
            check_bound(value, wanted, path, errors, ExclusiveMaximum)
          "multipleOf" => check_multiple_of(value, wanted, path, errors)
          "minLength" => check_length(value, wanted, path, errors, true)
          "maxLength" => check_length(value, wanted, path, errors, false)
          "pattern" => check_pattern(value, wanted, path, errors, ctx)
          _ => ()
        }
      }
    Bool(value=true) => ()
    Bool(value=false) =>
      errors.push({ path, message: "it is rejected by the false schema", })
    // Compilation accepts only objects and booleans.
    _ => ()
  }
}

///|
/// Branch errors belong to that branch until the applicator decides what to
/// retain. The path always refers to the instance being checked.
fn branch_errors(
  value : @pjson.Json,
  schema_tokens : Array[String],
  path : String,
  ctx : SchemaEvaluationContext,
) -> Result[Array[SchemaError], SchemaEvaluationError] {
  let errors = []
  evaluate_schema_child(value, schema_tokens, None, path, errors, ctx)
  match ctx.failure {
    Some(error) => Err(error)
    None => Ok(errors)
  }
}

///|
fn check_const(
  value : @pjson.Json,
  wanted : @pjson.Json,
  path : String,
  errors : Array[SchemaError],
) -> Unit {
  if !same_value(value, wanted) {
    errors.push({
      path,
      message: "it is not the constant value the schema specifies",
    })
  }
}

///|
fn check_combination(
  value : @pjson.Json,
  wanted : @pjson.Json,
  keyword : String,
  path : String,
  errors : Array[SchemaError],
  ctx : SchemaEvaluationContext,
) -> Unit {
  let branches = match wanted {
    Array(items~) => items
    // Compilation rejects nonarrays and empty arrays.
    _ => return
  }
  let mut matches = 0
  for index, _schema in branches {
    let violations = match
      branch_errors(value, [keyword, index.to_string()], path, ctx) {
      Ok(violations) => violations
      Err(_) => return
    }
    if violations.is_empty() {
      matches = matches + 1
    } else if keyword == "allOf" {
      for violation in violations {
        errors.push({
          path: violation.path,
          message: "allOf[" + index.to_string() + "]: " + violation.message,
        })
      }
    }
  }
  if keyword == "anyOf" && matches == 0 {
    errors.push({ path, message: "it does not match any anyOf branch", })
  }
  if keyword == "oneOf" && matches != 1 {
    errors.push({
      path,
      message: "it matches " +
      matches.to_string() +
      " oneOf branches; exactly one is required",
    })
  }
}

///|
/// Names declared explicitly or matched by a pattern in this object are covered,
/// even when their values fail. Other branches and required names do not count.
fn check_additional_properties(
  value : @pjson.Json,
  wanted : @pjson.Json,
  schema_members : Array[(String, @pjson.Json)],
  path : String,
  errors : Array[SchemaError],
  ctx : SchemaEvaluationContext,
) -> Unit {
  let declared = match find_member(schema_members, "properties") {
    Some(Object(members~)) => members
    _ => []
  }
  let patterned = match find_member(schema_members, "patternProperties") {
    Some(Object(members~)) => members
    _ => []
  }
  match value {
    Object(members~) =>
      for (name, held) in members {
        if ctx.failure != None {
          break
        }
        if !declared.any(fn(entry) { entry.0 == name }) &&
          !patterned.any(fn(entry) {
            match_compiled_pattern(
              compiled_schema_pattern(ctx.compiled.patterns, entry.0),
              name,
            )
          }) {
          let here = child_path(path, name)
          match wanted {
            Bool(value=false) => {
              // Count the boolean child as a node visit while preserving the
              // established additional-property diagnostic.
              evaluate_schema_child(
                held,
                ["additionalProperties"],
                Some(name),
                here,
                [],
                ctx,
              )
              if ctx.failure == None {
                errors.push({
                  path: here,
                  message: "additional property is not allowed",
                })
              }
            }
            _ =>
              evaluate_schema_child(
                held,
                ["additionalProperties"],
                Some(name),
                here,
                errors,
                ctx,
              )
          }
        }
      }
    _ => ()
  }
}

///|
fn check_pattern_properties(
  value : @pjson.Json,
  wanted : @pjson.Json,
  path : String,
  errors : Array[SchemaError],
  ctx : SchemaEvaluationContext,
) -> Unit {
  match (value, wanted) {
    (Object(members~), Object(members=rules)) =>
      for (text, _schema) in rules {
        if ctx.failure != None {
          break
        }
        let pattern = compiled_schema_pattern(ctx.compiled.patterns, text)
        for (name, held) in members {
          if ctx.failure != None {
            break
          }
          if match_compiled_pattern(pattern, name) {
            evaluate_schema_child(
              held,
              ["patternProperties", text],
              Some(name),
              child_path(path, name),
              errors,
              ctx,
            )
          }
        }
      }
    _ => ()
  }
}

///|
fn check_property_count(
  value : @pjson.Json,
  wanted : @pjson.Json,
  path : String,
  errors : Array[SchemaError],
  least : Bool,
) -> Unit {
  let limit = match length_argument(wanted) {
    Ok(limit) => limit
    Err(_) => return
  }
  match value {
    Object(members~) => {
      let count = members.length()
      if (least && count < limit) || (!least && count > limit) {
        errors.push({
          path,
          message: "it has " +
          count.to_string() +
          (if count == 1 { " property" } else { " properties" }) +
          (if least {
            ", but the schema requires at least "
          } else {
            ", but the schema allows at most "
          }) +
          limit.to_string(),
        })
      }
    }
    _ => ()
  }
}

///|
/// Whether a value is of the type a name stands for.
fn type_matches(json : @pjson.Json, name : String) -> Bool {
  match name {
    "object" =>
      match json {
        Object(_) => true
        _ => false
      }
    "array" =>
      match json {
        Array(_) => true
        _ => false
      }
    "string" =>
      match json {
        Text(_) => true
        _ => false
      }
    "number" =>
      match json {
        Number(_) => true
        _ => false
      }
    // An integer is a number with nothing after the point rather than a number
    // that is not written as a fraction: `1.0` and `1e3` are both integers, and
    // reading them as doubles to find that out would answer for a numeral too
    // long for a double by rounding it first.
    "integer" =>
      match json {
        Number(raw~) => is_whole_number(raw)
        _ => false
      }
    "boolean" =>
      match json {
        Bool(_) => true
        _ => false
      }
    "null" =>
      match json {
        Null => true
        _ => false
      }
    // Unreachable: `schema_problems` refuses any other name.
    _ => false
  }
}

///|
/// Determine integrality from the normalized mathematical value, including
/// fractional mantissas shifted by positive or negative exponents.
fn is_whole_number(raw : String) -> Bool {
  schema_number(raw).is_integer()
}

///|
/// How a JSON type name reads in a sentence, article and all.
fn type_name(name : String) -> String {
  match name {
    "object" => "an object"
    "array" => "an array"
    "string" => "a string"
    "number" => "a number"
    "integer" => "an integer"
    "boolean" => "a boolean"
    "null" => "null"
    // Unreachable: `schema_problems` refuses any other name.
    other => other
  }
}

///|
/// The names a `type` keyword holds, whether it holds one or a list of them.
fn type_names(wanted : @pjson.Json) -> Array[String] {
  match wanted {
    Text(value~) => [value]
    Array(items~) =>
      items.filter_map(fn(item) {
        match item {
          Text(value~) => Some(value)
          // Unreachable: `schema_problems` refuses the rest.
          _ => None
        }
      })
    // A `type` that is neither is one this tool cannot read, and there is
    // nothing to expect of the value: `schema_problems` is where it is answered.
    _ => []
  }
}

///|
/// Join a list of names into a phrase: `a`, `a or b`, `a, b or c`.
fn join_or(names : Array[String]) -> String {
  match names.length() {
    0 => ""
    1 => names[0]
    _ => {
      let head = names[0:names.length() - 1].join(", ")
      head + " or " + names[names.length() - 1]
    }
  }
}

///|
/// `type`: the value has to be of one of the kinds the schema names.
fn check_type(
  value : @pjson.Json,
  wanted : @pjson.Json,
  path : String,
  errors : Array[SchemaError],
) -> Unit {
  let names = type_names(wanted)
  if names.length() == 0 {
    return
  }
  let mut matched = false
  for name in names {
    if type_matches(value, name) {
      matched = true
    }
  }
  if !matched {
    errors.push({
      path,
      message: "it is " +
      kind_name(value) +
      " where the schema expects " +
      join_or(names.map(type_name)),
    })
  }
}

///|
/// `required`: every name has to be a member of the object.
///
/// The names are checked in the order the schema lists them, so a report reads
/// in that order rather than in the order the object happens to be missing them.
fn check_required(
  value : @pjson.Json,
  wanted : @pjson.Json,
  path : String,
  errors : Array[SchemaError],
) -> Unit {
  let names = match wanted {
    Array(items~) =>
      items.filter_map(fn(item) {
        match item {
          Text(value~) => Some(value)
          // Unreachable: `schema_problems` refuses the rest.
          _ => None
        }
      })
    // Unreachable: `schema_problems` refuses a `required` that is not a list.
    _ => []
  }
  match value {
    Object(members~) =>
      for name in names {
        let mut found = false
        for entry in members {
          if entry.0 == name {
            found = true
          }
        }
        if !found {
          errors.push({
            path,
            message: "required member \"" + name + "\" is missing",
          })
        }
      }
    // A `required` says nothing about a value that has no members, and `type`
    // is the keyword that says the value should not be one.
    _ => ()
  }
}

///|
/// `properties`: every member the schema names is checked against the schema it
/// is given, and a member it does not name is left as it is.
///
/// Members the document does not have are not reported here: a schema that
/// requires them says so with `required`, and one that does not means what it
/// says. The walk follows the schema rather than the document, so a report reads
/// in the order the schema lists what it is about, which is the order its reader
/// reads.
fn check_properties(
  value : @pjson.Json,
  wanted : @pjson.Json,
  path : String,
  errors : Array[SchemaError],
  ctx : SchemaEvaluationContext,
) -> Unit {
  let subschemas = match wanted {
    Object(members~) => members
    // Unreachable: `schema_problems` refuses a `properties` that is not an
    // object.
    _ => []
  }
  let members = match value {
    Object(members~) => members
    // A `properties` says nothing about a value that has no members, and `type`
    // is the keyword that says the value should not be one.
    _ => []
  }
  for entry in subschemas {
    if ctx.failure != None {
      break
    }
    match find_member(members, entry.0) {
      Some(held) =>
        evaluate_schema_child(
          held,
          ["properties", entry.0],
          Some(entry.0),
          child_path(path, entry.0),
          errors,
          ctx,
        )
      None => ()
    }
  }
}

///|
/// Only the suffix after this schema object's prefixItems is checked by items.
/// Declarations in other objects and prefix validation outcomes do not affect it.
fn check_items(
  value : @pjson.Json,
  _wanted : @pjson.Json,
  schema_members : Array[(String, @pjson.Json)],
  path : String,
  errors : Array[SchemaError],
  ctx : SchemaEvaluationContext,
) -> Unit {
  let start = match find_member(schema_members, "prefixItems") {
    Some(Array(items~)) => items.length()
    _ => 0
  }
  match value {
    Array(items~) =>
      for index, item in items {
        if ctx.failure != None {
          break
        }
        if index >= start {
          evaluate_schema_child(
            item,
            ["items"],
            Some(index.to_string()),
            path + "[" + index.to_string() + "]",
            errors,
            ctx,
          )
        }
      }
    _ => ()
  }
}

///|
fn check_prefix_items(
  value : @pjson.Json,
  wanted : @pjson.Json,
  path : String,
  errors : Array[SchemaError],
  ctx : SchemaEvaluationContext,
) -> Unit {
  match (value, wanted) {
    (Array(items~), Array(items=schemas)) =>
      for index in 0..<Int::min(items.length(), schemas.length()) {
        if ctx.failure != None {
          break
        }
        evaluate_schema_child(
          items[index],
          ["prefixItems", index.to_string()],
          Some(index.to_string()),
          path + "[" + index.to_string() + "]",
          errors,
          ctx,
        )
      }
    _ => ()
  }
}

///|
/// Only contains triggers traversal. Bounds belong to this same schema object;
/// all positions count independently, including positions covered by prefixItems.
fn check_contains(
  value : @pjson.Json,
  schema_members : Array[(String, @pjson.Json)],
  path : String,
  errors : Array[SchemaError],
  ctx : SchemaEvaluationContext,
) -> Unit {
  let items = match value {
    Array(items~) => items
    _ => return
  }
  let minimum = match find_member(schema_members, "minContains") {
    None => 1
    Some(wanted) =>
      match length_argument(wanted) {
        Ok(n) => n
        Err(_) => abort("invalid minContains in compiled schema")
      }
  }
  let maximum = match find_member(schema_members, "maxContains") {
    None => None
    Some(wanted) =>
      match length_argument(wanted) {
        Ok(n) => Some(n)
        Err(_) => abort("invalid maxContains in compiled schema")
      }
  }
  let mut count = 0
  for index, item in items {
    let violations = []
    evaluate_schema_child(
      item,
      ["contains"],
      Some(index.to_string()),
      path + "[" + index.to_string() + "]",
      violations,
      ctx,
    )
    // An execution error never becomes a nonmatching item. Do not stop after
    // satisfying the minimum: later items may exhaust the shared budget/cycle.
    if ctx.failure != None {
      return
    }
    if violations.is_empty() {
      count = count + 1
    }
  }
  let prefix = "contains matched " +
    count.to_string() +
    (if count == 1 { " item" } else { " items" })
  if count < minimum {
    errors.push({
      path,
      message: prefix + "; expected at least " + minimum.to_string(),
    })
  }
  match maximum {
    Some(n) =>
      if count > n {
        errors.push({
          path,
          message: prefix + "; expected at most " + n.to_string(),
        })
      }
    None => ()
  }
}

///|
fn check_array_length(
  value : @pjson.Json,
  wanted : @pjson.Json,
  path : String,
  errors : Array[SchemaError],
  least : Bool,
) -> Unit {
  let limit = match length_argument(wanted) {
    Ok(limit) => limit
    // Compilation rejects invalid or unsupported counts.
    Err(_) => return
  }
  match value {
    Array(items~) => {
      let count = items.length()
      if (least && count < limit) || (!least && count > limit) {
        errors.push({
          path,
          message: "it has " +
          count.to_string() +
          (if count == 1 { " item" } else { " items" }) +
          (if least {
            ", but the schema requires at least "
          } else {
            ", but the schema allows at most "
          }) +
          limit.to_string(),
        })
      }
    }
    _ => ()
  }
}

///|
/// Pairwise deep equality requires O(n^2) element comparisons in the worst
/// case. Report only the first equal pair without rewriting any input values.
fn check_unique_items(
  value : @pjson.Json,
  wanted : @pjson.Json,
  path : String,
  errors : Array[SchemaError],
) -> Unit {
  match (value, wanted) {
    (Array(items~), Bool(value=true)) =>
      for first in 0..<items.length() {
        for second in (first + 1)..<items.length() {
          if same_value(items[first], items[second]) {
            errors.push({
              path,
              message: "items at indexes " +
              first.to_string() +
              " and " +
              second.to_string() +
              " are equal, but uniqueItems is true",
            })
            return
          }
        }
      }
    _ => ()
  }
}

///|
/// `enum`: the value has to be one of the values listed.
///
/// The message gives the number of them rather than the values: the list is in
/// the schema the reader has to hand, and a schema naming fifty values would
/// otherwise put all fifty on one line of the report.
fn check_enum(
  value : @pjson.Json,
  wanted : @pjson.Json,
  path : String,
  errors : Array[SchemaError],
) -> Unit {
  let allowed = match wanted {
    Array(items~) => items
    // A keyword this tool cannot read is a fact about the schema, which
    // `schema_problems` answers, and not a document that does not match it: a
    // list of no values would have said every document is wrong.
    _ => return
  }
  let mut found = false
  for allowed_value in allowed {
    if same_value(value, allowed_value) {
      found = true
    }
  }
  if !found {
    errors.push({ path, message: "it is not " + listed(allowed.length()), })
  }
}

///|
/// How a number of listed values reads in a sentence: `the value the schema
/// lists`, `one of the 3 values the schema lists`.
///
/// A list with nothing in it lists no values at all, and a value it holds
/// nothing for is a value the schema cannot accept rather than one it does not
/// know.
fn listed(count : Int) -> String {
  match count {
    0 => "one of the values the schema lists"
    1 => "the value the schema lists"
    _ => "one of the " + count.to_string() + " values the schema lists"
  }
}

///|
priv enum SchemaBound {
  InclusiveMinimum
  InclusiveMaximum
  ExclusiveMinimum
  ExclusiveMaximum
}

///|
/// Bounds use exact decimal comparison, without rounding, overflow or underflow.
fn check_bound(
  value : @pjson.Json,
  wanted : @pjson.Json,
  path : String,
  errors : Array[SchemaError],
  mode : SchemaBound,
) -> Unit {
  let bound = match wanted {
    Number(raw~) => Some(raw)
    // Unreachable: `schema_problems` refuses a bound that is not a number.
    _ => None
  }
  match (value, bound) {
    (Number(raw~), Some(bound)) => {
      let order = schema_number_compare(raw, bound)
      let (violated, prefix) = match mode {
        InclusiveMinimum => (order < 0, "it is less than the minimum ")
        InclusiveMaximum => (order > 0, "it is more than the maximum ")
        ExclusiveMinimum =>
          (order <= 0, "it is not greater than the exclusive minimum ")
        ExclusiveMaximum =>
          (order >= 0, "it is not less than the exclusive maximum ")
      }
      if violated {
        errors.push({ path, message: prefix + raw_of(wanted), })
      }
    }
    _ => ()
  }
}

///|
fn check_multiple_of(
  value : @pjson.Json,
  wanted : @pjson.Json,
  path : String,
  errors : Array[SchemaError],
) -> Unit {
  match (value, wanted) {
    (Number(raw~), Number(raw=divisor)) =>
      if !schema_number_multiple_of(raw, divisor) {
        errors.push({ path, message: "it is not a multiple of " + divisor, })
      }
    _ => ()
  }
}

///|
/// `minLength` and `maxLength`: the string has to be long enough, or short
/// enough. The length is counted in characters, as the columns of a diagnostic
/// are.
fn check_length(
  value : @pjson.Json,
  wanted : @pjson.Json,
  path : String,
  errors : Array[SchemaError],
  least : Bool,
) -> Unit {
  let length = match length_argument(wanted) {
    Ok(length) => length
    // Unreachable: `schema_problems` refuses a length that is not a count.
    Err(_) => return
  }
  match value {
    Text(value~) => {
      let count = count_chars(value)
      if least && count < length {
        errors.push({
          path,
          message: "it is " +
          characters(count) +
          " long, and the schema asks for at least " +
          length.to_string(),
        })
      }
      if !least && count > length {
        errors.push({
          path,
          message: "it is " +
          characters(count) +
          " long, and the schema asks for at most " +
          length.to_string(),
        })
      }
    }
    _ => ()
  }
}

///|
/// How a length reads in a sentence, singular and all: `1 character`, `2
/// characters`.
fn characters(count : Int) -> String {
  if count == 1 {
    "1 character"
  } else {
    count.to_string() + " characters"
  }
}

///|
/// `pattern`: the string has to hold a match of the expression.
///
/// The expression is matched by `pattern.mbt`, whose subset of regular
/// expressions is the one schemas are written with; a pattern it cannot read has
/// already been reported by `schema_problems`, and a document is not the place
/// to say so again.
fn check_pattern(
  value : @pjson.Json,
  wanted : @pjson.Json,
  path : String,
  errors : Array[SchemaError],
  ctx : SchemaEvaluationContext,
) -> Unit {
  let pattern = match text_of(wanted) {
    Some(pattern) => pattern
    // Unreachable: `schema_problems` refuses a `pattern` that is not a string.
    None => return
  }
  match text_of(value) {
    Some(text) =>
      if !match_compiled_pattern(
          compiled_schema_pattern(ctx.compiled.patterns, pattern),
          text,
        ) {
        errors.push({
          path,
          message: "it does not match the pattern \"" + pattern + "\"",
        })
      }
    _ => ()
  }
}

///|
/// Every keyword in the schema that this tool cannot read, with the path of the
/// keyword it is under.
///
/// Check one queued node and enqueue its supported subschemas, definitions and
/// resolved reference targets. The shared node table prevents cyclic compilation.
/// Only supported assertions and explicit annotations are accepted.
/// Values inside const, enum, default and examples stay data unless explicitly referenced.
fn check_schema(
  schema : @pjson.Json,
  path : String,
  errors : Array[SchemaProblem],
  cache : Map[String, Result[Pattern, PatternProblem]],
  ctx : SchemaCompileContext,
) -> Unit {
  match schema {
    Object(members~) =>
      for entry in members {
        let (keyword, wanted) = entry
        let here = child_path(path, keyword)
        match keyword {
          "type" => check_type_argument(wanted, here, errors)
          "required" => check_name_list(wanted, here, errors)
          "const" => ()
          "$ref" =>
            match wanted {
              Text(value=raw) =>
                match resolve_schema_ref(ctx.root, raw) {
                  Ok((pointer, target)) => {
                    let id = enqueue_schema(ctx, target, pointer, pointer)
                    ctx.references[pointer_child(ctx.pointer, "$ref")] = id
                  }
                  Err((kind, message)) =>
                    errors.push({ path: here, kind, message, })
                }
              _ =>
                errors.push({
                  path: here,
                  kind: InvalidSchema,
                  message: "expected a reference string",
                })
            }
          "allOf" | "anyOf" | "oneOf" | "prefixItems" =>
            match wanted {
              Array(items~) => {
                if items.is_empty() {
                  errors.push({
                    path: here,
                    message: "expected a nonempty array of schemas",
                    kind: InvalidSchema,
                  })
                }
                for index, subschema in items {
                  enqueue_schema_child(
                    ctx,
                    subschema,
                    [keyword, index.to_string()],
                    here + "[" + index.to_string() + "]",
                  )
                }
              }
              _ =>
                errors.push({
                  path: here,
                  message: "expected a nonempty array of schemas, but this is " +
                  kind_name(wanted),
                  kind: InvalidSchema,
                })
            }
          "not" | "additionalProperties" | "contains" =>
            enqueue_schema_child(ctx, wanted, [keyword], here)
          "patternProperties" =>
            match wanted {
              Object(members~) =>
                for (text, subschema) in members {
                  let location = here + "[\"" + escape_json_string(text) + "\"]"
                  cache_schema_pattern(text, location, errors, cache)
                  enqueue_schema_child(
                    ctx,
                    subschema,
                    [keyword, text],
                    location,
                  )
                }
              _ =>
                errors.push({
                  path: here,
                  kind: InvalidSchema,
                  message: "expected an object mapping patterns to schemas, but this is " +
                  kind_name(wanted),
                })
            }
          "properties" | "$defs" =>
            match wanted {
              Object(members=subschemas) =>
                for entry in subschemas {
                  enqueue_schema_child(
                    ctx,
                    entry.1,
                    [keyword, entry.0],
                    child_path(here, entry.0),
                  )
                }
              _ =>
                errors.push({
                  kind: InvalidSchema,
                  path: here,
                  message: "expected an object naming the members it is about, but this is " +
                  kind_name(wanted),
                })
            }
          "items" =>
            match wanted {
              Object(_) | Bool(_) =>
                enqueue_schema_child(ctx, wanted, [keyword], here)
              _ =>
                errors.push({
                  kind: InvalidSchema,
                  path: here,
                  message: "expected one schema for the items, but this is " +
                  kind_name(wanted) +
                  "; a list of schemas is not read here",
                })
            }
          "enum" =>
            match wanted {
              Array(_) => ()
              _ =>
                errors.push({
                  kind: InvalidSchema,
                  path: here,
                  message: "expected a list of values, but this is " +
                  kind_name(wanted),
                })
            }
          "minimum" | "maximum" | "exclusiveMinimum" | "exclusiveMaximum" =>
            match wanted {
              Number(_) => ()
              _ =>
                errors.push({
                  kind: InvalidSchema,
                  path: here,
                  message: "expected a number, but this is " + kind_name(wanted),
                })
            }
          "multipleOf" =>
            match wanted {
              Number(raw~) =>
                if schema_number_compare(raw, "0") <= 0 {
                  errors.push({
                    path: here,
                    message: "expected a strictly positive number, but this is " +
                    raw,
                    kind: InvalidSchema,
                  })
                }
              _ =>
                errors.push({
                  path: here,
                  message: "expected a strictly positive number, but this is " +
                  kind_name(wanted),
                  kind: InvalidSchema,
                })
            }
          "minItems" | "maxItems" | "minContains" | "maxContains" =>
            match length_argument(wanted) {
              Ok(_) => ()
              Err(kind) =>
                errors.push({
                  path: here,
                  kind,
                  message: match wanted {
                    Number(raw~) =>
                      if kind == UnsupportedFeature {
                        raw +
                        " exceeds the supported item count limit of 1000000000"
                      } else {
                        raw +
                        " is not a count of items; a count must be a nonnegative integer"
                      }
                    _ =>
                      "expected a count of items, but this is " +
                      kind_name(wanted)
                  },
                })
            }
          "minProperties" | "maxProperties" =>
            match length_argument(wanted) {
              Ok(_) => ()
              Err(kind) =>
                errors.push({
                  path: here,
                  kind,
                  message: match wanted {
                    Number(raw~) =>
                      if kind == UnsupportedFeature {
                        raw +
                        " exceeds the supported property count limit of 1000000000"
                      } else {
                        raw +
                        " is not a count of properties; a count must be a nonnegative integer"
                      }
                    _ =>
                      "expected a count of properties, but this is " +
                      kind_name(wanted)
                  },
                })
            }
          "uniqueItems" =>
            match wanted {
              Bool(_) => ()
              _ =>
                errors.push({
                  path: here,
                  kind: InvalidSchema,
                  message: "expected a boolean, but this is " +
                  kind_name(wanted),
                })
            }
          "minLength" | "maxLength" =>
            match length_argument(wanted) {
              Ok(_) => ()
              Err(kind) =>
                errors.push({
                  kind,
                  path: here,
                  message: match wanted {
                    Number(raw~) =>
                      if kind == UnsupportedFeature {
                        raw +
                        " exceeds the supported character count limit of 1000000000"
                      } else {
                        raw +
                        " is not a count of characters; a count must be a nonnegative integer"
                      }
                    _ =>
                      "expected a count of characters, but this is " +
                      kind_name(wanted)
                  },
                })
            }
          "pattern" => check_pattern_argument(wanted, here, errors, cache)
          "title" | "description" | "$comment" | "format" =>
            match wanted {
              Text(_) => ()
              _ =>
                errors.push({
                  path: here,
                  message: "expected a string, but this is " + kind_name(wanted),
                  kind: InvalidSchema,
                })
            }
          "default" => ()
          "examples" =>
            match wanted {
              Array(_) => ()
              _ =>
                errors.push({
                  path: here,
                  message: "expected an array, but this is " + kind_name(wanted),
                  kind: InvalidSchema,
                })
            }
          "$schema" =>
            match wanted {
              Text(value~) =>
                if value != "https://json-schema.org/draft/2020-12/schema" {
                  errors.push({
                    path: here,
                    message: "unsupported schema version: " + value,
                    kind: UnsupportedVersion,
                  })
                }
              _ =>
                errors.push({
                  path: here,
                  message: "expected a schema version URI string, but this is " +
                  kind_name(wanted),
                  kind: InvalidSchema,
                })
            }
          _ =>
            errors.push({
              path: here,
              message: "keyword is not supported",
              kind: UnsupportedFeature,
            })
        }
      }
    Bool(_) => ()
    _ =>
      errors.push({
        kind: InvalidSchema,
        path,
        message: "a schema must be an object or a boolean, but this is " +
        kind_name(schema),
      })
  }
}

///|
/// Whether a `type` keyword holds the name of a type or a list of them.
fn check_type_argument(
  wanted : @pjson.Json,
  path : String,
  errors : Array[SchemaProblem],
) -> Unit {
  match wanted {
    Text(value~) => check_type_name(value, path, errors)
    Array(items~) => {
      if items.is_empty() {
        errors.push({
          path,
          message: "expected at least one JSON type name",
          kind: InvalidSchema,
        })
      }
      for index, item in items {
        match item {
          Text(value~) => {
            check_type_name(value, path + "[" + index.to_string() + "]", errors)
            if items[:index].any(fn(previous) {
                text_of(previous) == Some(value)
              }) {
              errors.push({
                path: path + "[" + index.to_string() + "]",
                message: "duplicate JSON type name: " + value,
                kind: InvalidSchema,
              })
            }
          }
          _ =>
            errors.push({
              kind: InvalidSchema,
              path: path + "[" + index.to_string() + "]",
              message: "expected a JSON type name, but this is " +
              kind_name(item),
            })
        }
      }
    }
    _ =>
      errors.push({
        kind: InvalidSchema,
        path,
        message: "expected a JSON type name or a list of them, but this is " +
        kind_name(wanted),
      })
  }
}

///|
/// Whether a name is one of the seven JSON types.
fn check_type_name(
  name : String,
  path : String,
  errors : Array[SchemaProblem],
) -> Unit {
  match name {
    "object" | "array" | "string" | "number" | "integer" | "boolean" | "null" =>
      ()
    _ =>
      errors.push({
        kind: InvalidSchema,
        path,
        message: "\"" +
        name +
        "\" is not a JSON type; the types are object, array, string, number, integer, boolean and null",
      })
  }
}

///|
/// Whether a `required` keyword holds a list of member names.
fn check_name_list(
  wanted : @pjson.Json,
  path : String,
  errors : Array[SchemaProblem],
) -> Unit {
  match wanted {
    Array(items~) =>
      for index, item in items {
        match item {
          Text(value~) =>
            if items[:index].any(fn(previous) {
                text_of(previous) == Some(value)
              }) {
              errors.push({
                path: path + "[" + index.to_string() + "]",
                message: "duplicate required member name: " + value,
                kind: InvalidSchema,
              })
            }
          _ =>
            errors.push({
              kind: InvalidSchema,
              path: path + "[" + index.to_string() + "]",
              message: "expected a member name, but this is " + kind_name(item),
            })
        }
      }
    _ =>
      errors.push({
        kind: InvalidSchema,
        path,
        message: "expected a list of member names, but this is " +
        kind_name(wanted),
      })
  }
}

///|
/// Exact nonnegative integer count for strings and arrays, distinguishing
/// invalid parameters from
/// mathematically valid counts exceeding the current implementation limit.
fn length_argument(wanted : @pjson.Json) -> Result[Int, SchemaProblemKind] {
  match wanted {
    Number(raw~) => schema_number_count(raw)
    _ => Err(InvalidSchema)
  }
}

///|
/// Whether a `pattern` keyword holds an expression this tool can read,
/// answering with the reason it cannot if it does not.
fn check_pattern_argument(
  wanted : @pjson.Json,
  path : String,
  errors : Array[SchemaProblem],
  cache : Map[String, Result[Pattern, PatternProblem]],
) -> Unit {
  match text_of(wanted) {
    Some(pattern) => cache_schema_pattern(pattern, path, errors, cache)
    _ =>
      errors.push({
        kind: InvalidSchema,
        path,
        message: "expected a pattern, but this is " + kind_name(wanted),
      })
  }
}

///|
/// Whether two values are the same value, as `enum` means it.
///
/// Numbers are compared as the numbers they denote rather than as the text they
/// were written with, so 1, 1.0 and 1e0 are equal. Comparisons are exact even
/// beyond floating-point range. Two objects are equal when they hold the same
/// members, whatever order they were written in, and two arrays when they hold
/// the same values in the same order. Values of different kinds are never the
/// same one.
fn same_value(one : @pjson.Json, other : @pjson.Json) -> Bool {
  match (one, other) {
    (Null, Null) => true
    (Bool(value=first), Bool(value=second)) => first == second
    (Number(raw=first), Number(raw=second)) =>
      schema_number_equal(first, second)
    (Text(value=first), Text(value=second)) => first == second
    (Array(items=first), Array(items=second)) => {
      let mut equal = first.length() == second.length()
      if equal {
        for index, item in first {
          if !same_value(item, second[index]) {
            equal = false
          }
        }
      }
      equal
    }
    (Object(members=first), Object(members=second)) => {
      let mut equal = first.length() == second.length()
      if equal {
        for entry in first {
          match find_member(second, entry.0) {
            Some(value) => if !same_value(entry.1, value) { equal = false }
            None => equal = false
          }
        }
      }
      equal
    }
    _ => false
  }
}

///|
/// The text of a value, if it is a string.
fn text_of(json : @pjson.Json) -> String? {
  match json {
    Text(value~) => Some(value)
    _ => None
  }
}

///|
/// The value of one member, if the object has it.
fn find_member(
  members : Array[(String, @pjson.Json)],
  key : String,
) -> @pjson.Json? {
  for entry in members {
    if entry.0 == key {
      return Some(entry.1)
    }
  }
  None
}

///|
/// The path of a member of the value at `path`.
///
/// The root of a document has the empty path, which is the path `--paths` gives
/// it: a member of the root is named by its key alone, and everything below it
/// is joined with dots.
fn child_path(path : String, key : String) -> String {
  if path == "" {
    key
  } else {
    path + "." + key
  }
}

///|
/// The text a number was written with.
fn raw_of(wanted : @pjson.Json) -> String {
  match wanted {
    Number(raw~) => raw
    // Unreachable: every caller has already read the number out of it.
    _ => ""
  }
}
