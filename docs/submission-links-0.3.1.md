# moonjson-toolkit 0.3.1 最终申报与复验入口

核对日期：2026-10-24（Asia/Shanghai）。本页整理已取得的交付证据，可用于复制填写
申报问卷；本笔没有重新测试、下载发布包、运行外部消费或触发 CI，也没有代填或提交问卷。

## 固定版本与公开入口

发布模块为 `BigSaltyMan/moonjson-toolkit@0.3.1`，标签为 `v0.3.1`。
完整发布代码 SHA：

```text
393a77281eb7603d7533025720a1c83c75ea938a
```

| 内容 | 最终入口与对应关系 |
| --- | --- |
| 代码版本 | [v0.3.1 代码](https://github.com/BigSaltyMan/moonjson-toolkit/tree/v0.3.1)，[固定代码提交](https://github.com/BigSaltyMan/moonjson-toolkit/tree/393a77281eb7603d7533025720a1c83c75ea938a)；远程附注标签解析到上述完整 SHA |
| 发布版本 | [Mooncakes 0.3.1 精确版本元数据](https://mooncakes.io/api/v0/manifest/BigSaltyMan/moonjson-toolkit@0.3.1)、[GitHub Release v0.3.1](https://github.com/BigSaltyMan/moonjson-toolkit/releases/tag/v0.3.1) |
| 使用文档 | [Mooncakes 0.3.1 文档与 README](https://mooncakes.io/docs/BigSaltyMan/moonjson-toolkit@0.3.1)、[版本英文 README](https://github.com/BigSaltyMan/moonjson-toolkit/blob/v0.3.1/README.mbt.md)、[版本中文 README](https://github.com/BigSaltyMan/moonjson-toolkit/blob/v0.3.1/README.zh-CN.md) |
| Schema 支持范围 | [该版本兼容性报告](https://github.com/BigSaltyMan/moonjson-toolkit/blob/v0.3.1/docs/schema-compatibility.md)、[README 支持范围与限制](https://github.com/BigSaltyMan/moonjson-toolkit/blob/v0.3.1/README.mbt.md#validating-against-a-json-schema) |
| 结构化报告 | [报告版本 1 契约](https://github.com/BigSaltyMan/moonjson-toolkit/blob/v0.3.1/docs/schema-report-format.md)、[历史跨平台复验记录](https://github.com/BigSaltyMan/moonjson-toolkit/blob/v0.3.1/docs/schema-report-verification.md) |
| 自动验证 | [最终发布代码的 Linux CI #24](https://github.com/BigSaltyMan/moonjson-toolkit/actions/runs/40062410755)，实际 `head_sha` 为上述发布代码 SHA |
| 发布核对 | [补齐实际结果的发布记录](https://github.com/BigSaltyMan/moonjson-toolkit/blob/ad21f18380557c7e1cf661933371a936f1decc65/docs/release-0.3.1.md)、[注册表源码 ZIP](https://download.mooncakes.io/user/BigSaltyMan/moonjson-toolkit/0.3.1.zip)、[Release 源码 ZIP](https://github.com/BigSaltyMan/moonjson-toolkit/releases/download/v0.3.1/moonjson-toolkit-0.3.1.zip) |

发布记录提交 `ad21f18380557c7e1cf661933371a936f1decc65` 仅补充实际交付结果，
不包含在已发布源码包中；标签继续指向代码提交 `393a772…`，没有为后补记录重新打包。
历史跨平台复验记录实际验证的是 `c8b4b2b39026153b836444d1f8c84e4569df198c`，
它用于追溯报告契约演进，不能代替 `0.3.1` 最终代码的 CI #24。

审计包、注册表包和 Release 附件内容一致：189 个文件，970,436 字节。源码包 SHA-256：

```text
da406936c9961a8e0bbad3599fa7ac2f55b41690ead5be471564c6542b7cad61
```

两个 ZIP 入口均为 Mooncakes 源码包，不是预编译 native 可执行程序。

## 验证结果与证据来源

| 来源 | 已有结果及范围 | 公开证据 |
| --- | --- | --- |
| Linux CI #24，发布代码 `393a772…` | native 严格检查、构建通过；native 测试 **481/481**；真实 CLI 报告验收 **9/9（八组）**；HTTP 回环验收 **8/8** | [native job](https://github.com/BigSaltyMan/moonjson-toolkit/actions/runs/40062410755/job/120778551407)及该运行上传的验收产物 |
| 同一 Linux native job | 标准测试 **462 组、2354 条**：实际执行并通过 **1022**，编译拒绝 **442**，明确跳过 **890**；分类及逐条诊断与审阅基线一致 | [版本兼容性报告](https://github.com/BigSaltyMan/moonjson-toolkit/blob/v0.3.1/docs/schema-compatibility.md)及 CI 的 `schema-suite-reports` 产物 |
| Windows 本地候选工作树 | native 严格检查、构建通过；两个版本定向用例各 **1/1**，报告验收 **9/9**，HTTP 回环验收 **8/8**；不是一次 Windows 全量回归 | [实际发布记录中的本地证据](https://github.com/BigSaltyMan/moonjson-toolkit/blob/ad21f18380557c7e1cf661933371a936f1decc65/docs/release-0.3.1.md#针对性验证与文档预检查) |
| 干净包与注册表消费，原固定工具链 | ZIP 解包构建、最小 CLI 检查通过；本地干净包外部消费 **3/3**；发布后精确注册表版本消费 **3/3**，无本地覆盖，安装成员摘要全部匹配 | [外部消费发布记录](https://github.com/BigSaltyMan/moonjson-toolkit/blob/ad21f18380557c7e1cf661933371a936f1decc65/docs/release-0.3.1.md#外部消费与平台文档) |
| 隔离固定新版工具链 | `moonc v0.10.16+b1a0e846e` 下干净解析依赖、native 检查与 `moon doc` 通过；保留兼容性警告，不宣称新版零警告 | [独立文档 job](https://github.com/BigSaltyMan/moonjson-toolkit/actions/runs/40062410755/job/120778551289)及 `documentation-compatibility` 产物 |
| Mooncakes 平台 | `0.3.1` 文档构建成功，README 从版本说明完整渲染到许可证结尾，四种报告、限制、退出码及重要链接已验收；本笔只读复核元数据 `build_status: success` | [精确版本页面](https://mooncakes.io/docs/BigSaltyMan/moonjson-toolkit@0.3.1)、[平台构建日志](https://mooncakes.io/api/v0/builds/log?module=BigSaltyMan%2Fmoonjson-toolkit&version=0.3.1)、[发布记录](https://github.com/BigSaltyMan/moonjson-toolkit/blob/ad21f18380557c7e1cf661933371a936f1decc65/docs/release-0.3.1.md) |

标准测试的拒绝和跳过不计入通过数。以上结果支持声明的 JSON Schema Draft 2020-12
明确子集，不是完整标准实现或兼容性认证。远程/动态引用及 `unevaluated*` 等未支持约束
继续明确拒绝；`format` 作为注解，不执行格式断言。报告 `reportVersion` 保持 `1`。

HTTP 验收使用本地回环服务和模拟响应，不是调用真实 AI 服务，也不构成模型效果评测。
Windows、Linux、注册表消费和平台文档属于不同来源，不合并成一次测试。
原申报书的覆盖率和性能数值保留为历史记录，不转称 `0.3.1` 当前测量结果；现有原文
未完整标注这些测量的版本与环境，本页不补造信息或重新测量。

## 可复制到问卷的内容

以下为通用字段材料，不假定原问卷的实际字段名称。

**最终代码地址**

https://github.com/BigSaltyMan/moonjson-toolkit/tree/v0.3.1

**发布版本地址**

- 模块：`BigSaltyMan/moonjson-toolkit@0.3.1`
- Mooncakes：https://mooncakes.io/docs/BigSaltyMan/moonjson-toolkit@0.3.1
- GitHub Release：https://github.com/BigSaltyMan/moonjson-toolkit/releases/tag/v0.3.1

**文档地址**

https://mooncakes.io/docs/BigSaltyMan/moonjson-toolkit@0.3.1

**验证入口**

- 最终代码 CI：https://github.com/BigSaltyMan/moonjson-toolkit/actions/runs/40062410755
- 支持范围：https://github.com/BigSaltyMan/moonjson-toolkit/blob/v0.3.1/docs/schema-compatibility.md
- 发布核对：https://github.com/BigSaltyMan/moonjson-toolkit/blob/ad21f18380557c7e1cf661933371a936f1decc65/docs/release-0.3.1.md

**整改摘要**

已修复JSON Schema未支持约束静默放行：CLI与库接口强制预检查，提前拒绝并报告位置和类别；数值使用精确十进制语义，完成约定的Draft 2020-12子集及本地引用递归保护。新增独立检查及四种结构化报告，覆盖独立检查、单文档、批量文件和JSONL。标准测试实际执行通过1022条，拒绝和跳过不计通过；Windows本地、对应代码的Linux CI和注册表消费均有验证证据。0.3.1已修复旧依赖并解除平台文档构建阻塞，仍不宣称完整支持标准。

## 供复验者使用的入口

此处仅列出既有脚本，没有在本笔执行。使用 `v0.3.1` 的干净检出和发布记录注明的
固定工具链，在 Git Bash 或 Linux 中运行；native CLI 路径均相对于仓库根目录。

```sh
moon build --target native --debug cmd/main
python scripts/check_schema_reports.py --cli _build/native/debug/build/cmd/main/main.exe
python scripts/check_ai_http.py --cli _build/native/debug/build/cmd/main/main.exe
```

标准套件复验命令见固定版本兼容性报告；完整自动门禁和固定文档工具链见
[该版本工作流](https://github.com/BigSaltyMan/moonjson-toolkit/blob/v0.3.1/.github/workflows/ci.yml)。
外部问卷尚未代填或提交。
