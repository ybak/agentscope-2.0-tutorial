# MCP:跨框架工具接入协议

> 状态:**初稿 v2(2026-10-24)——基于官方规范原文([modelcontextprotocol/modelcontextprotocol](https://github.com/modelcontextprotocol/modelcontextprotocol) 2026-07-28)逐章对照重写**;TS SDK v2.4.0 双端实测。发布前按各章「复核清单」完成 Java 实测与 spec 字段级终核,升 status: published 后进站点。

## 定位

Model Context Protocol,统一工具接入的跨框架标准。本书讲两件事:**协议本身**(核心概念、版本演进、能力建模与安全)与**规模化落地**(业务中台数千接口的 MCP 化、治理与企业路线)。让同一套工具能力被不同编排框架复用,并给出中台场景从 Pilot 到规模化的完整工程路径。

## 目标读者

- 后端工程师(主要实现者):Server 构建、接口到工具的映射工程
- 平台/架构:Gateway 聚合、多租户工具治理、版本与安全策略
- 集成方:各框架(agentscope-java / ragflow / copilotkit / AI CLI)的接入,详见各书交叉引用

## 与平台缺口地图的对应

以下条目来自[设计规格附录 A](../../docs/superpowers/specs/2026-10-24-multi-book-restructure-design.md)(跨境电商智能体多租户平台 · 技术缺口地图):

| 角色 | 技术域 | 具体内容 | 覆盖 |
|------|--------|---------|------|
| 开发 | 协议 | MCP 工具接入 | 🔜 mcp 书 |

## 贯穿案例

**中台售后域的规模化切片**:业务中台某域约 20 个 REST 接口 → 按任务语义聚合为 6 个 MCP 工具 → 经 Gateway 暴露 → 被 agentscope-java 后端 Agent 与前端应用同时消费。第 4 章初始化,第 5 章打磨工具质量,第 6 章完整走一遍规模化方法,第 7 章多框架收尾。

## 章节规划(初稿)

| 章节 | 内容一句话 | 分量 |
|------|-----------|------|
| [第 1 章 初识 MCP](chapters/01-overview.md) | N×M 集成爆炸 → N+M;与 function calling/插件的对比;生态与版本演进概览 | 薄(最后写) |
| [第 2 章 协议核心概念](chapters/02-core-concepts.md) | 以 **2026-07-28 无状态核心**为主线:角色模型、tools/resources/prompts 语义边界(新手最常混淆,独立一节)、JSON-RPC 消息结构 | 中 |
| [第 3 章 协议版本演进与兼容](chapters/03-spec-versions.md) | 五个版本逐个讲:2024-11-05 → 2025-03-26(Streamable HTTP)→ 2025-06-18(OAuth 2.1、elicitation)→ 2025-11-25 → **2026-07-28(无状态核心、去握手、多轮请求、header 路由、授权重写 RFC 9207、Tasks 转扩展,含破坏性变更)**;版本协商、兼容矩阵、存量 Server 迁移 | 中 |
| [第 4 章 快速上手](chapters/04-quickstart.md) | 官方 SDK(含 Java)最小 Server + Inspector 调试;首次工具调用全链路时序图;贯穿案例初始化 | 中 |
| [第 5 章 工具接入实战](chapters/05-tool-authoring.md) | 参数 schema 设计、命名与描述质量(LLM 靠描述选工具)、错误处理(可重试/不可重试)、大结果分页、幂等性 | 重 |
| [第 6 章 规模化:业务中台的 MCP 化](chapters/06-mcp-at-scale.md) | **接口 ≠ 工具**(任务粒度聚合);OpenAPI/Swagger → MCP 工具自动生成管线;域拆分 + MCP Gateway 聚合;工具检索与动态发现(search+load、分页、按角色挂载);命名规范与目录治理 | **最重** |
| [第 7 章 跨框架客户端接入](chapters/07-client-integrations.md) | 框架 × MCP 支持矩阵;agentscope-java 为主例(细节引其第 26 章),ragflow/copilotkit/AI CLI 交叉引用;贯穿案例多框架收尾 | 中 |
| [第 8 章 部署与安全](chapters/08-deploy-security.md) | stdio vs Streamable HTTP 选型;鉴权与 2026-07-28 授权框架;多租户工具可见性;tool poisoning、描述注入、Server 供应链可信、最小权限;生产监控(→ langfuse 书) | 重 |
| [第 9 章 企业落地路线图](chapters/09-adoption-roadmap.md) | Pilot(高频场景)→ 域 Server 试点 → 网关+检索规模化 → 常态治理;中台团队与业务团队分工;成本模型;与现有微服务治理体系融合;反模式清单 | 中 |

> 九章初稿已全部完成(2026-10-24),写作顺序(4→2→5→6→7→8→3→9→1)按计划执行;发布前按各章复核清单收尾。

---

元数据(bookId / title / tagline)以 `build/books/registry.mjs` 为准。
