# moonjson-toolkit 0.3.0 发布准备

本次为 `BigSaltyMan/moonjson-toolkit` 准备 `0.3.0`，根模块采用 Apache-2.0。
这里只完成发布准备；未上传 Mooncakes，未创建发布标签或 GitHub Release。
依赖版本和前端模块版本保持不变，不新增产品库公开 API。

## 新增能力

- `--check-schema`：独立读取、解析和编译 Schema，不读取业务 JSON。
  `true`、`false` 都可以编译成功；成功不表示所有业务数据都会符合。
- `--schema-output text|json`：默认文本输出，JSON 模式可供脚本和编辑器集成。
- 四种结构化报告：Schema 独立检查、单文档校验、批量文件校验、单输入 JSONL 校验。
  批量和 JSONL 会继续处理全部输入，并按输入顺序保存结果。
- 区分 Schema、业务输入和求值执行问题，保留类别、显示位置，以及执行错误中的两个指针。
  JSONL 保留实际行号，每条记录独立解析和求值。
- 真实 native CLI 验收通过进程退出码、UTF-8 stdin、stdout/stderr 和完整 JSON 文档
  检查机器集成行为，并保存原始输入输出及汇总证据。

## 最小使用示例

```sh
moonjson-toolkit --check-schema schema.json --schema-output json

moonjson-toolkit -v --schema schema.json \
  -f data.json --schema-output json

moonjson-toolkit -v --schema schema.json \
  -f first.json -f second.json --schema-output json

moonjson-toolkit -v --schema schema.json \
  --jsonl -f data.jsonl --schema-output json
```

成功报告写入 stdout，失败报告写入 stderr，另一输出流为空。退出码为 `0`（成功）、
`1`（输入问题或普通违规）、`2`（Schema 或求值问题），汇总优先级为 `2 > 1 > 0`。
Schema 独立检查成功退出 `0`，检查失败退出 `2`。参数错误和模式冲突仍可能使用普通文本，
消费者应先检查退出码，再严格解析选定流，不能把所有 stderr 无条件当作 JSON。

完整字段、问题类别、统计口径和版本兼容规则见
[结构化报告契约](schema-report-format.md)，不在此重复协议。

## 支持边界

- 仍以 JSON Schema Draft 2020-12 的明确子集为范围，本轮报告功能没有增加 Schema 关键字。
  未支持约束继续明确拒绝，不能静默放行。
- 仍不支持多个 JSONL 文件组合的 JSON 报告；JSONL 报告本身是一个汇总 JSON 文档，
  不是按记录输出的 NDJSON。
- 普通 `location` 沿用显示路径，不是 JSON Pointer；执行问题中的 `instancePointer`、
  `schemaPointer` 才是 JSON Pointer，JSONL 实例位置相对于当前记录。
- 软件版本为 `0.3.0`，结构化报告的 `reportVersion` 继续为 `1`，二者独立。
- 报告和验收结果不代表完整的标准兼容性认证。

## 验证与发布准备证据

已有跨平台记录见 [Linux 复验记录](schema-report-verification.md)。其中
[CI #21](https://github.com/BigSaltyMan/moonjson-toolkit/actions/runs/39929569486)
实际验证的代码 SHA 为 `c8b4b2b39026153b836444d1f8c84e4569df198c`：native 测试
481/481、真实 CLI 验收八组 9/9，标准测试执行 1022/1022 并与原基线一致。
Windows 结果使用当时的本地证据，来源与限制在复验记录中说明。
这些是历史证据，**不是 `0.3.0` 最终发布准备提交的 Linux CI 结论**。

本次最终代码 SHA、CI 链接及实际包清单、大小、SHA-256、README/许可证检查、干净目录构建
和外部消费结果，单独保存在 `_build/release-audit/` 并在交付回报中列明。
只在对应最终提交的 CI 实际通过后，才将该提交称为已验证的发布候选。

打包使用当前工具链实际支持的 `moon package`，不执行 `moon publish`。发布源从本次
已提交内容导出到仓库之外的独立临时目录，避免工作区无关改动或父目录忽略规则影响包内容。
发布目录中的 README 根据模块配置准备，再检查真实 ZIP 中的文本和本地链接。
第三方来源及其许可证保持原样，不把上游 MIT 文本替换为项目的 Apache-2.0。

外部消费使用当前工具链支持的
[moon.work 本地模块工作区](https://docs.moonbitlang.com/en/latest/toolchain/moon/workspace.html)，
明确依赖准备发布的 `0.3.0` 源内容，不使用已发布版本的缓存替代本地模块。

本地仅运行现有版本同步定向测试、native 严格检查和指定差异检查；干净目录构建、最小
CLI 命令和外部消费另行记录，不混称为全量回归。历史性能、兼容性和发布记录中的原版本
保留，不通过全局替换改写历史。
