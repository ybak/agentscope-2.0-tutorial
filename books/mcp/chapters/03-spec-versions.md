---
chapter: 3
title: 协议版本演进与兼容
source: https://modelcontextprotocol.io/specification/2026-07-28/changelog
---

# 第 3 章 协议版本演进与兼容

> **初稿状态(2026-10-24)**:各版本要点依据官方 changelog 与发布文(逐版本标注来源);字段级差异发布前对照两个 changelog 原文(2025-11-25 / 2026-07-28)复核。

网上大量 MCP 教程停留在 2025 年中的协议形态——**对 2026-07-28 已经过时**。这一章把五个版本串成一条线:每个版本解决了什么问题、留下了什么债,以及最重要的——存量 Server 怎么迁到 latest。理解了演进,第 2 章的无状态模型就不再是"凭空的设计",而是三次还债的结果。

## 3.1 五个版本,一条主线

```
2024-11-05 ──▶ 2025-03-26 ──▶ 2025-06-18 ──▶ 2025-11-25 ──▶ 2026-07-28
 初版           Streamable     OAuth 2.1      Tasks/CIMD     无状态核心
 (stdio+SSE)    HTTP 取代 SSE   elicitation    extensions     MRTR/header 路由
```

### 2024-11-05:初版

stdio + HTTP+SSE 两种传输;initialize 握手建立会话;tools/resources/prompts 三类能力成型。确立了"模型上下文"的协议骨架——**后来所有版本都在还这一版"有状态"欠下的债**。

### 2025-03-26:Streamable HTTP

SSE 的单向流 + 会话粘性难以服务化,由 Streamable HTTP 取代。信号:Server 要进生产,传输层先得像个 HTTP 服务。

### 2025-06-18:安全规范化

- Server 正式定位为 **OAuth 2.1 Resource Server**;elicitation(server 向用户要输入)进入核心
- 规范化是起点,离"企业敢用"还有距离——下一版补课

### 2025-11-25:一周年大版(协议一周年发布)

- **Tasks(实验)**:"call-now, fetch-later"——长任务返回 task 句柄,client 轮询取结果
- **授权大改**:引入 **CIMD**(URL 元数据文档自述身份);**DCR(动态客户端注册)从 SHOULD 降级为 MAY**——实现层普遍出现安全缺陷后的降级;强制 **RFC 8707 Resource Indicators**(token 绑定资源,防混用)
- **Extensions 框架**:核心之外的扩展协商机制
- 元数据补齐:icons、audio content、resource links、websiteUrl

这一版的主题是**企业化的安全与异步**,但每一步都还在"有状态"框架内打补丁。

### 2026-07-28:无状态重构(破坏性)

- **协议级会话移除**:无 initialize 握手、无会话——每个请求自含(第 2 章主线模型)
- **MRTR**:`input_required` 机制替代会话内 server-to-client 请求,交互性在无状态世界重建
- **header 路由**:HTTP 寻址原生支持网关分派
- **授权收紧**:RFC 9207(`iss` 参数 + client 强制校验,SEP-2468)、CIMD 转正为标准、六个 OAuth SEP
- **Tasks 移为扩展**(实验特性退出核心);三个核心特性弃用
- **破坏性变更**:v1 时代 SDK 不支持本版(官方明确),错误码有变化

三个核心特性弃用的完整清单与错误码变化,以 [官方 changelog](https://modelcontextprotocol.io/specification/2026-07-28/changelog) 为准。⚠️ 动笔时逐条核对补全。

## 3.2 版本协商:协议怎么"谈拢"

两代协商机制并存:

- **现代(2026-07-28)**:无握手,client 以声明/探针方式表达支持的版本集合(SDK 内为 `SUPPORTED_PROTOCOL_VERSIONS` / `LATEST_PROTOCOL_VERSION` 常量与 `VersionNegotiationMode` 选项)
- **legacy(≤2025-11-25)**:initialize 握手中的 `protocolVersion` 字段

**TS SDK v2.4.0 实测**:同一 Server,现代 client 直发 `tools/list` 直接服务;2025-06-18 的 `initialize` 被 legacy 路径识别,返回 `protocolVersion: "2025-06-18"` 的标准握手结果——**一份代码双代服务**。这是 SDK 层对"迁移期"的答案:入口按消息形态分类(modern route / legacy route),Server 逻辑只写一份。

## 3.3 兼容矩阵

| Server \ Client | ≤2025-11-25(legacy) | 2026-07-28(modern) |
| --- | --- | --- |
| **2026-07-28 Server** | △ 经 SDK legacy 兼容入口(默认 `serve`;可配 `reject` 硬切)——能力以旧协议子集为准 | ✅ 全量 |
| **≤2025-11-25 Server** | ✅ | ✅(modern client 保留 legacy 协商路径;能力受限) |

△ 是本章最实用的一格:**升级 Server 不必等所有 client 升完**——legacy 入口兜底,但 legacy client 拿不到 MRTR/新授权等新能力。规划里把它当"过渡窗口",不是"永久状态"。

不匹配的硬错误(双方声明集合无交集)在 TS SDK 中为 `UnsupportedProtocolVersionError`——联调时见到它,先查两端版本声明,再查传输。

## 3.4 存量迁移:2025-06-18 → 2026-07-28 改造清单

以典型"2025 年中技术栈"的域 Server 为例,按序改造:

1. **握手与会话**:删除 initialize/会话管理代码;每个 handler 改为自含(请求内带全上下文)
2. **交互性**:会话内 server→client 请求(elicitation/sampling 调用)改写为 **MRTR** 的 `input_required` 返回(语义对应,形态不同)
3. **长任务**:Tasks(实验)用法迁到 extensions 形态,或改用自建异步 + 轮询工具(第 6 章贯穿案例选后者,协议面更薄)
4. **授权**:对齐 RFC 9207(`iss` 校验进 client)、CIMD 登记消费端身份、token audience 绑定核查
5. **弃用项**:对照 changelog 逐条替换(⚠️ 清单发布前补全)
6. **双代过渡**:SDK legacy 入口开启,灰度期间新旧 client 并行,按流量比例切

## 3.5 选型建议

- **新项目:直接 2026-07-28**,SDK 选 v2 大版本(TS v2.x / Java mcp-core 2.0.x)——不为旧教程兼容性买单
- **存量:按 3.4 清单评估**,破坏性变更集中会话/交互/授权三处,改造量与"Server 用了多少 server-to-client 交互"成正比
- **教学中**:任何未标注 spec 版本日期的 MCP 教程(包括本书以外的),默认按 2025 年中形态理解,对照本章后再用

## 3.6 小结

- 主线:初版有状态 → 传输规范化 → 安全规范化 → 企业化补课 → **无状态重构**
- 双代兼容靠 SDK 入口分类,一份 Server 代码服务两代 client(实测)
- 迁移清单五步:会话、交互、长任务、授权、弃用项
- 选型:新项目 latest,存量按清单评估,外源教程先对版本

→ 协议与生产的主体(第 2、4-8 章)到此完整;**第 9 章**谈组织与路线。

## 复核清单(发布前)

- [ ] 五版本要点逐条对照两份官方 changelog(2025-11-25 / 2026-07-28)
- [ ] 2026-07-28 的三个弃用特性与错误码变化清单补全
- [ ] `legacy: 'reject'` 行为实测(当前仅实测默认 `serve`)
- [ ] Java SDK 的版本协商/legacy 机制核对(mcp-core 2.0.x 文档)
