// Learn more about moon.mod configuration:
// https://docs.moonbitlang.com/en/latest/toolchain/moon/module.html
//
// To add a dependency, run this command in your terminal:
//   moon add moonbitlang/x
//
// Or manually declare it in `import`, for example:
// import {
//   "moonbitlang/x@0.4.6",
// }

name = "BigSaltyMan/moonjson-toolkit"

version = "0.1.0"

readme = "README.mbt.md"

repository = "https://github.com/BigSaltyMan/moonjson-toolkit"

license = "Apache-2.0"

keywords = [ "json", "formatter", "cli", "validation", "ai" ]

preferred_target = "native"

description = "A JSON toolkit for MoonBit: format, validate, diagnose, analyse and visualise JSON documents."

import {
  "Nanaloveyuki/parsec@0.1.3",
  "oboard/mio@0.5.4",
  "moonbitlang/x@0.5.5",
  "moonbitlang/async@0.22.1",
}
