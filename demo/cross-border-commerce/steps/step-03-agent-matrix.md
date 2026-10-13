---
step: "03"
title: 商家 Agent 矩阵：同能力不同租户配置
---

# Step 03 · 商家 Agent 矩阵：同能力不同租户配置

> **本步导读**：两家商家入驻后，各自开始配置自己的 Agent 矩阵。本步让你看到多租户平台的核心卖点——**同一平台、同名能力、按租户定制**：海岸优品配齐选品/客服/物流三个 Agent，极光数码只配一个客服 Agent，但同样是"客服"，两家的人设（system prompt）、语气、职责完全不同。每个 Agent 的工具执行环境（Environment）由平台按 namespace 自动开通。

```mermaid
flowchart LR
    subgraph S["seashore-main（海岸优品）"]
        E1["default-local 环境<br/>env_5c1ee6f847b3"]
        A1["xbd-seashore-product-scout<br/>选品专员"]
        A2["xbd-seashore-cs-agent<br/>客服专员"]
        A3["xbd-seashore-logistics-agent<br/>物流专员"]
        E1 --- A1 & A2 & A3
    end
    subgraph AU["aurora-main（极光数码）"]
        E2["default-local 环境<br/>env_2f629473ada5"]
        A4["xbd-aurora-cs-agent<br/>客服专员（活泼风）"]
        E2 --- A4
    end
```

*图 3-1：两家商家的 Agent 矩阵与环境归属*

## 创建租户 Agent：v5 Agent Catalog

Agent 管理走 **v5 Agent Catalog API**（`/api/v1/agents`）。一个 Managed Agent 由三部分组成：`agent`（稳定身份）、`binding`（运行绑定，`kind:"managed"` 表示全托管）、`definition`（可移植定义：人设、模型、工具）。创建请求：

```bash
curl -sS -X POST "$BASE_URL/api/v1/agents" \
  -H "Authorization: Bearer $ALICE_TOKEN" -H 'Content-Type: application/json' \
  -H "X-AgentScope-Tenant: default" -H "X-AgentScope-Namespace: seashore-main" \
  -d '{
    "agentKey": "xbd-seashore-cs-agent",
    "displayName": "海岸优品·客服专员",
    "binding": { "kind": "managed" },
    "definition": {
      "name": "xbd-seashore-cs-agent",
      "system": "你是海岸优品店铺客服，语气亲切专业，只回答与订单、物流、售后相关的问题。",
      "model": "qwen-plus"
    }
  }' | jq '{id:.agent.id, key:.agent.agentKey, ns:.agent.namespace, env:.definition.defaultEnvironmentId}'
```

真实响应：

```json
{
  "id": "c5c56dc3-8edf-41dc-92f6-aff8f5394756",
  "key": "xbd-seashore-cs-agent",
  "ns": "seashore-main",
  "env": "env_5c1ee6f847b3"
}
```

三个要点：

1. **`agentKey` 是稳定业务键**（demo 用 `xbd-` 前缀 + 商家域 + 用途），`agent.id` 是平台 UUID。后续步骤用 id 引用，脚本用 agentKey 先查后建保证幂等。
2. **请求作用域用请求头通道**——Agent 落到哪个 namespace 由 `X-AgentScope-Namespace` 决定。
3. **Environment 无需手动创建**：managed 绑定的工作流会按 namespace 自动开通 `default-local` 环境（type: local，即数据面容器内执行）。同一商家的多个 Agent 共享该环境，不同商家的环境相互独立（见上图两个 env id）。

demo 脚本依次创建四个 Agent，真实输出：

```
  + 创建 xbd-seashore-product-scout (77bd3fc7-…)  环境: env_5c1ee6f847b3
  + 创建 xbd-seashore-cs-agent (c5c56dc3-…)  环境: env_5c1ee6f847b3
  + 创建 xbd-seashore-logistics-agent (6994d2be-…)  环境: env_5c1ee6f847b3
  + 创建 xbd-aurora-cs-agent (6560111d-…)  环境: env_2f629473ada5
```

对比两家客服的 `definition.system`：同一个"客服"能力，海岸优品要求"亲切专业、只答订单物流售后"，极光数码要求"活泼年轻化、专注 3C 配件"——**这就是租户级配置**。

## 列表与读取：通道不对称（实测）

一个容易踩的坑：**这个 API 家族的读写作用域通道不对称**。

```bash
# 列表：按查询参数过滤（请求头不影响列表结果）
curl -sS "$BASE_URL/api/v1/agents?tenant=default&namespace=seashore-main" \
  -H "Authorization: Bearer $ALICE_TOKEN" | jq '[.items[] | .agentKey]'
```

真实输出：

```json
[
  "xbd-seashore-product-scout",
  "xbd-seashore-cs-agent",
  "xbd-seashore-logistics-agent"
]
```

单资源读取则按作用域头严格隔离——alice 带 seashore 作用域读取极光的 Agent：

```bash
curl -sS "$BASE_URL/api/v1/agents/$AURORA_CS_ID" \
  -H "Authorization: Bearer $ALICE_TOKEN" \
  -H "X-AgentScope-Tenant: default" -H "X-AgentScope-Namespace: seashore-main"
```

真实响应（HTTP 404）：

```json
{"error":"resource not found in authorized scope"}
```

列表是"目录"（可发现），单资源是"边界"（可操作）——Step 05 将把这套隔离语义做成完整的负向测试。

## 归属验证

demo 脚本最后由两家商家各自在**自家作用域**读取自家客服 Agent 并断言归属：

```
  ✓ 海岸客服 Agent 归属 seashore-main
  ✓ 极光客服 Agent 归属 aurora-main
```

## 脚本执行

```bash
bash steps/step-03-agent-matrix.sh
```

> **注意**：本步的 `/api/v1/agents`（Agent Catalog）与教程第 30 章写作时点的 `/api/agents` 产品层接口是不同版本形态（后者已从当前源码移除）；`definition` 的字段（system/model/maxIters/tools/workspaceId 等）以本 demo 实测与源码为准。`agentKey` 在创建后不可变，是跨版本稳定的引用键。

## 本步小结

1. Managed Agent = 身份（agentKey）+ 绑定（binding.kind=managed）+ 定义（definition：人设/模型/工具）。
2. Environment 按 namespace 自动开通（`default-local`），同商家共享、跨商家隔离。
3. 通道不对称实测：POST 创建看请求头、GET 列表看查询参数、GET 单资源按作用域硬隔离（404）。
4. `agentKey` 是幂等先查后建的匹配键，`agent.id` 是运行时引用键。

**验收清单**

- ☐ 四个 Agent 创建成功且归属正确（3 个 seashore / 1 个 aurora）
- ☐ 同能力不同配置：两家客服 `definition.system` 不同
- ☐ 跨租户单资源读取返回 404（预告 Step 05）
- ☐ 脚本连跑两遍第二遍全部 `↺ 复用`（幂等）

> **延伸阅读**：Agent 定义全字段与 Workspace/技能/子 Agent 体系见教程第 30 章。下一步 → [Step 04 Session 调用面](step-04-session-api.md)。
