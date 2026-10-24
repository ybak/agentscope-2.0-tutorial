---
chapter: 5
title: 工具接入实战
source: https://modelcontextprotocol.io/specification/2026-07-28/server/tools
---

# 第 5 章 工具接入实战

> 本章逐节对照规范 server/tools 原文(2026-07-28);错误路径与结构化输出经 TypeScript SDK v2.4.0 实测印证。

先立一个规范原文的立场:工具是 **model-controlled** 的——模型根据上下文自主发现并调用。这意味着工具设计的全部功夫,都花在帮模型"选得对、填得准、错了自己爬起来"。同时规范同样强调另一面:**任何时刻都应有人类在环(human in the loop)并有权拒绝调用**——Host 应该展示暴露了哪些工具、调用时有视觉指示、敏感操作弹确认。这两句话放在一起,就是本章的世界观:给模型自由,给人类缰绳。

## 5.1 工具定义解剖

`tools/list` 返回的每个工具,完整构成:

| 字段 | 作用 | 给谁看 |
| --- | --- | --- |
| `name` | 唯一标识,调用凭据 | 协议(模型引用) |
| `title` | 人类可读名 | 人(目录/审批界面) |
| `description` | 功能描述 | **模型**(选择依据) |
| `inputSchema` / `outputSchema` | 参数与输出的 JSON Schema | 协议校验 + 模型填参 |
| `icons` | 界面图标 | 人 |
| `annotations` | 行为注解(readOnlyHint 等) | Host(⚠️ 规范明示:**来自不可信 Server 时视为不可信**) |

**工具名规范**(SHOULD):1-128 字符;大小写敏感;仅 `A-Za-z0-9_.-`;Server 内唯一。关键细节:**唯一性的作用域是单个 Server**——聚合多 Server 的 Host/网关会遇到两个 Server 都叫 `search` 的撞名,应当加前缀消歧,且不能依赖 `serverInfo.name`(不保证全局唯一)。这正是第 6 章命名规范(`domain_action`)的协议依据。

无参数工具的规范写法(推荐显式拒绝多余属性):

```json
{ "type": "object", "additionalProperties": false }
```

## 5.2 Schema:约束写进结构,别靠劝说

`inputSchema` 默认 JSON Schema 2020-12(可 `$schema` 显式指定 draft-07 等,实现至少支持 2020-12)。四条设计规则:

1. **类型最小化**:扁平优于深嵌套,模型对深层结构的填参错误率显著更高
2. **必填慎用**:每个 `required` 都是模型"编一个值"的诱惑;无法从上下文推断的参数做成可选,或用 MRTR 向用户要(5.5)
3. **约束进 schema**:格式(正则)、枚举、范围放 schema 约束——它们会被校验层执行;description 只是劝说
4. **每字段带 description**:zod 的 `.describe()` 原样进入 JSON Schema(第 4 章实测),成本最低收益最大

**`$ref` 安全**:2020-12 允许 `$ref` 指向网络 URI,但实现**不得**自动解引用网络引用(可提供默认关闭的 opt-in,且需 host 白名单/超时/日志);因未解析的 `$ref` 而校验失败的 schema 应拒绝而非当宽松处理。组合关键字(`anyOf`/`oneOf`/`if-then-else`)要有深度/数量/时间预算上限——恶意 schema 是校验器的 DoS 向量。

## 5.3 描述质量:模型靠 description 选工具

工具选择的本质是模型拿用户意图与描述做匹配。同一能力两种写法:

```text
❌ 系统视角:"调用售后中台工单查询接口 /api/v1/tickets/query"
✅ 任务视角:"按售后单号查询售后单当前进度(审核/维修/退款/完结)。
   单号格式 T-YYYY-NNNN。查物流轨迹用 logistics 域工具,不要用本工具。"
```

三条来源:**任务语义**(说做什么,不说调哪个接口)、**边界声明**(什么情况别用我——防误选)、**格式示例**(给模型可模仿的填参样例)。Server 级还有 `server/discover` 的 `instructions` 字段——写给模型的 Server 使用说明(第 2.6),与工具描述是同一门手艺的两级。

## 5.4 调用与结果:content、structuredContent 与两类错误

`tools/call` 的结果分**非结构化**(`content` 数组)与**结构化**(`structuredContent`)两种载体。content 支持五种类型,都可带 annotations(audience/priority):

- `text` / `image`(base64)/ `audio`(base64)
- `resource_link`:指向资源的 URI(可被订阅或拉取;注意:工具返回的资源链接**不保证**出现在 `resources/list` 里)
- `resource`:直接内嵌资源内容

**结构化输出**:定义了 `outputSchema` 时,Server **必须**返回符合它的 `structuredContent`(任意 JSON 值);client **应该**据此校验。向后兼容:返回结构化内容的工具**应**同时在 text content 里给序列化 JSON。v2.4.0 实测(第 4 章)印证了并存形态。

### 两类错误,两条路

规范对错误的分类,是工具错误处理的总纲:

| | 协议错误(Protocol Error) | 工具执行错误(Tool Execution Error) |
| --- | --- | --- |
| 例子 | 未知工具、请求畸形、Server 内部错误 | API 失败、输入校验失败(日期格式/值越界)、业务规则不允许 |
| 形态 | JSON-RPC `error` 对象 | 正常 result + `isError: true`,消息进 content |
| 模型能否自纠 | 较难(client 可以给模型,但恢复率低) | **应给模型**——规范的用词是 self-correct |

官方示例的错误消息值得抄进团队规范:`"Invalid departure date: must be in the future. Current date is 08/08/2025."`——三要素齐活:错了什么、规则是什么、模型下一步该怎么改。

## 5.5 缺输入怎么办:工具里的 MRTR

工具执行到一半缺用户输入(确认、必选字段),返回 `resultType: "input_required"` 的 `InputRequiredResult`。完整协议流转(规范原文示例译述):

```json
// ① Server 返回,inputRequests 以键命名每个所需输入,requestState 原样带回
{ "resultType": "input_required",
  "inputRequests": { "github_login": { "method": "elicitation/create",
      "params": { "mode": "form", "message": "Please provide your GitHub username",
        "requestedSchema": { "type": "object", "properties": { "name": { "type": "string" } }, "required": ["name"] } } } },
  "requestState": "eyJsb2NhdGlvbiI6Ik5ldyBZb3JrIn0..." }

// ② client 收集后,重试原始请求:inputResponses 对应同键,requestState 原样带回
{ "method": "tools/call", "params": { "name": "...", "arguments": {...},
    "inputResponses": { "github_login": { "action": "accept", "content": { "name": "octocat" } } },
    "requestState": "eyJsb2NhdGlvbiI6Ik5ldyBZb3JrIn0..." } }
```

三个协议细节,实现时全要踩对:**重试的 JSON-RPC `id` 必须与原请求不同**;`requestState` 是 Server 放置续接上下文的不透明载体(client 原样带回,不解析);elicit 结果带 `action`(accept/decline/cancel),Server 要处理拒绝分支。SDK 层(TS v2.4.0)的 `inputRequired` 构造器封装了 ①。

## 5.6 有状态工具:显式句柄模式

无状态协议下"购物车""打开的浏览器会话""数据库事务"怎么办?规范给了专门的非规范指导(Stateful Tools),模式一句话:**创建工具返回显式句柄,后续工具把句柄当普通参数传入**——线路上看,句柄就是结果里的一个字符串、下次调用的一个参数:

```jsonc
// tools/call: { "name": "create_basket" }
{ "structuredContent": { "basket_id": "bsk_a1b2c3" } }

// tools/call: { "name": "add_item", "arguments": { "basket_id": "bsk_a1b2c3", "sku": "..." } }
```

模型负责把 `basket_id` 带到下一次调用;Server 按 key 存取购物车内容。句柄设计四要点(规范原文归纳):

1. **授权**:句柄是名字,不是能力凭证——已认证 Server 每次调用都要按调用者校验句柄归属;未认证 Server 的句柄实质是 bearer token,要够熵(UUIDv4)且限时
2. **不透明**:编码内部结构的句柄会诱发解析与猜测;不透明 ID 不会
3. **生命周期**:句柄活得比任何连接久,保留策略写进**创建工具的 description**(如"24 小时不活跃即过期")——模型要在决定创建状态时看到它
4. **过期可自纠**:对过期/未知句柄的调用返回工具执行错误(isError),消息说明"创建一个新的即可"——模型能恢复

这是无状态重构后最重要的工具设计范式,贯穿案例的售后单撤销流程(先查后撤,单号即句柄)就是它的应用。

## 5.7 x-mcp-header:参数镜像为 HTTP 头

Streamable HTTP 下,Server 可以在 inputSchema 的属性上标注 `x-mcp-header: "Region"`,调用时 client 把参数值镜像为 `Mcp-Param-Region: us-west1` HTTP 头——**让 LB/代理/WAF 不解析 body 就能按参数路由**。约束:值符合 HTTP token 语法、大小写不敏感唯一、仅限原始类型参数(string/integer/boolean,number 不行)、必须从 schema 根静态可达;**敏感参数(密码/key/token/PII)不得标注**——头对网络中间件可见。client 在 Streamable HTTP 下必须剔除违规工具的定义(并记警告),不牵连其他工具。

这是第 6 章 Gateway 路由的协议级机关:域路由、租户头都可以由此从参数层浮到网络层。

## 5.8 安全清单:规范分给两边的责任

**Server 必须**:校验所有工具输入;实现访问控制;对调用限流;消毒工具输出。

**Client 应该**:敏感操作请求用户确认;调用前向用户展示工具输入(防恶意或意外的数据外泄);工具结果交给 LLM 前先校验;实现调用超时;记录工具使用审计日志。

加上 5.1 的"annotations 视为不可信"与 5.2 的 `$ref` 规则,工具层的攻击面防线就齐了。多租户与授权的体系化展开在第 8 章。

## 5.9 贯穿案例:售后域前三件套

| 工具 | 聚合的中台接口 | 本章知识点落地 |
| --- | --- | --- |
| `after_sales_query_ticket` | 单查询 + 进度轨迹(2 接口) | 正则约束单号;outputSchema + structuredContent;错误消息三要素 |
| `after_sales_create_ticket` | 校验 + 风控 + 创建(3 接口) | 幂等键参数;缺退款方式 → input_required(elicit 表单,requestState 续接) |
| `after_sales_estimate_refund` | 退款试算(1 接口) | description 声明"仅试算不产生退款";annotations 只读提示 |

每一步走"差版描述 → 观察误选 → 好版对照"的评审流程——这就是团队评审工具定义的标准动作。

## 5.10 小结

- 模型控制 + 人在环:给模型自由,给人类缰绳
- schema 是约束层(执行),description 是劝说层(选择);名字的消歧在聚合层
- 两类错误两条路:协议错误难自纠,执行错误 isError 进 content 让模型自纠
- 缺输入走 input_required(重试原请求,id 要新,requestState 原样带)
- 有状态 = 显式句柄:名字不是能力,过期要可自纠
- x-mcp-header 把参数浮上网络层——Gateway 的路由机关

→ 单工具的手艺到此完整;**第 6 章**放大到数千接口的中台。

## 复核清单(发布前)

- [x] 全章对照 server/tools.mdx 原文(2026-10-24,含 x-mcp-header 约束与 Stateful Tools 指导)
- [ ] Java 侧平行示例(mcp-core 2.0.x)实测补充
- [ ] annotations 全集(readOnlyHint 等)对照 schema.ts 补表
- [ ] elicitation 的 form/URL 两种模式细节(client/elicitation.mdx,671 行)按需补节
