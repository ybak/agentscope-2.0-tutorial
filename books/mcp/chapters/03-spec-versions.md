---
chapter: 3
title: 协议版本演进与兼容
source: https://modelcontextprotocol.io/specification/2026-07-28/changelog
---

# 第 3 章 协议版本演进与兼容

> 生产环境选版本、管兼容、做迁移的依据章。**在协议主体(第 2、4-8 章)定型后写。**

## 本章节级大纲

- 五个版本逐个讲:
  - 2024-11-05:初版,stdio + HTTP+SSE,有状态握手
  - 2025-03-26:Streamable HTTP 取代 HTTP+SSE
  - 2025-06-18:OAuth 2.1 鉴权规范化、elicitation
  - 2025-11-25:(以官方 changelog 为准补全)
  - **2026-07-28:无状态核心(移除协议级会话、去掉 initialization 握手)、多轮请求、header 路由、授权框架重写(RFC 9207)、三个核心特性弃用、Tasks 移为扩展——含破坏性变更**
- 版本协商机制在各版本下的形态
- 兼容矩阵:client × server × 版本的可用组合
- 存量 Server 迁移指引:2025-06-18 → 2026-07-28 的改造清单(会话/握手/授权逐项)
- 团队选型建议:新项目直接 latest;存量迁移的时机与步骤

## 写作备注

- 素材:官方 changelog(逐版本)、官方 blog 发布文、WorkOS / AWS / Cloudflare 等对 2026-07-28 的解读与迁移文(引用标注来源)
- 核对清单:2025-11-25 版本内容我方尚未核实,动笔前以官方 changelog 补全;破坏性变更的完整清单须逐条对官方 changelog 核验
