---
chapter: 7
title: 跨框架客户端接入
source: https://modelcontextprotocol.io/specification/2026-07-28/client + 各书交叉引用
---

# 第 7 章 跨框架客户端接入

> 书架价值的集中体现:同一个 Server,全框架通用。**框架 API 细节一律交叉引用,不重复**。

## 本章节级大纲

- 「框架 × MCP 支持矩阵」:agentscope-java / ragflow / copilotkit / AI CLI(Claude Code 等)——支持的传输、版本、能力边界
- agentscope-java 为主例:client 配置与一次真实调用(API 细节 → agentscope-java 书第 26 章)
- ragflow / copilotkit / AI CLI:各一小节接入要点 + 交叉引用对应书
- 贯穿案例收尾:售后域 Server 被 ≥2 个框架同时消费的完整演示
- 客户端侧的坑:版本协商失败、工具描述截断、并发调用限制

## 写作备注

- 素材:各框架文档;书架各书成稿后的对应章节(若其他书未成稿,占位引用并在出版前回补)
- 核对清单:矩阵逐格以各框架当前版本文档核实,标注核实日期(spec 演进快,矩阵会过期)
