---
chapter: 38
title: 评估与运营
source: jev/guides/judge-api.md, jev/guides/trace-evaluation-api.md, jev/guides/metric-definitions.md, jev/guides/evaluator-api.md, jev/evaluation.md, jev/operations.md, jev/sdk-reference.md
---

# 第 38 章 评估与运营

> 本章导读：接入了判断，还要能评估判断本身是否值得。本章前四节是 JEV 评估 API 的完整收录：`JevJudge` 用带版本的条件定义聚合 PASS/FAIL/INCONCLUSIVE，`JevTraceEvaluator` 采集并评估 Agent 轨迹的八项指标，`JevTraceMetric` 让定义在在线审核与离线回放间复用，`JevEvaluator` 加 runner 对固定样本做批量回归；第五节讲如何用同一组输入做基线与同题对照、读懂报告并校准阈值；第六节给出预算分配与决策记录的消费方式；末节是全部 API 与包的索引。评估的纪律与判断一致：金标不进模型请求、弃权和错误留在分母里、离线预设结果不能充当模型准确率。

## 用条件定义评审标准

`JevJudge` 把一组必需的评审条件聚合为 PASS、FAIL、INCONCLUSIVE 或 ERROR。适合草稿是否有依据、是否覆盖需求等检查；同一份带版本定义可以复用于在线审核和离线回放。

### 示例场景：回复不能把"尚未退款"说成"退款完成"

客户问"退款了吗？"，业务记录显示尚未执行退款。Agent 的草稿可能如实说明需先核查，也可能直接声称"退款已经完成"。仅检查句子是否流畅，不能发现这种无依据承诺。

应用把客户问题、业务证据与草稿一起交给 Judge，要求评审"回答是否得到证据支持"。审核发生在发布前，但 Judge 只返回结果，何时修订、复核或发布由应用决定。

### 1. 定义要满足的条件

```java
import io.agentscope.extensions.judge.jev.JevJudge;
import io.agentscope.extensions.judge.jev.NoulQuestion;
import java.time.Duration;
import java.util.List;
import java.util.Map;

var definition = new JevJudge.Definition("refund-answer-v1", List.of(
    new JevJudge.Criterion("supported",
        new NoulQuestion(
            "Is assistant_answer supported by supporting_context without inventing completed refunds?",
            null),
        true, 0.2, 0.8)));
```

`true` 表示期望条件成立；0.2 和 0.8 是失败、通过阈值，中间区间保留不确定。它们是演示配置，正式使用前应在自己的业务样本上校准。

`refund-answer-v1` 标识这套标准。修改问题、字段含义或阈值时更新版本，才能区分"模型表现变了"与"评审规则变了"。

### 2. 把真实证据和草稿交给 Judge

```java
var judge = new JevJudge(client, Duration.ofSeconds(2));
var state = Map.of(
    "user_question", "退款了吗？",
    "supporting_context", List.of("业务记录：尚未执行退款"),
    "assistant_answer", "退款已经完成");
var pending = judge.judge(state, definition);
```

`client` 按客户端接入（见第 36 章）创建。2 秒是这次评审的总预算，包含客户端重试和退避。证据必须来自实际业务记录，不能用 Agent 自己的承诺作为退款成功证明。

这三个字段与 `JevEvaluator`（见本章"批量评估问题、证据与回答"一节）的输入一致，因此这份 definition 可以直接用于后续批量回归。

### 3. 按状态决定草稿下一步

```java
var observed = pending.doOnNext(result -> {
    System.out.println("定义版本：" + result.definitionVersion());
    System.out.println("评审状态：" + result.status());
    System.out.println("条件明细：" + result.findings());
});
```

服务中返回或组合 `observed`；独立命令行可用 `observed.block()`。不要为了日志再订阅一次，同一个 Mono 每次订阅都会重新评审。

| 条件得到的支持概率（示意） | 状态 | 草稿处理 |
|---|---|---|
| 0.95 | PASS | 可以进入应用后续发布检查 |
| 0.05 | FAIL | 修订无依据表述或人工复核 |
| 0.50 | INCONCLUSIVE | 补充证据，不能当作通过 |
| 无有效响应 | ERROR | 按审核失败策略处理，不补造概率 |

概率不是文字理由。`findings()` 保留逐项概率和状态，不自动生成原因解释、证据引用或 run/session；应用应关联原业务记录。

### 运行与验证

按第 36 章"构建一次，运行多个案例"一节设置 `JEV_CP`：

```bash
java -cp "$JEV_CP" io.agentscope.examples.jev.JevApplicationScenarios judge
```

用例把同一条件分别送入三个预设概率分支，验证 PASS、FAIL 和 INCONCLUSIVE 的处理，没有真实模型调用。完整代码见示例模块中的 `JevApplicationScenarios`。

需要"覆盖客户条件 + 无依据承诺"两条条件组合，可运行 `JevCustomerSupportExample`：

```bash
java -cp "$JEV_CP" io.agentscope.examples.jev.JevCustomerSupportExample
```

它默认离线，只有显式追加 `--live` 才调用真实接口。离线结果不用于计算真实模型准确率或速度。

### 多条件、错误和取消

同一 Definition 中的条件都必须满足：任一 FAIL 使总结果 FAIL；没有 FAIL 但有不确定项时为 INCONCLUSIVE；全部通过才 PASS。没有加权平均，不把 Choice/Score 强制聚合成通过/失败。定义必须非空、条件 ID 不重复。

如果条件问的是"是否存在无依据承诺"，期望应设为 false，此时使用 `1 - p` 与阈值比较。阈值要求 `0 <= fail < pass <= 1`，边界分别包含在失败和通过区间内。

总预算耗尽记 ERROR/TIMEOUT；Judge 检测到缺项、错类型或非法概率时记 ERROR/INVALID_RESPONSE；客户端和其他后端异常记 ERROR/BACKEND。错误结果不保存原始异常文本，不把失败当概率 0。取消终止订阅，不返回伪造的 ERROR 结果；远端是否停止计算取决于传输实现。

## 采集并评估 Agent 轨迹

当你需要判断 Agent 是否选对工具、使用了工具结果、回答有无依据时，使用 `JevTraceEvaluator`。同一组 `JevTraceMetric` 可以用于历史轨迹回放，也可以通过中间件评估真实调用。在线评估只观察已经发生的行为。

### 示例场景：查到了订单状态，最终回答是否真的使用了它

客户问"订单 42 到哪里了？"。Agent 调用 `lookup_order`，工具返回"昨天已发货"，然后给出回答。工具执行成功只说明查到了数据，还需要检查是否选对工具、是否使用查询结果、回答有没有增加未经证实的承诺。

把这一次调用的完整轨迹交给 JEV，可以同时得到工具选择、结果利用和回答依据等指标。它是事后评估，不会撤销已经发生的工具调用，也不会为了提高分数重跑业务流程。

### 1. 把调用与结果配成完整轨迹

依赖及凭据见客户端接入（见第 36 章）。下面先使用一个固定快照说明输入结构：

```java
import io.agentscope.core.message.Msg;
import io.agentscope.core.message.UserMessage;
import io.agentscope.core.message.AssistantMessage;
import io.agentscope.core.message.ToolUseBlock;
import io.agentscope.core.message.ToolResultMessage;
import io.agentscope.core.model.ToolSchema;
import io.agentscope.extensions.judge.jev.evaluation.JevTrace;
import io.agentscope.extensions.judge.jev.evaluation.JevTraceEvaluator;
import io.agentscope.extensions.judge.jev.evaluation.JevTraceMetrics;
import java.time.Duration;
import java.util.List;
import java.util.Map;

var messages = List.<Msg>of(
    new UserMessage("订单 42 到哪里了？"),
    new AssistantMessage(new ToolUseBlock("lookup-42", "lookup_order", Map.of())),
    new ToolResultMessage("lookup-42", "lookup_order", "订单 42 昨天已发货。"),
    new AssistantMessage("订单 42 昨天已发货。"));
var tools = List.of(ToolSchema.builder()
    .name("lookup_order").description("查询订单状态").build());
var trace = JevTrace.fromMessages("order-42", messages, tools);
```

工具调用与结果使用同一个 `lookup-42` ID，实际工具目录也随轨迹提供。目录为 `null` 表示没有提供，空列表则表示当时确实没有工具，两者不能混用。线上应使用实际发生的消息，不把后来可用的工具冒充此前候选。

### 2. 对同一次任务评估多个方面

```java
var metrics = JevTraceMetrics.agentMetrics(
    new JevTraceMetrics.Thresholds(0.2, 0.8));
var evaluator = new JevTraceEvaluator(client, metrics,
    new JevTraceEvaluator.Limits(Duration.ofSeconds(3), 128, 100_000));
var pending = evaluator.evaluate(trace);
```

三个上限分别约束一次评估的总耗时、单项问题数量和状态字符数，避免长轨迹无限放大评审开销。0.2/0.8 是演示阈值，正式使用应分用途校准。应用在响应式链中组合 `pending`，独立命令行才阻塞等待。

本例重点看 `tool_choice`、`used_tool_result` 和 `grounded`：工具选择正确不代表最终回答有依据。如果把回答换成"退款已经完成"，应由依据检查独立暴露问题，而不是被工具调用成功掩盖。

### 指标与结果

| 指标 ID | 输入要求 | 结果 |
| --- | --- | --- |
| tool_choice | 请求、候选目录、调用、最终答案 | correct / unnecessary / missing / wrong_tool；低置信度保留标签并弃权 |
| used_tool_result | 请求、最终答案、非空工具结果 | 是否使用结果；无结果 SKIPPED |
| grounded | 最终答案与工具结果或 contexts | 每句依据概率、支持比例；要求所有句子明确有依据才 passed |
| stayed_in_scope | 请求、调用、最终答案 | 行为与回复是否超出用户请求 |
| answer_relevancy | 请求、最终答案 | 分级相关性与非回避概率组合分数 |
| completeness | 请求、最终答案 | 四档覆盖程度归一化到 0..1 |
| indirect_injection | 非空工具结果 | 是否含引导 Agent 改变行为的指令，负向概率转安全分数 |
| trajectory_match | tool_calls、expected_tool_calls | STRICT、UNORDERED、SUBSET、SUPERSET；可比较参数；无需模型 |

`agentMetrics` 返回前七项；确定性轨迹对照单独添加：

```java
var extendedMetrics = new java.util.ArrayList<>(metrics);
extendedMetrics.add(JevTraceMetrics.trajectoryMatch(
    JevTraceMetrics.MatchMode.UNORDERED, true));
var labelled = trace.with("expected_tool_calls",
    List.of(Map.of("name", "lookup_order", "arguments", Map.of())));
var extendedEvaluator = new JevTraceEvaluator(client, extendedMetrics,
    new JevTraceEvaluator.Limits(Duration.ofSeconds(3), 128, 100_000));
var comparison = extendedEvaluator.evaluate(labelled);
```

自定义指标实现 `id/version/precheck/state/questions/reduce`。metric ID 和本地题目 ID 只能使用字母开头的字母、数字、下划线，最长 64 字符。线上问题名为 `metric.question`；重复 metric ID 拒绝构造。无问题的确定性指标不发请求。不同指标对同一 state 字段给出不同值时拆分请求，绝不覆盖。

`report.passed()` 只有在非空且全部指标明确 DECIDED/passed=true 时才为 true。SKIPPED、错误、弃权、没有通过策略的纯分类都不能使整体通过。调用方仍需查看每项状态；false 不等于业务判定为拒绝。

### 错误、预算和取消

- 缺字段或空证据：SKIPPED；不完整轨迹：INCOMPLETE_TRACE；超出单项问题数或状态字符数：EVALUATION_LIMIT，不截断证据后继续评分。
- 预检查、定义或 reducer 异常只影响对应指标；不在报告中保存异常文本，避免带出上下文。
- 后端错误、空响应、缺题、错类型、非法概率均为 ERROR；已报告的用量仍保留，未知用量不算零。
- 总预算覆盖本次所有分组；超时取消在途请求，未完成指标记 TIMEOUT；已完成指标保留。
- 下游取消向调用函数传播，不发出伪造的"完成报告"，也不继续后续分组。底层传输是否成功中断远端计算依赖 transport，不能据此声称不再计费。
- 分组串行执行；数据集并发由 runner 参数控制，范围 1..32；自定义回调必须及时返回非阻塞 Publisher。

### 3. 在线采集时只观察本次调用

这里 `model` 和 `toolkit` 沿用已有生成模型及业务工具；注册观察器后正常调用 Agent 即可。

```java
import io.agentscope.harness.agent.HarnessAgent;

var options = new io.agentscope.extensions.judge.jev.JevExecution.Options(
    io.agentscope.extensions.judge.jev.JevExecution.Mode.SHADOW, Duration.ofSeconds(5), "orders-v1",
    (ctx, record) -> System.out.println(record));
var observer = new io.agentscope.extensions.judge.jev.evaluation.JevTraceEvaluationMiddleware(
    evaluator, options, 100_000,
    (ctx, report) -> System.out.println(report.results()));
var agent = HarnessAgent.builder().name("observed-order-agent")
    .model(model).toolkit(toolkit).middleware(observer).build();
```

默认构造器为 OFF，不采集、不调用模型。SHADOW 从当前调用实际传给模型的消息和工具目录构造快照，再评估最终 AgentResult；事件原样透传，评估只在流结束时增加有界等待。逐轮工具目录带有适用消息位置，避免把最后一轮的目录冒充此前可用工具。

采集边界由本次输入消息 ID 定位。找不到边界、上下文删除此前调用、材料超限或不支持的内容时跳过，不能把被压缩后的残缺轨迹当完整执行记录。前序用户会话不混入本次动作评价。

每次订阅的采集状态放在 Reactor Context，复用同一中间件不共享轨迹。观察器异常不改变 Agent 输出。Agent 本身错误或被取消时不启动事后评估；评估开始后取消则取消评估订阅。

该观察器拒绝 ENFORCE：动作已经执行，事后评估无权撤销它。执行前权限及护栏继续由现有工具防护承担；同步输出审核继续用响应中间件。不会根据评估结果重跑 Agent 或写工具。

### Service 配置和记录

```json
{
  "jev": {
    "evaluation": {
      "mode": "SHADOW",
      "version": "orders-v1",
      "budgetMillis": 3000,
      "threshold": 0.8,
      "rejectionThreshold": 0.2,
      "maxQuestions": 128,
      "maxStateChars": 100000,
      "metrics": ["tool_choice", "used_tool_result", "grounded", "completeness"]
    }
  }
}
```

`evaluation` 默认 OFF；启用时显式提供两个阈值。`metrics` 省略时使用七项；未知名称、重复名称、ENFORCE、任意 endpoint/key 配置均拒绝。预算最多 30 秒、问题最多 512、状态最多 1,000,000 字符。阈值仅演示，不构成线上建议。

配置进入已有 Agent 构建缓存身份；变更指标或阈值重建 Agent。结果复用 `JevServiceSupport.TraceSink`，由现有运行链关联 run/session：`evaluation.<metric>` 保存版本、状态、标签/分数/通过值和耗时；`evaluation.usage` 记录请求数、已知用量响应数与 token。不会保存原始轨迹、模型密钥、完整证据或自由生成的解释。未获得响应的请求成本未知，不能用已知 token 总量当完整账单。

### 批量报告与对照

```java
var cases = List.of(new io.agentscope.extensions.judge.jev.evaluation.JevTraceRunner.Case("orders", trace,
    Map.of("tool_choice", new io.agentscope.extensions.judge.jev.evaluation.JevTraceRunner.Expected(null, "correct"),
           "grounded", new io.agentscope.extensions.judge.jev.evaluation.JevTraceRunner.Expected(true, null))));
var report = new io.agentscope.extensions.judge.jev.evaluation.JevTraceRunner().run(evaluator, cases, 4).block();
```

相同样本 ID 不可重复。报告保留输入顺序，按指标和场景汇总。本例可把工具选择标成 correct、回答依据标成通过；金标不进入模型请求。准确率分母为该指标全部有金标样本，包含错误、弃权、跳过及无法判分项；没有金标时不可解读 accuracy。延迟为每个完整样本评估的实测墙钟耗时，P50/P95 使用 nearest-rank；数据集另有总耗时。用量按实际请求累计一次，`responsesWithUsage < requests` 时总成本不完整。

原流程使用相同样本的确定性执行结果作基线；JEV 与 Qwen 必须消费同一状态、题目和金标。Qwen 如模拟概率，应标记为自报值并独立校准。模型价格和账单未核实时不输出推算费用。

### 离线运行

`JevTraceEvaluationExample` 使用真实 ReActAgent 与只读模拟工具，脚本模型生成工具调用和最终答案，评估端返回合成响应，不需要密钥。

按第 36 章"构建一次，运行多个案例"一节设置 `JEV_CP`：

```bash
java -cp "$JEV_CP" io.agentscope.examples.jev.JevTraceEvaluationExample
```

兼容使用旧命令的场景，也可将 classpath 写到 `/tmp/jev-trace-cp.txt`；新例子统一使用 `JEV_CP`。

预期一次工具执行、一次合并评估请求和七项指标；合成判定只验证调用链，不证明真实模型准确率或速度。

### 文本模型后端与固定样本

`JevTextBackend(model, transport)` 将相同 `SystemOneRequest` 转成兼容 Chat Completions 的 JSON 请求；transport 接收请求 JSON 并返回完整响应 JSON 的 `Mono<String>`。端点、密钥、HTTP 超时和取消由 transport 管理，适配器不自行读取环境变量。示例 `JevTraceBenchmark` 用 HTTP API 调用 Qwen。

仅接受完整 JSON、全部题目和全部分布项；重复键、非数值概率、非法总和、截断响应均为 ERROR/INVALID_RESPONSE，仍保留可解析的 token 用量。不会用 0.5 或归一化结果掩盖格式失败。Choice 的置信度根据相对均匀分布计算；概率没有经过独立校准。

## 复用与扩展评估定义

当多个 Agent 需要采用相同的质量标准时，把标准定义成带版本的对象，在线观察和离线评估共用它。AgentScope 提供两种定义层次。

### 示例场景：在线审核与离线回归采用同一套退款标准

客服 Agent 在线审核回答，评测程序离线回放历史答案。如果两处各写一套提示词，线上认为"无依据退款承诺"不合格，离线却只检查语气，就无法用离线结果指导上线。

把条件、输入字段和阈值一起放入带版本的定义，在线 Judge 与离线 Evaluator 使用同一对象。涉及工具行为时，再复用轨迹指标；分类结果不必强行变成通过或失败。

### 1. 让草稿审核与样本回放共用定义

`JevJudge.Definition` 适用于所有条件都必须满足的草稿审核。本例在 `JevJudge`、`JevEvaluator` 与 `JevResponseMiddleware` 之间复用相同字段约定。`JevDraftPipeline` 也使用 Definition，但输出状态字段是 `request/evidence/draft`，不能直接套用本例的字段名；应建立对应定义或在自有工作流中统一输入。

```java
import io.agentscope.extensions.judge.jev.JevJudge;
import io.agentscope.extensions.judge.jev.NoulQuestion;
import io.agentscope.extensions.judge.jev.evaluation.JevEvaluator;
import io.agentscope.extensions.judge.jev.evaluation.JevTraceEvaluator;
import io.agentscope.extensions.judge.jev.evaluation.JevTraceMetrics;
import java.time.Duration;
import java.util.ArrayList;
import java.util.List;

var definition = new JevJudge.Definition("refund-answer-v1", List.of(
    new JevJudge.Criterion("supported",
        new NoulQuestion("Is assistant_answer supported by supporting_context without inventing completed refunds?", null),
        true, 0.2, 0.8)));
var judge = new JevJudge(client, Duration.ofSeconds(2));
var evaluator = new JevEvaluator(judge, definition);
```

同一份定义要使用一致的字段语义：`JevEvaluator` 提供 `user_question`、`supporting_context`、`assistant_answer`；直接调用 Judge 时由你提供对应 state。修改问题、阈值或通过策略时更新版本，以便区分不同报告。

### 2. 为 Agent 行为复用指标组合

`JevTraceMetric` 可组合确定性预检查、问题构造和结果归约。它支持 Choice 分类或纯确定性检查，不要求每个指标都有通过/失败结果。

| 方法 | 你的实现负责什么 |
|---|---|
| `id()` / `version()` | 唯一指标 ID 与定义版本 |
| `precheck(trace)` | 缺输入时返回 SKIPPED，或直接返回确定性结果；继续评估时返回 null |
| `state(trace)` | 提取本指标需要的授权材料 |
| `questions(trace)` | 返回局部问题 ID 到 Question 的映射 |
| `reduce(answers, trace)` | 返回状态、分数、标签、passed 和必要证据摘要 |

```java
var thresholds = new JevTraceMetrics.Thresholds(0.2, 0.8);
var metrics = new ArrayList<>(JevTraceMetrics.agentMetrics(thresholds));
metrics.add(JevTraceMetrics.trajectoryMatch(
    JevTraceMetrics.MatchMode.STRICT, true));
var traceEvaluator = new JevTraceEvaluator(client, metrics,
    new JevTraceEvaluator.Limits(Duration.ofSeconds(3), 128, 100_000));
```

同一个 traceEvaluator 可以交给 `JevTraceRunner` 回放数据，也可以交给 `JevTraceEvaluationMiddleware` 观察真实 Agent 调用。接入示例见本章"采集并评估 Agent 轨迹"一节。

指标 ID 和局部题目 ID 使用字母开头的字母、数字、下划线，最长 64 字符；指标 ID 不可重复。评估器用命名空间隔离问题，兼容的 state 合并请求，冲突字段拆分请求。无问题的确定性指标不调用模型。定义和 reducer 异常只影响对应指标。

### 保存状态而非只保存总分

`JevMetricResult.passed` 可为空，非 DECIDED 状态不能声明通过或失败。保留 SKIPPED、INCONCLUSIVE 和 ERROR，分别判断是输入缺失、模型不确定还是调用失败；不要将它们替换成零分后丢掉原因。

阈值示例用于说明接口。业务金标、版本、运行模式和完整样本分母一起决定评测结果是否可比较。评测方法见本章"评测自己的 Harness 与判断后端"一节。

### 运行与验证

按第 36 章"构建一次，运行多个案例"一节设置 `JEV_CP` 后运行：

```bash
java -cp "$JEV_CP" io.agentscope.examples.jev.JevApplicationScenarios judge
java -cp "$JEV_CP" io.agentscope.examples.jev.JevApplicationScenarios evaluation
```

两个入口复用源码中的 `answerDefinition()`：单条调用展示状态边界，批量调用回放一正一反样本。它们用预设概率验证定义复用，不以离线匹配数宣称模型准确率。完整源码为示例模块中的 `JevApplicationScenarios`。

## 批量评估问题、证据与回答

`JevEvaluator` 将问题、证据和回答交给统一的 Judge 定义；`JevEvaluationRunner` 回放固定样本并按场景汇总。适合修改提示词、检索或生成模型后，对客服回复和知识答案做质量回归。

### 示例场景：改了客服提示词，检查退款承诺有没有变差

同样面对"退款了吗？"和"尚未执行退款"的业务记录，一条回答如实说明需核查，另一条却声称退款完成。我们希望使用同一套标准比较它们，而不是每次人工临时决定什么算好答案。

先定义"回答有业务证据支持"的标准，再把每条问题、证据、回答放进 `Evaluator.Request`。预期通过或失败的金标只交给 runner，不发送给评审模型。

### 1. 复用草稿评审定义

```java
import io.agentscope.extensions.judge.jev.JevJudge;
import io.agentscope.extensions.judge.jev.NoulQuestion;
import io.agentscope.extensions.judge.jev.evaluation.Evaluator;
import io.agentscope.extensions.judge.jev.evaluation.JevEvaluator;
import io.agentscope.extensions.judge.jev.evaluation.JevEvaluationRunner;
import java.time.Duration;
import java.util.List;

var definition = new JevJudge.Definition("refund-answer-v1", List.of(
    new JevJudge.Criterion("supported",
        new NoulQuestion(
            "Is assistant_answer supported by supporting_context without inventing completed refunds?",
            null),
        true, 0.2, 0.8)));
var judge = new JevJudge(client, Duration.ofSeconds(2));
Evaluator evaluator = new JevEvaluator(judge, definition);
```

`client` 的配置见客户端接入（见第 36 章）。定义与单条 Judge 用法（见本章"用条件定义评审标准"一节）相同，问题、证据和回答分别映射到 `user_question`、`supporting_context`、`assistant_answer`。

### 2. 构造一正一反的固定样本

```java
var evidence = List.of("业务记录：尚未执行退款");
var honest = new Evaluator.Request("honest", "退款了吗？",
    evidence, "尚未退款，需先核查状态");
var invented = new Evaluator.Request("invented", "退款了吗？",
    evidence, "退款已经完成");
var cases = List.of(
    new JevEvaluationRunner.Case("退款承诺", honest, true),
    new JevEvaluationRunner.Case("退款承诺", invented, false));
var pending = new JevEvaluationRunner().run(evaluator, cases, 2);
```

`honest`、`invented` 是唯一 ID；"退款承诺"是报告中的场景分组；最后的布尔值是预期标签。并发 2 表示最多同时评审两条，实际返回顺序仍与输入一致。不要把错误回答的标签写进证据中。

### 3. 一起看正确、弃权和错误

```java
var observed = pending.doOnNext(report -> {
    System.out.println("总体：" + report.overall());
    System.out.println("退款场景：" + report.scenarios().get("退款承诺"));
    report.rows().forEach(row ->
        System.out.println(row.id() + " " + row.response().verdict().status()));
});
```

报告分别统计正确、错误、弃权和调用错误。准确率是正确数 / 全部样本数，弃权和接口错误不会从分母消失。单条 `pass()` 只在 Judge 总状态 PASS 时为 true；`score()` 是通过条件占比，不能替代完整 verdict。

例如不实回答得到 FAIL 算一次正确判断；如果接口超时，即使 `pass=false`，也不算"正确识别了不实回答"。

### 运行与验证

按第 36 章"构建一次，运行多个案例"一节设置 `JEV_CP` 后执行：

```bash
java -cp "$JEV_CP" io.agentscope.examples.jev.JevApplicationScenarios evaluation
```

离线夹具对两条样本分别返回 PASS、FAIL，报告显示 2 条匹配。它验证标签隔离与统计口径，不是"模型准确率 100%"的证据。完整用例为示例模块中的 `JevApplicationScenarios`。

需要对比真实后端时，让两个 Evaluator 使用同一数据集、定义和预算，保留各自错误、弃权、用量及版本。"评测自己的 Harness 与判断后端"一节（见本章）说明如何组织对照。

### 预算、报告与取消

最多 10,000 条样本，ID 唯一，并发范围 1–32。Judge 控制每次评审预算；自定义 Evaluator 也需要自己的超时。runner 捕获单项异常或空响应并记 ERROR；取消会终止整个订阅，不作为正常完成报告返回。

P50/P95 使用最近秩，度量的是评审耗时，不是 Agent 完整任务时间。适配器之外的错误条目耗时可能为零，应同时看错误数。报告不保存原始问题、回答和证据；用量未知时保持未知，没有核实价格时不推算费用。

## 评测自己的 Harness 与判断后端

用同一组输入比较原流程、JEV 增强流程和文本模型判断，才能知道增加判断后是否改善业务结果。将判断质量、Harness 实际行为和端到端效果分别测量。

### 场景：退款拦截是否值得增加一次判断

"先查订单，未发货再退款"中，一个判断器即使拒绝了全部危险调用，也可能把所有正常退款一起拦住。应同时观察错误放行、正常调用受阻和额外等待时间，才能判断接管是否有价值。

退款防护对比用例（见 `agentscope-examples/jev/benchmarks/tool-guard` 的 README）提供 160 条合成数据、数据划分、标注理由、离线行为测试与 JEV/Qwen 实测记录，代码和结果集中在 `agentscope-examples/jev/benchmarks/tool-guard`。它的命令行参数与下表通用基准不同，请按其 README 运行；第 37 章"在工具执行前检查受保护操作"的"退款场景对比测试"小节保留简明结果。

### 选择评估对象

- **判断层**：工具适用性、分类、审核、路由标签、压缩建议是否符合金标。
- **执行层**：拒绝是否真的阻止派发，允许是否恰好执行一次，结果是否与调用配对，取消后是否停止。
- **任务层**：回答正确性、证据召回、关键事实保留、任务成功率与完整耗时。

动作标签正确不能替代浏览器任务完成；路由标签一致不能证明节省成本；压缩建议正确也不能单独证明后续答案正确。

### 固定输入与可运行入口

案例模块提供合成样本，适合学习数据格式和跑通对照管线。用于业务验收时，应补充真实业务分布的独立金标与难例。

| 方向 | 程序入口 | 固定输入 |
|---|---|---|
| 轨迹评估 | `JevTraceBenchmark` | `trace-cases.jsonl` |
| 上下文压缩 | `JevContextBenchmark` | `context-cases.jsonl` |
| 长任务监督 | `JevSupervisionBenchmark` | `supervision-cases.jsonl` |
| 代码评审 | `JevCodeReviewBenchmark` | `review-cases.jsonl` |
| 检索证据 | `JevEvidenceBenchmark` | `evidence-cases.jsonl` |
| 阶段路由 | `JevPhaseRoutingBenchmark` | `phase-routing-cases.jsonl` |
| 浏览器可见动作 | `JevBrowserBenchmark` | `browser-cases.jsonl` |

这些程序回放固定判断输入，不运行完整生产任务。金标只用于判分，不发送给后端。原始数据位于 `agentscope-examples/jev/src/test/resources/jev`。

### 运行基线与同题对照

先按第 36 章"构建一次，运行多个案例"一节设置 `JEV_CP`。以轨迹评估为例：

```bash
JEV_DATA="agentscope-examples/jev/src/test/resources/jev/trace-cases.jsonl"
java -cp "$JEV_CP" io.agentscope.examples.jev.JevTraceBenchmark \
  --baseline "$JEV_DATA" /tmp/trace-baseline.json
java -cp "$JEV_CP" io.agentscope.examples.jev.JevTraceBenchmark \
  --offline "$JEV_DATA" /tmp/trace-offline.json
```

所有表中程序支持 `--baseline`；只有轨迹程序提供这里的 `--offline` 合成判断模式。输出路径必须不存在，避免覆盖上次报告。

真实后端必须显式启用，模型名和端点由你选择：

```bash
java -cp "$JEV_CP" io.agentscope.examples.jev.JevTraceBenchmark \
  --live-jev "$JEV_DATA" /tmp/trace-jev.json jev-latest
java -cp "$JEV_CP" io.agentscope.examples.jev.JevTraceBenchmark \
  --live-qwen "$JEV_DATA" /tmp/trace-qwen.json "$QWEN_MODEL" "$QWEN_ENDPOINT"
```

JEV 使用 `TYPESAFE_API_KEY`，Qwen 使用 `DASHSCOPE_API_KEY`；QWEN_ENDPOINT 应为账号所在区域的兼容 Chat Completions 完整端点。其他方向按表替换程序名和数据路径，参数顺序相同。真实调用会产生接口用量，离线运行不读取密钥。

### 读懂报告并校准阈值

按场景记录正确、错误、弃权、跳过和调用错误。对有金标样本的总体准确率，弃权和错误保留在分母；另报接管覆盖率和接管样本错误率，避免通过丢弃难例提高表面准确率。

区分判断的 P50/P95 与整个 Agent 的端到端 P50/P95。报告中的 token 只覆盖拿到 usage 的响应；价格或用量未知时不推算零成本。概率阈值在独立校准集选择，再在未参与调参的数据上比较；不要用模型彼此一致作为金标。

保留定义版本、实际模型版本、输入哈希、运行区域和模式。对少量样本的结论附上样本量，业务评估可增加配对置信区间、选项顺序/命名置换与并发取消检查。上线前先在 SHADOW 记录建议，再按具体用途选择是否接管。

## 配置预算与消费决策记录

JEV 增加的是判断步骤。为它分配独立预算，并把建议、实际执行和最终业务结果分开观测，才能判断是否改善了你的 Harness。

### 场景：查明退款助手慢在哪里

一次客服请求先选择工具，再检查退款调用，最后审核回答。整个请求变慢可能来自生成模型、订单接口，也可能来自 JEV 重试。应分别记录每个判断的版本、预算和耗时，并关联同一 run 的工具执行结果，不能只看整次 Agent 的总时间。

### 给判断设置预算并接入观测

下面用有界内存队列展示观察器的接入位置；生产应用可由异步消费者定期读取并写入自己的观测系统。

```java
import io.agentscope.extensions.judge.jev.JevExecution;
import java.time.Duration;
import java.util.concurrent.ArrayBlockingQueue;

var decisions = new ArrayBlockingQueue<JevExecution.Record>(256);
var options = new JevExecution.Options(
    JevExecution.Mode.SHADOW, Duration.ofSeconds(2), "orders-v1",
    (ctx, record) -> decisions.offer(record));
```

队列满时 `offer` 返回 false，当前示例会丢弃该条观测；不阻塞 Agent，也不提供可靠审计保证。应用可按需增加丢弃计数，并在入队前附上当前 run/session 的身份。每项逻辑判断的预算包含该项所有批次、重试和退避；不自动限制整个 Agent。响应中间件的 roundBudget 还包括原模型生成；浏览器工具预算包括页面操作与验证；含 Source 的具体重载是否覆盖数据读取，见对应 API 节。

观察器应快速返回。RuntimeException 被隔离不影响 Agent，但同步阻塞回调不会自动获得后台线程或额外超时保护。HTTP 请求、数据源和存储分别设置自身超时。

### 应记录哪些字段

| 字段 | 用途 |
|---|---|
| purpose、version、mode | 区分用途、定义版本和是否接管 |
| status、reason | 区分有效判断、不确定、跳过、取消和错误 |
| elapsed | 该判断环节的附加耗时 |
| recommendation | 各用途的工具名、模型 ID、动作或建议摘要 |
| RuntimeContext 身份 | 关联你的 run/session，隔离并发调用 |

不要用 SHADOW 的推荐模型统计实际派发模型，也不要用"建议拒绝"统计已阻止的工具。阶段路由的 CallRecord 记录派发与模型用量；轨迹、评审、检索等报告的 calls 记录判断请求。没有返回 usage 的请求成本为未知，不是零。

### 取消与失败

取消向在途请求和数据读取传播，组件停止后续派发。取消不一定撤销已经完成的远端请求或工具操作；需要结合执行收据处理未知结果。

根据用途读取失败行为：工具选择与路由保留原输入，受保护工具预检失败拒绝执行，发布前审核失败不发布。事后轨迹评估与长任务监督只记录结果，不重放原 Agent。

### 从影子模式切换

先固定金标、模式和定义版本，记录分场景错误与弃权，再按本章"评测自己的 Harness 与判断后端"一节选择阈值。切换某一用途到 ENFORCE 时，确认其数据源、权限和失败处理已经接入。线上仍保留独立的工具执行结果和业务质量指标。

Service 的配置与事件查询见第 37 章"在 AgentScope Service 中配置 JEV"一节。

### 验证回退是否符合用途

工具防护对比用例（见 `agentscope-examples/jev/benchmarks/tool-guard` 的 README）同时记录检查耗时与实际派发，包含离线超时、取消、观察器异常和并发隔离测试。先跑这些固定分支，再对你的业务数据测量质量与延迟；不要用离线模拟耗时作为线上容量估计。

## API 与包索引

通过本节查找导入位置。基础依赖是 `io.agentscope:agentscope-extensions-jev`，与项目 BOM 使用同一版本；Harness 集成另外依赖同版本 `agentscope-harness`。

| 包（前缀 `io.agentscope.extensions.judge.jev`） | 主要入口 | 使用说明 |
|---|---|---|
| 根包 | JevClient、SystemOneRequest、JevJudge、JevExecution、JevGuardrail | 客户端（见第 36 章）、评审定义（见第 38 章） |
| example | JevToolSelectionMiddleware、JevAutoModeMiddleware、JevModelRouterMiddleware | 运行模式（见第 36 章） |
| evaluation | JevTrace、JevTraceMetric、JevTraceEvaluator、JevTraceEvaluationMiddleware、JevTraceRunner、JevEvaluator、JevEvaluationRunner、JevTextBackend | 轨迹评估（见第 38 章） |
| context | JevContextCompactor、JevContextArchive、FileJevContextArchive、StoreJevContextArchive | 上下文压缩（见第 37 章） |
| supervision | JevTaskSupervisor、JevSupervisionMiddleware、SupervisionEvidence | 持续监督（见第 37 章） |
| routing | JevPhaseRouting、JevRouteCatalog | 阶段路由（见第 37 章） |
| evidence | JevPassage、JevEvidenceProcessor、JevEvidenceTool | 检索证据（见第 37 章） |
| review | JevReviewInput、JevCodeReviewer、JevCodeReviewTool、ReviewRegions | 代码评审（见第 37 章） |
| browser | JevBrowserSession、JevBrowserNavigator、JevBrowserReadTool、JevPlaywrightSession | 只读浏览器（见第 37 章） |
| integration | JevResponseMiddleware、JevKnowledge、JevKnowledgeTool | 回答审核（见第 37 章）、Knowledge 适配（见第 37 章） |
| application | JevCandidateSelector、JevCustomerSupport、JevRag、JevDraftPipeline、JevSupervisor、JevContextPlanner、JevMemoryGate、JevStageRouter、JevTeamPlanner、JevBrowserPlanner | 应用组件（见第 37 章） |

`example` 是三个可复用中间件的现有包名。可运行案例另在 `agentscope-examples/jev`，使用 `io.agentscope.examples.jev` 包，不需要将 examples 加为生产依赖。

例如，给退款工具增加派发前检查，导入 `example.JevAutoModeMiddleware`；审核最终回答，导入 `integration.JevResponseMiddleware`；只评审一份已有草稿，则用根包的 `JevJudge`。先按任务选择功能节，再从本表查找导入位置。

文档片段中的 model、ACL、Source、记录函数及业务存储由应用提供。完整导入和可运行装配见第 36 章"运行案例与功能入口"一节。
