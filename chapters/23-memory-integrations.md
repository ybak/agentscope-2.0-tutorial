---
chapter: 23
title: 长期记忆集成
source: integration/memory/index.md, integration/memory/overview.md, integration/memory/mem0.md, integration/memory/bailian.md, integration/memory/reme.md
---

# 第 23 章 长期记忆集成

> 本章导读：用户在第 3 次会话里说的偏好，Agent 在第 10 次会话还记得吗？这就是长期记忆要解决的问题。本章讲清 `LongTermMemory` 统一接口、三种官方实现的选型，以及它们与第 14 章 Harness 内置记忆的分工。选好之后，各实现的初始化参数与检索增强特性见在线文档。

## 先分清：与第 14 章的分工

第 14 章的 Harness 内置记忆基于**工作区文件**、由框架内置 hook 维护；本章的三种实现走**外部服务**路线——记忆的抽取与检索交给所选后端。判断依据：需要与工作区强绑定、随 Workspace 版本管理的记忆用内置记忆；需要跨 Agent 共享、依赖专业记忆服务（语义去重、rerank、轨迹摘要）的场景用本章的外部实现。

## 三种实现怎么选

`io.agentscope.core.memory.LongTermMemory` 是统一接口，三种实现经 `ReActAgent.builder().longTermMemory(...)` 直接挂入：

| 扩展 | 后端 | 适合场景 |
| --- | --- | --- |
| Mem0 | Mem0 平台 / 自托管 | 通用语义记忆；`agentId / userId / runId` 三层多租户隔离与自定义 metadata 过滤 |
| Bailian | 阿里云百炼记忆服务 | 云上托管；rerank / judge / rewrite 等检索增强 |
| ReMe | 自托管 ReMe 服务 | workspace 级隔离；基于对话轨迹（trajectory）的整体摘要 |

选型一句话导航：

- 本地一把 `docker run` 跑起来 → **Mem0** 或 **ReMe**；
- 已在阿里云百炼上有记忆库 → **Bailian**；
- 需要 metadata 过滤（按业务维度切分记忆）→ **Mem0**；
- 关注会话轨迹整体摘要而非单条事实 → **ReMe**。

## 接入方式都是同一套

```java
ReActAgent agent = ReActAgent.builder()
    .name("Assistant")
    .model(model)
    .longTermMemory(memory)                       // 任选一种实现
    .longTermMemoryMode(LongTermMemoryMode.BOTH)  // 同时记录与检索
    .build();
```

`longTermMemoryMode` 决定记录与检索的组合（只记不查、只查不记、两者都开）。每个实现仅在初始化参数和过滤模型上有差异，对 Agent 侧透明。

一个容易被忽略的边界：外部记忆服务保存的是"模型认为值得记的内容"，抽取质量取决于后端的策略——把记忆当作可观测的数据而不是黑盒，定期审查记了什么、检索召回是否合理，是运营工作的一部分（评测方法与第 38 章的评估纪律一致：金标只用于判分）。

各实现的依赖、初始化、三层 ID 与 metadata 过滤的逐步配置见在线文档 `docs/integration/memory/` 对应小节。

## 本章小结

1. 外部长期记忆与 Harness 内置记忆是分工不是替代：前者跨 Agent 共享、后端专业，后者随工作区走；
2. 三种实现同一接口同一用法，选型看隔离粒度（多租户/workspace）与检索增强需求；
3. 记忆抽取质量取决于后端策略，需要当作可观测数据运营。
