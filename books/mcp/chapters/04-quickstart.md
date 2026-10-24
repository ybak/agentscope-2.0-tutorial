---
chapter: 4
title: 快速上手
source: https://modelcontextprotocol.io/specification/2026-07-28 (SDK quickstart)
---

# 第 4 章 快速上手

> **全书先写本章**(写作顺序第 1 位):上手后回写概念更准。贯穿案例在此初始化。

## 本章节级大纲

- 环境准备:SDK 选型(TypeScript / Python / **Java**——Java SDK 对 agentscope 读者群最重要,给足篇幅),版本号写明
- 最小 MCP Server:10-20 行跑起第一个工具(三个 SDK 各一份,结构对照)
- Inspector 调试:连接、列出工具、手动调用
- 首次工具调用的全链路时序图(mermaid):Host 发起 → client → server → 返回
- 贯穿案例初始化:售后域 Server 骨架(空的 tools/list + 第一个 echo 级工具)
- 常见第一坑:传输不通、schema 校验失败、描述缺失导致模型不选工具

## 写作备注

- 素材:各官方 SDK 仓库的 quickstart 与 2026-07-28 兼容版本说明
- 核对清单:**我的 SDK 知识截至 2025-06-18 时代 API,2026-07-28 下 SDK 的包名、初始化 API、无状态化后的写法必须以官方 SDK 文档现况重查再写**;所有代码示例写入前实测可跑
