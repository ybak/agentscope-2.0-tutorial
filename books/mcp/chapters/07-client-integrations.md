---
chapter: 7
title: 跨框架客户端接入
source: https://modelcontextprotocol.io/specification/2026-07-28/client + 各书交叉引用
---

# 第 7 章 跨框架客户端接入

> **初稿状态(2026-10-24)**:TS 双端(client/server)在本章实测;矩阵中未实测的格子明确标注。矩阵会过期——每格都带核实日期,引用前重查。

第 6 章结束时,售后域 Server 已经能被"一个"消费端调用。这一章兑现 MCP 的核心承诺——**同一个 Server,不同框架通用**:先给一张跨框架支持矩阵,再用两个 SDK 实测双端调用,最后收拢贯穿案例。

## 7.1 框架 × MCP 支持矩阵

| 消费端 | 2026-07-28 支持 | 传输 | 核实状态 |
| --- | --- | --- | --- |
| TS SDK `@modelcontextprotocol/client` | ✅ v2.x(2.3.1+,实测 2.4.x) | stdio / Streamable HTTP | **本书实测**(2026-10-24) |
| Java SDK `io.modelcontextprotocol.sdk:mcp-core` | ✅ 2.0.x(`modern` 包,37 项一致性通过) | stdio / Streamable HTTP | 查证未实测 |
| agentscope-java | 见其第 26 章(Agent 协议) | — | → agentscope-java 书 |
| ragflow | ⚠️ 待核实 | — | → ragflow 书 |
| CopilotKit(前端 Host) | ⚠️ 待核实 | — | → copilotkit 书 |
| AI CLI(Claude Code 等) | ✅(GitHub MCP Server 已宣布支持 2026-07-28,可旁证生态就绪) | 各 CLI 自定 | 待按版本核实 |
| GitHub 官方 MCP Server(Server 侧生态参照) | ✅ 2026-07-23 宣布 | HTTP | 查证 |

矩阵的使用方式:接入前查两格——**目标框架对 2026-07-28 的支持版本**与**传输交集**(双端都支持的传输才是可用传输)。`⚠️ 待核实` 的格子在本框架书成稿时回填并注明核实日期。

## 7.2 双端实测:Client 连接我们的售后域 Server

Host 侧只需三步:构造 transport(指向 Server 进程/端点)→ 连接 → 调用。以下代码 **v2.4.0 实测通过**(2026-10-24):

```typescript
// npm i @modelcontextprotocol/client zod
import { Client } from "@modelcontextprotocol/client";
import { StdioClientTransport } from "@modelcontextprotocol/client/stdio";

// ① transport:拉起 Server 子进程(stdio);HTTP 场景换 StreamableHTTPClientTransport
const transport = new StdioClientTransport({
  command: "node",
  args: ["server.mjs"],   // 第 4 章的售后域 Server
});

// ② client:Host 身份声明
const client = new Client({ name: "book-host", version: "0.1.0" });
await client.connect(transport);

// ③ 发现与调用
const tools = await client.listTools();
// → tools.tools.map(t => t.name) === ["echo"]

const res = await client.callTool({
  name: "echo",
  arguments: { text: "双端实证成功" },
});
// → res.content === [{ type: "text", text: "双端实证成功" }]

await client.close();
```

值得注意的细节:

- **Host 侧工具目录来自 `listTools()`**——第 2 章"Host 管可见性"在此落地:Host 决定把哪些工具注入模型上下文,这个过滤动作在 Host 代码里,不在协议里。
- `callTool` 的返回即第 5 章的 `content` / `structuredContent` / `isError` 结构——**双端共享同一套结果语义**,这是"跨框架通用"的微观基础。
- client 同样是无状态语义的使用者:`connect` 之后直接业务调用,无握手依赖(与第 4 章 Server 侧实测互为印证)。

## 7.3 agentscope-java 侧:主线消费端

agentscope-java 是本书读者群的日常框架,它的 MCP 接入方式与最佳实践在 **agentscope-java 书第 26 章(Agent 协议)** 有完整覆盖——本章不重复其 API 细节,只给集成视角的三条:

1. **版本对齐**:agentscope-java 侧的 MCP 版本与域 Server 的 spec 版本对齐(第 3 章兼容矩阵),升级节奏由第 6 章目录治理统一管。
2. **工具可见性**:Agent 按角色挂工具子集(客服 Agent 只挂售后+物流)——Host 侧过滤,呼应第 6.4 节。
3. **联调验证**:Server 每次发版,用真实 Agent 冒烟(模型选中率、参数填对率),这比单测更接近真实质量。

(本节在 agentscope-java 书第 26 章成稿/本书出版前,以该章内容为准回补具体配置示例。)

## 7.4 多框架消费:贯穿案例收尾

贯穿案例的终局验证——**同一个售后域 Server,两个异构消费端**:

```
                    ┌─────────────────────────┐
                    │  after-sales MCP Server  │
                    │  (第 4 章建,第 5 章充实) │
                    └────────┬────────────────┘
              ┌──────────────┴──────────────┐
     TS Client(本章实测)          agentscope-java Agent
     CopilotKit 前端原型            (第 26 章接入,待联调)
```

同一份工具定义(`inputSchema` + `description`),TS Host 与 Java Host 拿到的目录一致、调用协议一致、结果语义一致——**第 5 章打磨的描述质量只投入一次,所有框架受益**。这就是书架里 mcp 书存在的理由。

## 7.5 客户端侧的常见坑

- **传输交集**:Server 只支持 stdio、前端 Host 只能 HTTP——接入前先对传输清单,别到联调才发现。
- **版本协商失败**:legacy client 连现代 Server(或反之)的报错形态,两端 SDK 都有明确错误(如 `UnsupportedProtocolVersionError`)——按第 3 章兼容矩阵定位,而不是盲改配置。
- **目录刷新**:Server 的 `tools/list_changed` 通知到达后,Host 需重新 `listTools`——长驻 Host(如 CLI 会话)忽略此通知会拿着过期目录选工具。
- **描述截断**:个别 Host 对工具描述做长度截断,再好的描述被截也就失效了——接入新框架时检查它的截断策略。

## 7.6 小结

- 双端调用三步:transport → connect → listTools/callCall(TS v2.4.0 实测)
- Host 侧可见性过滤是治理的落点
- 跨框架通用 = 目录一致 + 协议一致 + 结果语义一致
- 矩阵是活的文档,每格带核实日期

→ **第 8 章**把这套东西放进生产:传输选型、鉴权、多租户与安全。

## 复核清单(发布前)

- [ ] 矩阵 `⚠️ 待核实` 格子在对应书成稿时回填(标注核实日期)
- [ ] Java SDK 双端示例实测补齐(mcp-core 2.0.1 client 侧)
- [ ] agentscope-java 第 26 章成稿后回补 7.3 配置示例
- [ ] `UnsupportedProtocolVersionError` 等错误类型名与 v2.4.0 导出核对
