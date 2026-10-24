---
chapter: 22
title: RAG 知识库集成
source: integration/rag/index.md, integration/rag/overview.md, integration/rag/simple.md, integration/rag/dify.md, integration/rag/haystack.md, integration/rag/ragflow.md, integration/rag/bailian.md
---

# 第 22 章 RAG 知识库集成

> 本章导读：想让模型答得准，就要让它先查资料再回答——RAG（Retrieval-Augmented Generation，检索增强生成）。本章讲清 AgentScope 接入外部知识库的统一接口 `Knowledge`、五种官方实现的选型，以及"接入方式都是同一套"的设计含义。选好之后，每种实现的逐步配置（依赖、初始化参数、检索调优）见在线文档。

## 五种实现怎么选

`io.agentscope.core.rag.Knowledge` 是接入外部知识库的统一接口：Agent 在推理时通过它检索文档片段，再交给模型生成。`agentscope-extensions-*` 仓库提供五种实现：

| 扩展 | 类型 | 适合场景 |
| --- | --- | --- |
| Simple | 自建：embedding + 向量库 | 对接自家向量库（PgVector / Milvus / Qdrant / Elasticsearch / 内存） |
| Bailian | 阿里云百炼知识库 | 用百炼托管的企业级知识库 |
| Dify | Dify 数据集 | 已经在 Dify 上维护知识库 |
| HayStack | 自托管 HayStack RAG | 已经基于 HayStack 搭建索引流水线 |
| RAGFlow | RAGFlow 服务 | 需要 OCR、知识图谱增强的复杂文档场景 |

一句话导航：**已有知识库平台就接它的适配（Dify / RAGFlow / 百炼 / HayStack）；从零自建或要用自家向量库选 Simple**。选型的真正依据是"索引流水线维护在哪里"——检索后端与文档写入应该在同一个平台治理。

## 接入方式都是同一套

无论选哪种实现，Agent 侧的使用方式完全一致：

```java
ReActAgent agent = ReActAgent.builder()
    .name("Assistant")
    .model(model)
    .knowledge(knowledge)        // 任选一种 Knowledge 实现
    .ragMode(RAGMode.AGENTIC)    // 或 STATIC、NONE
    .build();
```

也可以包装成工具，让 Agent 自主决定是否检索：

```java
KnowledgeRetrievalTools tools = new KnowledgeRetrievalTools(knowledge);
Toolkit toolkit = new Toolkit();
toolkit.registerObject(tools);
```

`AGENTIC` 模式下模型在推理循环里自主调用检索；`STATIC` 模式在每轮推理前固定检索一次。两者怎么选取决于你的场景里"要不要检索"本身是否需要判断——大多数知识问答用 AGENTIC，检索成本高或必须检索的场景用 STATIC。

## 一个值得理解的设计：管控分离

除 Simple 外的所有实现**只负责检索**——文档写入、切片、索引维护保留在对应平台上，Java 侧统一读取。这不是偷懒，而是管控边界的划分：知识库的内容治理（谁能上传、怎么切分、何时更新）留在平台侧的权限与流程里，Agent 侧只拿到一个只读的检索视图。因此多个实现才可能在使用侧完全可替换。

各实现的依赖、初始化参数、检索调优（topK、score 阈值、重排）等逐步配置见在线文档 `docs/integration/rag/` 对应小节；JEV 对检索结果的语义过滤（注入识别、依据检查）见第 37.2 节。

## 本章小结

1. `Knowledge` 一个接口、五种实现，Agent 侧用法完全一致，后端可替换；
2. 选型依据是"索引流水线维护在哪里"，不是功能对比表；
3. 除 Simple 外只做检索——管控分离让内容治理留在平台侧。
