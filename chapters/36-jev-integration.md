---
chapter: 36
title: 发起判断：客户端、问题类型与运行模式
source: jev/guides/client.md, jev/guides/harness-runtime.md, jev/guides/agent-integration-example.md, jev/concepts.md
---

# 第 36 章 发起判断：客户端、问题类型与运行模式

> 本章导读：第 35 章回答了"为什么需要独立的判断能力"并跑通了一个最小例子；本章把这个例子扩展成**一个判断的完整生命周期**——引入依赖、配置客户端、构造问题、读取结果、处理错误，然后把判断挂进 Harness 链路（OFF/SHADOW/ENFORCE 运行模式、总预算与决策观察器），最后讲清两组最容易混淆的状态契约。全部代码与命令原样可运行。读完本章，你能独立发起生产可用的类型化判断，并知道每种失败/不确定状态该怎么处理。

两条边界先说在前面：其一，本章多处使用离线案例——它们注入预设概率、不调用 HTTP、不读取密钥，只用于演示状态与执行分支，**离线结果不能作为模型效果、准确率或性能的证据**；其二，环境变量中存在密钥不会自动启用任何 Harness 能力——工具选择、防护等中间件需要显式注册并设置运行模式。

## 一个判断的完整生命周期

从第 35 章的例子开始补全。第一步是引入依赖：

```xml
<dependency>
  <groupId>io.agentscope</groupId>
  <artifactId>agentscope-extensions-jev</artifactId>
  <version>${agentscope.version}</version>
</dependency>
```

涉及 Harness 中间件、压缩或 Agent 案例时，还需要同版本 `agentscope-harness`；扩展中的 Harness 依赖为 optional。

### 构造客户端与请求

业务记录是"尚未发起退款"，Agent 却生成了"退款已完成"。把回答与记录放在同一份 state 中，询问记录是否支持回答：

```java
import io.agentscope.extensions.judge.jev.*;
import java.time.Duration;
import java.util.Map;

var client = JevClient.builder()
    .apiKey(System.getenv("TYPESAFE_API_KEY"))
    .model("jev-latest")
    .timeout(Duration.ofSeconds(5))
    .retryPolicy(new JevRetryPolicy(2, Duration.ofMillis(500)))
    .build();
var request = SystemOneRequest.builder()
    .state(Map.of("answer", "退款已完成", "record", "尚未发起退款"))
    .question("supported", new NoulQuestion(
        "Does the business record support the answer?", null))
    .build();
var pending = client.systemOne(request); // Mono<SystemOneResult>
var result = pending.block();            // 独立命令行案例可阻塞等待
var answer = (NoulAnswer) result.answers().get("supported");
System.out.println("记录支持回答的概率：" + answer.noul());
```

返回的数值不是退款状态，也不会改变业务记录。若需要 PASS/FAIL/INCONCLUSIVE 与阈值处理，直接使用条件评审组件（第 38 章），避免各业务重复实现分支。

写法上有三条约定：在响应式服务中返回或组合 `Mono`，避免为了记录结果重复订阅（同一个 Mono 每次订阅都会重新评审）；共享 state 在请求完成前不要修改；需要多个判断时，在同一个 builder 上按不同 ID 添加 `.question(...)`，一次请求带回全部答案。

### 客户端配置与错误

默认端点为 `https://api.typesafe.ai`，默认模型为 `jev-latest`，单次请求超时 5 秒。没有显式 key 时，依次读取 `TYPESAFE_API_KEY`、`JEV_API_KEY`。

客户端向 `/v1/systemone` 发请求，对 HTTP 429、529 和 5xx 按策略退避重试；非重试错误、重试耗尽和响应校验失败抛出 `JevException`。它检查题目集合、答案类型、概率分布和 Score 等级。**应用不应从缺失答案中补造成功结果**——缺答案就是失败，与"判断为否"是两回事。

单次 HTTP 超时与一次逻辑判断的总预算是两回事：多批次、重试和退避的总上限由 `JevExecution` 设置（见下一节）。取消可以停止本地订阅，远端请求是否中断取决于传输实现。

Spring Boot 项目可以用 starter 代替手工构建：

```xml
<dependency>
  <groupId>io.agentscope</groupId>
  <artifactId>agentscope-jev-spring-boot-starter</artifactId>
  <version>${agentscope.version}</version>
</dependency>
```

```yaml
agentscope:
  jev:
    api-key: ${TYPESAFE_API_KEY:}
    model: jev-latest
    timeout: 5s
    retry:
      max-retries: 2
      initial-backoff: 500ms
```

可用 `JevClientBuilderCustomizer` bean 定制构建器。Starter 只配置客户端；具体 Harness 能力仍需显式注册和设置模式。

还没有密钥时，可以先用文本模型做同题对照：`JevTextBackend(model, transport)` 接收 `SystemOneRequest`，生成兼容 Chat Completions 的请求，transport 是应用提供的 `Function<String, Mono<String>>`。适配器严格校验 JSON、题目和分布，不补缺项、不自动归一化非法概率；**文本模型自报的概率需单独校准**（第 38 章）。

## 三种问题类型的使用规则

第 35 章给出了三种类型的定义，这里补齐使用规则——选错类型是 JEV 最常见的误用。

| 类型 | API | 返回值 | 典型用途 |
|---|---|---|---|
| 是非判断 | `NoulQuestion` / `NoulAnswer` | 陈述为真的概率 | 工具是否适用、回答是否有依据 |
| 单选 | `ChoiceQuestion` / `ChoiceAnswer` | 选项、完整分布和置信度 | 模型路由、动作选择 |
| 评分 | `ScoreQuestion` / `ScoreAnswer` | 等级分布、加权分数和置信度 | 风险严重度、分级评估 |

构造判断时，先决定你需要的是概率、单选还是评分，再决定应用如何消费它；结果符合结构并不保证语义正确。以条件性退款为例：用户要求"查订单，未发货再退款"，判断"退款工具是否适用"时，订单查询和退款**都可能适用**，应分别问是非题；判断"这次分析选哪个模型"才是单选的用武之地；评估一项风险的严重程度则用分级评分。**多选适用性必须逐候选判断，不能用一次互斥 Choice 代替。**

请求与输入的组织也有两条纪律。一个 `SystemOneRequest` 包含共享 `state` 和按 ID 命名的多个问题：把业务材料放入 state，把判断标准写进问题。**不要把金标答案（预先标注的期望结果）混入待评输入**——金标只用于离线判分（第 38 章），进入请求就等于让考生看答案。同理，不要把隐式授权混入待评输入：JEV 判断不授予工具权限，即使 JEV 认为退款操作合适，也要检查订单事实与执行权限。把业务输入、语义建议和执行结果分开，后续各项 API 的状态才不会被误读。

## 挂进 Harness：运行模式、预算与观察器

直接调用覆盖了"应用自己有材料"的场景；JEV 更大的价值在 Agent 链路里——工具选择、执行防护、模型路由。这些 Harness 能力通过 `JevExecution.Options` 统一配置：每个用途有自己的模式、预算、版本标识和观察器，可以独立验证、独立灰度。

三种运行模式再明确一次：**OFF** 不发起判断，沿原流程执行；**SHADOW** 实际发起判断并记录建议，但无论建议如何，原输入都继续交给后续流程；**ENFORCE** 发起判断，并按防护结果阻止或放行受保护调用。

### 示例场景：先观察退款防护，再开启实际拦截

你准备给客服 Agent 增加退款前检查，但尚不知道判断会不会误拦正常请求。直接接管可能影响业务，完全关闭又无法积累样本。SHADOW 会实际发起判断并记录建议，同时把原输入继续交给后续流程——这样可比较"建议拦截"与业务预期；验证和校准后（第 38 章），再把退款防护单独切到 ENFORCE。

```java
import io.agentscope.extensions.judge.jev.JevExecution;
import io.agentscope.extensions.judge.jev.example.JevAutoModeMiddleware;
import java.time.Duration;

var options = new JevExecution.Options(
    JevExecution.Mode.SHADOW, Duration.ofSeconds(2), "refund-guard-v1",
    (ctx, record) -> System.out.println(record));
var guard = JevAutoModeMiddleware.builder(client)
    .execution(options)
    .guardedTool("refund")
    .build();
```

`guard` 注册到 `HarnessAgent.builder().middleware(guard)`。版本（`refund-guard-v1`）用于区分不同配置的观察结果；改了评审用途或阈值时不要沿用无法区分的版本标识。2 秒覆盖一次逻辑判断的**所有批次、客户端重试和退避**，不包含之后 Agent 执行工具的时间——客户端单次 HTTP 超时不能代替这个总预算。

### 区分建议与实际动作

| 模式 | 是否发起判断 | 退款例子中的实际行为 |
|---|---|---|
| OFF | 不调用 | 沿原流程，可能不产生观察记录 |
| SHADOW | 需要判断时调用 | 即使建议拒绝，退款仍进入原执行链 |
| ENFORCE | 需要判断时调用 | 按防护结果阻止或放行受保护调用 |

切换模式需要应用明确更新配置并重新装配中间件；不同用途可以采用不同模式，例如工具选择保持 SHADOW，退款防护单独接管。

### 记录足以比较的决策元数据

观察器收到当前 RuntimeContext 和 Record：

| 字段 | 如何使用 |
|---|---|
| `purpose / version / mode` | 区分工具选择、防护等用途及当时配置 |
| `status / reason` | 区分明确判断、不确定、调用失败和取消 |
| `elapsed` | 查看这次检查耗时，不误当成整个 Agent 时间 |
| `recommendation` | 记录推荐模型、拒绝调用 ID 等建议，与实际执行记录对照 |

Record 不包含消息全文、工具参数、密钥或原始错误。宿主可以用 RuntimeContext 关联 run/session；观察器应快速返回，数据库写入需自行排队。观察器抛出的 RuntimeException 不会阻断 Agent，但同步阻塞不会自动转成后台任务。

### 按用途理解失败策略

第 35 章说过"判断失败降级到安全路径"，具体到每个用途：

| 用途 | ENFORCE 判断失败时 |
|---|---|
| 工具选择 | 保留原候选工具 |
| 模型路由 | 使用原模型，不重跑 Agent |
| 执行前防护 | 拒绝受保护调用，其他工具沿原流程 |
| 内容及质量审核 | 不发布未通过的文本 |

公共状态包括 DECIDED、INCONCLUSIVE、ERROR、CANCELLED、SKIPPED；TIMEOUT 和 CALL_OR_RESPONSE_ERROR 是故障原因。取消只通知观察器，不伪造一个回退结果继续派发。轨迹事后评估与长任务监督只允许 OFF/SHADOW——它们不能撤销已经发生的行为。直接调用 Judge、记忆评审等应用 API 会立即进入各自评审流程，不隐式读取全局模式；应用的用途开关应包围完整工作流。

## 两组状态契约：评审结果与执行决策

到这里，配置与请求都会写了，剩下的是读结果的纪律。JEV 有三组返回状态，混用它们是线上误判的常见来源——每一组的语义都不同。

**`JevJudge` 的评审状态**：对一组 Noul 条件聚合为 `PASS`、`FAIL`、`INCONCLUSIVE`、`ERROR`，适合"全部条件都必须满足"的审核。期望为 false 的条件按 `1-p` 计算满足概率。误读反例：把 INCONCLUSIVE（没判断出来）当作 PASS（判断通过了）——前者该补证据，后者才能发布，两者处理路径完全不同。

**`JevExecution.Decision` 的执行状态**：`DECIDED`、`INCONCLUSIVE`、`ERROR`、`CANCELLED`、`SKIPPED`，表达**组件是否形成了有效建议**。误读反例：`DECIDED` 只说明"判断有效"，不等于任务成功，更不等于内容通过——防护 DECIDED 且建议拒绝时，动作恰恰不该执行。具体动作要读组件自己的结果。

**`JevMetricResult` 的指标状态**：把状态、分类 label、分数 score 和可空的 passed 分开。没有通过策略的分类指标不应被强制转成 PASS/FAIL——分类标签是"哪一个"，不是"好不好"。

统一的收尾纪律与第 35 章的回退原则一脉相承：**低置信度、明确否定和请求失败是三种不同情况**。工具选择可能回退原候选，执行防护可能拒绝受保护调用，事后评估则保留错误或弃权——按具体用途处理，不能把"没有有效判断"统一解释为允许。概率和置信度需要按场景校准，校准方法见第 38 章。

## 离线案例：先确认链路，再接真实后端

模式、预算和观察器都配置好了，但声明不等于运行。真实后端的验证既需要密钥，结果也不可复现；官方案例把同样的链路做成了离线可跑——先在合成判断上确认 SHADOW 记录建议、ENFORCE 产生拦截，再替换为真实后端。

所有案例位于 `agentscope-examples/jev`，包名为 `io.agentscope.examples.jev`。在仓库根目录构建一次：

```bash
mvn -pl agentscope-dependencies-bom,agentscope-distribution/agentscope-bom,agentscope-examples/jev -am install -DskipTests
mvn -pl agentscope-examples/jev dependency:build-classpath -Dmdep.outputFile=/tmp/jev-examples-cp.txt
JEV_CP="agentscope-examples/jev/target/classes:$(cat /tmp/jev-examples-cp.txt)"
```

先跑本章开头那类退款证据判断的三种状态：

```bash
java -cp "$JEV_CP" io.agentscope.examples.jev.JevApplicationScenarios judge
```

再跑 Harness 组合案例——对相同的工具选择、防护与路由输入依次运行三种模式：

```bash
java -cp "$JEV_CP" io.agentscope.examples.jev.JevHarnessExample
```

观察输出可以看到 SHADOW 的拒绝建议仍进入模拟派发，ENFORCE 才产生拒绝工具结果。组合入口 `JevIntegrationExample` 则完整走一遍"查询退款条件、取回证据、生成草稿、审核失败后仅修订文本"：

```bash
java -cp "$JEV_CP" io.agentscope.examples.jev.JevIntegrationExample
```

预期最终回答保留"未使用、七天内"两项退款条件；生成模型共调用三次：提出检索工具、生成不完整草稿、仅重写文本——修订阶段不携带工具。控制台中的合成评审统计用于确认预设分支，不是线上准确率。

想单独演练某个能力，把类名换成 `JevHarnessScenarios`（参数 `selection` 或 `routing`）、`JevTraceEvaluationExample`、`JevContextCompactionExample` 等——全部入口的速查表见第 38 章末的参考速查。唯一需要本地环境的是浏览器案例：

```bash
java -cp "$JEV_CP" io.agentscope.examples.jev.JevBrowserLocalExample \
  --browser "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
```

接入真实调用：客服案例追加 `--live` 才调用客户端；基准程序使用显式 `--live-jev` / `--live-qwen` 参数；仅设置环境变量不会将离线案例切换为真实请求。本章的客户端代码访问真实接口需显式配置密钥；接口失败应走错误处理，不能用离线结果替代真实判断。

## 本章小结

一个判断的生命周期由四段组成：

1. **发起**：`JevClient` + `SystemOneRequest`，默认端点与重试开箱即用，失败统一抛 `JevException`，不补造结果；
2. **选型**：Noul / Choice / Score 三种问题类型；多选适用性逐候选判断，金标与隐式授权不进请求；
3. **接入**：`JevExecution.Options` 按用途配置 OFF/SHADOW/ENFORCE、总预算与决策观察器，灰度路径"先 SHADOW、后 ENFORCE"，失败按用途降级；
4. **读结果**：`JevJudge` 状态（审核）、`Decision`（执行）、`JevMetricResult`（指标）三组契约不可混用，"没有有效判断"不能统一解释为允许。

下一章把这套生命周期应用到三个完整的判断域——工具防护、证据检查、内容审核——每一个都从场景配置走到阈值校准。

**验收清单**——读到这里，你应该能：

- ☐ 在 Maven 工程中引入扩展、创建 `JevClient`，发起一次多问题的 `systemOne` 判断并读出 `NoulAnswer` 的概率；
- ☐ 为一个"三选二适用"的场景选对问题类型，说出为什么不能用一次 Choice 代替逐候选 Noul；
- ☐ 说出 OFF/SHADOW/ENFORCE 各自的行为，以及为什么灰度路径是"先 SHADOW、后 ENFORCE"；
- ☐ 为一个用途配置预算、版本与决策观察器，说清观察器里该记录哪些字段、Record 不包含什么；
- ☐ 区分 `JevJudge` 状态、`Decision` 状态与 `JevMetricResult`，并为"把 INCONCLUSIVE 当 PASS"这类误读各举一个后果；
- ☐ 本机跑通 `JevHarnessExample`，说出 SHADOW 与 ENFORCE 输出的差别、以及离线结果不能证明什么。
