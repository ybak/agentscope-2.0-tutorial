# CopilotKit:从前端接入 AI Agent

> 状态:规划中

## 定位

在前端应用中植入 copilot 体验,从组件到自治 Agent。本书聚焦**前端 AI 集成**:用 CopilotKit 在 React 应用中实现流式输出、HITL(人工介入)与工具透明度的前端交互,让智能体能力以自然的方式进入业务界面。

## 目标读者

- 前端工程师:为业务系统接入 copilot 体验与 Agent 交互界面
- 与后端编排框架对接的全栈工程师(涉及 Runtime 配置部分)

## 与平台缺口地图的对应

以下条目来自[设计规格附录 A](../../docs/superpowers/specs/2026-10-24-multi-book-restructure-design.md)(跨境电商智能体多租户平台 · 技术缺口地图):

| 角色 | 技术域 | 具体内容 | 覆盖 |
|------|--------|---------|------|
| 开发 | 前端 AI 集成 | CopilotKit(React) | 🔜 copilotkit 书 |

## 章节规划(初稿)

| 章节 | 内容一句话 |
|------|-----------|
| 第 1 章 初识 CopilotKit | CopilotKit 的定位、架构与在 React 应用中的角色 |
| 第 2 章 快速开始 | 最小可运行的 copilot 前端接入示例 |
| 第 3 章 Copilot 组件与自定义 UI | 内置侧边栏/组件体系与自定义聊天界面 |
| 第 4 章 流式输出 | 流式渲染、状态同步与打字机体验的实现要点 |
| 第 5 章 接入后端 Agent | Runtime 配置,与 AgentScope 等后端编排框架对接 |
| 第 6 章 工具透明度 | 工具调用过程在前端的可视化呈现与中间态展示 |
| 第 7 章 HITL 人工介入 | 人机协同确认、审批交互与前端打断 |
| 第 8 章 自治 Agent 与生产化 | 从辅助组件到自治 Agent 的演进路径与上线考量 |

> 章节规划为初稿,启动时细化。

---

元数据(bookId / title / tagline)以 `build/books/registry.mjs` 为准。
