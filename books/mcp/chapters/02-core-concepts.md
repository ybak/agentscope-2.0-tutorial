---
chapter: 2
title: 协议核心概念
source: https://modelcontextprotocol.io/specification/2026-07-28/architecture
---

# 第 2 章 协议核心概念

> 以 **2026-07-28 无状态核心**为主线讲解;旧的有状态握手模型不在本章展开(放第 3 章演进史)。

## 本章节级大纲

- 角色模型:Host / Client / Server 各自的职责边界(2026-07-28 语义)
- 无状态核心:请求/响应与通知的消息模型;无会话化对部署与扩展的影响
- 三类能力建模:**tools / resources / prompts 的语义边界**——什么该建模为 tool、什么该是 resource、什么时候用 prompt(新手最常混淆,独立一节,配决策表)
- JSON-RPC 消息结构:请求、响应、错误码
- 能力协商与多轮请求(Multi Round-Trip Requests)
- mermaid:角色关系图 + 一次工具调用的消息时序图

## 写作备注

- 素材:2026-07-28 spec 的 architecture / basic 页;官方 blog 对 stateless core 的说明
- 核对清单:2026-07-28 移除协议级会话后,Host/Client/Server 职责描述以最新 spec 文字为准;与 2025-06-18 模型的差异只留一句话引子(详见第 3 章)
