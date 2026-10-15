# JSON Schema 整改验收说明

更新日期：2026-10-15。功能完成版本：[c008a03](https://github.com/BigSaltyMan/moonjson-toolkit/commit/c008a035493a0e7c950200c574b864bac6b921e8)。

P0、P1、P2 完成表示**本项目约定的整改范围完成**，不表示完整支持 JSON Schema Draft 2020-12，也不替代评审结论。当前仍是明确列出的 Draft 2020-12 子集；超出能力在编译阶段明确拒绝。

## 原反馈与整改结果

原反馈由参赛者提供：JSON Schema 常用约束覆盖不足，未支持的约束被忽略，可能把不符合要求的数据判为通过。原申报功能另见[更新后的申报说明](october-submission.md)中的逐项核对。

| 原问题 | 已完成整改 | 验证依据 |
| --- | --- | --- |
| 未支持约束被忽略 | 所有公开校验入口强制编译预检查；完整检查未选中分支和未访问位置 | `unsupported` 示例退出 2；库返回 `SchemaProblems`，不会得到 `Ok([])` |
| 常用关键词覆盖不足 | 完成约定的 P1、P2：组合、对象、数组、条件、依赖与属性名 | 下方能力表、454 项回归及[兼容性报告](schema-compatibility.md) |
| 数值处理可能失真 | Schema 数字按原文做精确十进制比较和倍数判断；指数使用 BigInt，不展开巨大十次幂 | `schema_number_wbtest.mbt`、`schema_wbtest.mbt`、`schema_test.mbt` 的指数、大数、边界和倍数断言 |
| 引用可能无法完成 | 同文档 JSON Pointer 引用、活动引用检测、深度与访问预算；属性名有独立求值身份 | `reference-cycle` 示例退出 2；`schema_ref_wbtest.mbt` 检查循环、超限与上下文恢复 |
| 缺少标准兼容性证据 | 固定上游数据、逐组声明范围、严格运行、跨平台逐条诊断基线 | 固定上游 SHA、严格报告、`check_schema_suite_report.py` 和 Linux CI |

严格拒绝未知关键词是本项目避免误用的产品策略，不声称所有 JSON Schema 实现都必须拒绝未知扩展。

## 完成记录

| 提交 | 范围 |
| --- | --- |
| [372781a](https://github.com/BigSaltyMan/moonjson-toolkit/commit/372781a) | P0：强制预检查、结构化失败、CLI 与库一致 |
| [0079f5a](https://github.com/BigSaltyMan/moonjson-toolkit/commit/0079f5a) | P0：指数整数、大数比较、精确相等与计数参数 |
| [e923d79](https://github.com/BigSaltyMan/moonjson-toolkit/commit/e923d79) | 布尔 Schema、const、组合及额外属性 |
| [186973c](https://github.com/BigSaltyMan/moonjson-toolkit/commit/186973c) | 独占边界、精确 multipleOf |
| [404be7c](https://github.com/BigSaltyMan/moonjson-toolkit/commit/404be7c) | 数组长度、唯一性、2020-12 元组 |
| [c815d70](https://github.com/BigSaltyMan/moonjson-toolkit/commit/c815d70) | 对象数量、模式属性与正则编译复用 |
| [33c4370](https://github.com/BigSaltyMan/moonjson-toolkit/commit/33c4370) | 同文档引用和递归保护 |
| [19ae3ee](https://github.com/BigSaltyMan/moonjson-toolkit/commit/19ae3ee) | 固定标准测试、清单、严格报告及 CI 基线 |
| [33bbdb4](https://github.com/BigSaltyMan/moonjson-toolkit/commit/33bbdb4) | contains 及匹配数量限制 |
| [6717af0](https://github.com/BigSaltyMan/moonjson-toolkit/commit/6717af0) | if/then/else 条件分支 |
| [6dada59](https://github.com/BigSaltyMan/moonjson-toolkit/commit/6dada59) | dependentRequired、dependentSchemas |
| [c008a03](https://github.com/BigSaltyMan/moonjson-toolkit/commit/c008a03) | propertyNames，完成本次 P0/P1/P2 功能范围 |

历史规划 `october-schema-remediation-plan.md` 保留原状；它记录的是整改前的问题与计划，不作为当前完成状态的证明。

## 当前支持范围与限制

| 能力 | 已支持 |
| --- | --- |
| Schema 形态 | 对象、布尔 Schema |
| 基础 | type（含数学整数）、enum、const |
| 数值 | minimum、maximum、exclusiveMinimum、exclusiveMaximum、multipleOf；精确十进制语义 |
| 字符串 | minLength、maxLength、pattern |
| 数组 | prefixItems、items、minItems、maxItems、uniqueItems、contains、minContains、maxContains |
| 对象 | required、properties、patternProperties、additionalProperties、minProperties、maxProperties、dependentRequired、dependentSchemas、propertyNames |
| 组合、条件 | allOf、anyOf、oneOf、not、if、then、else |
| 本地引用 | $defs、同文档 # 或 #/ JSON Pointer $ref；$ref 同级约束仍执行 |
| 版本、注解 | 支持声明的 https://json-schema.org/draft/2020-12/schema URI；缺省按本子集处理。title、description、$comment、default、examples、format 按约定形状接受 |

- `format` 仅为注解，不断言 email 等格式；`default` 不改写输入。
- 未支持：unevaluatedItems、unevaluatedProperties、外部或跨文件引用、$id、命名锚点、动态引用、词汇表机制、旧版 dependencies/additionalItems 和其他未列出的关键词或版本。
- 正则是明确子集：字面量、点、字符类、普通组、分支、重复及锚点。环视、反向引用等机制明确拒绝，不宣称完整 ECMA-262。
- 长度、数量参数上限为 1,000,000,000；超限属于 `UnsupportedFeature`，负数或非整数属于 `InvalidSchema`。
- 编译快照：最大 JSON 深度 128、最多 100,000 个 JSON 节点（含注解）。每条输入的求值：最多 128 层活动 Schema、100,000 次节点访问。所有分支、元素和属性名共享预算。
- 同实例循环、深度或访问超限是执行错误；普通分支不匹配不能吞掉这些错误。属性名错误使用所属对象的真实 Pointer，消息注明名称，不虚构属性名 Pointer。
- `uniqueItems` 复用精确深层相等，最坏做二次数量的元素比较；格式化保留数字原文。数据排序不在本次精确 Schema 数值承诺内。

## 库与 CLI 结果语义

| 结果 | 库接口 | Schema CLI |
| --- | --- | --- |
| 完成且符合 | `validate_schema` 或编译后校验返回 `Ok([])` | 退出 0，输出匹配结论 |
| 完成但不符合 | `Ok(非空 SchemaError 数组)` | 退出 1，给出实例位置和违规原因 |
| Schema 无效、未支持关键词/版本 | `compile_schema` 返回 `Err(Array[SchemaProblem])`；直接校验返回 `Err(SchemaProblems(...))` | 退出 2，在读取业务输入前拒绝 |
| 校验无法完成 | 编译后校验返回 `Err(SchemaEvaluationError)`；直接校验返回 `Err(EvaluationFailed(...))` | 退出 2，包含循环/资源限制类别及 Schema、实例位置 |

`SchemaProblemKind` 区分 `InvalidSchema`、`UnsupportedFeature`、`UnsupportedVersion`。`CompiledSchema` 只能由成功编译获得，并保存隔离快照。所有分支完整预检查，只有符合触发条件的分支在运行时执行。

单文件失败不输出成功结论。`--continue-on-error` 的 JSONL/批量模式可以向 stdout 输出失败汇总，具体错误写入 stderr；不能把汇总误读为成功。批量继续处理时，任何执行失败的退出码 2 优先于普通失败的 1。产品其他模式另有 AI 失败退出码 3，不属于标准测试运行器的退出码。

## 复验示例

```bash
bash scripts/check_schema_acceptance.sh
```

脚本从自身位置定位仓库，可在任意工作目录调用；要求已安装工具链和项目依赖。它只读取本地样例，构建/调用 native CLI，不访问 AI 或远程 Schema。输出位于 `_build/schema-acceptance/`，每例保留 stdout、stderr 和实际/预期退出码；构建失败或任何结果不符都会使脚本失败。

| 示例 | 预期 | 关键证据 |
| --- | --- | --- |
| valid | 0 | 合法 person Schema 和数据匹配 |
| extra-property | 1 | extra 属性被 additionalProperties:false 拒绝 |
| one-of-overlap | 1 | 同时匹配两个 oneOf 分支 |
| unsupported | 2 | unevaluatedProperties 不支持 |
| invalid-parameter | 2 | minLength 为负数 |
| reference-cycle | 2 | 同实例 $ref 循环 |
| mixed-jsonl | 1 | 第 2 行不符合；第 1、3 行通过，按文件汇总为失败 |
| mixed-batch、reversed-batch | 均为 2 | 普通失败与执行失败同时出现；调换顺序仍以 2 为整体结果 |

具体文件和单例命令见[样例说明](../examples/schema-acceptance/README.md)。批量参数按当前 CLI 写成 `-f a.json -f b.json`，不是一个 `-f` 后跟多个裸路径。

## 测试证据与复现命令

本地 Git Bash：根模块 native 合计 **454/454**（根库包 445，标准运行器包 9）；独立前端模块 JS **4/4**。本次不改产品逻辑、不更新快照或标准测试基线。

固定标准数据来自 [JSON-Schema-Test-Suite](https://github.com/json-schema-org/JSON-Schema-Test-Suite/tree/55719286c33ae0d1823bfb65fea10338a19bc37c) 的完整提交 `55719286c33ae0d1823bfb65fea10338a19bc37c`。MIT 许可证、原始字节与摘要留在 `testdata/json-schema-suite/`。

2354 条中：**1022 条实际执行并通过、442 条按明确能力限制编译拒绝、890 条明确跳过**。误通过、误拒绝、执行错误、范围错误均为零。**拒绝和跳过不计作标准测试通过数。** 每项分类和原因见[兼容性报告](schema-compatibility.md)、清单与 CI 的 JSON artifact。编译拒绝不会当作上游 `valid:false` 的一次通过。

```bash
bash scripts/check_schema_acceptance.sh
moon check --target native --deny-warn
moon test --target native
moon build --target native
moon run --target native cmd/schema_suite -- \
  --manifest testdata/schema-suite-manifest.json \
  --report-json _build/schema-suite/report.json \
  --report-md _build/schema-suite/acceptance-report.md --strict
python scripts/check_schema_suite_report.py
(cd frontend && moon check --target js --deny-warn && moon test --target js)
moon info && moon fmt
git diff --check
```

Linux 可用 `python3` 代替 `python`。CI 固定工具链为 moon 0.1.20260915、moonc v0.10.13+cbb11c36f，安装归档及摘要见 `scripts/install_pinned_moonbit.sh`；Windows 本地验证使用相同版本。首次准备依赖可在根模块和 frontend 分别执行 `moon update`，标准测试及样例本身不在运行时下载数据。

- 功能完成版本的[成功 Linux CI](https://github.com/BigSaltyMan/moonjson-toolkit/actions/runs/38685252852) 已验证 native、前端、严格标准测试和逐条诊断基线。
- 本次交付示例的 Linux CI 尚未核验；仅在实际成功后补录链接。
- CI 在失败时也上传 `schema-suite-reports` 和 `schema-acceptance-outputs`，保留诊断而非只展示通过数量。

当前远程默认分支为 main，但本地整改提交并不等于已更新默认分支或发布包。发布包是否包含 c008a03 的整改功能、最终代码地址与原问卷更新，留到下一步逐项核验；本次不发布、不修改问卷。
