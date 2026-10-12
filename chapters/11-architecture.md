---
chapter: 11
title: Harness 架构深入
source: docs/harness/architecture.md
---

# 第 11 章 Harness 架构深入

> 本章导读：当你的 Agent 要从第 2 章的最小示例走向真实业务——先启用哪项能力、三种调用方式选哪个、出了问题去哪一层找状态——你需要一张工程视角的全景图，而不是再来一遍概念介绍。第 3 章已经画过"每项能力是什么"的地图，本章换到工程视角讲 `HarnessAgent`"怎么运转"——一次执行的读取与保存节奏、三种调用方式的选择、十余项内置能力各自的配置入口、状态在调用内 / 跨调用 / 长期记忆三层之间如何流转，以及在不绕过内置链路的前提下插入自定义 middleware 的注意事项。读完本章，你在启用任何一项 Harness 能力之前，先知道它挂在执行时序的哪个位置、状态又存在哪一层。

## 你什么时候需要它

- **要给 Agent 加能力，不知道从哪配起。** 工作区、记忆、压缩、沙箱、技能……每项能力都有自己的配置入口。"能力配置总览"一节把十余项能力汇成一张检索表，按业务需要逐项启用，不必一次全开。
- **同一个 Agent，三种打开方式。** 在工作流里拿一条回复用 `call`，页面上要看实时进度用 `streamEvents`，任务要转后台、支持排队与中断恢复用 `agent.session(ctx)`。"选择调用方式"一节给出选择依据。
- **排查"数据去哪了"。** 会话恢复不了、多用户状态串了、重启后记忆还在不在——先分清状态属于调用内、跨调用还是长期记忆这三层中的哪一层，再到对应后端去查。"状态怎么流转"一节就是这张定位图。

与已学内容的关系和边界：第 3 章是地图——回答"有哪些能力、各解决什么问题"；本章是深入——回答"这些能力怎么运转、在哪配置、状态落在哪层"。各项能力本身的机制与配置细节由第 12-20 章逐个展开，本章只负责把它们挂到同一条执行时序上。

## 从概念地图到架构

第 3 章已经给出"ReActAgent → HarnessAgent → Managed Agent"三层叠加的能力地图，也看过推理-行动循环中各项能力的参与位置；本章不再重复概览，而是深入 Harness 的运转方式。先回顾一句话：`HarnessAgent` 将推理、工具与上下文管理，和工作区、长期记忆、技能、子 Agent、沙箱等能力组合在一起；`ReActAgent` 提供推理循环、工具、权限和会话上下文等基础 API，Harness 在这些能力上提供开箱即用的组合与默认配置。两者都支持 `call` 和 `streamEvents`，这部分基础用法见第 4 章。还没有跑通问答的读者，可以先按第 2 章（快速开始）操作，再按业务需要逐项增加能力。

实例生命周期方面，推荐在应用启动时配置共享 `HarnessAgent.Builder`，每次直接调用前用 `builder.build()` 创建新实例，执行结束后关闭。会话通过稳定身份与同一日志后端延续，不依赖保留上一次请求的 Java 对象——具体代码和共享实例的适用方式见第 4 章"实例生命周期"一节。后台 `AgentSession` 的实例则由会话管理器持有到后台执行结束（见第 19 章）。

## 核心工作原理

一次执行会读取当前会话状态，构建模型输入，按需调用工具，再保存结果。工作区、记忆和压缩等能力在这些步骤中生效；业务通过 builder、工具和 middleware 定制行为。

其中"构建模型输入"这一步值得单独强调：Harness 在最终模型调用边界统一组织 System、对话、任务状态和参考材料；动态业务信息通过 contextSource（动态业务数据的接入点）接入。每轮请求如何选择材料、如何计算预算，配置、默认行为和限制见第 13 章（上下文管理）。

## 选择调用方式

执行节奏清楚了，接下来是业务侧的选择：以哪种方式调用 Agent。

- **获取回复或把 Agent 接入工作流**：使用 `call(input, ctx)`。
- **在当前请求内展示实时文本和工具进度**：使用 `streamEvents(input, ctx)`。
- **让任务在后台继续，支持排队、补充要求和中断恢复**：使用 `agent.session(ctx)` 提供的 `AgentSession`。

直接调用也支持多轮会话，并使用默认的 Session Log 和 checkpoint 保存状态。AgentSession 进一步负责持久接收任务、安排执行和关联待办；业务无需为这些操作自行管理执行订阅。两种方式使用同一个 Agent 的模型、工具和中间件配置。

调用示例见第 4 章（Agent 与 ReAct 循环），完整的后台会话流程见第 19 章（会话日志与恢复）。已有工作流调度器的应用可继续直接调用；托管 HTTP 接入使用 Service 的 Session API（见第 31 章）。

## 能力配置总览

第 3 章的表格回答了"每项能力解决什么问题"；下表进一步补充"配置或操作入口"，作为本篇第 12-20 章的检索目录——按应用需要配置能力，或调用会话操作。

| 能力 | 解决什么问题 | 配置或操作 | 详见 |
|---|---|---|---|
| 工作区驱动的人格 | 人格 / 知识 / 子 agent / 技能 / MCP 白名单都以文件形式存在 | `.workspace(path)` | 第 12 章 |
| 状态持久化与执行日志 | 完整事实、checkpoint、跨请求和跨节点恢复 | 默认 EVENT_LOG；`.sessionLogStore(...)` 替换 | 第 19 章 |
| 会话任务管理 | 后台执行、持久排队、补充信息和恢复 | `agent.session(ctx)` | 第 19 章 |
| 双层长期记忆 | 长会话里有价值的事实自动沉淀到 `MEMORY.md` | 默认开启；`.memory(...)` 定制 prompt / 触发策略 | 第 14 章 |
| 对话压缩 | 上下文有界；模型真的溢出时强制重试 | `.compaction(...)` | 第 13 章 |
| 大工具结果卸载 | 超 80K 字符的结果落盘 + 占位符 | `.toolResultEviction(...)` | 第 13 章 |
| 子 agent 编排 | 委派给子 agent，支持同步或后台，自动反向通知 | `.subagent(...)` 或 `workspace/subagents/` | 第 16 章 |
| 可插拔文件系统 | 本机 + shell / 共享存储 / 沙箱，不改代码切换 | `.filesystem(...)` | 第 12 章 |
| 沙箱隔离 | 文件与命令隔离，跨调用恢复，多副本部署 | `.filesystem(new DockerFilesystemSpec()...)` | 第 18 章 |
| 计划模式 | 只读思考阶段 + HITL 退出 | `.enablePlanMode()` | 第 17 章 |
| 技能装配 | 来自 Git / Nacos / MySQL / classpath / 工作区 | `.skillRepository(...)` | 第 15 章 |
| MCP 集成与工具白名单 | 声明式 MCP server + 工具粒度允许 / 拒绝 | `workspace/tools.json` | 第 12 章 |
| Channel 路由 | 会话管理、per-session 并发控制、多 agent 路由、流式事件 | `agent.channel(...)` / `GatewayBootstrap` | 第 20 章 |

## 状态怎么流转

状态分三层，框架自动在层之间搬数据。

- **调用内状态** —— `AgentState`（对话上下文、权限规则、Plan Mode 状态、工具状态）加上 `RuntimeContext`（`sessionId`、`userId`、沙箱句柄、extra）。
- **跨调用状态** —— 默认从 Session Log 的 checkpoint 及后续可应用事实恢复；完整历史保留，JSONL 仅按需导出。LEGACY 使用 AgentStateStore；文件、子任务及 sandbox 元数据仍由各自后端保存。
- **长期记忆** —— 跨 session 累积：`memory/YYYY-MM-DD.md` 只追加；后台节流任务把它周期合并到 `MEMORY.md`；`MEMORY.md` 每次 call 加载为参考上下文，不作为 System 指令。

三个值得记住的规律：

- 最终请求每轮重新构建，但工作区文件按 call 加载；修改 AGENTS.md 或 MEMORY.md 后下一次 call 生效，不需要重启。
- 压缩、记忆提炼、后台维护都被节流闸门（限频：强制两次运行之间留出最小间隔）管着，不会每轮都跑。
- `AgentState` 的持久化由 Core 执行生命周期管理：EVENT_LOG 写 checkpoint，LEGACY 写旧状态存储。Harness 配置默认日志后端。

`AgentState` 与 `RuntimeContext` 的字段细节、LEGACY / EVENT_LOG 两种执行模式的差异，见第 8 章（上下文）。

## 自己加 middleware 时要注意什么

要在不绕过 Harness 内置链路的前提下插入自定义行为：

- 用 `.middleware(...)`：你的 middleware 会跑在所有 Harness 内置之前。
- 通过 agent 上的 `RuntimeContext` 读当前调用的身份（`userId` / `sessionId`）。
- 读写工作区用 `harnessAgent.getWorkspaceManager()`，它会按当前文件系统模式（本机 / 沙箱 / 远端）正确路由。直接 `java.nio.Files` 在沙箱或远端模式下会写错地方。

middleware 六类扩展点的完整说明见第 9 章（中间件）。

## 相关文档

- 第 19 章（会话日志与恢复）—— 后台任务、排队、交互和续做
- 第 40 章（最佳实践：可恢复会话聊天）—— 从提交任务到前端断线续传的完整应用
- 第 12 章（工作区与文件系统）—— 目录结构、指令与参考材料的来源、`tools.json`
- 第 8 章（上下文）—— `AgentState`、`RuntimeContext`、`AgentStateStore` 持久化、多用户隔离
