---
chapter: 28
title: 基础设施与生态工具
source: integration/overview.md, integration/infrastructure/index.md, integration/infrastructure/overview.md
---

# 第 28 章 基础设施与生态工具

> 本章导读：第四篇的收尾章。开篇先给出 AgentScope 集成扩展的全景地图——把模型、分布式存储、沙箱、记忆、RAG、技能仓库、Channel、协议八组扩展分别指回第 18、21~27 章；然后讲余下两组：基础设施（Higress AI 网关经 MCP 引入网关工具、Nacos 统一控制面、Scheduler 让 Agent 按 CRON 定时跑）与生态扩展（Chat Completions Web 把 Agent 暴露成 OpenAI 兼容接口、Studio 可视化调试、Training 在线训练闭环）。读完本章，你可以把 Agent 接入企业既有技术栈（网关、注册中心、调度器），并按需开启调试与训练流水线。

AgentScope Java 与第三方系统、生态服务的集成扩展都是 `agentscope-extensions/` 下的独立 Maven 模块，按需引入即可。按主题分为以下几组：

## 集成扩展全景

| 分组 | 内容 | 详见 |
| --- | --- | --- |
| 模型提供商 | 十家提供商的独立模型扩展模块，`agentscope-core` 只保留共享模型契约；完整模型创建方式、Spring Boot 配置、formatter、credential 和高级 registry 行为另见第 6 章 | 第 21 章 |
| 分布式存储（Distributed Store） | 生产多副本部署所需的全链路分布式存储：`DistributedStore` 一键配置 Agent 状态、工作区文件系统、沙箱快照与并发锁，后端 Redis / JDBC / 阿里云 OSS（另有 MongoDB）可混合搭配 | 第 24 章 |
| 沙箱执行环境（Sandbox） | 隔离的代码执行环境，均为 `SandboxFilesystemSpec` 实现：Docker 内置在 harness 中（无需额外依赖），Kubernetes、AgentRun（阿里云）、Daytona、E2B 为独立扩展模块 | 第 18 章 |
| 记忆（Memory） | 跨会话持久化用户偏好与事实，所有实现都符合 `LongTermMemory` 接口：Mem0、百炼记忆、ReMe | 第 23 章 |
| RAG 知识库 | 通过 `Knowledge` 接口接入不同的检索后端：Simple（自建 embedding + 向量库）、百炼知识库、Dify、HayStack、RAGFlow | 第 22 章 |
| 技能仓库（Skill） | `AgentSkillRepository` 的多种存储实现：Git、MySQL、PostgreSQL，也可以使用 Nacos 技能仓库（见本章"Nacos"一节） | 第 27 章 |
| Channel 适配器 | 通过 Harness Channel 接口将 Agent 接入消息平台：钉钉、飞书 / Lark、GitHub、GitLab、企业微信 | 第 25 章 |
| 智能体协议 | 让 Agent 与外部世界以标准方式交互：A2A（Agent-to-Agent）、AG-UI、Agent Protocol | 第 26 章 |
| 基础设施 / 中间件 | 把 Agent 接到企业基础设施：Higress AI 网关、Nacos、Scheduler（Quartz / XXL-Job） | 本章 |
| 生态扩展 | 运行环境、语言生态、调试与训练流水线：Chat Completions Web、AgentScope Studio、在线训练（Training） | 本章 |

> **注意**：`agentscope-extensions-model-e2e-tests` 是仓库测试模块，不是面向用户的模型集成依赖。

> **注意**：若你正在使用 Spring Boot，绝大多数扩展都有对应的 `agentscope-spring-boot-starter-*` 一键接入版本，可减少手动装配代码。

前八组已分别在第 18 章与第 21~27 章展开；本章余下各节讲最后两组——基础设施与生态扩展。

## 基础设施

这一组扩展把 AgentScope 接到企业里常见的基础设施上，让 Agent 能像普通服务一样被治理、被调度、被发现。

| 扩展 | 中间件 | 主要能力 |
| --- | --- | --- |
| Higress | [Higress](https://higress.io/) AI 网关 | 通过 MCP 把网关上的工具引入 Toolkit |
| Nacos | [Nacos](https://nacos.io/) | A2A AgentCard 注册发现、Prompt 配置中心、Skill 仓库 |
| Scheduler | XXL-Job / Quartz | 让 Agent 按 CRON 或固定速率定时跑 |

各扩展的接入细节见本章后续各节。

### 整体定位

- **Higress / Nacos** 把"接入网关、注册中心"作为 AgentScope 的横向能力。
- **Scheduler** 解决"Agent 不一定是被人类触发，可能由调度器周期性触发"的需求。

各扩展之间相互独立，可以按需组合。

## Higress

`agentscope-extensions-higress` 把 [Higress](https://higress.io/) 上以 MCP（Model Context Protocol）方式发布的工具引入 AgentScope。Higress 在网关层做了工具搜索、鉴权、限流、可观测；Agent 这边只负责调用对应工具。

### 何时使用

- 已经在用 Higress 作为 AI 网关，希望把网关上的工具直接喂给 Agent。
- 想把工具治理（路由、鉴权、配额）和 Agent 业务逻辑解耦。

### 添加依赖

```xml
<dependency>
    <groupId>io.agentscope</groupId>
    <artifactId>agentscope-extensions-higress</artifactId>
    <version>${agentscope.version}</version>
</dependency>
```

### 快速上手

```java
import io.agentscope.extensions.higress.HigressMcpClientBuilder;
import io.agentscope.extensions.higress.HigressMcpClientWrapper;
import io.agentscope.extensions.higress.HigressToolkit;

// 1) 通过 Higress 网关发布的 MCP endpoint 创建客户端
HigressMcpClientWrapper client = HigressMcpClientBuilder
    .create("higress")
    .streamableHttpEndpoint("http://gateway/mcp-servers/union-tools-search")
    .build();

// 2) 注册到 HigressToolkit（Toolkit 子类，额外缓存了 Higress 客户端引用）
HigressToolkit toolkit = new HigressToolkit();
toolkit.registerMcpClient(client).block();

// 3) 给 Agent 使用
ReActAgent agent = ReActAgent.builder()
    .name("Assistant")
    .model(model)
    .toolkit(toolkit)
    .build();
```

### 选择性启用工具

`HigressToolkit` 沿用了 `Toolkit` 的 fluent registration API，可以按 group / 名称白名单细粒度控制：

```java
toolkit.registration()
    .mcpClient(client)
    .enableTools(List.of("search-doc", "fetch-url"))
    .group("knowledge")
    .apply();
```

### 拿到底层 MCP 客户端

如果你需要直接调用 Higress 提供的扩展 API（比如工具搜索 `HigressToolSearchResult`）：

```java
HigressMcpClientWrapper higressClient = toolkit.getHigressMcpClient();
```

> Higress 上的工具治理（鉴权、限流、路由、可观测）由网关侧完成，无需在 Agent 这边重复实现。

## Nacos

`agentscope-extensions-nacos` 把 [Nacos](https://nacos.io/) 用作 AgentScope 的统一控制面：注册发现 A2A Agent、动态加载 Prompt、托管 Skill。包含三个子模块，按需组合使用。

| 子模块 | 解决的问题 |
| --- | --- |
| `agentscope-extensions-nacos-a2a` | A2A AgentCard 与服务实例的注册/发现 |
| `agentscope-extensions-nacos-prompt` | 把 Prompt 模板放到 Nacos，热更新到运行中的 Agent |
| `agentscope-extensions-nacos-skill` | 从 Nacos AI 模块加载 Skill 包（ZIP） |

### A2A 注册发现

#### 添加依赖

```xml
<dependency>
    <groupId>io.agentscope</groupId>
    <artifactId>agentscope-extensions-nacos-a2a</artifactId>
    <version>${agentscope.version}</version>
</dependency>
```

#### 服务端：把 AgentCard 注册到 Nacos

```java
import io.agentscope.core.nacos.a2a.registry.NacosA2aRegistry;
import io.agentscope.core.nacos.a2a.registry.NacosA2aRegistryProperties;

Properties props = new Properties();
props.setProperty("serverAddr", "127.0.0.1:8848");
NacosA2aRegistry registry = new NacosA2aRegistry(props);

NacosA2aRegistryProperties props2 = new NacosA2aRegistryProperties();
// props2.setNamespace(...) / setGroup(...) 等
registry.registerAgent(agentCard, props2);
```

注册后，AgentCard 与服务端点会写入 Nacos 的 AI Service，供消费者发现。

#### 客户端：通过 Nacos 拿到远端 AgentCard

```java
import io.agentscope.core.nacos.a2a.discovery.NacosAgentCardResolver;

NacosAgentCardResolver resolver = new NacosAgentCardResolver(props, "translator-agent");
A2aAgent remote = A2aAgent.builder()
    .name("translator")
    .agentCardResolver(resolver)
    .build();
```

### Prompt 配置中心

#### 添加依赖

```xml
<dependency>
    <groupId>io.agentscope</groupId>
    <artifactId>agentscope-extensions-nacos-prompt</artifactId>
    <version>${agentscope.version}</version>
</dependency>
```

#### 用法

```java
import com.alibaba.nacos.api.ai.AiService;
import io.agentscope.core.nacos.prompt.NacosPromptListener;

NacosPromptListener prompts = new NacosPromptListener(aiService);

String tpl = prompts.getPrompt("system-prompt", Map.of(
    "userName", "Alice"
));
```

监听器内部维护本地缓存，Nacos 上 prompt 更新时会自动推送进来，下一次 `getPrompt(...)` 立即拿到新版本，无需重启。

### Skill 仓库

`agentscope-extensions-nacos-skill` 提供一个 `AgentSkillRepository` 实现，把 Nacos AI 模块管理的技能 ZIP 包下载下来解析。

```xml
<dependency>
    <groupId>io.agentscope</groupId>
    <artifactId>agentscope-extensions-nacos-skill</artifactId>
    <version>${agentscope.version}</version>
</dependency>
```

```java
import io.agentscope.core.nacos.skill.NacosSkillRepository;

Properties props = new Properties();
props.setProperty(NacosSkillRepository.SKILL_VERSION_PATH, "1.2.0");
// 或 SKILL_LABEL_PATH = "stable"

NacosSkillRepository repo = new NacosSkillRepository(aiService, "default-namespace", props);
AgentSkill skill = repo.getSkill("calculator");
```

版本/标签的解析顺序是：构造时传入的 `Properties` → JVM `-D` 系统属性 → 环境变量。同时设置版本和标签时，**版本优先**，标签不会用于下载。

### 与其他扩展配合

- 结合 A2A（见第 26 章）：`AgentScopeA2aServer.builder().agentRegistry(...)` 可以注入一个把 AgentCard 推到 Nacos 的注册器，启动后自动暴露给整个集群。
- 结合 Skill 仓库（见第 27 章）：可以与 Git/MySQL 的 `AgentSkillRepository` 并存，把同一个 Toolkit 用多个数据源拼起来。

## Scheduler

`agentscope-extensions-scheduler` 让 Agent 可以按调度器配置周期性执行——比如"每天 8 点跑一次日报 Agent"、"每 5 秒做一次健康巡检"。模块抽出统一的 `AgentScheduler` 接口，提供两个实现：

| 子模块 | 实现 | 部署形态 |
| --- | --- | --- |
| `agentscope-extensions-scheduler-quartz` | [Quartz](https://www.quartz-scheduler.org/) | 单机或集群（共享 Quartz 数据库） |
| `agentscope-extensions-scheduler-xxl-job` | [XXL-Job](https://www.xuxueli.com/xxl-job/) | 分布式调度，依赖 admin server |

底层 SPI 在 `agentscope-extensions-scheduler-common`，可以自己实现接入其他调度框架。

### 共享概念

- `AgentConfig`（或 `RuntimeAgentConfig`）：定义 Agent 怎么"造"出来——名字、模型配置、system prompt、工具集等。
- `ScheduleConfig`：定义调度策略——CRON、固定速率、最大并发等。
- `AgentScheduler`：核心接口，`schedule(...)` / `pause(...)` / `resume(...)` / `cancel(...)` / `shutdown()`。
- `ScheduleAgentTask`：一次注册返回的"被调度的 Agent 任务"句柄。

每次任务触发时，调度器会"现造"一个新的 Agent 实例并执行，避免状态串台。

### Quartz 模式（单机/集群）

#### 添加依赖

```xml
<dependency>
    <groupId>io.agentscope</groupId>
    <artifactId>agentscope-extensions-scheduler-quartz</artifactId>
    <version>${agentscope.version}</version>
</dependency>
```

#### 用法

```java
import io.agentscope.extensions.scheduler.AgentScheduler;
import io.agentscope.extensions.scheduler.config.AgentConfig;
import io.agentscope.extensions.scheduler.config.DashScopeModelConfig;
import io.agentscope.extensions.scheduler.config.ScheduleConfig;
import io.agentscope.extensions.scheduler.config.ScheduleMode;
import io.agentscope.extensions.scheduler.quartz.QuartzAgentScheduler;

AgentScheduler scheduler = QuartzAgentScheduler.builder()
    .autoStart(true)
    .build();

AgentConfig agent = AgentConfig.builder()
    .name("DailyReportAgent")
    .modelConfig(DashScopeModelConfig.builder()
        .apiKey(apiKey).modelName("qwen-plus").build())
    .sysPrompt("你是日报助手，请每天生成销售汇总")
    .build();

ScheduleConfig schedule = ScheduleConfig.builder()
    .scheduleMode(ScheduleMode.FIXED_RATE)
    .fixedRate(5_000L)   // 每 5 秒
    // 或 .scheduleMode(ScheduleMode.CRON).cron("0 0 8 * * ?")
    .build();

scheduler.schedule(agent, schedule);
```

支持运行时管控：

```java
scheduler.pause("DailyReportAgent");
scheduler.resume("DailyReportAgent");
scheduler.cancel("DailyReportAgent");
scheduler.shutdown();
```

### XXL-Job 模式（分布式）

#### 添加依赖

```xml
<dependency>
    <groupId>io.agentscope</groupId>
    <artifactId>agentscope-extensions-scheduler-xxl-job</artifactId>
    <version>${agentscope.version}</version>
</dependency>
```

#### 用法

```java
import com.xxl.job.core.executor.impl.XxlJobSpringExecutor;
import io.agentscope.extensions.scheduler.xxljob.XxlJobAgentScheduler;

// 1) 启动 XXL-Job Executor
XxlJobSpringExecutor executor = new XxlJobSpringExecutor();
executor.setAdminAddresses("http://localhost:8080/xxl-job-admin");
executor.setAppname("agentscope-demo");
executor.setAccessToken("xxxxxxxx");
executor.setPort(9999);
executor.start();

// 2) 把它包成 AgentScheduler
AgentScheduler scheduler = new XxlJobAgentScheduler(executor);

// 3) 注册一个 Agent 作为 JobHandler
ScheduleAgentTask task = scheduler.schedule(agentConfig, ScheduleConfig.builder().build());
```

之后，**调度策略（CRON、并发、路由）在 XXL-Job 控制台配置**，Agent 名 `DailyReportAgent` 会作为 JobHandler 显示。

### 工具绑定

绑定 Toolkit 时使用 `RuntimeAgentConfig`（过渡 API，未来可能调整）：

```java
RuntimeAgentConfig agent = RuntimeAgentConfig.builder()
    .name("OpsAgent")
    .modelConfig(modelConfig)
    .sysPrompt("巡检并发送告警")
    .toolkit(toolkit)
    .build();
```

### 选型建议

- **本地或小集群、不想引入外部调度服务** → Quartz
- **需要可视化控制台、跨节点路由、任务日志** → XXL-Job
- **想接其他调度框架** → 自己实现 `AgentScheduler` 接口

## 生态扩展

放在这一组里的扩展不属于"记忆/会话/RAG/协议/基础设施"任一具体大类，而是对运行环境、语言生态、调试工具、训练流水线的扩展：

| 扩展 | 用途 |
| --- | --- |
| Chat Completions Web | 把 Agent 暴露成 OpenAI Chat Completions 兼容接口 |
| Studio | 把 Agent 接入 AgentScope Studio，便于可视化调试 |
| Training | 把生产流量自动采样喂给训练后端，闭环优化 |

各扩展的接入细节见本章后续各节。

## Chat Completions Web

`agentscope-extensions-chat-completions-web` 把 AgentScope Agent 包装成 [OpenAI Chat Completions](https://platform.openai.com/docs/api-reference/chat) 兼容接口，让 OpenAI SDK、LangChain、LlamaIndex、ChatBox 等客户端"以为自己在调 OpenAI"。

### 何时使用

- 想把 Agent 变成"标准 LLM"暴露给已有客户端，无需改对端代码。
- 希望保留流式输出、工具调用过程，符合 OpenAI 的 SSE 协议格式。

### 添加依赖

```xml
<dependency>
    <groupId>io.agentscope</groupId>
    <artifactId>agentscope-extensions-chat-completions-web</artifactId>
    <version>${agentscope.version}</version>
</dependency>
```

注意：本扩展**只**提供框架无关的核心适配器，真正的 HTTP/SSE 路由请使用对应的 Spring Boot Starter（或自行写 Controller）。

### 核心适配器

```java
import io.agentscope.core.chat.completions.streaming.ChatCompletionsStreamingAdapter;
import io.agentscope.core.chat.completions.model.ChatCompletionsRequest;
import io.agentscope.core.chat.completions.model.ChatCompletionsChunk;
import reactor.core.publisher.Flux;

ChatCompletionsStreamingAdapter adapter = new ChatCompletionsStreamingAdapter();

// 把 OpenAI 风格 Request 转成 Agent 调用 + 反向把事件流转回 OpenAI chunks
Flux<ChatCompletionsChunk> stream = adapter.stream(agent, request);
```

适配器把 AgentScope 的 `Event` 流（含 `REASONING`、`TOOL_RESULT` 等）转成 OpenAI 兼容的 `ChatCompletionsChunk`，包括：

- 文本增量 → `delta.content`
- 工具调用 → `delta.tool_calls[]`
- 流结束 → 带 `finish_reason` 的 chunk

### 在 Spring Boot 里暴露 SSE

最简单的方式是引入 starter（推荐），它会自动注册控制器。也可以自己写：

```java
@RestController
public class ChatController {
    private final ChatCompletionsStreamingAdapter adapter = new ChatCompletionsStreamingAdapter();
    @Autowired private Agent agent;

    @PostMapping(value = "/v1/chat/completions",
                 produces = MediaType.TEXT_EVENT_STREAM_VALUE)
    public Flux<String> chat(@RequestBody ChatCompletionsRequest req) {
        return adapter.stream(agent, req)
            .map(this::toSseLine);  // 序列化 + "data: ..." 包装
    }
}
```

### 模型对照表

OpenAI 客户端发起调用时通常会带 `model` 字段，可在控制器层做映射：

```java
String model = req.getModel();   // 例如 "gpt-4o"，路由到不同 Agent
Agent target = agentRegistry.lookup(model);
return adapter.stream(target, req);
```

### 适合搭配

- **AG-UI**：偏 Web 前端可视化，关注事件粒度的 UI 渲染。
- **Chat Completions Web**：偏标准 LLM 接入，只关心 OpenAI 兼容。

## Studio

`agentscope-extensions-studio` 把 Agent 接入 [AgentScope Studio](https://github.com/agentscope-ai/agentscope-studio)：每次 Agent 调用都会被推送到 Studio，用作可视化调试、链路回放、Human-in-the-Loop 输入。

### 何时使用

- 开发期想在 Studio 里看到 Agent 的事件流、推理过程、工具调用。
- 需要在 Studio 里发起 `requestUserInput`，让真人介入答题。

### 添加依赖

```xml
<dependency>
    <groupId>io.agentscope</groupId>
    <artifactId>agentscope-extensions-studio</artifactId>
    <version>${agentscope.version}</version>
</dependency>
```

### 快速上手

```java
import io.agentscope.core.studio.StudioManager;
import io.agentscope.core.studio.StudioMessageHook;

// 1) 初始化 Studio 连接（HTTP + WebSocket）
StudioManager.init()
    .studioUrl("http://localhost:8000")
    .project("MyProject")
    .runName("experiment_001")
    .initialize()
    .block();

// 2) 把 StudioMessageHook 挂到 Agent 上，自动把消息推到 Studio
ReActAgent agent = ReActAgent.builder()
    .name("Assistant")
    .model(model)
    .hook(new StudioMessageHook(StudioManager.getClient()))
    .build();

// 3) 正常调用 Agent，Studio 上会同步看到对话
agent.call(msg).block();
```

### Studio 提供的能力

- **消息推送**：每条 user / assistant / tool 消息都被同步到 Studio。
- **链路追踪**：Studio 内部会按 `runName` 把整次运行编排成一棵 trace 树。
- **Human-in-the-Loop**：通过 `StudioUserAgent` 或 `requestUserInput`，让 Studio UI 弹出输入框等待真人填写后再继续。

### API 概览

| 类 | 用途 |
| --- | --- |
| `StudioManager` | 单例式入口，初始化和获取 client |
| `StudioConfig` | URL / project / runName 等配置 |
| `StudioClient` | HTTP 客户端，推送事件、消息、注册 run |
| `StudioWebSocketClient` | WebSocket 客户端，接收 Studio 侧的指令（如 user input） |
| `StudioMessageHook` | 注入到 `ReActAgent` 的 `Hook`，自动推送 `Msg` |
| `StudioUserAgent` | "真人扮演的 Agent"，调用时阻塞等待 Studio 输入 |

### 何时关闭

生产部署一般不挂这个 Hook（避免每次调用都向 Studio 写一份）。建议通过 Spring Profile 或 `@ConditionalOnProperty` 控制：

```java
@Bean
@ConditionalOnProperty("agentscope.studio.enabled")
StudioMessageHook studioHook() {
    StudioManager.init().studioUrl(url).project(project).initialize().block();
    return new StudioMessageHook(StudioManager.getClient());
}
```

## 在线训练

`agentscope-extensions-training` 在 AgentScope 之上接入 Trinity 训练后端：把生产流量按策略采样、收集 trace、计算奖励，再周期性提交训练，形成闭环。

### 何时使用

- 已有 Trinity（或兼容服务）作为模型训练后端。
- 想把线上流量当训练数据，做强化学习或在线微调。
- 不想改业务调用代码，希望训练流水线对 Agent 调用方"透明"。

### 添加依赖

```xml
<dependency>
    <groupId>io.agentscope</groupId>
    <artifactId>agentscope-extensions-training</artifactId>
    <version>${agentscope.version}</version>
</dependency>
```

### 快速上手

```java
import io.agentscope.core.training.runner.TrainingRunner;
import io.agentscope.core.training.strategy.SamplingRateStrategy;

TrainingRunner runner = TrainingRunner.builder()
    .trinityEndpoint("http://localhost:8080")
    .modelName("/path/to/model")
    .selectionStrategy(SamplingRateStrategy.of(0.1))   // 10% 流量进训练
    .rewardCalculator(agent -> 0.0)                    // 自定义奖励
    .commitIntervalSeconds(300)                        // 每 5 分钟 commit 一次
    .build();

runner.start();          // 拦截 Agent，开始采样

// 业务侧照常使用 Agent，无须感知 runner
agent.call(msg).block();

runner.stop();           // 停止训练流水线
```

### 选样策略

- `SamplingRateStrategy.of(0.1)`：按比例随机采样。
- `ExplicitMarkingStrategy.create()`：完全由调用方显式标记哪些请求要进训练。
- 也可以实现 `TrainingSelectionStrategy` 自定义。

### 奖励计算

`rewardCalculator` 是一个 `Function<AgentBase, Double>`，每次采样产生 trajectory 后调用。可以是：

- Lambda：基于回答长度、工具调用次数等启发式打分。
- 自定义类：实现 `RewardCalculator` 接口，封装更复杂的指标。

```java
TrainingRunner runner = TrainingRunner.builder()
    .trinityEndpoint(endpoint)
    .modelName(model)
    .selectionStrategy(SamplingRateStrategy.of(0.1))
    .rewardCalculator(new MyMetricRewardCalculator())
    .build();
```

### 工作机制

1. `runner.start()` 之后，Agent 的请求会经 `TrainingRouter` 路由：
   - 命中采样 → 调用替换为 Trinity 后端，trace 数据被收集；
   - 未命中 → 走原有模型，无副作用。
2. 命中样本会调 reward calculator 算分，再通过 `TrinityClient.feedback(...)` 反馈。
3. `commitIntervalSeconds` 周期到达时调用 `commit(...)`，触发训练任务。

`runner.stop()` 时会优雅关闭定时器与连接池。

### 关键配置

| 字段 | 说明 |
| --- | --- |
| `trinityEndpoint` | Trinity 服务地址 |
| `modelName` | 训练目标模型路径或别名 |
| `selectionStrategy` | 采样策略 |
| `rewardCalculator` | 奖励计算函数 |
| `commitIntervalSeconds` | commit 周期，默认 300 |

### 与 Studio 配合

可以同时挂载 `StudioMessageHook`，在 Studio 上实时看到哪些会话被采样进训练；reward 也可以写入 Studio 用于可视化分析。
