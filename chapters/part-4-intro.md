---
title: 第四篇 生态与集成
source: 新写
---

第三篇讲完单个 `HarnessAgent` 的工程能力之后，本篇把视野扩展到 AgentScope 与外部世界的连接：模型从哪里来、知识从哪里检索、记忆存在哪里、状态如何跨副本共享、消息从哪些平台进来、Agent 之间如何对话、技能放在哪个仓库，以及网关、注册中心、调度器、调试与训练工具如何把 Agent 纳入企业既有技术栈。第 21 章是全书唯一的"合并精编"章：用一张提供商总表，加上每家固定的"依赖 / 凭据 / 配置 / 专属说明"四段式，把十家模型提供商——OpenAI 及其兼容栈上的 DeepSeek、GLM、Kimi、MiniMax，以及 OpenAI Official、DashScope、Gemini、Anthropic、Ollama——的接入方式一次讲清。第 22~27 章按主题成体系收录六类集成：RAG 知识库（第 22 章）、长期记忆（第 23 章）、会话存储与分布式部署（第 24 章）、IM 渠道（第 25 章）、Agent 协议（第 26 章）、Skill 仓库（第 27 章）；第 28 章以集成扩展全览表开篇，收拢基础设施（Higress、Nacos、Scheduler）与生态工具（Studio、Chat Completions Web、在线训练）。

这八章共享同一条设计主线：**每类能力都先定义一个核心接口，扩展模块只负责"把外部系统适配到这个接口"**——`Knowledge` 之于检索、`LongTermMemory` 之于记忆、`AgentStateStore` 与 `DistributedStore` 之于状态与工作区文件、Channel 之于消息平台、协议适配器（A2A / Agent Protocol / AG-UI）之于跨系统交互、`AgentSkillRepository` 之于技能来源。因此多数章节的读法相同：先看概览里的选型表确定后端，再跳到对应小节抄配置。也正因为接口统一，除 Simple 外的 RAG 实现都只做检索、文档写入保留在对应平台，Java 侧统一读取——多个实现才可能在使用侧完全可替换。

读完本篇，你可以在模型、存储、消息与协议四个维度上把前几篇搭好的 Agent 接入真实生产环境：多副本共享状态（第 24 章）、接入企业 IM 与代码托管平台（第 25 章）、向前端和其他 Agent 系统开放标准接口（第 26 章）。第五篇将在此之上介绍 AgentScope Service 平台——把这些集成托管起来的官方运行时。
