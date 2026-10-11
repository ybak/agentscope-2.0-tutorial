---
chapter: 2
title: 快速开始
source: docs/quickstart.md
---

# 第 2 章 快速开始

> 本章导读：从零搭建第一个可运行的 AgentScope Java 应用——安装依赖、用共享 Builder 创建 HarnessAgent、完成问答与流式输出，并了解何时需要引入 AgentSession。读完本章，你将获得一个能跨实例恢复会话的最小示例。

## 安装

AgentScope Java 需要 JDK 17 及以上版本，构建工具推荐 Maven 3.9+。

### Maven 依赖

`HarnessAgent` 是推荐的入口，把工作区、长期记忆、会话持久化、子 agent、沙箱等工程能力打包在一个 builder 里；依赖 `agentscope-harness` 会自动把核心 `agentscope-core` 一并拉进来：

```xml
<dependency>
    <groupId>io.agentscope</groupId>
    <artifactId>agentscope-harness</artifactId>
    <version>${agentscope.version}</version>
</dependency>
```

> **注意**：把 `${agentscope.version}` 替换为最新版本号即可，最新版本请参考附录 A（Release Notes）。

如果只需要 `ReActAgent` 的推理、工具和上下文 API，并自行组合应用所需能力，`agentscope-core` 足够提供 agent 本身。具体模型提供商是独立的：特定模型提供商的 Chat Model 与 formatter 位于独立的 `agentscope-extensions-model-*` 模型扩展模块中。`ReActAgent` 与 `HarnessAgent` 的区别详见第 3 章与第 11 章。

下面的 quickstart 通过 `.model("dashscope:qwen-plus")` 使用 DashScope，因此还需要引入对应模型扩展：

```xml
<dependency>
    <groupId>io.agentscope</groupId>
    <artifactId>agentscope-extensions-model-dashscope</artifactId>
    <version>${agentscope.version}</version>
</dependency>
```

MCP 集成需要官方 MCP SDK，参考 `agentscope-examples/documentation/pom.xml`。

## 第一个智能体

推荐在应用启动时定义共享 Builder，每次请求用 `builder.build()` 创建新的 Agent，执行完成后关闭。Builder 保存通用配置，请求身份放在独立的 `RuntimeContext` 中；新建实例不会改变会话身份。下面用两个实例完成同一会话的两轮问答。运行前设置模型凭据：

```bash
export DASHSCOPE_API_KEY=your_api_key
```

```java
import io.agentscope.core.agent.RuntimeContext;
import io.agentscope.core.message.Msg;
import io.agentscope.core.message.UserMessage;
import io.agentscope.harness.agent.HarnessAgent;
import java.nio.file.Path;

public class FirstAgent {
    // 应用启动时配置一次，之后只调用 build()。
    private static final HarnessAgent.Builder AGENT_BUILDER = HarnessAgent.builder()
            .name("note-taker")
            .agentId("note-taker")
            .sysPrompt("你是一个帮助用户做笔记的助手。")
            .model("dashscope:qwen-plus")
            .workspace(Path.of(".agentscope/workspace"));

    public static void main(String[] args) {
        try (HarnessAgent agent = AGENT_BUILDER.build()) {
            RuntimeContext ctx = RuntimeContext.builder()
                    .userId("alice").sessionId("demo-session").build();
            agent.call(new UserMessage("我叫天宇，今天准备一个技术分享。"), ctx).block();
        }

        // 下一次请求使用新实例；相同会话身份从持久日志恢复上下文。
        try (HarnessAgent agent = AGENT_BUILDER.build()) {
            RuntimeContext ctx = RuntimeContext.builder()
                    .userId("alice").sessionId("demo-session").build();
            Msg reply = agent.call(new UserMessage("我叫什么？今天要干什么？"), ctx).block();
            System.out.println(reply.getTextContent());
        }
    }
}
```

`call` 返回 `Mono<Msg>`；这里用 `block()` 启动执行并等待回复，适合命令行示例。一次调用可以多次推理和执行工具。相同 `userId`、`sessionId` 的下一次调用会使用同一段会话的上下文。

默认情况下，Harness 会自动保存执行日志和用于继续对话的状态快照（checkpoint）。重启时保留相同的 `agentId`、用户、会话身份和存储配置，即可继续对话；这不需要额外创建 `AgentSession`。

这个本地示例的原生日志位于 Workspace Filesystem 为当前身份解析的根目录下 `.agentscope-runtime/`。配置隔离目录或分布式 Filesystem 后，实际位置跟随对应根目录或 namespace。需要查看记录、更换后端时，再查阅第 19 章的“存储位置与后端配置”一节。

### 流式查看推理与工具调用

需要边生成边显示时，用 `streamEvents` 发起这次请求。把下面的 import 加到文件顶部，在 `main` 中为这次请求创建新实例：

```java
import io.agentscope.core.event.AgentEventType;
import io.agentscope.core.event.TextBlockDeltaEvent;
import io.agentscope.core.event.ToolCallStartEvent;

try (HarnessAgent agent = AGENT_BUILDER.build()) {
    RuntimeContext ctx = RuntimeContext.builder()
            .userId("alice").sessionId("demo-session").build();
    agent.streamEvents(new UserMessage("帮我把分享的准备工作列成三条。"), ctx)
            .doOnNext(event -> {
                if (event.getType() == AgentEventType.TEXT_BLOCK_DELTA) {
                    System.out.print(((TextBlockDeltaEvent) event).getDelta());
                } else if (event.getType() == AgentEventType.TOOL_CALL_START) {
                    System.out.println("\n[tool] " + ((ToolCallStartEvent) event).getToolCallName());
                }
            })
            .blockLast();
}
```

`streamEvents` 返回 `Flux<AgentEvent>`，订阅后启动执行；`blockLast()` 在这里等待流结束。它与 `call` 使用相同的 Agent 能力和持久化配置。

同一个请求按输出需求选择 `call` 或 `streamEvents`。如果先 `call`，再用相同输入调用 `streamEvents`，会再次执行该请求。

### 在 Web 请求中使用

WebFlux 中使用 `Mono.using` 管理实例：订阅时从共享 Builder 构建 Agent，执行完成、报错或取消时关闭。不要在 `try` 块中返回尚未订阅的 `Mono`，否则 Agent 会提前关闭。下面是 handler 中的调用表达式：

```java
import reactor.core.publisher.Mono;

RuntimeContext ctx = RuntimeContext.builder()
        .userId(userId).sessionId(sessionId).build();
return Mono.using(
        AGENT_BUILDER::build,
        agent -> agent.call(new UserMessage(userInput), ctx),
        HarnessAgent::close);
```

`userId` 应来自已认证身份，`sessionId` 应经过访问权限检查。Builder 配置完成后不要在请求中调用 setter；共享的模型、工具和中间件仍须支持并发使用。不同会话可以并行；同一会话跨实例的请求应由应用按顺序调度，日志写入隔离不等于自动排队。生命周期与并发规则见第 4 章“实例生命周期”一节。

### 什么时候使用 AgentSession

日常问答、工作流节点以及随当前请求完成的流式界面，可以继续使用 `call` / `streamEvents`。直接把执行流作为 HTTP 响应时，客户端断连可能取消该次执行。

当产品需要“关闭页面后继续运行”“忙时接收并保存下一项任务”“运行中补充要求”或“中断后继续原任务”时，使用 `agent.session(ctx)` 提供的 `AgentSession`。它负责接收任务和安排后台执行，前端独立读取快照与持久事件。

后台任务的 Agent 由应用的会话管理器或任务 worker 持有，在任务停止或应用退出后再关闭；不要在提交任务的 HTTP 请求返回时关闭它。这里的生命周期覆盖整个后台执行，不只覆盖一次提交请求。

下一步阅读第 19 章（会话日志与恢复），或参考第 40 章的可恢复聊天示例。通过 HTTP 使用托管 Agent 的应用，直接阅读第 31 章。

## 接下来

到这里，你已经跑通了一个最小但完整的 HarnessAgent：依赖安装、共享 Builder、`call` 与 `streamEvents`，以及跨实例的会话恢复。下一章（第 3 章）会给出全书的核心概念地图，说明 ReActAgent、HarnessAgent 与 Service Managed Agent 三层能力的叠加关系，帮助你在进入细节前建立全局视图；随后第 4 章深入 Agent 本身，讲解实例生命周期、并发规则、结构化输出与人工介入。工作区（第 12 章）、上下文管理与长期记忆（第 13、14 章）等主题，可在需要时按目录选读。
