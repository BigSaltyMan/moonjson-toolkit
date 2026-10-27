# JSONL 流式输入跨平台复验

核对日期：2026 年 10 月 27 日。结论：开发代码的 Linux native 门禁及四个真实 CLI
场景均通过，下载产物完整，稳定报告字段与 Windows 证据一致。

## 验证对象

- CI 接入及实际验证代码：`610e4cb7467ccaf1f465049996ed5e8de1ac2218`。
- [固定代码](https://github.com/BigSaltyMan/moonjson-toolkit/tree/610e4cb7467ccaf1f465049996ed5e8de1ac2218)。
- [Linux CI #26](https://github.com/BigSaltyMan/moonjson-toolkit/actions/runs/40440053973)，
  run ID `40440053973`，第 1 次运行，push 触发并成功。
- [native job](https://github.com/BigSaltyMan/moonjson-toolkit/actions/runs/40440053973/job/121977986953)。

运行元数据、产物的 `workflow_run.head_sha`，以及 checkout 日志中的 `git log -1 --format=%H`
均对应上述完整 SHA。本记录随后单独提交，**该 CI 不是本记录文档提交本身的验证**。

流式解析、文本输入和结构化输入分别来自开发提交 `00e96a3`、`969fe80`、`76d8d66`。
这些改动尚未发布，不能把它们写成已发布的 `v0.3.1` 已有能力。本笔没有调整版本或发布。

## Windows 证据来源

沿用 Commit 29 的 `_build/jsonl-stream-input-acceptance/` 和 Commit 30 的
`_build/jsonl-stream-report-acceptance/`：两组各 2/2 通过，分别验证保持 stdin 打开时
退出和 EOF 后汇总。原证据已复制到 `_build/jsonl-stream-verification/windows/` 下的
`commit-969fe80-text/`、`commit-76d8d66-report/`，没有覆盖。

原汇总没有单独记录 Git HEAD，其代码归属来自对应开发步骤的执行记录，不能仅凭汇总文件
反推精确 SHA。本笔修改了两份脚本的异常清理，因此仅重跑这两个受影响脚本，各 2/2 通过；
没有重建 Windows CLI，没有运行本地 MoonBit 测试。复跑使用 Commit 30 已构建的 native
CLI，产品实现与本笔验证代码一致。其 SHA-256 为：

```text
d42e22efc270ecf05a0d73aaeb95a30930b08c5c03debbdeece4bf4ee3e7b063
```

复跑证据位于 `windows/ci-setup-text/`、`windows/ci-setup-report/`，另有
`windows/manifest.json` 记录 CLI 和脚本摘要。重复执行分别记录，不算新增场景。

## Linux 实际结果

以下数量来自此次 native job 日志和下载产物，不沿用发布版本的历史数量。

| 检查 | 实际结果 |
| --- | --- |
| native 严格检查 | `moon check --target native --deny-warn` 通过 |
| native 单元测试 | **501/501**，0 失败 |
| native 构建 | `moon build --target native --debug` 通过 |
| 文本 JSONL 流式验收 | **2/2** 通过 |
| JSONL 结构化流式验收 | **2/2** 通过 |
| 原结构化报告验收 | **9/9**，8 组，通过 |
| 原本地 HTTP 服务验收 | **8/8** 通过；不等于真实 AI 服务调用 |
| 原 Schema CLI 示例 | **9 例**通过 |
| 标准测试严格运行 | 462 组、2354 条中，实际执行 **1022 条全部通过** |
| 标准测试其余分类 | 442 条编译拒绝、890 条跳过，不计作通过 |
| 标准测试差异 | 误通过、误拒绝、执行错误均为 0 |
| 兼容性基线 | 分类及逐条诊断与原基线一致，未修改基线 |
| 两份流式验收产物上传 | 均成功，配置为 `if: always()` |

固定工具链记录为：

```text
moon 0.1.20260915 (2e1a46d 2026-09-15)
moonc v0.10.13+cbb11c36f (2026-09-15)
moonrun 0.1.20260915 (2e1a46d 2026-09-15)
Feature flags enabled: rr_moon_mod,rr_moon_pkg
```

工具链和前端 job 未修改。既有前端与文档兼容 job 随本次 workflow 自动运行并通过，
本笔没有额外手动启动它们。没有本地全量、标准兼容性、前端或性能复测。

## 四个进程场景及产物审计

| 场景 | Linux 原始证据确认的行为 |
| --- | --- |
| `fail-fast-before-eof` | 非法记录带 LF；stdin 保持打开，退出 1；stdout 为空，stderr 为第 1 行解析诊断 |
| `schema-check-before-input` | 未发送业务数据且 stdin 保持打开，退出 2；stdout 为空，stderr 为不支持 Schema 的文本诊断 |
| `stdin-segments-then-eof` | 分次写入，UTF-8 字符跨写入，含 CRLF、空白行和无末尾换行记录；EOF 前等待且无输出，EOF 后退出 1；stderr 是一个完整 JSON 文档，stdout 为空 |
| `schema-error-before-input` | stdin 保持打开且无业务数据，退出 2；stderr 是一个完整 JSON Schema 错误报告，stdout 为空 |

分段 JSONL 的行号为 `1/3/4`，结果依次为 `valid/invalid/valid`，记录退出码为 `0/1/0`；
统计为 `records: 3, valid: 2, invalid: 1, errors: 0`。Schema 错误报告为
`UnsupportedFeature`，位置 `unevaluatedProperties`，没有虚构记录。

已下载并逐项检查：

- [文本流式验收产物](https://github.com/BigSaltyMan/moonjson-toolkit/actions/runs/40440053973/artifacts/12705337746)：
  `jsonl-stream-input-acceptance`，6 个成员，含两例原始 stdout/stderr、汇总及 Schema 输入。
- [结构化流式验收产物](https://github.com/BigSaltyMan/moonjson-toolkit/actions/runs/40440053973/artifacts/12705367830)：
  `jsonl-stream-report-acceptance`，7 个成员，含两例原始 stdout/stderr、汇总及两个 Schema 输入。
- [标准测试产物](https://github.com/BigSaltyMan/moonjson-toolkit/actions/runs/40440053973/artifacts/12705287945)：
  标准测试报告、工具链记录和兼容性报告；下载报告的可移植投影再次与仓库基线核对一致。

三个 ZIP 均校验了 GitHub 上传摘要，安全解包到 `_build/jsonl-stream-verification/linux/`。
四个场景无遗漏、无重复、无 `fatal_errors`，没有 ANSI 或额外文本混入 JSON 输出。
Windows/Linux 对照保留版本、类型、状态、计数、顺序、类别及位置，允许 Schema 绝对路径
和人类诊断文案存在平台差异，没有要求原始输出逐字节相同。

本地归档另含 `run.json`、`jobs.json`、`artifacts.json`、`native-job.log`、三个 ZIP 和
`artifact-audit.json`；这些机器证据不纳入源码提交。产物也可从上述 CI 的 Artifacts 区域下载。

## 本笔修复及复现入口

代码检查发现 stdin 写入异常后，清理阶段关闭管道可能再次抛出 `OSError`，使原始输出未能
保存。本笔在 `610e4cb` 中处理该异常，并让文本脚本在异常路径也收集原始输出。
未放宽退出码、保持 stdin 打开、EOF 等待或完整 JSON 解析断言，没有产品平台修复。

CI 两组验收均在同一 native 构建后使用 `--cli`，脚本不重复构建。两步允许在另一组失败后
继续收集各自证据，但没有 `continue-on-error`，任一失败仍使 job 失败。
该固定 MoonBit 工具链在 Linux 也生成 `main.exe` 文件名；实际执行的是 Linux native 产物。
子进程使用参数数组，路径作为单个参数传入，不经 shell 拆分。

本地复现（仓库根目录；已有产物时省略构建）：

```sh
moon build --target native --debug
python scripts/check_jsonl_stream_input.py --cli _build/native/debug/build/cmd/main/main.exe
python scripts/check_jsonl_stream_report.py --cli _build/native/debug/build/cmd/main/main.exe
```

两份脚本各自从自身路径定位仓库根目录，支持 `--cli` 指定已构建产物。
单进程退出等待上限为 10 秒，清理等待为 5 秒；这些是验收超时，不是性能测量。

## 能力边界

文本 JSONL 校验和 JSONL 结构化校验已经逐条读取，JSONL 格式化仍完整读取输入。
内存仍会随最长记录、诊断和报告结果增长。JSON 汇总等待正常 EOF；中途读取失败时
保留已完成记录并报告错误。报告结果仍保存在内存中，尚未实现完整流式输出。
