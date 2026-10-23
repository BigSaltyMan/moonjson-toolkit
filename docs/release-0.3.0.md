# moonjson-toolkit 0.3.0 发布说明与交付记录

本次为 `BigSaltyMan/moonjson-toolkit` 准备 `0.3.0`，根模块采用 Apache-2.0。
最初的发布准备阶段未上传 Mooncakes，也未创建标签或 GitHub Release。
2026-10-23 已上传注册表；平台文档构建失败，完整交付尚未完成，详见末尾实际记录。
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

## 2026-10-23 实际发布结果

### 上传与注册表包

- 模块及版本：`BigSaltyMan/moonjson-toolkit@0.3.0`。
- 发布代码 SHA：`a7c2728c0b4af91ef9fab0c06d165f0b74950717`。
- 注册表记录的创建时间：`2026-10-23T14:21:39.196994+00:00`，
  即北京时间 `2026-10-23 22:21:39.196994`。
- 从上述提交导出的独立目录发布，README 采用已审计的完整文档准备方式，
  没有将当前工作区的无关修改打包。上传命令退出 `0`，服务器返回 `200 OK`。
- [注册表精确版本元数据](https://mooncakes.io/api/v0/manifest/BigSaltyMan/moonjson-toolkit@0.3.0)
  可查询，版本未被撤回；模块、版本、Apache-2.0 许可证、仓库地址和四项直接依赖与包一致。
- [注册表源码 ZIP](https://download.mooncakes.io/user/BigSaltyMan/moonjson-toolkit/0.3.0.zip)
  已实际下载，共 185 个文件、959,980 字节；与已审计 ZIP 逐字节相同，
  成员清单及逐文件摘要也全部一致，没有重新封装差异。
- 审计包、发布工具生成包和注册表下载包的 SHA-256 均为：

  ```text
  cb357a6fcf24d41c2a8bec0c4e64140b17f9c0d4614cca71e31f0d101347eca4
  ```

注册表包保留完整 README、源码、模块配置和第三方许可证；README 不是符号链接占位文本。
根许可证为 Apache-2.0，上游标准测试集的 MIT 声明保持原样。
包内 README 核对通过与平台渲染核对是两项独立结果。

### 精确代码 SHA 的 Linux CI

[Linux CI #22](https://github.com/BigSaltyMan/moonjson-toolkit/actions/runs/39965922972)
实际验证的代码 SHA 为 `a7c2728c0b4af91ef9fab0c06d165f0b74950717`，结果成功。
native 测试 481/481，真实 CLI 报告验收八组 9/9；标准测试共 2354 条，
执行并通过 1022 条、明确拒绝 442 条、跳过 890 条，兼容性基线一致。
这些是该次 Actions 的结果，本次发布操作没有重新运行上述本地测试。

### 注册表外部消费

在独立临时项目中复用发布准备阶段的三项消费检查，依赖声明使用精确版本
`BigSaltyMan/moonjson-toolkit@0.3.0`，没有 `moon.work` 或本地模块覆盖。
`moon tree` 解析到注册表的 `0.3.0`；测试日志确认实际下载该版本，安装后的
185 个包成员与注册表 ZIP 的内容摘要全部一致。

使用原有工具链 `moon 0.1.20260915 (2e1a46d 2026-09-15)`、
`moonc v0.10.13+cbb11c36f (2026-09-15)`，三项检查 3/3 通过：

1. 支持的 Schema 可以编译，符合约束的数据校验通过。
2. 普通数据违规返回违规列表。
3. 未支持的约束返回 Schema 问题。

该结果限定于上述消费工具链，不代表平台文档构建使用的工具链已经通过。

### 平台文档失败及待完成步骤

[0.3.0 版本文档页](https://mooncakes.io/docs/BigSaltyMan/moonjson-toolkit@0.3.0)
明确显示版本 `0.3.0 (latest)`，但状态为 **Build failed**。
点击该页 Build log 后，日志显示平台在发现传递依赖
`bikallem/compress@0.3.4` 时拒绝其旧 `moon.mod.json`：

```text
moon.mod.json ... is no longer supported. Run `moon fmt` to migrate to `moon.mod`.
```

native、wasm-gc、wasm、js 四个目标均因此中断，最后报告 `Build failed for all targets`。
[构建队列](https://mooncakes.io/build-queue) 已将该版本列在 Recent Builds，
不是仍在排队。平台日志没有提供可记录的具体工具链版本，不能用本地版本代替。

因此，版本页 README 的完整渲染、四种报告说明及其中重要文档链接尚未验收成功。
注册表上传成功、包内容一致、固定工具链外部消费通过，均不替代这项失败结果。

按照本笔发布顺序约定，**尚未创建或推送 `v0.3.0`，尚未创建 GitHub Release**，
没有重传或尝试覆盖已存在的 `0.3.0`。文档页问题需要先解决并实际复验，
之后才能继续标签与 Release；未来标签仍应指向上述已验证的发布代码 SHA。
若解决问题需要改变发布源码或依赖，应另行准备新版本，不能用后补文档冒充已修复包。

上传输出、注册表元数据及实际 ZIP、逐文件审计、外部消费日志和文档失败日志摘录，
保存在本地 `_build/release-audit/publish/`。该目录不作为发布源码提交。
本次只更新本发布记录，没有重跑 Windows 全量、标准兼容性、前端或性能测试，
也没有重新打包包含本记录的 `0.3.0`。
