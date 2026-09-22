///|
/// One MoonBit module as its manifest declares it: the name it is published
/// under, the version this copy is, and the modules it asks for.
///
/// A dependency is a `(name, version)` pair, and the version may be empty. The
/// `moon.mod` form allows an entry that pins nothing — `"moonbitlang/x"` beside
/// `"moonbitlang/async@0.22.1"` — and an empty string is how such an entry is
/// carried: it is the difference between a version that is unknown and a
/// version that is a number.
pub(all) struct ModuleInfo {
  name : String
  version : String
  deps : Array[(String, String)]
}

///|
/// One module in a dependency tree, with everything it depends on beneath it.
///
/// The shape is a tree rather than a graph: a module asked for twice is shown
/// twice, once under each module that asks for it. That is what `moon tree`
/// prints, and it is what makes a version conflict visible — the same name
/// appearing at two versions in one tree is the whole report.
pub(all) struct DepNode {
  info : ModuleInfo
  children : Array[DepNode]
}

///|
/// A module that more than one manifest in a tree asks for, at more than one
/// version.
pub(all) struct VersionConflict {
  name : String
  /// One `(version, those who asked)` pair per version, in the order the tree
  /// met them, with the requesters joined for printing.
  requests : Array[(String, String)]
}

///|
/// The two names a module manifest is published under, in the order a lookup
/// tries them.
///
/// Both are in current use and they are different formats, not two spellings:
/// `moon.mod.json` is JSON, and `moon.mod` is a list of `key = value` lines
/// whose dependencies sit in an `import { ... }` block. A module that ships the
/// JSON form ships only that one, so a reader that knew one of them would miss
/// most of a real tree.
let module_json_file : String = "moon.mod.json"

///|
let module_source_file : String = "moon.mod"

// ---------------------------------------------------------------------------
// Reading a manifest
// ---------------------------------------------------------------------------

///|
/// Read the module a `moon.mod.json` describes.
///
/// Only the three fields that make up a dependency tree are read. Everything
/// else in the file — the readme, the keywords, the licence — belongs to
/// publishing rather than to depending, and is left where it is.
pub fn parse_module_file(json : @pjson.Json) -> Result[ModuleInfo, String] {
  let name = match required_text(json, "name") {
    Ok(name) => name
    Err(message) => return Err(message)
  }
  let version = match required_text(json, "version") {
    Ok(version) => version
    Err(message) => return Err(message)
  }
  let deps = match module_deps(json) {
    Ok(deps) => deps
    Err(message) => return Err(message)
  }
  Ok({ name, version, deps, })
}

///|
/// The text of the string field `field`, or the reason there is none.
fn required_text(json : @pjson.Json, field : String) -> Result[String, String] {
  match object_field(json, field).bind(text_value) {
    Some(value) => Ok(value)
    None => Err("the manifest has no \"" + field + "\" string")
  }
}

///|
/// The `deps` object of a `moon.mod.json`, as pairs in the order it lists them.
fn module_deps(json : @pjson.Json) -> Result[Array[(String, String)], String] {
  let deps : Array[(String, String)] = []
  match object_field(json, "deps") {
    Some(Object(members~)) =>
      for entry in members {
        let (name, value) = entry
        match text_value(value) {
          Some(version) => deps.push((name, version))
          None => return Err("the version of " + name + " is not a string")
        }
      }
    Some(_) => return Err("\"deps\" is not an object")
    // A manifest with no dependencies has no `deps` at all, which is not the
    // same as having an empty one but reads the same way here.
    None => ()
  }
  Ok(deps)
}

///|
/// Read a manifest written in either of the two forms.
///
/// Which one it is shows in the first character that is not white space: JSON
/// opens with `{`, and the `moon.mod` form opens with a key. Guessing from the
/// file name would be wrong half the time — this is called for a manifest read
/// from a dependency directory, where the name is the only thing that said
/// which form to expect, and it is better to read what is actually there.
pub fn parse_module_text(text : String) -> Result[ModuleInfo, String] {
  if opens_with_brace(text) {
    match parse_with_diagnostic(text, None) {
      Ok(json) => parse_module_file(json)
      Err(diagnostic) => Err(diagnostic.render())
    }
  } else {
    parse_module_source(text)
  }
}

///|
/// Whether the first character that is not white space is `{`.
fn opens_with_brace(text : String) -> Bool {
  for ch in text.to_array() {
    if ch == ' ' || ch == '\t' || ch == '\r' || ch == '\n' {
      continue
    }
    return ch == '{'
  }
  false
}

///|
/// Read a manifest written in the `moon.mod` form.
///
/// The form is a list of `key = value` lines, with the dependencies gathered
/// into an `import { "name@version", ... }` block that may open and close on one
/// line or run on for several. Only `name`, `version` and that block are read;
/// a `keywords = [ "a", "b" ]` line is a list of quoted strings too, which is
/// why the quotes are only looked for inside the block.
fn parse_module_source(text : String) -> Result[ModuleInfo, String] {
  let mut name : String? = None
  let mut version : String? = None
  let deps : Array[(String, String)] = []
  let mut in_import = false
  for raw_line in text.split("\n") {
    // `trim` answers with a view into the line it was given, so the `to_owned`
    // after it is what makes this a line the parser below can take apart.
    let line = without_comment(raw_line.to_owned()).trim().to_owned()
    if in_import {
      // The block ends on the line that closes it, and anything after that
      // brace on the same line is not part of it.
      match line.find("}") {
        Some(close) => {
          deps.append(
            import_entries(line.exact_view(start=0, end=close).to_owned()),
          )
          in_import = false
        }
        None => deps.append(import_entries(line))
      }
    } else if line.has_prefix("import") {
      // A block that closes on its own line, or on the line it opens: both are
      // written, and the entries are the same either way.
      match line.find("{") {
        Some(open) => {
          let rest = line.exact_view(start=open + 1).to_owned()
          match rest.find("}") {
            Some(close) =>
              deps.append(
                import_entries(rest.exact_view(start=0, end=close).to_owned()),
              )
            None => {
              deps.append(import_entries(rest))
              in_import = true
            }
          }
        }
        None => ()
      }
    } else {
      match line.find("=") {
        Some(position) => {
          let key = line
            .exact_view(start=0, end=position)
            .to_owned()
            .trim()
            .to_owned()
          let value = unquote(
            line.exact_view(start=position + 1).to_owned().trim().to_owned(),
          )
          if key == "name" {
            name = Some(value)
          } else if key == "version" {
            version = Some(value)
          }
        }
        None => ()
      }
    }
  }
  let name = match name {
    Some(name) => name
    None => return Err("the manifest has no \"name\" line")
  }
  let version = match version {
    Some(version) => version
    None => return Err("the manifest has no \"version\" line")
  }
  Ok({ name, version, deps, })
}

///|
/// `line` with a `//` comment removed from it.
///
/// The scan is over the line rather than over a `split`, because a comment is
/// only a comment outside a string: the repository line of a real manifest
/// reads `repository = "https://github.com/..."`, and cutting at the slashes
/// there would leave a quoted string that never closes.
fn without_comment(line : String) -> String {
  let chars = line.to_array()
  let mut in_string = false
  let mut index = 0
  while index < chars.length() {
    let ch = chars[index]
    if ch == '"' {
      in_string = !in_string
    } else if ch == '/' &&
      !in_string &&
      index + 1 < chars.length() &&
      chars[index + 1] == '/' {
      return String::from_array(chars[0:index])
    }
    index = index + 1
  }
  line
}

///|
/// The value of a `key = value` line, with the quotes around it removed.
///
/// A value written without quotes is taken as it stands, and a quoted one ends
/// at its closing quote, so that a stray character after it cannot join the
/// value.
fn unquote(value : String) -> String {
  let chars = value.to_array()
  if chars.length() == 0 || chars[0] != '"' {
    return value
  }
  let mut stop = 1
  while stop < chars.length() && chars[stop] != '"' {
    stop = stop + 1
  }
  String::from_array(chars[1:stop])
}

///|
/// Every quoted `"name@version"` in `text`, as dependency pairs.
fn import_entries(text : String) -> Array[(String, String)] {
  let entries : Array[(String, String)] = []
  let chars = text.to_array()
  let mut index = 0
  while index < chars.length() {
    if chars[index] == '"' {
      let start = index + 1
      let mut stop = start
      while stop < chars.length() && chars[stop] != '"' {
        stop = stop + 1
      }
      entries.push(split_requirement(String::from_array(chars[start:stop])))
      index = stop + 1
    } else {
      index = index + 1
    }
  }
  entries
}

///|
/// Split `"moonbitlang/x@0.5.5"` into the module and the version it pins.
///
/// The split is at the last `@`, which is the only one a module name cannot
/// contain. An entry that pins nothing has no `@` at all and yields an empty
/// version.
fn split_requirement(text : String) -> (String, String) {
  let chars = text.to_array()
  let mut at = -1
  for index, ch in chars {
    if ch == '@' {
      at = index
    }
  }
  if at < 0 {
    (text, "")
  } else {
    (String::from_array(chars[0:at]), String::from_array(chars[at + 1:]))
  }
}

// ---------------------------------------------------------------------------
// Building the tree
// ---------------------------------------------------------------------------

///|
/// Build the dependency tree that starts at `root`, asking `lookup` for each
/// dependency's own manifest in turn.
///
/// A module `lookup` cannot answer for becomes a leaf rather than an error. A
/// dependency that has not been downloaded is a fact about the tree that is
/// worth printing — the manifest names it, and the version it names is often
/// the interesting part — and it is also what the bottom of every real tree
/// looks like, since the last level is exactly the set of modules whose own
/// manifests the toolchain did not need.
///
/// A module that asks for itself, however long the way round, is kept as a leaf
/// as well: the walk has to end somewhere, and the repeated name left in the
/// tree is what `find_cycles` reads back out of it.
pub async fn build_dep_tree_from(
  root : ModuleInfo,
  lookup : async (String) -> Result[ModuleInfo, String],
) -> DepNode {
  build_below(root, lookup, [root.name])
}

///|
/// The recursive half of `build_dep_tree_from`, carrying the names of the
/// modules the walk is already inside.
async fn build_below(
  info : ModuleInfo,
  lookup : async (String) -> Result[ModuleInfo, String],
  ancestors : Array[String],
) -> DepNode {
  let children : Array[DepNode] = []
  for dep in info.deps {
    let (name, version) = dep
    if index_of(ancestors, name) >= 0 {
      children.push({ info: { name, version, deps: [], }, children: [], })
      continue
    }
    children.push(
      match lookup(name) {
        Ok(child) => build_below(child, lookup, ancestors + [name])
        Err(_) => { info: { name, version, deps: [], }, children: [], }
      },
    )
  }
  { info, children, }
}

///|
/// Build the tree beneath `root`, reading each dependency's manifest from
/// `deps_dir`.
///
/// A dependency directory holds one directory per module, named the way the
/// module is, each with the manifest of the version that was downloaded — which
/// is not always the version that was asked for, and is why the tree prints
/// what each manifest declares rather than what its dependents wanted.
pub async fn build_dep_tree(root : ModuleInfo, deps_dir : String) -> DepNode {
  build_dep_tree_from(root, async fn(name) {
    read_module_manifest(deps_dir + "/" + name)
  })
}

///|
/// Read the manifest of the module in `module_dir`, in whichever of the two
/// forms it was published in.
pub async fn read_module_manifest(
  module_dir : String,
) -> Result[ModuleInfo, String] {
  match read_file(module_dir + "/" + module_json_file) {
    Ok(text) => parse_module_text(text)
    Err(_) =>
      match read_file(module_dir + "/" + module_source_file) {
        Ok(text) => parse_module_text(text)
        Err(message) => Err(module_dir + ": " + message)
      }
  }
}

///|
/// The directory a manifest's dependencies are read from: the `.mooncakes` that
/// `moon` downloads them into, beside the manifest itself.
///
/// A manifest read from standard input has no directory of its own, so its
/// dependencies are looked for under the working directory — the same place
/// they would be if the manifest had been written there.
pub fn dependency_directory(source : String) -> String {
  let parent = parent_directory(source)
  if parent == "." {
    ".mooncakes"
  } else if parent == "/" {
    // A manifest at the root of the file system: the separator is already
    // there. `//` is not the same path — some systems read it as a network
    // location, and none of them read it as `/`.
    "/.mooncakes"
  } else {
    parent + "/.mooncakes"
  }
}

///|
/// Everything before the last separator in `path`, or `.` when there is none.
fn parent_directory(path : String) -> String {
  let chars = path.to_array()
  let mut cut = -1
  for index, ch in chars {
    if ch == '/' || ch == '\\' {
      cut = index
    }
  }
  if cut < 0 {
    "."
  } else if cut == 0 {
    "/"
  } else {
    String::from_array(chars[0:cut])
  }
}

///|
/// The position of `value` in `values`, or -1 when it is not there.
fn index_of(values : Array[String], value : String) -> Int {
  let mut index = 0
  while index < values.length() {
    if values[index] == value {
      return index
    }
    index = index + 1
  }
  -1
}

// ---------------------------------------------------------------------------
// What a tree says about itself
// ---------------------------------------------------------------------------

///|
/// Every circular dependency in `tree`, each written as the path that closes on
/// itself: `["a", "b", "a"]` for a module that ends up asking for itself
/// through one other.
///
/// The path starts at the module that closes the circle, not at the root of the
/// tree, because the module a circle is entered from says nothing about the
/// circle: the same one is reached from every module above it.
pub fn find_cycles(tree : DepNode) -> Array[Array[String]] {
  let found : Array[Array[String]] = []
  collect_cycles(tree, [], found)
  found
}

///|
/// The recursive half of `find_cycles`, carrying the path down to `node`.
fn collect_cycles(
  node : DepNode,
  path : Array[String],
  found : Array[Array[String]],
) -> Unit {
  let here = path + [node.info.name]
  for child in node.children {
    let start = index_of(here, child.info.name)
    if start >= 0 {
      // The name is already on the path, so the walk has come back to where it
      // was: the circle is the tail of the path from there, closed by the name
      // again. A name reached from two different places is not a circle, which
      // is why this asks about the path rather than about everything seen.
      let cycle : Array[String] = []
      for index in start..<here.length() {
        cycle.push(here[index])
      }
      cycle.push(child.info.name)
      if !has_path(found, cycle) {
        found.push(cycle)
      }
    } else {
      collect_cycles(child, here, found)
    }
  }
}

///|
/// Whether `paths` already holds exactly `path`.
fn has_path(paths : Array[Array[String]], path : Array[String]) -> Bool {
  for seen in paths {
    if same_path(seen, path) {
      return true
    }
  }
  false
}

///|
/// Whether two paths name the same modules in the same order.
fn same_path(left : Array[String], right : Array[String]) -> Bool {
  if left.length() != right.length() {
    return false
  }
  let mut index = 0
  while index < left.length() {
    if left[index] != right[index] {
      return false
    }
    index = index + 1
  }
  true
}

///|
/// Every module in `tree` that is required at more than one version, each with
/// the versions and the modules that asked for them.
///
/// A module required twice at the *same* version is not a conflict: that is a
/// diamond, and the toolchain resolves it by taking the one copy. Two versions
/// is a decision the toolchain makes on the reader's behalf, and the report is
/// that it was made.
pub fn find_version_conflicts(tree : DepNode) -> Array[VersionConflict] {
  let entries : Array[Requirements] = []
  collect_requirements(tree, entries)
  let conflicts : Array[VersionConflict] = []
  for entry in entries {
    if entry.versions.length() > 1 {
      let requests : Array[(String, String)] = []
      for wanted in entry.versions {
        requests.push((wanted.0, wanted.1.join(", ")))
      }
      conflicts.push({ name: entry.name, requests, })
    }
  }
  conflicts
}

///|
/// The versions one module was asked for, and who asked for each.
priv struct Requirements {
  name : String
  versions : Array[(String, Array[String])]
}

///|
/// Note down that `requester` asks for `name` at `version`.
fn note_requirement(
  entry : Requirements,
  version : String,
  requester : String,
) -> Unit {
  let mut index = 0
  while index < entry.versions.length() {
    let (wanted, requesters) = entry.versions[index]
    if wanted == version {
      if index_of(requesters, requester) < 0 {
        requesters.push(requester)
      }
      return
    }
    index = index + 1
  }
  entry.versions.push((version, [requester]))
}

///|
/// Read every requirement in `tree` into `entries`, one entry per module name,
/// in the order the names are first met.
fn collect_requirements(node : DepNode, entries : Array[Requirements]) -> Unit {
  let requester = describe_module(node.info)
  for dep in node.info.deps {
    let (name, version) = dep
    // An entry that pins no version asks for no particular one, so it is not
    // evidence of a conflict with anything.
    if version != "" {
      note_requirement(entry_for(entries, name), version, requester)
    }
  }
  for child in node.children {
    collect_requirements(child, entries)
  }
}

///|
/// The entry for `name`, added to the end of `entries` if it is new.
fn entry_for(entries : Array[Requirements], name : String) -> Requirements {
  for entry in entries {
    if entry.name == name {
      return entry
    }
  }
  let entry : Requirements = { name, versions: [], }
  entries.push(entry)
  entry
}

// ---------------------------------------------------------------------------
// Printing
// ---------------------------------------------------------------------------

///|
/// A module as one printed name: `name@version`, or just the name when the
/// manifest pins no version.
fn describe_module(info : ModuleInfo) -> String {
  if info.version == "" {
    info.name
  } else {
    info.name + "@" + info.version
  }
}

///|
/// Draw `tree` as the indented lines of a dependency tree, ending in a newline.
pub fn render_dep_tree(tree : DepNode) -> String {
  let out = StringBuilder()
  out.write_string(describe_module(tree.info))
  out.write_char('\n')
  render_branches(tree.children, "", out)
  out.to_string()
}

///|
/// Draw one level of the tree, each branch under `prefix`.
///
/// The last branch is drawn with a corner and the ones before it with a tee,
/// and it is the same distinction that decides what hangs below them: a line
/// drawn down the left of a level has to stop under the corner, so the last
/// branch is followed by nothing where the others are followed by a line.
fn render_branches(
  children : Array[DepNode],
  prefix : String,
  out : StringBuilder,
) -> Unit {
  let last = children.length() - 1
  for index, child in children {
    let is_last = index == last
    out.write_string(
      prefix + (if is_last { "└── " } else { "├── " }),
    )
    out.write_string(describe_module(child.info))
    out.write_char('\n')
    render_branches(
      child.children,
      prefix + (if is_last { "    " } else { "│   " }),
      out,
    )
  }
}

///|
/// What a tree has to say about itself beyond its shape, as one block of text
/// per warning, in the order they are worth reading.
///
/// A circular dependency comes first: it is the one thing here that cannot be
/// resolved by reading the manifests again, since a toolchain given one has no
/// order in which to build. A version conflict follows, because the toolchain
/// *can* resolve it and does.
pub fn dependency_warnings(tree : DepNode) -> Array[String] {
  let blocks : Array[String] = []
  for cycle in find_cycles(tree) {
    blocks.push(
      "warning: circular dependency detected\n  " + cycle.join(" → "),
    )
  }
  for conflict in find_version_conflicts(tree) {
    let out = StringBuilder()
    out.write_string(
      "warning: " +
      conflict.requests.length().to_string() +
      " versions of " +
      conflict.name +
      " are required",
    )
    for request in conflict.requests {
      out.write_string("\n  " + request.0 + " by " + request.1)
    }
    blocks.push(out.to_string())
  }
  blocks
}

///|
/// Answer one module manifest: the tree of modules it depends on, and a warning
/// for each thing about that tree worth knowing.
///
/// The tree is the whole of the output — there is no document here to print
/// beside it — and the warnings follow it after a blank line, each standing on
/// its own. A run that finds a circular dependency or a version conflict is not
/// a run that failed: both are readings of the manifest that was given, and the
/// manifest was read.
async fn run_moon_deps(source : String, text : String) -> RunResult {
  let root = match parse_module_text(text) {
    Ok(root) => root
    Err(message) =>
      return failure(
        error_prefix() +
        source +
        " is not a valid MoonBit module manifest\n" +
        message,
        exit_input_error,
      )
  }
  let tree = build_dep_tree(root, dependency_directory(source))
  let warnings = dependency_warnings(tree)
  let out = StringBuilder()
  out.write_string(render_dep_tree(tree))
  if warnings.length() > 0 {
    out.write_string("\n")
    out.write_string(warnings.join("\n\n"))
    out.write_string("\n")
  }
  { out: out.to_string(), err: "", code: exit_success, }
}
