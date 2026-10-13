# 设计文档：跨境电商 Agent 多租户平台 Service 控制面 Demo 教学目录

> 编号已同步为 Step 01–13。本文保留早期设计与实施过程；当前可执行命令、API 和验收范围以 [Demo README](../../../demo/cross-border-commerce/README.md) 与 [验证记录](../../../demo/cross-border-commerce/verification.md) 为准。

- 日期：2026-10-13
- 状态：待用户审阅
- 代码基线：`/Users/ybak/work/code/agentscope/agentscope-java/agentscope-service`（当前 main）
- 目标仓库：`/Users/ybak/work/code/agentscope/agentscope-2.0-tutorial`（本仓库）

## 1. 背景与目标

教程第五篇（第 29-34 章）系统讲解了 AgentScope Service 平台，但全书没有跨境电商案例，也没有任何可运行的配套代码——第 34 章引用的样例文件只存在于上游官方仓库。本设计在教程仓库根目录新建一个 **demo 教学目录**，通过 REST API 编排、循序渐进地演示如何用 Service 控制面的 API 构建一个**跨境电商 Agent 多租户平台**，与第五篇形成"书讲原理、demo 动手"的配套关系。

**用户已确认的关键决策：**

| 决策点 | 结论 |
| --- | --- |
| Demo 形态 | 每步 Markdown 教程 + 同名可执行 .sh 脚本 + run-all.sh 一键编排 |
| 教学范围 | 01–13 连续编号，共 13 步 |
| 质量保障 | 全程实测：本地启动 agentscope-service，每条命令真实执行验证后才写入文档 |
| 组织方案 | 方案 A：状态文件驱动的增量搭建，`demo/` 顶层目录可扩展 |

**成功标准**：读者按 demo 从零执行，能在本地 `http://localhost:18080` 上跑通完整的多租户平台搭建流程；`run-all.sh` 一键跑通且重复执行幂等；文档中每个命令与示例响应均来自真实运行输出。

## 2. 关键事实（探索结论，设计依据）

### 2.1 真实 API 面（已从 Go 控制面源码与官方 smoke.sh 验证）

控制面 API 主体在 Go 单体 `aistiod`（8081），Gateway（18080）是唯一对外入口。demo 只使用 Gateway 地址。

| 类别 | 真实路径 | 认证 |
| --- | --- | --- |
| 登录 | `POST /api/auth/login` → JWT | 用户名密码 |
| 用户管理 | `GET/POST /api/admin/users`、`PATCH /api/admin/users/{id}/...` | Bearer JWT（admin） |
| 作用域 | `GET /api/v1/me/scope`、`GET /api/v1/me/namespaces` | Bearer JWT |
| Namespace | `POST /api/v1/namespaces`（body: name/displayName/owner/members，需平台 admin）、`GET/PUT /api/v1/namespaces/{name}` | Bearer JWT |
| Environment | `GET/POST /api/environments`、`POST /api/environments/{id}/rotate-key` | Bearer JWT + 作用域头 |
| Agent | `GET/POST /api/agents`、`GET/PUT /api/agents/{id}` | Bearer JWT + 作用域头 |
| Session | `POST /api/sessions`、`GET /api/sessions`、`GET/PATCH /api/sessions/{id}`、`POST .../archive` | Bearer JWT |
| 发消息 | `POST /api/sessions/{id}/events`，body `{"events":[{"type":"user.message","payload":{"text":"..."}}]}` | Bearer JWT |
| 事件流 | `GET /api/sessions/{id}/events/stream`（SSE）、`GET .../events` | Bearer JWT |
| Team | `GET/POST /api/v1/teams`、`GET /api/v1/teams/{id}/overview`、成员管理 | Bearer JWT + 作用域头 |
| Workflow | `POST /api/v1/orchestration-definitions`、`POST .../validate`、`POST .../publish`、`POST .../runs`、`GET /api/v1/orchestration-runs/{id}`(+`/graph`,`/events`)、`POST .../pause|resume|cancel|rerun` | Bearer JWT |
| HITL | `POST/GET /api/v1/approvals`、`POST /api/v1/approvals/{id}/decide`；Agent 侧 `POST /api/v1/agent-tasks/{taskId}/runtime-approvals` → `GET .../decision` → `POST .../ack` | Bearer JWT / 任务令牌 |
| Automation | `POST/GET /api/v1/automations`、`POST .../schedule-preview`、`POST .../trigger`、`GET .../runs|deliveries`；入站 `POST /hooks/v1/automations/{id}/{triggerId}` | Bearer JWT / X-Automation-Secret |
| Endpoint | `GET/POST /api/v1/endpoints`、`POST .../publish|disable`、`GET .../credentials`、`POST .../credentials`（签发） | Bearer JWT |
| 对外调用 | `POST /invoke/v1/endpoints/{slug}/conversations` → `POST /invoke/v1/conversations/{cid}/turns`；作业式 `POST /invoke/v1/endpoints/{slug}/jobs` → `GET /invoke/v1/jobs/{id}` | Endpoint API Key（Bearer） |

多租户作用域三通道（冲突报 400）：查询参数 `?tenant=&namespace=` → 请求头 `X-AgentScope-Tenant` / `X-AgentScope-Namespace` → JSON body 的 `tenant`/`namespace` 字段。demo 统一使用请求头通道。

### 2.2 多租户模型现状（demo 必须如实呈现）

- **tenant 是部署级配置**：`AISTIO_DEFAULT_TENANT`（默认 `default`）在 aistiod 启动时固定；namespace 创建时 Tenant 字段取服务端默认值，运行时 API 不能创建新 tenant。
- **namespace 是运行时的租户单元**：`POST /api/v1/namespaces` 创建共享 namespace（不能以 `personal-` 开头），创建时即可通过 `members`（用户名→角色数组）授权；每个用户另有自动创建的 personal namespace。
- 因此 demo 的"商家入驻"落在 **namespace 级隔离**（namespace + 成员角色 + 资源归属），同时演示 `X-AgentScope-Tenant/Namespace` 请求头契约。demo 文档注明：多 tenant 部署属生产形态（部署配置决定），本地单租户部署用 namespace 表达多租户。

### 2.3 与教程第 31 章的 API 差异（demo 中须注明）

教程第 31 章写的 `POST /api/v1/agent-sessions` + `X-API-Key`（Application 凭据）+ `/turns` 在当前代码中**不存在**；当前真实调用面是 `/api/sessions` + `/api/sessions/{id}/events`（Bearer JWT）与 `/api/v1/endpoints` + `/invoke/v1/**`（Endpoint API Key）。demo 以实测可跑的 API 为准，在各步用教程书风格的 `> **注意**` 框注明差异及版本演进原因。

### 2.4 本地环境

- 启动：`cd agentscope-service && export DASHSCOPE_API_KEY=sk-xxx && scripts/dev-down.sh && BUILDER_REBUILD=1 scripts/dev-up.sh`
- 入口 `http://localhost:18080`；种子账号 `admin/admin`、`alice/alice`、`bob/bob`；日志 `.dev-stack/`
- 栈健康验收：官方 `scripts/smoke.sh`
- Agent 真实执行依赖 DashScope 模型 API（默认 qwen-max）

## 3. 场景设定

「星帆出海」是一家跨境电商 SaaS 服务商，用 AgentScope Service 为入驻商家搭建多租户 Agent 平台。种子账号恰好映射三方角色：

| 现实角色 | 平台概念 | 演示账号 | 演示资源 |
| --- | --- | --- | --- |
| 平台运营方（星帆出海） | 平台 admin，负责入驻与治理 | `admin/admin` | 商家 namespace、成员授权 |
| 商家①「海岸优品」（家居出海） | namespace `seashore-main` | `alice/alice` | 选品专员 + 客服专员 Agent、客服 Team、选品 Workflow、对外客服 Endpoint |
| 商家②「极光数码」（3C 配件出海） | namespace `aurora-main` | `bob/bob` | 自己的客服 Agent（同能力不同配置）、隔离验证对象 |

设计原则：两家商家配置**同名能力、不同租户配置**的 Agent（如客服 Agent 的 system prompt、语气、工具集不同），体现"同一平台、按租户定制"。

## 4. 教学阶梯（01–13 连续编号，共 13 步）

每步 = 一篇 `.md` + 一个 `.sh`。`.md` 含：frontmatter（step/title）、导读、mermaid 图（导览或时序）、可复制 curl 正文（含真实响应示例）、小结、验收清单。步骤间依赖单向向下，依赖图在 demo README 中给出。

### 主线

| # | 文件名 | 主题 | API 面 | 情节与验收要点 |
| --- | --- | --- | --- | --- |
| 01 | `step-01-platform-init` | 平台初始化与身份体系 | `GET /healthz`、`/api/v1/version`、`POST /api/auth/login`、`GET /api/auth/me`、`GET /api/v1/me/scope`、`GET /api/v1/me/namespaces`、`GET/POST /api/admin/users` | 验证栈健康；admin 登录拿 JWT；理解作用域解析三通道与 personal namespace；验证/创建 alice、bob 账号。验收：三个账号均可登录 |
| 02 | `step-02-tenant-onboarding` | 商家入驻：namespace 即租户单元 | `POST /api/v1/namespaces`（members 授权）、`GET /api/v1/namespaces/{name}`、`GET /api/v1/me/namespaces`（以 alice/bob 身份） | admin 创建 `seashore-main`（owner alice）与 `aurora-main`（owner bob）；两家登录后只能看到自己的 namespace。验收：alice 的 namespace 列表不含 aurora |
| 03 | `step-03-agent-matrix` | 商家 Agent 矩阵 | `POST /api/environments`、`POST /api/agents`（definition：system/model/tools 等）、`GET /api/agents` | 以 alice 身份 + seashore 作用域头创建 Environment、选品专员 `xbd-seashore-product-scout`、客服专员 `xbd-seashore-cs-agent`；bob 创建 `xbd-aurora-cs-agent`（不同 system/model）。验收：四类资源归属正确 namespace |
| 04 | `step-04-session-api` | Session 调用面 | `POST /api/sessions`、`POST /api/sessions/{id}/events`（user.message）、`GET .../events/stream`（SSE）、`GET .../events`、`GET /api/sessions/{id}` | alice 的客服 Agent 接待客户咨询「订单 OD-2049 为什么还没到」；观察 SSE 事件流与最终回复。验收：拿到 Agent 真实回复，事件流可回放 |
| 05 | `step-05-isolation-check` | 多租户隔离验证（负向测试） | 复用前几步资源做越权访问 | alice 带 seashore 作用域头访问 aurora 的 Agent → 403/404；不带作用域头 → 回落 personal namespace 看不到商家资源。验收：断言脚本全绿，隔离行为实测记录 |
| 06 | `step-06-team-orchestration` | Team 编排：协作团队 | `POST /api/v1/teams`（leaderAgentId/members/policy）、`GET .../overview`、team session | 海岸优品建客服 Team（客服 lead + 物流专员 member），处理升级售后工单。验收：Team session 跑通，成员协作事件可查 |
| 07 | `step-07-workflow-pipeline` | Workflow 编排：选品上架流水线 | `POST /api/v1/orchestration-definitions`、`/validate`、`/publish`、`/runs`、`GET /api/v1/orchestration-runs/{id}(/graph|/events)` | 「市场调研 → 条件判断 → 人工审批 → 上架建议」流程发布并运行一次。验收：Run 图可见节点轨迹，产物可回溯 |
| 08 | `step-08-endpoint-publish` | Endpoint 发布与对外调用 | `POST /api/v1/endpoints`、`.../publish`、`.../credentials`；`POST /invoke/v1/endpoints/{slug}/conversations`、`POST /invoke/v1/conversations/{cid}/turns` | 把海岸优品客服 Agent 发布为受治理的对外 API；用签发的 API Key 以"商家外部系统"身份调用。验收：外部调用拿到真实回复，与 Step 04 形成调用面对比 |

### 09–13：审批、自动化与基础设施

| # | 文件名 | 主题 | API 面 | 情节 |
| --- | --- | --- | --- | --- |
| 09 | `step-09-hitl-approval` | HITL 工具审批 | `POST /api/v1/approvals`、`POST /api/v1/approvals/{id}/decide`、runtime-approvals 三段（request→decision→ack） | 客服 Agent 执行"退款"敏感工具前挂起，admin 人工批准后继续 |
| 10 | `step-10-automation` | Automation 定时任务 | `POST /api/v1/automations`（cron trigger + runbook）、`/schedule-preview`、`/trigger?test=true`、`GET .../runs|deliveries` | 每日 9 点竞品价格监控；演示手动 trigger 与运行记录查询 |

| 11 | `step-11-workspace` | Workspace | 文件、发布与 Agent 绑定 | 配置验收；模型读取另验 |
| 12 | `step-12-sandbox` | 沙箱 | Environment 与 E2B | 登记、绑定与隔离验收方法 |
| 13 | `step-13-model-channel` | 自有模型通道 | Dataplane 扩展与网关探针 | 适配、注册与分层验收 |

## 5. 目录结构

```
demo/cross-border-commerce/
├── README.md              # 总览：故事线、mermaid 架构图、前置条件、步骤依赖图、快速开始、FAQ
├── run-all.sh             # 一键编排：--from N / --only N / --list / --dry-run
├── teardown.sh            # 逆序清理 demo 资源（archive 优先，尽力清理）
├── .env.example           # BASE_URL / 三账号 / DASHSCOPE_API_KEY 说明（真实值不入库）
├── lib/
│   └── common.sh          # 公共函数库（见 §6）
├── steps/
│   ├── step-01-platform-init.md / .sh
│   ├── step-02-tenant-onboarding.md / .sh
│   ├── step-03-agent-matrix.md / .sh
│   ├── step-04-session-api.md / .sh
│   ├── step-05-isolation-check.md / .sh
│   ├── step-06-team-orchestration.md / .sh
│   ├── step-07-workflow-pipeline.md / .sh
│   ├── step-08-endpoint-publish.md / .sh
│   ├── step-09-hitl-approval.md / .sh
│   ├── step-10-automation.md / .sh
│   ├── step-11-workspace.md / .sh
│   ├── step-12-sandbox.md / .sh
│   └── step-13-model-channel.md / .sh
└── .state.env             # 运行时生成，加入 .gitignore
```

## 6. 脚本架构

### 6.1 lib/common.sh 提供的原语

| 函数 | 职责 |
| --- | --- |
| `require_env` | 检查 BASE_URL 可达（`/healthz`）、jq 存在、state 文件可写 |
| `api METHOD PATH [BODY] [TOKEN_VAR]` | curl 封装：BASE_URL + `Authorization: Bearer` + JSON 头 + `--fail-with-body`；失败打印状态码与响应体后退出 |
| `as_user NAME` | 以指定账号登录（密码同用户名约定可覆盖），JWT 缓存进 state，避免重复登录 |
| `scope_hdrs TENANT NS` | 输出 `-H "X-AgentScope-Tenant: …" -H "X-AgentScope-Namespace: …"` |
| `state_get KEY` / `state_set KEY VAL` | `.state.env` 读写（`source` 加载、`grep` 更新） |
| `ensure STATE_KEY LIST_CMD MATCH_JQ CREATE_CMD` | **先查后建**：执行 LIST_CMD，用 MATCH_JQ 按约定名匹配；命中则 `state_set` 复用，未命中执行 CREATE_CMD |
| `assert_eq / assert_contains / assert_status` | 断言原语；`assert_status 403` 用于负向测试（`--fail` 需绕过以捕获状态码） |
| `idem_key STEP PURPOSE` | 幂等键生成：`xbd-{step}-{purpose}-001`（固定后缀，重试同键） |

### 6.2 每步脚本统一骨架

```bash
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
source lib/common.sh
require_env
# 1. 加载 state；2. as_user 登录；3. ensure 先查后建；4. 断言产出
# 5. state_set 关键 ID；6. 打印本步产出与验收要点
```

### 6.3 run-all.sh

- 默认顺序执行 01→13；`--only N` 单步执行，`--from N` 从指定步骤续跑
- `--from N` 断点续跑、`--only N` 单步、`--list` 列步骤、`--dry-run` 只打印将执行的动作
- 前置检查失败（栈不可达/缺 jq）立即报错退出并给出修复提示
- 每步失败即停：打印失败步骤、state 现状，提示修复后 `--from N` 续跑
- 全部完成后打印平台总览：商家 namespace、Agent、Team、Workflow、Endpoint 清单及 ID

### 6.4 幂等与清理

- 资源命名约定：`xbd-` 前缀 + 商家域 + 用途（如 `xbd-seashore-product-scout`、`xbd-seashore-cs-team`）
- 所有创建走 `ensure` 先查后建；幂等键固定 `xbd-{step}-{purpose}-001`，重试沿用同键（呼应教程第 34 章"三条贯穿约束"）
- **重复执行 run-all.sh = 幂等复用**，不产生重复资源；实测阶段连跑两遍验证
- `teardown.sh`：按 state 中记录逆序 archive（Session/Team/Workflow 定义/Endpoint/Agent/Environment），namespace 保留（含成员授权，删除影响账号）并在输出中说明手动清理路径

## 7. 实测验证流程（全程实测）

1. **环境启动**：确认 Docker 运行、`DASHSCOPE_API_KEY` 可用（实施时向用户确认）→ `BUILDER_REBUILD=1 scripts/dev-up.sh` → 官方 `scripts/smoke.sh` 通过确认栈健康
2. **逐步实测**：每完成一步脚本立即真实执行至绿；**文档中的请求与示例响应全部回填真实输出**（仅截断超长 ID、脱敏 token）
3. **全量回归**：`teardown.sh` → `run-all.sh` 连跑两遍（第二遍验证幂等复用）
4. **负向验证**：step-05 的越权断言必须真实跑出 403/404
5. **差异处理**：实测行为与源码/本设计预期不符时，以实测为准修订文档与脚本，并在该步 `.md` 用 `> **注意**` 记录差异

已知风险：首次 dev 栈构建耗时较长（Maven + Go + 前端）；Team/Workflow/Endpoint 的 Agent 真实执行依赖模型 API 稳定性；SSE 在脚本中以限时读取（`timeout` + `curl -N`）收流。若某能力（如 Team 自动协作的深度依赖 Issue 流程）实测复杂度显著超预期，允许将该步降级为"演示核心路径 + 文档说明完整路径"，但须保持脚本可跑通。

## 8. 与教程仓库的挂接

- 根 `README.md` 在目录表之后新增「配套动手 Demo」小节：一句话定位 + 链接 `demo/cross-border-commerce/README.md`，标注"与第五篇（第 29-34 章）配套"
- **不改动 chapters/ 下 44 章正文**（控制范围；章内引用留待后续单独任务）
- demo 文档风格对齐全书：frontmatter、导读、mermaid 图、`> **注意**` 框、小结、验收清单、代码示例大写环境变量约定
- demo README 开头注明版本基线：demo 基于本地源码构建的 agentscope-service 实测，教程正文基于 2.1.0-BETA1 文档，两者 API 差异以 demo 实测为准并逐处标注

## 9. 范围外（明确不做）

- 不做 Console/前端自动化测试（demo 只走 REST API）
- 不改 chapters/ 正文与 build/ PDF 管线
- 不实现多 tenant 部署（`AISTIO_DEFAULT_TENANT` 改造）——文档说明即可
- 不做 Python/Java SDK 版脚本（保持零依赖 bash + curl + jq）
- 不做 Windows 兼容（bash + jq + Docker 环境假设）

## 10. 开放问题（实施中决定，不阻塞设计）

- Session 生命周期 API 的 202/终态语义细节以实测为准（产品层 `/api/sessions` 与教程 v1 契约的语义差异）
- Team 协作是否必须经 Issue 流程（教程第 32 章提及 Issue comments 路由）——实测后确定 step-06 的最简可跑路径
- Endpoint 发布的前置条件（readiness 检查项）以实测为准
