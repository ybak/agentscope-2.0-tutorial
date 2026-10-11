---
chapter: 23
title: 长期记忆集成
source: integration/memory/index.md, integration/memory/overview.md, integration/memory/mem0.md, integration/memory/bailian.md, integration/memory/reme.md
---

# 第 23 章 长期记忆集成

> 本章导读：讲解 AgentScope 在多轮、多会话之间持久化用户偏好、事实与要点的接口 `LongTermMemory`，以及三种开箱即用的后端实现：通用语义记忆 Mem0（支持多租户三层 ID 与 metadata 过滤）、云端托管的百炼记忆（rerank / judge / rewrite 检索增强）、基于对话轨迹抽取的 ReMe（workspace 级隔离）。三者实现同一接口，通过 `longTermMemory(...)` 直接挂入 Agent，本章末尾各自的 Builder 参数表可以直接对照选型。读完本章，你可以为 Agent 加上跨会话的长期记忆，并按隔离与检索质量需求选择后端。

`LongTermMemory` 是 AgentScope 用来在多轮、多会话之间持久化用户偏好、事实、要点的接口。`agentscope-extensions-*` 仓库下提供了对接主流记忆服务的开箱即用实现：

| 扩展 | 后端 | 适合场景 |
| --- | --- | --- |
| Mem0 | [Mem0](https://mem0.ai/) 平台 / 自托管 | 通用语义记忆，支持多租户隔离与自定义 metadata 过滤 |
| Bailian | 阿里云百炼记忆服务 | 云上托管，支持 rerank / judge / rewrite 等高级特性 |
| ReMe | 自托管 ReMe 服务 | 工作区级别记忆，支持轨迹（trajectory）摘要 |

三者都实现了同一个 `io.agentscope.core.memory.LongTermMemory` 接口，可通过 `ReActAgent.builder().longTermMemory(...)` 直接挂入 Agent，使用方式相同：

```java
ReActAgent agent = ReActAgent.builder()
    .name("Assistant")
    .model(model)
    .longTermMemory(memory)                       // 任选一种实现
    .longTermMemoryMode(LongTermMemoryMode.BOTH)  // 同时记录与检索
    .build();
```

## 选型建议

- **想要本地一把 `docker run` 跑起来 → Mem0** 或 **ReMe**
- **已经在阿里云百炼上有记忆库 → Bailian**
- **需要 metadata 过滤（按业务维度切分） → Mem0**
- **关注会话轨迹整体摘要 → ReMe**

每个实现仅在初始化参数和过滤模型上有差异，对 Agent 侧透明，细节见以下各节。

## Mem0

`agentscope-extensions-mem0` 接入 [Mem0](https://mem0.ai/) 记忆服务，提供基于向量检索 + LLM 抽取的长期记忆能力，支持 Mem0 Platform、自托管以及本地部署三种模式。

### 何时使用

- 需要给 Agent 加上跨会话的事实记忆，例如用户偏好、历史决策。
- 想用 `agentId / userId / runId` 三层 metadata 隔离不同租户、不同 session 的记忆。
- 想用自定义 metadata（例如 `category=travel`）做检索过滤。

### 添加依赖

```xml
<dependency>
    <groupId>io.agentscope</groupId>
    <artifactId>agentscope-extensions-mem0</artifactId>
    <version>${agentscope.version}</version>
</dependency>
```

### 快速上手

```java
import io.agentscope.core.memory.mem0.Mem0LongTermMemory;
import io.agentscope.core.memory.mem0.Mem0ApiType;

// 1. 构造记忆实例（本地无鉴权部署）
Mem0LongTermMemory memory = Mem0LongTermMemory.builder()
    .agentName("Assistant")
    .userId("user_123")
    .apiBaseUrl("http://localhost:8000")
    .apiType(Mem0ApiType.SELF_HOSTED)
    .build();

// 2. 挂到 Agent
ReActAgent agent = ReActAgent.builder()
    .name("Assistant")
    .model(model)
    .longTermMemory(memory)
    .longTermMemoryMode(LongTermMemoryMode.BOTH)
    .build();

// 3. 正常调用，记忆会自动在 record / retrieve 之间往返
agent.call(new UserMessage("我出差喜欢住民宿")).block();
```

### 部署模式

`Mem0ApiType` 决定客户端调用的 URL 与鉴权方式：

| 枚举 | 用途 | apiBaseUrl 示例 | apiKey |
| --- | --- | --- | --- |
| `PLATFORM`（默认） | 直连 Mem0 SaaS | `https://api.mem0.ai` | 必填 |
| `SELF_HOSTED` | 自托管 Mem0 Server | `http://your-host:8000` | 视部署而定 |

### 多租户隔离

`agentName / userId / runName` 是 Mem0 用来组织记忆的三层 ID：

```java
Mem0LongTermMemory memory = Mem0LongTermMemory.builder()
    .agentName("travel-bot")     // 跨用户共享的 Agent 维度记忆
    .userId("alice")             // 用户维度（租户）
    .runName("trip-2026-spring") // 单次会话维度
    .apiBaseUrl("http://localhost:8000")
    .build();
```

至少要提供其中之一，全部为空时 `build()` 抛出 `IllegalArgumentException`。检索时只会返回 metadata 完全匹配的记忆。

### 自定义 metadata 过滤

`metadata(...)` 同时影响写入和读取：写入时随记忆持久化，检索时作为 filter 注入。

```java
Map<String, Object> tags = Map.of(
    "category", "travel",
    "project_id", "proj_001"
);

Mem0LongTermMemory memory = Mem0LongTermMemory.builder()
    .agentName("Assistant")
    .userId("user_123")
    .apiBaseUrl("http://localhost:8000")
    .metadata(tags)
    .build();

// 之后所有 record() 都带上 tags，retrieve() 也只命中相同 tags 的记忆
```

适合按项目、按业务线切分知识；如果只是按用户切分，用 `userId` 就够了。

### Builder 配置参数

| 方法 | 是否必填 | 默认 | 说明 |
| --- | --- | --- | --- |
| `apiBaseUrl(String)` | ✅ | - | Mem0 服务地址 |
| `apiKey(String)` | 视部署 | - | API Key；本地无鉴权部署可省略 |
| `apiType(Mem0ApiType)` | ❌ | `PLATFORM` | 选择 SaaS 或自托管路由 |
| `agentName(String)` | 三选一 | - | Agent 维度 ID |
| `userId(String)` | 三选一 | - | 用户维度 ID |
| `runName(String)` | 三选一 | - | 会话/运行维度 ID |
| `metadata(Map)` | ❌ | `null` | 写入与检索时的额外 filter |
| `timeout(Duration)` | ❌ | `60s` | HTTP 请求超时 |

> 三个 ID（agentName / userId / runName）至少要填一个，否则 `build()` 抛 `IllegalArgumentException`。

## 百炼记忆

`agentscope-extensions-memory-bailian` 接入阿里云百炼的长期记忆服务，提供云端托管、企业级的语义记忆能力，支持 rerank、judge、rewrite 等检索增强特性。

### 何时使用

- 已经在使用阿里云百炼平台，希望直接复用平台上的记忆库。
- 关注检索质量，想启用百炼提供的 rerank / judge / rewrite 流水线。
- 需要按 `userId` + `memoryLibraryId` + `projectId` 三个维度做记忆隔离。

### 添加依赖

```xml
<dependency>
    <groupId>io.agentscope</groupId>
    <artifactId>agentscope-extensions-memory-bailian</artifactId>
    <version>${agentscope.version}</version>
</dependency>
```

### 快速上手

```java
import io.agentscope.core.memory.bailian.BailianLongTermMemory;

try (BailianLongTermMemory memory = BailianLongTermMemory.builder()
        .apiKey(System.getenv("DASHSCOPE_API_KEY"))
        .userId("user_001")
        .memoryLibraryId("lib_xxxxx")
        .projectId("proj_xxxxx")
        .build()) {

    ReActAgent agent = ReActAgent.builder()
        .name("Assistant")
        .model(model)
        .longTermMemory(memory)
        .longTermMemoryMode(LongTermMemoryMode.BOTH)
        .build();

    agent.call(new UserMessage("帮我每天 9 点提醒喝水")).block();
}
```

`BailianLongTermMemory` 实现了 `AutoCloseable`，建议用 try-with-resources，确保底层 HTTP 连接被释放。

### 检索增强开关

百炼记忆服务在召回基础上还支持三个流水线开关：

```java
BailianLongTermMemory memory = BailianLongTermMemory.builder()
    .apiKey(apiKey)
    .userId("user_001")
    .memoryLibraryId("lib_xxxxx")
    .topK(20)
    .minScore(0.4)
    .enableRerank(true)   // 二次重排，更准但更慢
    .enableJudge(true)    // 让 LLM 判断结果是否真的相关
    .enableRewrite(true)  // 在写入时做改写、合并
    .build();
```

不需要的特性建议保持默认（关闭），可以减少调用延迟和费用。

### 消息过滤行为

百炼记忆只会写入用户和助手之间的"自然"对话：

- 仅写入 `MsgRole.USER` 与 `MsgRole.ASSISTANT` 消息。
- 含 `ToolUseBlock` 的助手消息（即工具调用请求）会被跳过。
- 含 `<compressed_history>` 标记的压缩历史消息也会被跳过，避免重复存储。

如果你希望让工具调用结果进入记忆，需要自己用更上层的逻辑写入，再调用 `record(...)`。

### Builder 配置参数

| 方法 | 是否必填 | 默认 | 说明 |
| --- | --- | --- | --- |
| `apiKey(String)` | ✅ | - | 百炼 DashScope API Key |
| `userId(String)` | ✅ | - | 用户维度 ID |
| `memoryLibraryId(String)` | ❌ | - | 记忆库 ID |
| `projectId(String)` | ❌ | - | 项目 ID |
| `profileSchema(String)` | ❌ | - | 用户画像 schema ID |
| `apiBaseUrl(String)` | ❌ | `https://dashscope.aliyuncs.com` | 自定义网关时使用 |
| `topK(Integer)` | ❌ | `10` | 检索返回条数上限 |
| `minScore(Double)` | ❌ | `0.3` | 最低相似度阈值（0~1） |
| `enableRerank(Boolean)` | ❌ | `false` | 是否启用 rerank |
| `enableJudge(Boolean)` | ❌ | `false` | 是否启用 LLM judge |
| `enableRewrite(Boolean)` | ❌ | `false` | 写入时是否启用 rewrite |
| `metadata(Map)` | ❌ | - | 写入时附带的自定义 metadata |
| `httpTransport(HttpTransport)` | ❌ | 默认实现 | 替换 HTTP 客户端 |

## ReMe

`agentscope-extensions-reme` 接入自托管的 ReMe 记忆服务，特点是基于 **trajectory（对话轨迹）** 抽取长期记忆，并按 **workspace** 隔离。

### 何时使用

- 想要一个轻量的本地记忆服务，启动门槛低。
- 关注整段对话轨迹的摘要，而不是单条消息级的存储。
- 用 `userId` 表达逻辑工作区，每个用户一份独立记忆。

### 添加依赖

```xml
<dependency>
    <groupId>io.agentscope</groupId>
    <artifactId>agentscope-extensions-reme</artifactId>
    <version>${agentscope.version}</version>
</dependency>
```

### 快速上手

```java
import io.agentscope.core.memory.reme.ReMeLongTermMemory;

ReMeLongTermMemory memory = ReMeLongTermMemory.builder()
    .userId("task_workspace")            // 映射到 ReMe 的 workspace_id
    .apiBaseUrl("http://localhost:8002") // 你的 ReMe Server 地址
    .build();

ReActAgent agent = ReActAgent.builder()
    .name("Assistant")
    .model(model)
    .longTermMemory(memory)
    .longTermMemoryMode(LongTermMemoryMode.BOTH)
    .build();
```

`userId` 在 ReMe 里实际作为 `workspace_id`，这是 ReMe 用来切分记忆的最小单位。

### 工作机制

- **写入（record）**：把过滤后的对话拼成一个 `ReMeTrajectory`，作为整体送给 ReMe 的 `add` 接口；服务端再用 LLM 把轨迹抽取成可检索的记忆片段。
- **检索（retrieve）**：以当前消息为 query 调用 ReMe 的 `search`，优先返回服务端聚合的 `answer`，没有时退化为多个 memory 片段拼接。

写入时遵循与 Bailian 相同的过滤策略：

- 只保留 `USER` 与 `ASSISTANT` 消息。
- 跳过含 `ToolUseBlock` 的助手消息（工具调用请求不入记忆）。
- 跳过含 `<compressed_history>` 标记的压缩历史。

### Builder 配置参数

| 方法 | 是否必填 | 默认 | 说明 |
| --- | --- | --- | --- |
| `userId(String)` | ✅ | - | 工作区 ID（写入和检索都基于它） |
| `apiBaseUrl(String)` | ✅ | - | ReMe 服务地址，例如 `http://localhost:8002` |
| `timeout(Duration)` | ❌ | `60s` | HTTP 请求超时 |

> ReMe 暂未提供更细粒度的 metadata 过滤；如果需要按业务标签切分，建议在 `userId` 里编码命名空间（例如 `tenant-a:project-1`）。
