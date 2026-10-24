---
chapter: 28
title: 基础设施与生态扩展
source: docs/infra/index.md, docs/infra/higress.md, docs/infra/nacos.md, docs/infra/scheduler.md, docs/infra/studio.md, docs/infra/training.md, docs/infra/chat-completions-web.md
---

# 第 28 章 基础设施与生态扩展

> 本章导读：前三篇的 Agent 要落进企业真实环境，还需要与三类"邻居"打交道：基础设施中间件（AI 网关、注册中心、调度器）、既有客户端生态（把 Agent 包装成标准 LLM 接口）、开发与训练工具（可视化调试、在线强化学习）。本章按"解决什么问题"逐个介绍这些扩展的定位与选型时机；各扩展的依赖与逐步配置见在线文档。

## 基础设施：治理、发现与调度

| 扩展 | 对接对象 | 主要能力 |
| --- | --- | --- |
| Higress | Higress AI 网关 | 通过 MCP 把网关上的工具引入 Toolkit |
| Nacos | Nacos 注册/配置中心 | A2A AgentCard 注册发现、Prompt 配置中心、Skill 仓库 |
| Scheduler | XXL-Job / Quartz | 让 Agent 按 CRON 或固定速率定时执行 |

三者相互独立、按需组合，回答的是三个不同的运维问题：

- **Higress**：工具治理（路由、鉴权、配额）想从 Agent 业务逻辑里解耦出去，交给网关层——适合已把 Higress 用作 AI 网关的团队。它把网关上以 MCP 方式发布的工具直接引入 Toolkit，Agent 只负责调用；
- **Nacos**：Agent 要接入企业既有的注册与配置体系——A2A AgentCard 注册发现、Prompt 放配置中心动态调、技能走 Nacos 仓库（第 27 章提过）；
- **Scheduler**：Agent 不一定由人触发——定时巡检、周期报告这类场景把调度交给成熟的任务中间件，Agent 只实现入口。

## 生态扩展：让既有世界直接用你的 Agent

| 扩展 | 解决的问题 | 何时使用 |
| --- | --- | --- |
| Chat Completions Web | 把 Agent 包装成 OpenAI Chat Completions 兼容接口 | 已有客户端按"标准 LLM"对接，无需改对端代码；保留流式输出与工具调用过程，符合 OpenAI SSE 格式 |
| AgentScope Studio | 可视化调试台 | 开发期查看事件流、推理过程、工具调用；在 Studio 里发起 `requestUserInput` 让真人介入 |
| 在线训练（Training） | 线上流量变训练数据 | 已有 Trinity（或兼容）训练后端；做强化学习或在线微调，且不改业务调用代码——训练流水线对调用方透明 |

这三者的共同思路是**对既有生态零侵入**：客户端、调试工具、训练后端都不需要知道对面是一个 AgentScope Agent。

## 本章小结

本章没有新概念，只有一张接入企业环境的地图：治理与发现找 Higress/Nacos，定时触发找 Scheduler，兼容既有客户端用 Chat Completions Web，调试用 Studio，在线训练接 Trinity。各扩展的依赖与配置见在线文档 `docs/infra/`。

至此第四篇结束。第五篇进入 AgentScope Service——把这些集成托管起来的官方运行时。
