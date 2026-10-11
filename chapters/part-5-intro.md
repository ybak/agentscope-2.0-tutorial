---
title: 第五篇 AgentScope Service 平台
source: 新写
---

前四篇都在回答同一件事：如何用 SDK 把 Agent 能力构建进自己的应用。本篇转向另一种形态——AgentScope Service，一个可自托管的 Agent as a Service 平台。平台上的托管 Agent（Managed Agent）基于与 Harness SDK 相同的 HarnessAgent 内核，但运行管理交给了共享平台：你定义 Agent 要完成的工作并配置模型与工具，应用提交任务后由 Service 运行 Agent、保存执行过程，业务团队无需为每个 Agent 应用分别建设和维护运行服务。第 29 章从 Docker Compose 与 Kubernetes 两条路径部署平台；第 30 章创建并运行托管 Agent，并覆盖 Workspace 共享能力与 Hosted、External 两类接入已有 Agent 的方式；第 31 章是全书篇幅最长的一章，沿着"提交 → 事件 → 文件 → 记忆 → 密钥 → 工具 → 渠道"讲透 Session API 的完整调用面；第 32 章用 Team 与 Workflow 组织多 Agent 协作；第 33 章收拢运维、Console、权限配置与运营；第 34 章用六个实战案例演示如何把平台接回真实业务。

本篇的各章共享同一条对象主线：**Agent 描述可复用的能力，Session 代表应用围绕一项工作建立的交互记录，Turn 是其中每一轮提交的任务**。Managed、Hosted、External 三类运行绑定不同，但业务应用始终用同一套 Session API 创建会话、提交任务、订阅 SSE 事件并处理待办——更新执行目标不需要改接入代码，只需要在创建 Session 时换一个 `target`。也因此，多数小节可以直接当操作手册抄：准备 `BASE_URL`、`TOKEN`、`TENANT`、`NAMESPACE` 四个环境变量后，curl 命令逐条可跑。

读完本篇，你可以把一个或多个业务应用架在同一个自托管平台上：平台团队集中维护运行资源，业务团队在 Console 或 API 中配置和改进自己的 Agent，再围绕 Session、Turn 与 Artifact 组织产品内的交互与交付。第六篇将进入更进一步的 JEV 语义判断——为平台与 Harness 的执行质量建立可评估的判断层。
