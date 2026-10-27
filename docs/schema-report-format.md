# Schema 结构化报告格式（版本 1）

本文记录 `--schema-output json` 的现有四种报告，供脚本、编辑器和 CI 使用。
JSON 报告只表示本工具支持子集中的检查结果，不代表完整 JSON Schema 标准认证。
以下命令从仓库根目录运行，使用已安装的 `moonjson-toolkit`；真实 native CLI
验收的构建、输入及原始输出见文末。JSON 示例为便于阅读调整了排版。

## 公共约定

- 当前 `reportVersion` 是整数 `1`。对象字段顺序、缩进和末尾换行不是接口契约。
- 消费者应忽略不认识的新增字段。删除字段、改变字段类型或改变既有语义属于
  不兼容变化，需要调整报告版本；不能只更新文档就改变版本 1 的含义。
- 机器判断依赖类别、状态、位置和真实进程退出码。`message` 是供人阅读的诊断，
  **不承诺英文文案永久不变**，尤其不能匹配操作系统文件错误的完整文本。
- 报告是一个完整 UTF-8 JSON 文档，既不是输出中的某个 JSON 片段，也不是 NDJSON。
  不含 ANSI 颜色、文本标题或额外总结。任一流混入非空白文本或第二个 JSON 文档时，
  消费者应判定报告无法解析。
- 成功（退出 `0`）时报告在 stdout，stderr 为空；检查失败（退出 `1` 或 `2`）时
  报告在 stderr，stdout 为空，包括批量中有部分输入通过的情况。
- **参数解析错误和模式冲突仍可能是普通文本。** 应先检查退出码，再选择输出流，
  严格解析并检查报告版本、类型和字段；解析失败时保留原文，不能把所有 stderr
  无条件当作 JSON。
- `schemaFile` 和文件输入的 `inputFile` 保留命令行给出的路径；stdin 为 `"<stdin>"`。

### 问题字段和位置

`issues` 总是数组，每项至少包含以下字段：

| 字段 | 类型 | 含义 |
| --- | --- | --- |
| `kind` | string | 稳定的问题类别，见下表 |
| `location` | string 或 null | 原有显示路径；不是 JSON Pointer |
| `message` | string | 非空的人类可读诊断，不作为完整文案契约 |

独立检查的问题**没有 `stage`**。其他三种报告的问题有 `stage`：`schema`、`input`
或 `evaluation`。它标明失败阶段，不代替 `kind`。

| kind | stage（独立检查除外） | location / 其他位置 |
| --- | --- | --- |
| `ReadError` | `schema` 或 `input` | `null`；输入无法读取或中途读取失败 |
| `ParseError` | `schema` 或 `input` | `null`；消息包含解析行列 |
| `InvalidSchema` | `schema` | Schema 关键字的显示位置 |
| `UnsupportedFeature` | `schema` | 未支持能力的显示位置 |
| `UnsupportedVersion` | `schema` | 版本声明的显示位置 |
| `ValidationError` | `input` | 输入内的显示路径，根位置是 `""` |
| `ReferenceCycle` / `ResourceLimit` | `evaluation` | `null`，另有两个 JSON Pointer |

执行错误的 `instancePointer`、`schemaPointer` 是 RFC 6901 JSON Pointer 字符串，
空字符串表示根节点；不能从 `location` 反推出可靠的 JSON Pointer。
JSONL 的实例指针和普通违规位置均相对于当前记录，实际行号由结果的 `line` 单独表示。
解析消息中的行列对应整个原输入，不会因跳过空白行而重排。

## 1. Schema 独立检查

```sh
moonjson-toolkit --check-schema examples/schema-acceptance/person.schema.json --schema-output json
moonjson-toolkit --check-schema examples/schema-acceptance/unsupported.schema.json --schema-output json
```

顶层字段为 `reportVersion: int`、`schemaFile: string`、`status: string`、
`issues: array`。保持原格式：**没有 `reportType`、`inputFile`、`results` 或 `summary`**，
问题也不补加其他模式的 `stage`。

编译成功为 `supported`，退出 `0`；读取、解析、编译失败为 `error`，退出 `2`。
`true`、`false` Schema 都能编译，均返回 `supported`，因为此模式不校验业务数据。

最小成功示例（stdout）：

```json
{"reportVersion":1,"schemaFile":"examples/schema-acceptance/person.schema.json","status":"supported","issues":[]}
```

失败示例（stderr，退出 `2`）：

```json
{"reportVersion":1,"schemaFile":"examples/schema-acceptance/unsupported.schema.json","status":"error","issues":[{"kind":"UnsupportedFeature","location":"unevaluatedProperties","message":"keyword is not supported"}]}
```

## 2. 单文档校验

```sh
cat examples/schema-acceptance/valid.json | moonjson-toolkit -v --schema examples/schema-acceptance/person.schema.json --schema-output json
moonjson-toolkit -v --schema examples/schema-acceptance/person.schema.json -f examples/schema-acceptance/extra-property.json --schema-output json
```

零个 `-f` 表示 stdin，一个 `-f` 表示单文件。顶层字段为 `reportVersion: int`、
`reportType: "validation"`、`schemaFile: string`、`inputFile: string`、`status: string`、
`issues: array`；不含批量结果或统计。该输入的所有问题都在顶层 `issues`。

| 结果 | status | 退出码 |
| --- | --- | --- |
| 符合约束 | `valid` | `0` |
| 普通违规 | `invalid` | `1` |
| 输入读取、解析失败 | `error` | `1` |
| Schema 读取、解析、编译失败或求值无法完成 | `error` | `2` |

Schema 编译先于业务输入读取。`error` 并不总是退出 `2`，需要结合实际进程退出码判断。

最小成功示例（stdout）：

```json
{"reportVersion":1,"reportType":"validation","schemaFile":"examples/schema-acceptance/person.schema.json","inputFile":"<stdin>","status":"valid","issues":[]}
```

失败示例（stderr，退出 `1`）：

```json
{"reportVersion":1,"reportType":"validation","schemaFile":"examples/schema-acceptance/person.schema.json","inputFile":"examples/schema-acceptance/extra-property.json","status":"invalid","issues":[{"stage":"input","kind":"ValidationError","location":"extra","message":"additional property is not allowed"}]}
```

## 3. 批量文件校验

```sh
moonjson-toolkit -v --schema examples/schema-acceptance/person.schema.json -f examples/schema-acceptance/valid.json -f examples/schema-acceptance/valid.json --schema-output json
moonjson-toolkit -v --schema examples/schema-acceptance/batch.schema.json -f examples/schema-acceptance/batch-invalid.json -f examples/schema-acceptance/batch-cycle.json --schema-output json
```

两个及以上 `-f` 使用 `reportType: "batchValidation"`。其他顶层字段为
`reportVersion: int`、`schemaFile: string`、`status: string`、`summary: object`、
`issues: array`、`results: array`；没有顶层 `inputFile`。

`results` 按 `-f` 顺序保留每次输入，重复路径不去重。每项含 `inputFile: string`、
`status: string`、`exitCode: int` 和 `issues: array`。Schema 只编译一次，每个文件独立
求值，某文件失败后仍处理后续文件。文件问题放在对应结果内，不重复加入顶层 `issues`。

`summary` 的五个字段都是非负整数：

| 字段 | 口径 |
| --- | --- |
| `requested` | 指定路径的数量，重复路径分别计数 |
| `processed` | 已尝试处理的文件数，包含读取、解析失败 |
| `valid` | 状态为 `valid` 的文件数 |
| `invalid` | 普通违规文件数 |
| `errors` | 读取、解析、执行失败的文件数 |

`valid + invalid + errors == processed`。Schema 预检查失败时，顶层 `issues` 包含
`stage: "schema"` 的问题，`requested` 保留请求数，其余计数为 `0`，`results` 为空；
不读取业务输入，也不虚构文件结果。

最小成功示例（stdout，退出 `0`；同一路径确实处理两次）：

```json
{"reportVersion":1,"reportType":"batchValidation","schemaFile":"examples/schema-acceptance/person.schema.json","status":"valid","summary":{"requested":2,"processed":2,"valid":2,"invalid":0,"errors":0},"issues":[],"results":[{"inputFile":"examples/schema-acceptance/valid.json","status":"valid","exitCode":0,"issues":[]},{"inputFile":"examples/schema-acceptance/valid.json","status":"valid","exitCode":0,"issues":[]}]}
```

失败示例（stderr，退出 `2`）：

```json
{"reportVersion":1,"reportType":"batchValidation","schemaFile":"examples/schema-acceptance/batch.schema.json","status":"error","summary":{"requested":2,"processed":2,"valid":0,"invalid":1,"errors":1},"issues":[],"results":[{"inputFile":"examples/schema-acceptance/batch-invalid.json","status":"invalid","exitCode":1,"issues":[{"stage":"input","kind":"ValidationError","location":"n","message":"it is a string where the schema expects an integer"}]},{"inputFile":"examples/schema-acceptance/batch-cycle.json","status":"error","exitCode":2,"issues":[{"stage":"evaluation","kind":"ReferenceCycle","location":null,"message":"reference cycle","instancePointer":"/loop","schemaPointer":"/properties/loop/$ref"}]}]}
```

## 4. JSONL 校验

```sh
# 文件输入
moonjson-toolkit -v --schema examples/schema-acceptance/person.schema.json --jsonl -f examples/schema-acceptance/mixed.jsonl --schema-output json
# 最小成功 stdin
printf '%s\n' '{"id":1,"name":"Moon"}' | moonjson-toolkit -v --schema examples/schema-acceptance/person.schema.json --jsonl --schema-output json
# 最小失败 stdin
printf '%s\n' '{"id":1,"name":"Moon","extra":true}' | moonjson-toolkit -v --schema examples/schema-acceptance/person.schema.json --jsonl --schema-output json
```

只允许一个文件或 stdin，多个 JSONL 文件的 JSON 报告会被拒绝。
顶层字段为 `reportVersion: int`、`reportType: "jsonlValidation"`、`schemaFile: string`、
`inputFile: string`、`status: string`、`summary: object`、`issues: array`、`results: array`。

`results` 每项含 `line: int`（从 `1` 开始的实际行号）、`status: string`、
`exitCode: int` 和 `issues: array`。空白行跳过但仍计入行号；每条非空白记录解析后独立
求值，解析、普通违规或执行失败后仍继续处理。`line` 不拼进 `location` 或实例指针。

`summary.records` 为非空白记录数，**包括解析失败的记录**；`valid`、`invalid`、
`errors` 分别计数符合、普通违规及解析/执行失败，四个字段均为非负整数，满足
`valid + invalid + errors == records`。这不是批量文件的 `requested/processed` 统计。
空输入或纯空白输入为 `valid`、退出 `0`，四项计数为零。

Schema 预检查失败或打开输入失败时，问题在顶层 `issues`，四项计数均为 `0`，
`results` 为空。Schema 问题退出 `2`，打开输入失败的 `ReadError` 退出 `1`。
记录内的问题只在对应结果中，实例指针相对于当前记录。

JSONL 文本校验和结构化校验均按块读取文件或 stdin，完整记录形成后立即解析、校验；
JSONL 格式化仍完整读取输入。JSON 汇总报告必须等待正常 EOF 才能确定整份输入的结果，
不会提前输出成功或 JSON 片段。报告结果仍保存在内存中，最长记录、诊断和结果缓冲仍可能
增长；这不是恒定内存处理，也不是流式报告输出。

中途读取失败时，保留此前已完成的记录结果，并在顶层 `issues` 追加 `stage: "input"`、
`kind: "ReadError"`、`location: null` 的问题，顶层 `status` 为 `error`。
`summary.records` 只统计已完成处理的非空白记录，包含这些记录中的解析失败；
顶层读取错误不额外增加记录级 `summary.errors`。尚未完成的尾部不生成结果，
也不会把读取失败当作 EOF 再解析尾部、虚构一个 `ParseError`。
退出码仍按 **2 > 1 > 0** 汇总：没有执行错误时读取失败退出 `1`，已有执行错误时仍为 `2`。
包含完整记录结果和顶层读取错误的一个 JSON 文档写入 stderr，stdout 为空。

最小成功示例（stdout）：

```json
{"reportVersion":1,"reportType":"jsonlValidation","schemaFile":"examples/schema-acceptance/person.schema.json","inputFile":"<stdin>","status":"valid","summary":{"records":1,"valid":1,"invalid":0,"errors":0},"issues":[],"results":[{"line":1,"status":"valid","exitCode":0,"issues":[]}]}
```

失败示例（stderr，退出 `1`）：

```json
{"reportVersion":1,"reportType":"jsonlValidation","schemaFile":"examples/schema-acceptance/person.schema.json","inputFile":"<stdin>","status":"invalid","summary":{"records":1,"valid":0,"invalid":1,"errors":0},"issues":[],"results":[{"line":1,"status":"invalid","exitCode":1,"issues":[{"stage":"input","kind":"ValidationError","location":"extra","message":"additional property is not allowed"}]}]}
```

## 汇总状态与退出码

批量文件和 JSONL 的每项：符合为 `valid/0`，普通违规为 `invalid/1`，输入解析失败为
`error/1`，求值失败为 `error/2`；批量文件读取失败也为 `error/1`。
任一结果为 `error`，顶层状态为 `error`；否则有违规为 `invalid`，全部符合为 `valid`。
退出码优先级为 **2 > 1 > 0**，与输入顺序无关。Schema 预检查失败退出 `2`。
所有输入处理完成后才选择输出流，不能先把成功片段写到 stdout。

JSON 报告模式继续拒绝 AI、统计、变换、其他导出、`--fail-fast` 和
`--continue-on-error`；业务校验允许 `--max-depth` 和 `--no-color`。

## 真实 native CLI 验收与证据

依赖应事先安装。脚本仅使用 Python 标准库，从自身位置定位仓库根目录。
默认只构建一次，固定执行 `moon build --target native --debug --frozen cmd/main`，
随后直接运行 `_build/native/debug/build/cmd/main/main.exe`（MoonBit native 产物名），
不使用 `moon run`、不按修改时间搜索产物，也不访问网络或调用 AI。

```sh
python scripts/check_schema_reports.py
# 使用现有构建，跳过构建步骤；相对路径以仓库根目录解析
python scripts/check_schema_reports.py --cli _build/native/debug/build/cmd/main/main.exe
```

覆盖八组场景：独立检查 `true/false`、单文件违规、单文档 stdin 成功、stdin 解析失败、
Schema 错误优先、执行循环、批量混合结果、JSONL stdin。用例数量按实际执行统计；
本次 Windows native 本地验收为八组、九次 CLI 调用，全部通过；默认构建模式和从仓库外
启动的 `--cli` 模式均已验证，每次独立统计，不把重复执行计成新增场景。
JSONL stdin 包含中文、引号、反斜杠、转义换行、空白行和损坏记录，并确认后续记录继续处理。
这些是本次验收事实，不是报告版本 1 承诺永远固定的验收数量。

每个 CLI 进程超时为 20 秒，构建超时为 300 秒。stdin 显式传入 UTF-8 字节并关闭。
脚本逐例核对真实退出码、两条输出流、完整 JSON 解析、无 ANSI、类别、位置和计数；
不匹配人类可读消息全文，不从真实输出生成预期值。超时、产物不存在、任一断言失败
都会令脚本非零退出，并尽量收集剩余用例的失败。

证据保存在 `_build/schema-report-acceptance/`：每例 `.stdin`、`.stdout`、`.stderr` 原始字节，
默认构建日志 `build.stdout/build.stderr`，以及 `summary.json`、`summary.txt`。
汇总记录命令、预期/实际退出码、失败原因、实际统计、CLI 路径和 SHA-256。
目录被 Git 忽略，不提交机器路径和生成输入，也不自动更新源文件、快照或兼容性基线。

Linux CI **尚未验证**。现有 native job 已接入此脚本，使用同一 job 的 debug 构建并传入
`--cli`，失败时也上传验收目录；原单元测试和标准兼容性门禁保留。只有取得对应提交
的真实 Linux CI 成功结果后，才在交付记录中补充提交 SHA 和成功链接。

本节首次提交后的 Linux 验证进展、实际代码 SHA、日志及产物核对结果见
[结构化报告跨平台复验记录](schema-report-verification.md)。
