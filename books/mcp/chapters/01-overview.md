---
chapter: 1
title: 初识 MCP
source: https://modelcontextprotocol.io/specification/2026-07-28 (概览与生态)
---

# 第 1 章 初识 MCP

> 引子章,**全书最后写**——只有知道全书长什么样,引子才写得准。

## 本章节级大纲

- 集成爆炸问题:N×M(每套 Agent 框架 × 每个内部系统各写一遍适配)→ N+M(协议层解耦)
- MCP 是什么、不是什么:与 function calling / 自建插件机制 / OpenAPI 的对比
- 生态一瞥:官方 SDK(TypeScript / Python / Java)、Server 目录、各框架支持现状
- 版本演进速览(详细展开在第 3 章)
- 本书结构导读与贯穿案例(中台售后域规模化切片)预告

## 写作备注

- 素材:modelcontextprotocol.io 首页与 spec 概览;书架各书对 MCP 的引用点
- 核对清单:动笔前确认 latest spec 是否仍为 2026-07-28,若已有新版本,主线版本要重新拍板
- 风格:场景化导读开头(中台团队"每个 Agent 项目都重复封装一遍接口"的痛点场景)
