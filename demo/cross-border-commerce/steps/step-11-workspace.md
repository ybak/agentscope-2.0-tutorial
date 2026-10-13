---
step: "11"
title: Workspace 文件、发布与版本绑定
---

# Step 11 · 给客服准备一份可版本化的工作区

> 本步导读：商家的售后政策、操作规范和技能不能只存在于一次聊天中。本节为海岸优品建立独立 Workspace，把资料写成文件，发布为不可变版本，再绑定到实验 Agent。前置：完成 01–03；本节配置实验不调用模型，模型额度耗尽时也可做。

## 先分清：namespace、Workspace、Environment 管什么？

| 概念 | 回答的问题 | 本例 |
| --- | --- | --- |
| namespace | 谁能访问哪些资源？ | `seashore-main` 的资源与另一商家隔离 |
| Workspace | Agent 使用哪些指令、资料、Skills、工具定义？ | 售后政策、`AGENTS.md`、只读工具 |
| Environment | 文件和命令实际在哪里执行？ | Dataplane 本地、E2B 或自托管 Worker |
| Session / Chat | 本次对话与执行如何记录？ | 新 Chat 选择当前 Agent 定义，执行事件属于其 Session |

Workspace 不是另一种商家账号，也不等于 Docker 容器。即便两个 Agent 使用同一份工作区模板，运行数据的隔离仍需要检查身份与文件系统的 IsolationScope。

SDK 第 12 章里的 `.workspace(Path)` 描述 Harness 工作区；Service 则提供可管理、可发布的 Workspace 资源。不要把客户端 Mac 上的目录直接当作 Dataplane 可访问的路径。

```mermaid
flowchart LR
    F[AGENTS.md 与售后资料] --> D[Workspace 草稿]
    D --> P[发布 revision 与 digest]
    P --> B[Agent 固定 workspaceBinding.version]
    B --> C[创建新 Chat]
    C --> R[在选定 Environment 中执行]
    R --> V[核对工具读取记录与输出]
```

*图 11-1：配置发布与运行验收是两个阶段。*

## 第一步：把业务规范写成文件

样例已提供在 [examples/workspace](../examples/workspace/AGENTS.md)：

```text
workspace/
├── AGENTS.md                   # 角色职责、约束与资料读取约定
└── knowledge/
    └── refund-policy.md        # 售后政策，标记 XBD-POLICY-V1
```

`AGENTS.md` 中明确要求“回答退款规则前读取资料”“不编造订单与物流”“退款建议交人工复核”。政策文件提供 `XBD-POLICY-V1` 作为验收标记，而不是只问模型“你读过文件了吗”。

后续可通过 Workspace 的 Skills 和 subagents API 加入 `skills/<name>/SKILL.md` 与子 Agent 声明。资料放进工作区不等于所有文件全文进入上下文；应通过指令引导读取，并查看实际工具记录。

## 第二步：创建、写文件并发布

直接运行完整实验：

```bash
cd demo/cross-border-commerce
bash steps/step-11-workspace.sh
```

它创建 `xbd-seashore-workspace-lab` 和独立的 `xbd-workspace-lab` Agent，不修改主线客服、选品、物流 Agent。已存在同名资源则复用，同内容文件不重写。

要逐条理解请求，在同一个 Bash 终端加载公共封装：

```bash
source lib/common.sh
require_env
login_as alice alice XBD_TOKEN_ALICE
scope_as "$XBD_TENANT" seashore-main
WS_ID=$(state_get XBD_WORKSPACE_LAB)
api GET "/api/workspaces/$WS_ID/files" '' XBD_TOKEN_ALICE
api GET "/api/workspaces/$WS_ID/file?path=knowledge/refund-policy.md" '' XBD_TOKEN_ALICE
```

`api` 的参数顺序是 METHOD、PATH、BODY、TOKEN_KEY，GET 的第三个参数仍需保留空字符串。文件写入对应 `PUT /api/workspaces/{id}/file`：

```bash
CONTENT=$(cat examples/workspace/knowledge/refund-policy.md)
BODY=$(jq -n --arg c "$CONTENT" '{path:"knowledge/refund-policy.md",content:$c}')
api PUT "/api/workspaces/$WS_ID/file" "$BODY" XBD_TOKEN_ALICE
REV=$(api POST "/api/workspaces/$WS_ID/publish" '{}' XBD_TOKEN_ALICE)
jq '{version,draftVersion,digest,files:(.files|keys)}' <<<"$REV"
```

**草稿 version 与发布 version 不是同一个计数器。** 写文件增加草稿版本；publish 根据内容摘要判断是否需要新增 revision。相同内容重复发布会返回同一已发布版本。以发布响应的 `.version` 绑定 Agent，不要拿 Workspace 草稿 `.version` 代替。

发布快照包含定义文件，源码会排除 `memory/`、`sessions/`、`artifacts/` 等运行目录；发布 Workspace 不等于备份所有执行数据。

## 第三步：固定版本，避免草稿变更悄悄影响 Agent

实验 Agent 的定义使用：

```json
{
  "workspaceId": "填入实际 Workspace ID",
  "workspaceBinding": {
    "version": 1,
    "overrides": [],
    "instructions": "仅用于工作区配置实验。"
  }
}
```

其中 `1` 仅示意，要使用实际发布版本。`overrides: []` 表示继承 Workspace 的 tools、mcpServers、skills；额外职责放在 `workspaceBinding.instructions`。不能把字段名随意放入 overrides，当前支持的项是 `tools`、`mcpServers`、`skills`。

实验会回读 definition，比较 workspaceId、绑定版本与 digest。2026-10-13 实测摘要：

```json
{
  "workspaceId": "ws_1f00115de267",
  "workspaceVersion": 1,
  "workspaceBinding": {"version": 1,"overrides": []},
  "defaultEnvironmentId": "env_5c1ee6f847b3"
}
```

这是响应的选取字段，完整绑定还包含摘要和附加指令。脚本连续两遍运行都复用了 Workspace、发布版本与实验 Agent。

## 第四步：政策更新时，如何显式升级与回滚？

先修改实验资料并发布，再读取 Agent 当前完整 definition，保留模型、工具、环境和其他绑定，仅更新 Workspace 版本：

```bash
ID=$(state_get XBD_AGENT_WORKSPACE_LAB)
REV=$(api POST "/api/workspaces/$WS_ID/publish" '{}' XBD_TOKEN_ALICE)
NEW_VERSION=$(jq -er '.version' <<<"$REV")
CURRENT=$(api GET "/api/v1/agents/$ID/definition" '' XBD_TOKEN_ALICE)
PATCH=$(jq -c --argjson v "$NEW_VERSION" \
  '.definition | .workspaceBinding.version=$v | del(.workspaceBinding.digest)' <<<"$CURRENT")
api PATCH "/api/v1/agents/$ID/definition" "$PATCH" XBD_TOKEN_ALICE
```

PATCH 必须带当前 Agent definition 的 `name` 和 `version`；脚本中的 GET → 合并 → PATCH 保留它们。不要只发送 `workspaceId` 或只改一个字段，否则可能清空其他定义配置。409 时重新读取并评估变更，不能删除 version 强行覆盖。

回滚采用相同步骤，把绑定版本设为 `GET /api/workspaces/{id}/revisions` 中的旧发布版本。回滚配置后用新 Chat 验证；不要假设历史会话会自动换版本。重复运行本实验会恢复样例文件内容，因此练习自己的政策时建议复制成另一份 Workspace。

## 第五步：怎样证明模型真的用了这份资料？

模型可用后，使用实验 Agent 创建新的 Chat，并发送任务：

```bash
CHAT=$(api POST "/api/v1/chats$(scope_q "$XBD_TENANT" seashore-main)" \
  "$(jq -n --arg a "$ID" '{agentId:$a,title:"xbd-workspace-policy-check"}')" XBD_TOKEN_ALICE)
CHAT_ID=$(jq -er '.chat.id' <<<"$CHAT")
SESSION_ID=$(jq -er '.chat.sessionId' <<<"$CHAT")
api POST "/api/v1/chats/$CHAT_ID/turns$(scope_q "$XBD_TENANT" seashore-main)" \
  '{"message":"读取 knowledge/refund-policy.md，给出文件中的演示标记和退款建议流程。没有读取成功请明确说明。"}' XBD_TOKEN_ALICE
api GET "/api/v1/sessions/$SESSION_ID/events?chatId=$CHAT_ID" '' XBD_TOKEN_ALICE
```

最后一条要按 Step 04 的方式轮询，不能把首次快照当作终态。验收需要同时看到文件读取工具结果、正确标记、最终回复与本轮结束事件。若把标记直接写进问题里，就无法证明模型读了文件。

本轮没有执行这一模型步骤：延续之前保留的额度阻塞。当前只证明工作区文件、发布及绑定配置正确，未证明运行期文件投影和工具读取完成。

## 本步小结

1. namespace 管授权，Workspace 管定义材料，Environment 管执行位置。
2. 草稿变更、发布 revision、Agent 采纳版本是三个不同动作。
3. 配置回读与工具执行证据应分别验收。

**验收清单**

- ☑ 文件写入与回读、重复发布复用、Agent 版本和摘要绑定。
- ☐ 政策 V2 升级与旧版本回滚练习。
- ☐ 模型工具真实读取与新 Chat 运行验收（需可用模型）。

**继续阅读**：[第 12 章](../../../chapters/12-workspace.md)、[第 30 章](../../../chapters/30-managed-agents.md)、[Step 12](step-12-sandbox.md)。

源码核对：`aistio/internal/product/handlers_workspaces.go`、`workspace_publication.go`、`managed_definition.go`，均位于相邻 agentscope-service 源码中。
