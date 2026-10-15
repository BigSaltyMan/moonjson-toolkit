# JSON Schema 复验样例

从仓库根目录运行 `bash scripts/check_schema_acceptance.sh`，九个检查应全部符合预期。需要已安装 MoonBit 工具链与依赖；案例不依赖 AI 或网络。

| 场景 | Schema / 输入 | 退出码 |
| --- | --- | --- |
| 符合 | person.schema.json / valid.json | 0 |
| 额外字段 | person.schema.json / extra-property.json | 1 |
| oneOf 两次匹配 | one-of.schema.json / one-of-overlap.json | 1 |
| 不支持 | unsupported.schema.json / valid.json | 2 |
| 参数非法 | invalid-parameter.schema.json / valid.json | 2 |
| 执行失败 | cycle.schema.json / valid.json | 2 |
| JSONL 混合 | person.schema.json / mixed.jsonl | 1 |
| 批量混合及反向顺序 | batch.schema.json / batch-invalid.json、batch-cycle.json | 2 |

单例（预期的非零退出码表示所演示的失败）：

```bash
moon run --target native cmd/main -- --no-color -v \
  --schema examples/schema-acceptance/person.schema.json \
  -f examples/schema-acceptance/valid.json

moon run --target native cmd/main -- --no-color -v --jsonl --continue-on-error \
  --schema examples/schema-acceptance/person.schema.json \
  -f examples/schema-acceptance/mixed.jsonl

moon run --target native cmd/main -- --no-color -v --continue-on-error \
  --schema examples/schema-acceptance/batch.schema.json \
  -f examples/schema-acceptance/batch-invalid.json \
  -f examples/schema-acceptance/batch-cycle.json
```

JSONL 第 1、3 行符合，第 2 行有额外字段；汇总以文件为单位，所以显示 0 passed / 1 failed。批量的一个文件普通不符合、另一个文件发生执行错误，继续处理后整体退出 2；脚本也检查反向顺序。失败汇总不是“全部匹配”的成功结论。

逐例输出在 `_build/schema-acceptance/`，不会写回源文件、快照或兼容性基线。[整改验收说明](../../docs/schema-remediation.md)区分库和 CLI 的四种结果；[兼容性报告](../../docs/schema-compatibility.md)列出完整支持范围及排除原因。
