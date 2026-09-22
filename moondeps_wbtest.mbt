///|
/// The `moon.mod.json` form of a manifest, as a real one is written.
let module_json : String =
  #|{
  #|  "name": "bikallem/compress",
  #|  "version": "0.3.4",
  #|  "deps": {
  #|    "moonbitlang/async": "0.16.7",
  #|    "bikallem/blit": "0.2.2"
  #|  },
  #|  "license": "Apache-2.0"
  #|}

///|
/// The `moon.mod` form of a manifest, with the two things in it that a careless
/// reader would get wrong: a `keywords` list of quoted strings that is not a
/// list of dependencies, and a comment holding a quoted version number that is
/// not one either.
let module_source : String =
  #|// A manifest of the kind `moon new` writes.
  #|name = "app"
  #|
  #|version = "0.1.0"
  #|
  #|import {
  #|  "moonbitlang/x@0.5.5", // was "0.4.50" until the upgrade
  #|  "moonbitlang/async",
  #|}
  #|
  #|keywords = [ "json", "cli" ]
  #|
  #|repository = "https://github.com/example/app"

///|
/// A manifest built by hand, so that a test can state a tree without writing
/// the files a tree would have come from.
fn manifest_of(
  name : String,
  version : String,
  deps : Array[(String, String)],
) -> ModuleInfo {
  { name, version, deps, }
}

///|
/// A manifest's dependencies as one printable line, so that a test can say what
/// it expected in the words the tree itself would use.
fn describe_deps(info : ModuleInfo) -> String {
  info.deps
  .map(fn(dep) { if dep.1 == "" { dep.0 } else { dep.0 + "@" + dep.1 } })
  .join(", ")
}

///|
/// The manifests a walk can find, by module name, standing in for a directory
/// of downloaded modules.
///
/// The tree is built through a lookup function rather than through `.mooncakes`
/// because that is what lets a test state a tree directly — and because it is
/// the only way to build one with a circular dependency in it, which no
/// directory of downloaded modules would hold: the toolchain refuses to publish
/// a module it cannot order.
struct Library {
  manifests : Array[(String, ModuleInfo)]
}

///|
fn Library::of(manifests : Array[ModuleInfo]) -> Library {
  let entries : Array[(String, ModuleInfo)] = []
  for info in manifests {
    entries.push((info.name, info))
  }
  { manifests: entries, }
}

///|
fn Library::lookup(
  self : Library,
) -> async (String) -> Result[ModuleInfo, String] {
  fn(name) {
    for entry in self.manifests {
      if entry.0 == name {
        return Ok(entry.1)
      }
    }
    // A module the library does not hold is one that was never downloaded,
    // which is the answer a real directory gives for it too.
    Err("not downloaded: " + name)
  }
}

///|
test "a moon.mod.json manifest is read for its name, version and dependencies" {
  let info = match parse_module_file(require_json(module_json)) {
    Ok(info) => info
    Err(message) => abort("the manifest should have been read: " + message)
  }
  assert_eq(info.name, "bikallem/compress")
  assert_eq(info.version, "0.3.4")
  assert_eq(
    describe_deps(info),
    "moonbitlang/async@0.16.7, bikallem/blit@0.2.2",
  )
}

///|
/// The two forms are read into the same thing, which is the point of reading
/// both: a dependency tree does not care which spelling the manifest arrived
/// in. An entry that pins no version is the difference between the two that
/// survives — `moon.mod.json` has no way to write one.
test "a moon.mod manifest is read for the same three things" {
  let info = match parse_module_text(module_source) {
    Ok(info) => info
    Err(message) => abort("the manifest should have been read: " + message)
  }
  assert_eq(info.name, "app")
  assert_eq(info.version, "0.1.0")
  assert_eq(describe_deps(info), "moonbitlang/x@0.5.5, moonbitlang/async")
}

///|
test "a manifest with no deps has no dependencies" {
  let info = match
    parse_module_text("{\"name\":\"a/b\",\"version\":\"1.0.0\"}") {
    Ok(info) => info
    Err(message) => abort("the manifest should have been read: " + message)
  }
  assert_eq(info.deps.length(), 0)
}

///|
/// What a `deps` object may get wrong is not the same as what it may leave out:
/// a field the manifest does not have leaves a module with no dependencies,
/// while a version that is not a string, or a `deps` that is not an object at
/// all, is a manifest that cannot be read as one.
test "a deps object that cannot be read is refused, field by field" {
  let refusals = [
    ("{\"name\":\"a/b\"}", "the manifest has no \"version\" string"),
    (
      "{\"name\":\"a/b\",\"version\":\"1.0.0\",\"deps\":5}", "\"deps\" is not an object",
    ),
    (
      "{\"name\":\"a/b\",\"version\":\"1.0.0\",\"deps\":{\"moonbitlang/x\":1}}",
      "the version of moonbitlang/x is not a string",
    ),
  ]
  for refusal in refusals {
    let (text, message) = refusal
    match parse_module_file(require_json(text)) {
      Ok(_) => abort("a manifest that cannot be read should not be: " + text)
      Err(reason) => assert_eq(reason, message)
    }
  }
}

///|
/// An `import` block is not always the four-line shape this repository writes:
/// it may open and close on one line, and a manifest that has no dependencies
/// has no block at all. A manifest may also open with white space, which is the
/// one thing that would make the JSON form look like the key/value one.
test "the shapes an import block is written in" {
  let one_line = parse_module_text(
    "name = \"a\"\nversion = \"1.0.0\"\nimport { \"b@2.0.0\", \"c\" }\n",
  )
  match one_line {
    Ok(info) => assert_eq(describe_deps(info), "b@2.0.0, c")
    Err(message) => abort("the manifest should have been read: " + message)
  }
  // `import` with nothing after it names nothing, and is not a mistake: the
  // modules a manifest depends on are the ones it lists, and this one lists
  // none.
  match parse_module_text("name = \"a\"\nversion = \"1.0.0\"\nimport\n") {
    Ok(info) => assert_eq(info.deps.length(), 0)
    Err(message) => abort("the manifest should have been read: " + message)
  }
  match parse_module_text("name = \"a\"\n") {
    Ok(_) => abort("a manifest with no version should not be read")
    Err(message) => assert_eq(message, "the manifest has no \"version\" line")
  }
  match parse_module_text("\n  {\"name\":\"a/b\",\"version\":\"1.0.0\"}") {
    Ok(info) => assert_eq(info.version, "1.0.0")
    Err(message) => abort("the manifest should have been read: " + message)
  }
}

///|
test "a manifest that is neither form is refused" {
  // JSON that does not parse is reported where the mistake is, by the same
  // diagnostic every other bad document gets.
  match parse_module_text("{\"name\": \"a/b\",}") {
    Ok(_) => abort("a malformed manifest should not be read")
    Err(message) => assert_true(message.has_prefix("line 1, column 16:"))
  }
  // Text that is neither JSON nor a key/value manifest is a manifest with no
  // name in it, and that is what is wrong with it.
  match parse_module_text("hello") {
    Ok(_) => abort("a malformed manifest should not be read")
    Err(message) => assert_eq(message, "the manifest has no \"name\" line")
  }
  // A JSON document with no name in it is refused the same way, and the message
  // says which of the two forms was read so that the reader can tell which file
  // they are looking at.
  match parse_module_file(require_json("{\"a\": 1}")) {
    Ok(_) => abort("a document that is not a manifest should not be read")
    Err(message) => assert_eq(message, "the manifest has no \"name\" string")
  }
}

///|
/// The one tree every rendering test starts from: two levels, a module reached
/// twice, and a branch that is not the last one so that the line drawn down the
/// left of the tree has a child to hang under it.
async fn sample_tree() -> DepNode {
  let library = Library::of([
    manifest_of("oboard/mio", "0.5.4", [("bikallem/blit", "0.2.2")]),
    manifest_of("bikallem/blit", "0.2.2", []),
    manifest_of("moonbitlang/x", "0.5.5", []),
  ])
  let root = manifest_of("app", "0.1.0", [
    ("oboard/mio", "0.5.4"),
    ("moonbitlang/x", "0.5.5"),
  ])
  build_dep_tree_from(root, library.lookup())
}

///|
async test "a two-level tree is drawn from the manifests beneath it" {
  let tree = sample_tree()
  inspect(
    render_dep_tree(tree),
    content="app@0.1.0\n" +
      "├── oboard/mio@0.5.4\n" +
      "│   └── bikallem/blit@0.2.2\n" +
      "└── moonbitlang/x@0.5.5\n",
  )
  // A module reached from two places is two nodes, not a circle: what makes a
  // circle is a name met again on the way *down*, not a name met twice.
  assert_eq(find_cycles(tree).length(), 0)
  // The same version from both places is not a conflict either: the toolchain
  // has nothing to choose between.
  assert_eq(find_version_conflicts(tree).length(), 0)
  assert_eq(dependency_warnings(tree).length(), 0)
}

///|
async test "a dependency that was not downloaded is shown by name alone" {
  let library = Library::of([manifest_of("app", "0.1.0", [])])
  let root = manifest_of("app", "0.1.0", [
    ("moonbitlang/x", "0.5.5"),
    ("oboard/mio", "0.5.4"),
  ])
  let tree = build_dep_tree_from(root, library.lookup())
  inspect(
    render_dep_tree(tree),
    content="app@0.1.0\n" +
      "├── moonbitlang/x@0.5.5\n" +
      "└── oboard/mio@0.5.4\n",
  )
  // The version shown is the one the manifest asked for, since there is no
  // downloaded copy to have a version of its own.
  match tree.children[0] {
    { info, children, } => {
      assert_eq(info.version, "0.5.5")
      assert_eq(children.length(), 0)
    }
  }
}

///|
async test "a circular dependency is found and reported" {
  let library = Library::of([
    manifest_of("a", "1.0.0", [("b", "1.0.0")]),
    manifest_of("b", "1.0.0", [("a", "1.0.0")]),
  ])
  let tree = build_dep_tree_from(
    manifest_of("a", "1.0.0", [("b", "1.0.0")]),
    library.lookup(),
  )
  // The walk stops at the module it has already been inside, leaving the
  // repeated name in the tree as the last thing under it.
  inspect(
    render_dep_tree(tree),
    content="a@1.0.0\n└── b@1.0.0\n    └── a@1.0.0\n",
  )
  assert_eq(find_cycles(tree), [["a", "b", "a"]])
  inspect(
    dependency_warnings(tree).join("\n"),
    content="warning: circular dependency detected\n  a → b → a",
  )
}

///|
/// One tree holding everything a walk can find twice, because a circle is a
/// thing about the graph rather than about the way into it.
///
/// `a` and `b` depend on each other, and the walk enters that circle from four
/// places. Two of them walk it as `a → b → a`: the second is the same circle and
/// is not written down again. The other two enter at `b` and walk `b → a → b`,
/// which is the same circle by another route — and is a different list of names,
/// so it is written down. `d` depending on itself is a circle of one, and a
/// circle of one is not a longer one, which is a comparison the walk makes too.
async test "every circle is reported once, however many ways lead into it" {
  let library = Library::of([
    manifest_of("a", "1.0.0", [("b", "1.0.0")]),
    manifest_of("b", "1.0.0", [("a", "1.0.0")]),
    manifest_of("d", "1.0.0", [("d", "1.0.0")]),
    manifest_of("m", "1.0.0", [("a", "1.0.0")]),
  ])
  let root = manifest_of("app", "0.1.0", [
    ("a", "1.0.0"),
    ("b", "1.0.0"),
    ("d", "1.0.0"),
    ("m", "1.0.0"),
  ])
  let tree = build_dep_tree_from(root, library.lookup())
  assert_eq(find_cycles(tree), [["a", "b", "a"], ["b", "a", "b"], ["d", "d"]])
  inspect(
    dependency_warnings(tree).join("\n"),
    content="warning: circular dependency detected\n" +
      "  a → b → a\n" +
      "warning: circular dependency detected\n" +
      "  b → a → b\n" +
      "warning: circular dependency detected\n" +
      "  d → d",
  )
}

///|
/// A dependency named without a version has none to print, and the tree prints
/// the name alone: an `@` with nothing after it would claim a version that the
/// manifest never named.
async test "a dependency pinned to no version is drawn without one" {
  let root = match parse_module_text(module_source) {
    Ok(info) => info
    Err(message) => abort("the manifest should have been read: " + message)
  }
  let tree = build_dep_tree_from(root, Library::of([]).lookup())
  inspect(
    render_dep_tree(tree),
    content="app@0.1.0\n" +
      "├── moonbitlang/x@0.5.5\n" +
      "└── moonbitlang/async\n",
  )
}

///|
async test "a module required at two versions is reported" {
  let library = Library::of([
    manifest_of("m", "1.0.0", [("x", "2.0.0")]),
    // The copy of `x` that was downloaded, which is the one the tree prints:
    // the conflict is between what the manifests ask for, and the warnings are
    // where the asking is written down.
    manifest_of("x", "1.0.0", []),
  ])
  let root = manifest_of("app", "0.1.0", [("x", "1.0.0"), ("m", "1.0.0")])
  let tree = build_dep_tree_from(root, library.lookup())
  inspect(
    render_dep_tree(tree),
    content="app@0.1.0\n" +
      "├── x@1.0.0\n" +
      "└── m@1.0.0\n" +
      "    └── x@1.0.0\n",
  )
  let conflicts = find_version_conflicts(tree)
  assert_eq(conflicts.length(), 1)
  match conflicts[0] {
    { name, requests, } => {
      assert_eq(name, "x")
      assert_eq(requests, [("1.0.0", "app@0.1.0"), ("2.0.0", "m@1.0.0")])
    }
  }
  inspect(
    dependency_warnings(tree).join("\n"),
    content="warning: 2 versions of x are required\n" +
      "  1.0.0 by app@0.1.0\n" +
      "  2.0.0 by m@1.0.0",
  )
}

///|
/// Both refusals are about the same thing: the two options would each be
/// answering a question about a different kind of input, and a run gives one
/// answer, so the command line that asks both is refused rather than answered
/// in half. Neither needs an input: the command line is settled first.
async test "--moon-deps is refused beside the options it cannot be combined with" {
  let analyzer = StubAnalyzer::new(Ok("unused"))
  let refusals = [
    (
      ["--moon-deps", "--jsonl"],
      "--moon-deps reads one module manifest, and --jsonl reads many documents: the two cannot be combined",
    ),
    (
      ["--moon-deps", "--json-out", "stats.json"],
      "--json-out describes a JSON document, and --moon-deps reads a module manifest: the two cannot be combined",
    ),
  ]
  for refusal in refusals {
    let (args, message) = refusal
    let result = run(args, analyze=analyzer.analyzer())
    inspect(result.code, content="2")
    inspect(result.out, content="")
    assert_true(result.err.contains(message))
  }
  assert_eq(analyzer.calls, 0)
}

///|
/// A module reached from two places is two nodes, and both of them ask for the
/// dependencies underneath. That a module asks twice is not worth saying twice:
/// each version is listed with the modules that want it, and the module wants
/// this one whether it is drawn once or twice.
async test "a module reached twice asks for its dependencies once" {
  let root = manifest_of("app", "0.1.0", [("m1", "1.0.0"), ("m2", "1.0.0")])
  let library = Library::of([
    manifest_of("c", "1.0.0", [("x", "1.0.0")]),
    manifest_of("x", "1.0.0", []),
    manifest_of("m1", "1.0.0", [("c", "1.0.0")]),
    manifest_of("m2", "1.0.0", [("c", "1.0.0"), ("x", "2.0.0")]),
  ])
  let tree = build_dep_tree_from(root, library.lookup())
  // `c` is drawn twice, once under each of the modules that asks for it, and
  // `x` therefore has two `c` nodes above it in different branches.
  //
  // The version drawn is the one that was read, not the one that was asked
  // for: `m2` wants 2.0.0, and no such manifest was found, so its node is the
  // 1.0.0 copy like every other. What `m2` wanted is not lost — it is the
  // other half of the conflict asserted below.
  inspect(
    render_dep_tree(tree),
    content="app@0.1.0\n" +
      "├── m1@1.0.0\n" +
      "│   └── c@1.0.0\n" +
      "│       └── x@1.0.0\n" +
      "└── m2@1.0.0\n" +
      "    ├── c@1.0.0\n" +
      "    │   └── x@1.0.0\n" +
      "    └── x@1.0.0\n",
  )
  let conflicts = find_version_conflicts(tree)
  assert_eq(conflicts.length(), 1)
  match conflicts[0] {
    { name, requests, } => {
      assert_eq(name, "x")
      // `c@1.0.0` is named once: it asks for `x` at 1.0.0 from both of its two
      // nodes, and it is one module asking one question.
      assert_eq(requests, [("1.0.0", "c@1.0.0"), ("2.0.0", "m2@1.0.0")])
    }
  }
}

///|
test "the dependencies of a manifest are looked for beside it" {
  assert_eq(dependency_directory("app/moon.mod"), "app/.mooncakes")
  assert_eq(dependency_directory("moon.mod.json"), ".mooncakes")
  // A manifest on standard input has no directory, so it is read as though it
  // had been written in the working directory.
  assert_eq(dependency_directory("<stdin>"), ".mooncakes")
  // A manifest at the root of the file system is not a manifest in the working
  // directory: what is beside `/moon.mod` is `/.mooncakes`.
  assert_eq(dependency_directory("/moon.mod"), "/.mooncakes")
}

///|
/// A scratch directory holding one module and the `.mooncakes` beside it.
///
/// It carries the test's own name because `moon test` runs the tests of this
/// package at once: two tests sharing a directory would be two tests writing
/// each other's manifests.
struct ScratchTree {
  root : String
}

///|
fn ScratchTree::named(name : String) -> ScratchTree {
  { root: "moondeps_scratch_" + name, }
}

///|
/// Write `text` to `path`, creating the directories above it.
async fn write_manifest(path : String, text : String) -> Unit {
  @fs.mkdir(parent_directory(path), recursive=true)
  @fs.write_file(path, text)
}

///|
/// Delete a scratch directory and everything in it, ignoring the case where it
/// was never created.
async fn remove_tree(path : String) -> Unit {
  try @fs.rmdir(path, recursive=true) catch {
    _ => ()
  } noraise {
    _ => ()
  }
}

///|
async test "a tree is read from the .mooncakes directory beside the manifest" {
  let scratch = ScratchTree::named("disk")
  let manifest = scratch.root + "/moon.mod"
  write_manifest(
    manifest, "name = \"app\"\n\nversion = \"0.1.0\"\n\nimport {\n  \"oboard/mio@0.5.4\",\n  \"bikallem/blit@0.2.2\",\n}\n",
  )
  // One dependency in the JSON form, one in the source form, and one that was
  // never downloaded at all.
  write_manifest(
    scratch.root + "/.mooncakes/oboard/mio/moon.mod.json",
    "{\"name\":\"oboard/mio\",\"version\":\"0.5.4\",\"deps\":{\"moonbitlang/x\":\"0.5.5\"}}",
  )
  write_manifest(
    scratch.root + "/.mooncakes/bikallem/blit/moon.mod",
    "name = \"bikallem/blit\"\n\nversion = \"0.2.2\"\n\nimport {\n  \"moonbitlang/x@0.5.5\",\n}\n",
  )
  let text = match read_file(manifest) {
    Ok(text) => text
    Err(message) => abort("the scratch manifest should be readable: " + message)
  }
  let root = match parse_module_text(text) {
    Ok(root) => root
    Err(message) => abort("the scratch manifest should be read: " + message)
  }
  let tree = build_dep_tree(root, dependency_directory(manifest))
  inspect(
    render_dep_tree(tree),
    content="app@0.1.0\n" +
      "├── oboard/mio@0.5.4\n" +
      "│   └── moonbitlang/x@0.5.5\n" +
      "└── bikallem/blit@0.2.2\n" +
      "    └── moonbitlang/x@0.5.5\n",
  )
  remove_tree(scratch.root)
}

///|
/// The run a reader makes: one manifest, the modules it asks for downloaded
/// beside it, and one of them asking for a version the copy on disk is not.
///
/// Both halves of the answer are visible here. The tree prints the copy that
/// was read — `moonbitlang/x@0.5.5`, which is what is in `.mooncakes` — and the
/// warning below it says who wanted which, `mio` having asked for `0.4.50`.
async test "--moon-deps prints the tree of the manifest it is given" {
  let scratch = ScratchTree::named("cli")
  let manifest = scratch.root + "/moon.mod"
  write_manifest(
    manifest, "name = \"app\"\n\nversion = \"0.1.0\"\n\nimport {\n  \"oboard/mio@0.5.4\",\n  \"moonbitlang/x@0.5.5\",\n}\n",
  )
  write_manifest(
    scratch.root + "/.mooncakes/oboard/mio/moon.mod",
    "name = \"oboard/mio\"\n\nversion = \"0.5.4\"\n\nimport {\n  \"moonbitlang/x@0.4.50\",\n}\n",
  )
  write_manifest(
    scratch.root + "/.mooncakes/moonbitlang/x/moon.mod.json",
    "{\"name\":\"moonbitlang/x\",\"version\":\"0.5.5\",\"deps\":{}}",
  )
  let analyzer = StubAnalyzer::new(Ok("unused"))
  let result = run(["--moon-deps", "-f", manifest], analyze=analyzer.analyzer())
  remove_tree(scratch.root)
  inspect(result.code, content="0")
  inspect(
    result.out,
    content="app@0.1.0\n" +
      "├── oboard/mio@0.5.4\n" +
      "│   └── moonbitlang/x@0.5.5\n" +
      "└── moonbitlang/x@0.5.5\n" +
      "\n" +
      "warning: 2 versions of moonbitlang/x are required\n" +
      "  0.5.5 by app@0.1.0\n" +
      "  0.4.50 by oboard/mio@0.5.4\n",
  )
  inspect(result.err, content="")
  // Nothing was asked of the network, and no key had to be set for the run to
  // get this far: the mode neither reads the environment nor needs to.
  assert_eq(analyzer.calls, 0)
}

///|
async test "--moon-deps on an input that is not a manifest exits 1" {
  let scratch = ScratchTree::named("refused")
  let document = scratch.root + "/document.json"
  write_manifest(document, "{\"a\": 1}")
  let analyzer = StubAnalyzer::new(Ok("unused"))
  let result = run(["--moon-deps", "-f", document], analyze=analyzer.analyzer())
  remove_tree(scratch.root)
  inspect(result.code, content="1")
  // The document never reaches standard output: what was asked for is a tree,
  // and there is none to print.
  inspect(result.out, content="")
  assert_true(
    result.err.contains(document + " is not a valid MoonBit module manifest"),
  )
}

///|
async test "--moon-deps under --ai is the document review and nothing else" {
  let scratch = ScratchTree::named("ai")
  let document = scratch.root + "/document.json"
  write_manifest(document, "{\"name\":\"not-a-manifest\"}")
  let analyzer = StubAnalyzer::new(Ok("looks fine to me"))
  @env.set_env_var(api_key_variable, stub_api_key)
  let result = run(
    ["--moon-deps", "--ai", "-f", document],
    analyze=analyzer.analyzer(),
  )
  remove_tree(scratch.root)
  inspect(result.code, content="0")
  // `--ai` asks about the document, so it answers about the document: the
  // manifest is a JSON document here, and the review is of that.
  assert_eq(analyzer.calls, 1)
  assert_true(result.out.contains("\"name\": \"not-a-manifest\""))
  assert_true(result.out.contains("AI quality report"))
  assert_false(result.out.contains("moon-deps"))
}
