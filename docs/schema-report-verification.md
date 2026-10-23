# Schema 结构化报告跨平台复验记录

核对日期：2026 年 10 月 23 日。结论：指定代码提交的 Linux native 门禁、真实 CLI
验收和产物审计均通过，九个场景的稳定报告字段与已有 Windows 证据一致。

## 被验证的代码与证据来源

| 项目 | 实际记录 |
| --- | --- |
| 仓库 | [BigSaltyMan/moonjson-toolkit](https://github.com/BigSaltyMan/moonjson-toolkit) |
| 被验证的完整代码 SHA | `c8b4b2b39026153b836444d1f8c84e4569df198c` |
| Actions 运行 | [CI #21，运行 ID 39929569486](https://github.com/BigSaltyMan/moonjson-toolkit/actions/runs/39929569486) |
| 事件及尝试 | `push`，attempt `1` |
| Linux native job | [check-and-test，job ID 120334196207](https://github.com/BigSaltyMan/moonjson-toolkit/actions/runs/39929569486/job/120334196207) |
| 执行环境 | GitHub-hosted Ubuntu 24.04.5 LTS，Linux x86_64 |
| 工作流 | 该代码 SHA 下的 `.github/workflows/ci.yml` |

开始时按完整 SHA 查询 Actions，未发现对应运行；远程 `main` 当时为
`e771ce3c8b49d1df2789c6fc1f99d44f666a1350`。确认它是本地代码提交的祖先后，正常推送
上述代码 SHA 到 `main`，触发现有 CI，没有强制推送或改动门禁。

本记录核对了三处 SHA：Actions run 的 `head_sha`、native job 的 `head_sha`，以及
checkout 日志中 `git log -1 --format=%H` 的实际输出，三者均为
`c8b4b2b39026153b836444d1f8c84e4569df198c`。结论不依赖分支当前指向或最新绿色记录。
**本文是随后新增的文档提交，上述 CI 通过不等于本文所在文档提交已运行 CI。**

## Windows：复用已有本地证据

Windows 结果来自 Commit 20 的本地验收记录和现存
`_build/schema-report-acceptance/`，本笔没有重新启动 Windows CLI。
已有 `summary.json` 记录 `--cli` 模式，`summary-default.json` 记录默认构建模式；
两者分别为八组、九次 CLI 调用，9/9 通过。仓库外启动的 `--cli` 模式也已在该笔核对。

这些文件没有单独保存运行时的 Git HEAD，不能仅凭摘要反推出当时的 checkout SHA。
其来源是 Commit 20 提交前的本地工作树；从产品代码提交
`32c0cf955fabaf9ed28f38240ac6d85b0dcf0dfc` 到被验证提交 `c8b4b2b...`，只有契约文档、
验收脚本、README 和 CI 发生变化，MoonBit 产品实现未改变。Windows 证据与 Linux
精确 SHA 证据分开记录，不把二者混作一次运行。

Windows CLI SHA-256：

```text
038943df96762c6b2e532ea9d01109731c027e11c9c3c4c856311c2f582e1fec
```

本笔先将已有证据复制到 `_build/schema-report-verification/windows/`，再进行 Linux
下载和离线对照，没有覆盖原 Windows 验收目录。

## Linux native 门禁的实际结果

以下均来自指定 run 的 job 步骤状态、完整日志及上传产物，没有沿用历史测试数量。

| 现有检查 | 实际结果 |
| --- | --- |
| 固定工具链安装与版本记录 | 通过，归档的 `toolchain.txt` 存在 |
| `moon check --target native --deny-warn` | 通过 |
| `moon test --target native` | **481 项，481 通过，0 失败** |
| `moon build --target native --debug` | 通过 |
| 真实 CLI 结构化报告验收 | **八组、9/9 通过** |
| 原 Schema CLI 验收示例 | **9 例通过**，与上述结构化报告验收分开统计 |
| JSON Schema 标准测试严格运行 | 通过，退出 `0` |
| 兼容性基线检查 | 通过，分类与逐条诊断匹配原基线 |
| 三项验收/标准测试产物上传 | 全部通过 |

归档的工具链原文：

```text
moon 0.1.20260915 (2e1a46d 2026-09-15) ~/.moon/bin/moon
moonc v0.10.13+cbb11c36f (2026-09-15) ~/.moon/bin/moonc
moonrun 0.1.20260915 (2e1a46d 2026-09-15) ~/.moon/bin/moonrun
Feature flags enabled: rr_moon_mod,rr_moon_pkg
```

标准测试产物记录：462 组、2354 条，其中执行 1022 条且全部通过，442 条编译拒绝，
890 条明确跳过；误通过、误拒绝、执行错误均为 `0`。这是支持子集的验证结果，
不表示完整实现标准。下载报告的可移植投影另与仓库原基线核对一致，未更新基线。

前端 job 保留原配置，由这次现有工作流自动执行并通过；本笔没有手工启动前端测试，
也没有为本次复验增加新的 Linux 命令集或测试矩阵。

## 结构化报告产物与跨平台对照

Linux 脚本使用 native job 已构建的可执行文件：

```text
python3 scripts/check_schema_reports.py --cli _build/native/debug/build/cmd/main/main.exe
```

产物中的 `build` 为 `null`，确认脚本没有重复构建。Linux CLI SHA-256：

```text
51ff4ce5767f638bb37aac83f7be77f354002595234828fee58a66c90c3d0c23
```

Windows/Linux 可执行文件不同，不比较二进制哈希是否相同。哈希用于识别各自验收产物。

下载并核对 `schema-report-acceptance` 后，确认 `summary.json` 为八组、九例，
九个预期场景全部出现且无重复、无提前退出、无 `fatal_errors`，每例均有
`.stdin`、`.stdout`、`.stderr` 原始字节及真实进程退出码：

| 场景 | 实际结果 |
| --- | --- |
| `check-true`、`check-false` | 均为 `supported`，退出 `0`，保留独立检查原格式 |
| `single-invalid` | `invalid`、`ValidationError`、位置 `extra`，stderr，退出 `1` |
| `stdin-valid` | 实际 UTF-8 stdin，`inputFile: "<stdin>"`，stdout，退出 `0` |
| `stdin-parse` | `ParseError`、`stage: "input"`，stderr，退出 `1` |
| `schema-first` | 不存在的输入配合不支持约束，先报 `UnsupportedFeature`，退出 `2` |
| `cycle` | `ReferenceCycle`，`instancePointer: ""`、`schemaPointer: "/$ref"`，退出 `2` |
| `batch-mixed` | 依次为 `invalid/error/valid`，文件退出码 `1/2/0`；计数 `3/3/1/1/1`，整体退出 `2` |
| `jsonl-stdin` | 实际行号 `1/3/4/6`；四条记录中两条符合、一条违规、一条解析失败；整体退出 `1` |

批量五项计数按 `requested/processed/valid/invalid/errors` 顺序列出。
JSONL 的解析错误位于原输入第 `4` 行，诊断行号也为 `4`，其后第 `6` 行正常处理。
循环问题保留两个指针，批量循环的指针为 `/loop` 和 `/properties/loop/$ref`。

对 Windows 归档和 Linux 下载产物分别做离线审计：

- 对照原验收脚本中明确写定的预期用例、退出码和关键字段，不从输出生成预期值。
- 核对每例 stdin 原始字节与预期一致；实际 stdin 执行的结果同时由对应 CI 日志确认。
- 核对成功时 stderr 为空、失败时 stdout 为空，选定流整体解析为一个 JSON 文档，
  无额外文本、第二个文档或 ANSI 转义。
- 对比 `reportVersion`、`reportType`、状态、阶段、类别、退出码、统计、结果顺序、
  显示位置和两个指针；中文、引号、反斜杠和换行组成的字段名往返一致。
- 仅忽略 `message` 文案差异，并允许 `schemaFile/inputFile` 的路径分隔符差异；
  没有忽略类别、位置、指针或输出流。其他稳定字段九例全部一致。

本次未发现跨平台产品缺陷、脚本路径错误、UTF-8 或 stdin 差异，**没有修复提交**。
未放宽断言、跳过失败场景、修改报告版本/字段、更新快照或修改兼容性分类与基线。

## 证据定位与归档

在 [Actions 运行页](https://github.com/BigSaltyMan/moonjson-toolkit/actions/runs/39929569486)
底部 Artifacts 可定位以下上传产物；下载需相应 GitHub 访问权限，且产物需尚未过期：

| 产物 | ID / 链接 | 内容 |
| --- | --- | --- |
| `schema-report-acceptance` | [12491385951](https://github.com/BigSaltyMan/moonjson-toolkit/actions/runs/39929569486/artifacts/12491385951) | 九例原始输入/输出和结构化汇总 |
| `schema-suite-reports` | [12491625215](https://github.com/BigSaltyMan/moonjson-toolkit/actions/runs/39929569486/artifacts/12491625215) | 标准测试 JSON、工具链版本、兼容性报告 |
| `schema-acceptance-outputs` | [12491605218](https://github.com/BigSaltyMan/moonjson-toolkit/actions/runs/39929569486/artifacts/12491605218) | 原有九例 CLI 示例证据 |

本笔下载了前两项 ZIP，其 SHA-256 与该 job 上传日志完全一致：

```text
schema-report-acceptance.zip
37b27ce69b7fa6d5d8100deda8ffa1378a9405459c4871261b69a20b86b06b24

schema-suite-reports.zip
56f5549ffe5ad7149d93195f18602c10a409d771d73383883a8afe6df2395136
```

本地忽略目录 `_build/schema-report-verification/` 保留：

- `windows/`：复制的已有 Windows 证据。
- `linux/`：下载的结构化报告产物。
- `linux-suite/`：下载的标准测试与工具链产物。
- 两个原始 ZIP、`run.json`、`jobs.json`、`artifacts.json` 和 `native-job.log`。
- `artifact-audit.json`：九例稳定字段对比及基线核对结果；临时审计脚本不启动 CLI。

这些下载与审计材料不纳入产品包或通用测试框架，不覆盖仓库源文件和既有 Windows 输出。

## 复现入口与本笔范围

以下为后续本地复现入口，本笔没有重新执行 Windows 验收：

```sh
python scripts/check_schema_reports.py
# 已有同版本 native 构建时：
python scripts/check_schema_reports.py --cli _build/native/debug/build/cmd/main/main.exe
```

Linux 复现使用现有 CI 工作流的 push 或 `workflow_dispatch` 入口，事后核对目标 SHA、
job 日志及产物，不另建一套 Linux 门禁。

本笔只提交这份复验记录及契约文档中的链接。没有重复 Windows `moon info`、`moon fmt`、
编译、单元测试或 CLI 验收，没有手工运行前端或性能测试，没有修改申报书或发布 Mooncakes。
本地仅做已有证据读取、Linux 产物离线审计和 Git 差异检查。产品库公开 API 无变化。
