---
title: 附录 B：术语表
---

# 附录 B：术语表

> 附录导读：本表汇总全书 52 个高频术语，按英文字母顺序排列；释义提炼自相应章节的实际表述，细节请参阅正文对应章节（可按目录或术语出现的篇次查找）。

| 术语 | 释义 |
| --- | --- |
| A2A | Agent 间互通协议；把远端 Agent 包装成本地 Agent 互相调用。 |
| AG-UI | 前端协议适配层，把 AgentEvent 流转换为浏览器可实时渲染的事件。 |
| AgentEvent | Agent 执行过程的类型化事件，由 `streamEvents()` 流式返回。 |
| AgentSession | 会话操作入口，提供提交、引导、回复待办与中断恢复，支持后台执行。 |
| AgentStateStore | 按用户与会话分桶持久化 Agent 状态的存储接口，支撑跨副本恢复。 |
| Builder | Agent 的构建器；应用共享一个 Builder，每次请求构建新的轻量实例。 |
| Channel | 把钉钉、飞书等消息平台适配成会话管理、并发控制与多 Agent 路由模型的接入层。 |
| Checkpoint | 保存的会话状态快照，用于中断续做、页面刷新恢复与服务重启后的核对。 |
| Choice | JEV 单选题类型，返回选项、完整分布和置信度，用于模型路由、动作选择。 |
| Compaction | 对话压缩；结构化保留任务目标、关键发现与下一步计划，使上下文长度有界。 |
| ContentBlock | 消息的内容块模型（TextBlock 等），构成 Msg 的基本单元。 |
| Context | 一次调用中模型可见的信息，由指令、历史、任务状态与参考材料分层组织。 |
| DistributedStore | 分布式存储一键配置，统一覆盖 Agent 状态、工作区 KV、沙箱快照与并发锁。 |
| Endpoint | Service 中将 Agent、Team 或 Workflow 发布成的统一调用端点。 |
| External Agent | 已运行的自有 Agent 应用注册接入 Service，进程仍由你部署与运维。 |
| Formatter | 把消息列表转换为特定模型请求格式的组件，部分提供商提供专用实现。 |
| Guardrail | JEV 内容护栏；模型调用前检查输入、发布前检查输出，区分放行、复核与阻断。 |
| Harness | 工程化 SDK 层，在 ReAct 循环上叠加工作区、记忆、沙箱等能力。 |
| HarnessAgent | 封装 ReActAgent 的 Agent，内置工作区、记忆、技能与沙箱等能力。 |
| HITL | Human-in-the-Loop；敏感工具调用暂停，等用户确认后再继续。 |
| Hosted Agent | 经 Runtime Host 把本机上的 Coding Agent 接入平台的 Agent。 |
| Invocation API | Service 对外的统一调用接口：提交工作、查询结果、接收事件与处理待办。 |
| JEV | 为 Harness 中需要语义判断的环节提供类型化结果，如工具适用性与回答依据检查。 |
| Knowledge | 接入外部知识库的统一接口；Agent 推理时检索文档片段，再交给模型生成。 |
| LongTermMemory | Harness 双层长期记忆；跨会话有价值的事实自动沉淀到 `MEMORY.md`。 |
| Managed Agent | 以 HarnessAgent 为内核、由 Service 托管运行的 Agent。 |
| MCP | Model Context Protocol；以声明式 server 接入外部工具服务。 |
| Middleware | 在六类扩展点注入自定义逻辑的机制，提供洋葱式、变换式、通知式 hook。 |
| ModelRegistry | 把字符串模型 id 解析为 ChatModel 实例并缓存，覆盖主流提供商。 |
| Msg | 代表完整对话轮次的消息结构，由 ContentBlock 组成。 |
| Noul | JEV 是非判断题类型，返回陈述为真的概率，用于工具适用、回答是否有依据。 |
| Permission | 拦截每次工具调用的权限系统，由规则、权限模式与内置检查三层决策。 |
| Plan Mode | 动手前的只读规划阶段；写下计划经 HITL 确认后再进入执行。 |
| RAG | 检索增强生成；Agent 检索外部知识库文档，再交模型生成有依据的回答。 |
| ReAct | "推理 → 工具调用 → 观察"循环，全部 Agent 的执行基础。 |
| ReActAgent | 无状态推理核心，实现 ReAct 循环并提供权限、中间件等基础能力。 |
| Runtime Host | 运行 Coding Agent provider 的主机，负责启动与回报执行结果。 |
| RuntimeContext | 每次调用携带的用户与会话身份，随调用透传，支撑多用户隔离。 |
| Sandbox | 隔离执行环境（Docker 等），把不可信代码与命令关进容器。 |
| Score | JEV 评分题类型，返回等级分布、加权分数和置信度，用于风险严重度评估。 |
| Session Log | 保存输入、消息、工具执行与工作状态的执行日志，支撑刷新与断线恢复。 |
| Skill | 以 SKILL.md 描述的能力包，来自 Git、Nacos 等仓库或工作区。 |
| SSE | Server-Sent Events；单向推送事件流，支持断线续传。 |
| Subagent | 接收主 Agent 委派任务的子 Agent，支持同步或后台执行与自动反向通知。 |
| Team | Service 中持续分工的多 Agent 协作形态，Lead 协调成员并接受团队任务。 |
| Tool | 扩展 Agent 行动能力的函数单元，用 `@Tool` 注解或 ToolBase 定义。 |
| Tool Guard | JEV 执行防护；在工具派发前检查受保护操作是否得到当前证据支持。 |
| Toolkit | 工具集合，管理工具注册、工具组与执行模式（串行或并行）。 |
| Trace Evaluation | 轨迹评估；采集并评估 Agent 轨迹的工具使用、回答依据等八项指标。 |
| Turn | 向 Session 提交一次任务创建的执行单元，跟踪本轮执行的进度与结果。 |
| Workflow | Service 中固定流程的编排，支持定义、校验、发布、运行与人工审批。 |
| Workspace | Harness 的工作区目录，以文件形式承载人格、知识、技能、子 Agent 等定义。 |
