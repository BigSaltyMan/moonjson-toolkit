# moonjson-toolkit 0.3.2

这是 `v0.3.1` 之后的修复版本，当前处于发布准备阶段。尚未上传 Mooncakes，未创建
`v0.3.2` 标签或 GitHub Release。平台文档构建、注册表下载及消费尚未执行。

## 变更范围

- `--sort-by` 复用精确十进制比较，正确排列超出浮点范围的大数、极小数及指数数字。
  数学上相等的数字保持原有相对顺序，排序不改写数字原文。
- `--indent`、`--max-depth` 在整数累加运算前检查溢出，不再允许超长十进制参数回绕。
  原有正负号、前导零和参数范围保持不变；参数错误仍先于业务输入操作。
- JSONL 记录逐条解析，CLI 不再保留全部业务解析树和额外的完整行号数组。
- JSONL 文本校验、结构化校验和格式化均逐条读取文件或 stdin，共用现有记录处理逻辑。
  文本格式化与校验的 `--fail-fast` 可在 stdin EOF 前结束，并保留已完成记录的输出。
- 三种模式共六个真实 native CLI 场景已进入 Linux CI，覆盖保持 stdin 打开、Schema
  预检查、分段 UTF-8 输入及 EOF 后汇总。最终版本提交的验证结果另行记录。

对应开发提交：`ff56a33`、`b0183ab`、`00e96a3`、`969fe80`、`76d8d66`、`8e86f42`；
CI 接入与历史复验见[JSONL 流式输入复验记录](jsonl-stream-verification.md)。
历史 `f232f3f` 的成功 CI 不作为本版本最终代码的验证结果。

## 兼容性和内存边界

- 产品库公开 API 不变，软件版本为 `0.3.2`；报告 `reportVersion` 仍为 `1`。
- 没有新增 JSON Schema 关键字，仍支持 Draft 2020-12 的明确子集，未支持能力仍提前拒绝。
- 四种报告字段和退出码保持既有契约，详见[报告格式](schema-report-format.md)及
  [历史跨平台报告复验](schema-report-verification.md)。
- `--unique` 仍使用既有按序列化内容去重的语义，本次没有调整。
- 漂亮打印、紧凑输出、数字原文、记录顺序及错误恢复行为保持不变。
- 格式化输出、诊断和 JSON 汇总结果仍有内存缓冲；JSON 报告在输入结束或读取失败后
  一次性输出。最长记录和累计输出仍可能占用较多内存，尚未实现流式输出。
- 没有测量本版本的内存降幅、吞吐量或性能提升百分比，不提供此类推断数据。
- 根许可证为 Apache-2.0，第三方许可证保持原样；没有重新引入旧 HTTP/压缩依赖链。

## 最小使用示例

```sh
moonjson-toolkit --version
printf '%s\n' '[1e500,1e400]' | moonjson-toolkit --sort-by '' --compact
cat data.jsonl | moonjson-toolkit --jsonl --compact --fail-fast
moonjson-toolkit -v --jsonl --schema schema.json -f data.jsonl --schema-output json
```

## 准备阶段验证

本地 `moon info`、`moon fmt`、native 严格检查和 `git diff --check` 通过。
现有 `the version line reads as documented`、`the version constant matches moon.mod`
两项版本定向测试各 1/1 通过；未运行本地全量测试，未新增重复的版本用例。

### 发布代码与 Linux CI

版本准备代码：`174af39b5f5d6d49a612605ba36770cf4637d991`。
[Linux CI #30](https://github.com/BigSaltyMan/moonjson-toolkit/actions/runs/40488840658)
实际检出该 SHA，所有 job 通过：

- native 严格检查、构建及 **504/504** 测试通过。
- JSONL 文本校验、结构化报告和格式化三组真实 CLI 验收各 **2/2** 通过。
- 原有结构化报告 **9/9**、HTTP 回环服务验收 **8/8**、Schema 示例 **9 例**通过。
- 标准测试 462 组、2354 条中，实际执行并通过 **1022 条**，编译拒绝 442 条、
  跳过 890 条；误通过、误拒绝、执行错误均为 0，分类和逐条诊断匹配原基线。
- 固定开发工具链为 `moon 0.1.20260915` / `moonc v0.10.13+cbb11c36f`。
  独立文档兼容和原有前端 job 保留配置并自动通过，未额外手动运行前端测试。

本节是成功后补充的证据记录，和上述发布代码提交分开；不把 #30 的结果直接归给
后续文档提交，也不沿用历史 `f232f3f` 的成功记录。

### 实际 ZIP、干净文档和外部消费

首份实际包从上述已提交代码通过 `git archive` 导出独立临时目录，随后执行
`moon package`，没有从带有无关修改的开发工作区打包，也没有执行 `moon publish`。
包成员逐项与导出提交核对，根 README 在独立导出中实体化为完整发布文档，开发工作区的
`README.md` 保持原状。Apache-2.0、上游标准测试及前端第三方许可证原文均保留。
未发现本地申报书、联系方式、凭据、构建证据或依赖缓存；README 链接与必需源码已检查。

使用实际 ZIP 解包内容完成 native 构建，`--version` 显示 `0.3.2`；最小独立 Schema
检查成功，`reportVersion` 保持 `1`。临时外部项目通过 workspace 明确指向解包内容，
三项原有消费检查 **3/3** 通过：支持的 Schema 编译并校验、普通违规列表、未支持约束拒绝。
依赖树核对为包内代码，不使用仓库源码路径或已发布旧版本缓存。这是**干净包消费**，
不是注册表消费。本地未运行全量、完整兼容性、前端或性能测试。

从实际 ZIP 另行解包干净文档目录，复用已有隔离工具链
`moon 0.1.20261020` / `moonc v0.10.16+b1a0e846e` 重新解析依赖并生成文档。
文档索引、完整 README 和源码资产均非空，依赖树没有 `oboard/mio`、
`bikallem/compress`、`bikallem/blit`，没有旧 `moon.mod.json` 依赖清单。
这只是干净包的文档预检查，不冒充 Mooncakes `0.3.2` 平台构建。

本节补充内容会进入包，故文档提交后重新生成并核验最终 ZIP。最终打包来源 SHA、
文件清单、字节数、SHA-256、命令和检查结果保存在 `_build/release-audit-0.3.2/`，
并在准备完成回报中给出；首份包的旧摘要不作为重打包后的摘要。
发布代码 SHA、后补文档 SHA 和最终 ZIP 来源分别记录，不把包自身摘要反写进包内文档。

## 尚未执行的发布动作

- 上传 Mooncakes `0.3.2`：尚未执行。
- Mooncakes `0.3.2` 平台文档构建及页面验收：尚未执行。
- 注册表实际 ZIP 下载及精确版本消费：尚未执行。
- 创建和推送 `v0.3.2` 标签：尚未执行。
- 创建 GitHub Release：尚未执行。
