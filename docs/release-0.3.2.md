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
实际 ZIP 审计、干净包构建、文档生成、三项外部消费和最终 SHA 的 Linux CI 尚待完成，
取得实际结果后另行记录。不把干净包的本地消费称作注册表消费。

## 尚未执行的发布动作

- 上传 Mooncakes `0.3.2`：尚未执行。
- Mooncakes `0.3.2` 平台文档构建及页面验收：尚未执行。
- 注册表实际 ZIP 下载及精确版本消费：尚未执行。
- 创建和推送 `v0.3.2` 标签：尚未执行。
- 创建 GitHub Release：尚未执行。
