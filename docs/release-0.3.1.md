# moonjson-toolkit 0.3.1

本版本修复 Mooncakes 文档构建的旧版传递依赖。实际发布、消费及平台文档结果
在取得后追加；本文件的准备内容不表示已经上传。

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
