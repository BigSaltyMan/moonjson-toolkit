# moonjson-toolkit 0.3.1

本版本修复 Mooncakes 文档构建的旧版传递依赖。2026-10-24 已发布，注册表包、
外部消费、平台文档和 README 验收通过；实际交付证据见末尾记录。

## 依赖链与修复

`0.3.0` 已上传注册表，在固定工具链上可消费，但平台文档构建失败。
[0.3.0 发布记录](release-0.3.0.md)保持原样，不覆盖或重传旧版本。

```text
moonjson-toolkit@0.3.0
└─ oboard/mio@0.5.4
   ├─ moonbitlang/x@0.4.50（实际解析为 0.5.5）
   ├─ moonbitlang/async@0.20.6（实际解析为 0.22.1）
   └─ bikallem/compress@0.3.4
      ├─ bikallem/blit@0.2.2
      └─ moonbitlang/async@0.16.7（实际解析为 0.22.1）
```

compress、blit 均携带旧 `moon.mod.json`。平台在发现 compress 配置时失败，
尚未进入项目编译或文档渲染。平台原日志没有提供具体工具链版本。
没有通过修改开发目录的 `.mooncakes` 绕过问题。

查询注册表时 mio 最新版本仍为 `0.5.4`，没有可采用的升级版本。本项目只调用
`@mio.post(...).text()`，因此移除 mio，改用已有固定依赖
`moonbitlang/async@0.22.1` 的 `http` 包的 POST 和文本读取 API。
没有复制第三方模块或新增压缩实现，根模块保留 parsec 0.1.3、async 0.22.1、x 0.5.5。

请求正文、Content-Type、Bearer 认证、模型配置、60 秒超时、响应 JSON 提取及
错误处理保持不变。仍使用 native HTTP/HTTPS 和系统 TLS 根证书。
HTTP 只协商客户端支持的 gzip/identity，不声明 Brotli、deflate 或 zstd 支持。

## 功能与接口边界

- JSON Schema 语义、支持范围、四种报告格式和退出码不变。
- 软件版本为 `0.3.1`；报告 `reportVersion` 保持 `1`。
- 产品库公开 API 不变；没有新增兼容层公开接口。
- 保留 native 目标，不宣称支持全部目标。
- 根 Apache-2.0、上游测试集 MIT 和前端第三方许可证保持原样。

机器集成说明见[报告契约](schema-report-format.md)，历史证据见
[报告复验记录](schema-report-verification.md)。

## 针对性验证与文档预检查

本地按要求运行原固定工具链的 native 严格检查、构建和现有版本同步定向测试。
`scripts/check_ai_http.py` 使用回环 HTTP 服务启动真实 CLI，检查请求头、正文、UTF-8、
gzip、分块、分块 gzip、API 错误、非法 JSON、损坏 gzip 和断开连接，不调用真实 AI。
现有真实 CLI 报告验收继续执行。本地不另跑全量、完整标准兼容性、前端或性能测试。

新增独立文档 CI job 固定使用官方 `moonc v0.10.16+b1a0e846e`，
不替换主 job 的 `v0.10.13+cbb11c36f`。安装归档摘要固定，工具链和依赖目录隔离。
`scripts/check_doc_compatibility.py` 从提交导出干净内容，重新解析依赖，
确认旧链与旧模块清单消失，执行 native 检查、记录实际 `moon doc --help`，并运行
`moon doc`。新版检查保留兼容性警告，不宣称新版零警告。
原 CI 的全量、标准测试及基线门禁保持不变。

```sh
python scripts/check_ai_http.py --cli _build/native/debug/build/cmd/main/main.exe
python scripts/check_schema_reports.py --cli _build/native/debug/build/cmd/main/main.exe
python scripts/check_doc_compatibility.py --moon /absolute/path/to/isolated/bin/moon
```

文档预检查成功仅表示固定工具链可生成文档；最终仍须核对 Mooncakes 精确版本页面。
发布证据必须注明实际代码 SHA，不能沿用 `0.3.0` 的 CI 作为新版本结论。

本地定向证据（2026-10-24，Asia/Shanghai）：HTTP 回环验收 8/8，真实 CLI
报告验收八组 9/9。两个版本定向用例各 1/1、native 严格检查及构建通过。
干净候选目录使用 `moon 0.1.20261020 (2284bd2 2026-10-20)` /
`moonc v0.10.16+b1a0e846e` 完成依赖解析、native 检查和文档生成。
文档生成器实际产出模块/包 JSON 索引、Markdown README 和源码 HTML，已核对非空且
README 包含独立检查与结构化报告说明；不是假定存在一个 `index.html`。
最终提交 CI、实际包和公开版本页另行记录，不将这次候选预检查冒充平台构建结果。

## 实际发布与交付结果（2026-10-24）

### 发布代码与 CI

- 修复及发布代码 SHA：`393a77281eb7603d7533025720a1c83c75ea938a`。
- [Linux CI #24](https://github.com/BigSaltyMan/moonjson-toolkit/actions/runs/40062410755)
  实际检出上述 SHA，三个 job 均成功。
- 固定原工具链 native 门禁：严格检查、构建、481/481 测试通过；真实 CLI 报告验收
  八组 9/9，HTTP 回环验收 8/8，原有 Schema 示例验收通过。
- 标准测试：2354 条中执行并通过 1022 条、编译拒绝 442 条、跳过 890 条；
  逐条分类与诊断和已审阅基线一致，没有更新基线。
- 独立文档 job：固定 `moon 0.1.20261020 (2284bd2 2026-10-20)` /
  `moonc v0.10.16+b1a0e846e`，干净依赖解析、native 检查和实际 `moon doc` 均通过。
  文档索引、README 和源码资产已核对，证据已上传。
- 原 frontend job 按原配置自动通过；本地未额外运行前端测试。

这些完整回归结果来自修复代码提交的 Actions，不是后补发布记录提交的 CI 结论。
产品库 API 签名未变，生成接口的已有无关工作区差异未提交。

### 实际包与注册表

从上述已提交代码导出独立目录，按原审计流程准备完整 README，生成实际 Mooncakes
源码包。包共 189 个文件、970,436 字节；源码逐成员与固定提交一致，唯一必要的
导出准备是将根 README 链接实体化为完整 README 文本。
许可证、必需源码和模块配置齐全，没有构建产物、依赖缓存、凭据或本地申报材料。
根 Apache-2.0 和第三方原许可证均保留。

隔离目录重新生成包与审计包的成员摘要和 ZIP 摘要均一致。`moon publish` 仅执行一次，
退出 `0`，服务器返回 `200 OK`。
[注册表 0.3.1 元数据](https://mooncakes.io/api/v0/manifest/BigSaltyMan/moonjson-toolkit@0.3.1)
显示模块、版本、许可证、仓库和三项直接依赖均正确，版本未被撤回。
注册表创建时间为 `2026-10-24T04:29:50.762650+00:00`，
即北京时间 `2026-10-24 12:29:50.762650`。

[注册表下载包](https://download.mooncakes.io/user/BigSaltyMan/moonjson-toolkit/0.3.1.zip)
已实际下载，与审计包逐字节相同，没有成员或 ZIP 容器差异。
审计包、发布工具生成包及注册表包的 SHA-256 均为：

```text
da406936c9961a8e0bbad3599fa7ac2f55b41690ead5be471564c6542b7cad61
```

### 外部消费与平台文档

实际 ZIP 解包后 native 构建通过，CLI `--version` 为 `0.3.1`，最小独立 Schema
检查成功，报告 `reportVersion` 仍为 `1`。临时外部项目通过本地 workspace 明确消费
解包内容，原有三项接口检查 3/3 通过。

发布后另建没有 workspace 覆盖的项目，依赖固定为注册表
`BigSaltyMan/moonjson-toolkit@0.3.1`。依赖树和下载日志确认精确来源，安装后的
189 个成员与注册表包摘要全部一致。三项检查 3/3 通过：支持的 Schema 编译并验证、
普通数据违规返回违规列表、未支持约束返回 Schema 问题。
消费检查使用原固定开发工具链，和平台文档构建结果分别记录。

[0.3.1 平台文档页](https://mooncakes.io/docs/BigSaltyMan/moonjson-toolkit@0.3.1)
选择器明确显示 `0.3.1 (latest)`。平台日志已完成 native 检查和文档生成，最终为
`Done.`，不再因旧传递依赖失败；平台日志仍未提供具体工具链版本。
日志中的其他目标步骤不构成本项目支持所有目标的声明。

浏览器实际打开版本页，确认完整 README 从版本说明一直渲染到 Apache-2.0 许可证结尾，
正文约 108,004 个可见文本字符，不是空白或链接占位文本。独立检查、单文档、批量和
JSONL 报告说明、`stderr`、退出码优先级及支持边界均存在。
README 的发布说明、报告契约及其引用的复验记录链接均实际读取成功（HTTP 200）。

### 标签、Release 与证据

- `v0.3.1` 为已推送的附注标签，固定指向修复代码
  `393a77281eb7603d7533025720a1c83c75ea938a`，不指向本次后补文档提交。
- [GitHub Release v0.3.1](https://github.com/BigSaltyMan/moonjson-toolkit/releases/tag/v0.3.1)
  已创建，包含实际 Mooncakes 链接、代码 SHA、对应 CI、契约及包摘要。
- [Release 附件](https://github.com/BigSaltyMan/moonjson-toolkit/releases/download/v0.3.1/moonjson-toolkit-0.3.1.zip)
  是 Mooncakes 源码包，不是 native 可执行程序；没有发布未经验证的多平台二进制包。

实际包审计和干净消费证据保存在 `_build/release-audit-0.3.1/`；上传输出、注册表包、
外部注册表消费、平台日志、README 观察及 Release 核对记录在其 `publish/` 子目录。
这些本地证据不作为源码提交。原有无关工作区改动保留。

`0.3.0` 保持原样，本次没有重复上传或覆盖它，也没有为它补建标签或 Release。
本次只发布已验证的 `0.3.1` 内容；后补发布记录不触发重新打包。
注册表、外部消费和平台文档均实际通过，旧依赖造成的本次交付阻塞已解除。
