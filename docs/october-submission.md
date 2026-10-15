# moonjson-toolkit 十月更新申报说明

更新日期：2026-10-15。根据参赛者提供的原申报书，结合当前仓库与本次实际验证更新。原件留在工作区；本公开材料不重复联系方式。功能完成版本为 [c008a03](https://github.com/BigSaltyMan/moonjson-toolkit/commit/c008a035493a0e7c950200c574b864bac6b921e8)，本文件不预填尚未产生的文档提交 SHA。

## 项目与技术方案

- 项目：moonjson-toolkit；参赛者：BigSaltyMan；方向：语言与开发工具 / JSON 处理 CLI。
- 仓库：[BigSaltyMan/moonjson-toolkit](https://github.com/BigSaltyMan/moonjson-toolkit)。根模块 `BigSaltyMan/moonjson-toolkit`，配套前端 `BigSaltyMan/moonjson-dashboard`，当前声明版本均为 `0.1.0`；版本号本身不能证明发布包包含整改代码。
- 许可证：**Apache-2.0**，以根目录 LICENSE、根模块和前端 moon.mod 为准；修正原申报中的 MIT 表述。上游 JSON-Schema-Test-Suite 按其 MIT 许可保留原文；vendored Apache ECharts 的许可保留在前端 public 目录。
- CLI 当前构建、测试和运行目标为 **native**；前端目标为 **JS**，修正原申报“优先 wasm”的描述。
- 前端使用 **Rabbita 和 Apache ECharts**，**warren 用于开发与构建**；修正原依赖清单中的 yuecharts 表述。Rabbita 依赖见 frontend/moon.mod，图表绑定见 frontend/public/charts.js，warren 命令见 frontend/README.md。
- 原申报为原创工具项目，并非整项目移植。核心实现为 MoonBit：有序对象和数字原文解析、格式化、诊断、转换、统计、Schema 编译与校验、依赖分析和 CLI 编排。Nanaloveyuki/parsec 提供严格解析/诊断基础，oboard/mio 用于 AI HTTP 请求，moonbitlang/async 用于异步 I/O；不把使用开源依赖描述为全部从零实现。

项目面向本地格式化、CI 校验、JSONL 日志、数据清洗、模块依赖分析和统计可视化。除明确选择 AI 服务外，核心处理与 Schema 求值只使用本地数据。

## 本期实质整改

原反馈聚焦 Schema 覆盖不足与未支持约束静默放行。已完成约定的 P0/P1/P2：公开接口强制预检查、精确十进制语义、布尔/常量/组合、数值、数组、对象约束、同文档引用、contains、条件、依赖与属性名校验，并建立严格标准测试与循环/预算保护。[整改对照与提交记录](schema-remediation.md)逐项列出证据。

当前是 **JSON Schema Draft 2020-12 明确子集**，不是完整标准实现。支持列表与资源边界见[兼容性报告](schema-compatibility.md)。`format` 仅注解；外部引用、动态引用、$id/锚点、unevaluated*、旧版机制及未列关键词继续提前拒绝。计数参数上限 1,000,000,000；编译快照限制 128 层/100,000 JSON 节点，求值限制 128 层/每条输入 100,000 次访问。

- Schema CLI：0 为完成且符合，1 为普通不符合，2 为编译拒绝或执行错误。读取/JSON 错误仍为 1，命令行错误为 2；产品 AI 调用失败仍为 3。
- 库：只有 `Ok([])` 表示完成且符合；非空违规、`SchemaProblems` 和 `EvaluationFailed` 分别表示不符合、编译问题和执行错误。
- JSONL/批量继续处理时汇总全部失败；执行错误的 2 优先于普通失败的 1。原申报中的多文件写法应改为 `-f a.json -f b.json`，每个文件独立使用一个参数。
- 格式化保留数字原文；Schema 边界、相等和 multipleOf 采用精确十进制。未把该保证扩大到所有数值排序或统计实现。

## 原申报功能核对

下表区分实际运行、单元测试和未验证项目。核对代码基线是 c008a03；本地环境为 Windows Git Bash、固定 MoonBit 工具链。现场 CLI 输出留在 `_build/schema-acceptance/feature-*`；这些是生成证据，重新检出仓库后需按下方命令复现，不作为源码提交。

| 原承诺 | 本次状态与实际证据 | 边界 / 后续 |
| --- | --- | --- |
| 格式化、数字精度、错误定位 | **已运行**：compact 输出保留 `9007199254740993`、`1e-400`、`1.2300`、`1.2e1` 原文及键序；非法 JSON 输出 line 2, column 8 和箭头；重复键同时输出首次位置。对应 feature-format/diagnostic/duplicate 输出及 parser、formatter、diagnostics 回归 | 现有缩进、排序、深度、TTY 控制另由单元测试覆盖；本次不重测性能 |
| JSONL、批量、错误恢复 | **已运行**：JSONL 错行前后合法记录都输出；多文件读入、Schema 混合结果、双向顺序下 2 优先均通过。九例脚本及 feature-jsonl/batch；runner/jsonl 回归覆盖 fail-fast、continue-on-error | 实际多文件语法为重复 `-f`；源码的 4 路 I/O 窗口不等于本次测得 3 倍提速 |
| 清洗、压平与还原 | **已运行**：trim/prune-null/prune-empty/flatten 组合得到 `{"user.name":"Li"}`，unflatten 还原嵌套对象；feature-clean/unflatten 及 prune/flatten/transform 回归 | 点号键冲突等拒绝路径由现有测试覆盖，不承诺所有任意点号键都可无歧义往返 |
| 依赖分析 | **已运行**：读取本仓库 moon.mod 得到依赖树；本地构造 demo/app→a/b→shared 的版本冲突和 a→app 循环均输出警告。feature-dependencies/dependency-warnings；moondeps 回归 | 读取本地已存在的依赖清单；找不到的依赖作为叶节点，不代替包管理器下载或解析全部远端图 |
| 前端统计图展示 | **部分验证**：CLI --json-out 统计文件已生成并核对；独立 JS 模块 check 与 **4/4** 测试通过，覆盖字段解码、分布及发送图表前的数据往返；Rabbita/Apache ECharts 源码与本地资源已核对 | **浏览器实际柱状图/饼图渲染、warren build 本次未验证**。已有截图不是本次浏览器测试证据 |
| AI 配置及错误处理 | **已运行离线错误路径**：清除子进程的密钥配置后调用 --ai，退出 **3** 并提示配置变量；ai/runner 回归覆盖模型、端点、密钥优先级、API 错误信封和无效响应 | **真实 AI 服务调用未验证**。本次没有向任何服务发请求，单元测试通过不表示任意兼容服务均实测通过 |

本次没有因这些探针发现需要修改产品实现的问题。原文的批量参数写法与当前 CLI 不同，已在材料中纠正；若后续要兼容一个 `-f` 后跟多个路径，应另立功能提交。浏览器演示、真实 AI 联调若在后续发现缺陷，单独修复，不以本次材料提交掩盖。

可复制的核心功能核对命令（仓库根目录）：

```bash
printf '%s' '{"z":9007199254740993,"tiny":1e-400,"decimal":1.2300,"exp":1.2e1}' \
  | moon run --target native cmd/main -- --no-color --compact
printf '%s' '{"user":{"name":" Li ","junk":null},"empty":[]}' \
  | moon run --target native cmd/main -- --no-color --trim-strings --prune-null --prune-empty --flatten --compact
printf '%s' '{"user.name":"Li"}' \
  | moon run --target native cmd/main -- --no-color --unflatten --compact
printf '{\n  "a": }\n' | moon run --target native cmd/main -- --no-color -v
moon run --target native cmd/main -- --no-color --moon-deps -f moon.mod
moon run --target native cmd/main -- --no-color -f examples/schema-acceptance/valid.json \
  --json-out _build/schema-acceptance/feature-stats.json
```

非法 JSON 示例预期退出 1。AI 实测不在一键脚本内，避免评审误发请求或依赖私有凭证；前端浏览器复现的开发/构建命令见 [frontend/README.md](../frontend/README.md)。

## 当前测试与历史测量

- 根模块 native 测试合计 **454/454**：主库包 **445**，标准运行器包 **9**；独立前端模块 JS **4/4**。不是原申报的 221 项，也不把标准数据的 2354 条合并到单元测试数。
- 固定上游 SHA `55719286c33ae0d1823bfb65fea10338a19bc37c`：**1022 实际执行并通过、442 编译拒绝、890 跳过**，总计 2354；误通过、误拒绝、执行错误及范围错误均为 0。拒绝/跳过不能计入通过。
- `bash scripts/check_schema_acceptance.sh`：**9 个实际 CLI 场景**，包括四类 Schema 结果、JSONL 和批量优先级；每例核对退出码、关键诊断与成功结论的缺席/存在。
- 工具链：moon 0.1.20260915、moonc v0.10.13+cbb11c36f。Linux CI 使用固定归档与校验摘要，运行 native check/test/build、复验脚本、严格标准测试和基线校验；前端单独执行 JS check/test。

| 历史说法 | 原记录版本 / 环境 | 本次采用口径 |
| --- | --- | --- |
| 原申报覆盖率 94.2% | 当时 221 项测试；测量提交、工具链和环境未记录 | 未重新测量，不作为当前覆盖率 |
| README 覆盖率 95.9%（2558/2667） | 已存在于 c008a03 的 README；真正测量提交和环境未记录 | 是历史输出，不随新增代码自动保持有效 |
| 约 10 MB 格式化 0.30 s、校验 0.25 s | README 记录工具 0.1.0、Ryzen 9 8940HX、WSL2；表中 9.6 MB 为 0.304/0.248 s，best of 3；测量提交与工具链未记录 | 本次未重跑 bench，不作为整改版本性能结果 |
| 小文件批量约 3 倍提速 | 同一 README 的 200×小文件、4 路与 1 路窗口对照；工具 0.1.0、上述 WSL2 环境，测量提交未记录 | 本次仅验证正确性，不重申当前机器有相同倍率 |

完整复现命令、能力边界和提交对照见[整改验收说明](schema-remediation.md)。标准分类与逐条诊断由[已审阅基线](../testdata/schema-suite-baseline.json)检查，CI 不自动重写基线。

## 验证链接与交付状态

- [功能完成提交 c008a03](https://github.com/BigSaltyMan/moonjson-toolkit/commit/c008a035493a0e7c950200c574b864bac6b921e8)及其[实际成功 Linux CI](https://github.com/BigSaltyMan/moonjson-toolkit/actions/runs/38685252852)。
- 本次交付示例的 Linux CI 尚未核验；仅在实际成功后补录链接。
- [兼容性报告](schema-compatibility.md)、[整改验收说明](schema-remediation.md)、[本地样例](../examples/schema-acceptance/README.md)、[一键复验脚本](../scripts/check_schema_acceptance.sh)。
- 远程默认分支是 main，核对时仍指向整改前的 43fb503；功能提交的成功 CI 来自独立验证分支。**本地完成不等于默认分支、发布包和问卷都已更新。** 本次只准备材料；下一步需核对发布包是否包含整改版本，再更新原问卷中的最终代码和验证链接。

## 可复制到原问卷备注的整改摘要

> 十月已完成本项目约定的 JSON Schema P0/P1/P2 整改，功能完成提交 c008a03。所有公开入口强制预检查，未知约束不再静默放行；补齐常用数值、数组、对象、组合、条件、依赖、属性名及同文档引用，提供精确十进制语义、循环检测和求值预算。当前明确为 Draft 2020-12 子集，不声称完整标准兼容。固定版本 2354 条测试中，1022 条实际执行并通过，442 条明确拒绝、890 条跳过，拒绝和跳过不计通过。根模块 native 回归 454 项、前端 JS 4 项通过；一键复验脚本覆盖通过、不符合、不支持/非法参数和执行失败，以及 JSONL、批量退出码优先级。整改对照、原功能核对、实际 CI 及复现入口见 docs/schema-remediation.md、docs/october-submission.md 和 docs/schema-compatibility.md。真实 AI 服务调用与本次浏览器图表渲染未验证；发布包、默认分支和问卷最终链接仍待下一步核对更新。
