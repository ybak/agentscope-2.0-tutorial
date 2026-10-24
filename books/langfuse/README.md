# Langfuse:LLM 可观测与评估

> 状态:规划中

## 定位

LLM 应用的追踪、评估与 Prompt 管理。本书以 Langfuse 为抓手,覆盖 trace 与成本监控、评估数据集与评分、Prompt 版本管理与 A/B 实验——测试、运维、运营三个角色共用一本手册;并补充 LLM 质量工程专题(Prompt 回归、幻觉检测、红队)。

## 目标读者

- 测试工程师:搭建评估数据集与评分体系,做 Prompt 回归与质量工程
- 运维工程师:trace 采集、成本监控与线上质量看板
- 运营人员:Prompt 版本管理、A/B 实验与 badcase 运营

## 与平台缺口地图的对应

以下条目来自[设计规格附录 A](../../docs/superpowers/specs/2026-10-24-multi-book-restructure-design.md)(跨境电商智能体多租户平台 · 技术缺口地图):

| 角色 | 技术域 | 具体内容 | 覆盖 |
|------|--------|---------|------|
| 测试 | Agent 评估 | 轨迹评估、数据集与评分 | ✅ 书内第 39 章 + 🔜 langfuse 书 |
| 测试 | LLM 质量工程 | Prompt 回归、幻觉检测、红队 | 🔜 langfuse 书 |
| 运维 | LLM 可观测 | Langfuse trace/成本 | 🔜 langfuse 书 |
| 运营 | Prompt 运营 | 版本管理、A/B | 🔜 langfuse 书内章 |

## 章节规划(初稿)

| 章节 | 内容一句话 |
|------|-----------|
| 第 1 章 初识 Langfuse | LLM 可观测与评估平台全景,与日志系统/传统 APM 的区别 |
| 第 2 章 快速开始 | SDK 接入与第一条 trace |
| 第 3 章 Trace 与链路追踪 | span 层级、多轮会话串联与 trace 采集规范 |
| 第 4 章 成本与性能监控 | token 统计、成本核算、延迟分析与告警看板 |
| 第 5 章 Prompt 管理 | Prompt 版本管理、与 trace 的关联与回滚 |
| 第 6 章 数据集与评分 | 评估数据集建设、LLM-as-judge 与人工评分 |
| 第 7 章 A/B 与线上实验 | Prompt A/B 实验、版本切换与效果对比 |
| 第 8 章 LLM 质量工程 | Prompt 回归测试、幻觉检测与红队演练 |

> 章节规划为初稿,启动时细化。

---

元数据(bookId / title / tagline)以 `build/books/registry.mjs` 为准。
