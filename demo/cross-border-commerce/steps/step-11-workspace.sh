#!/usr/bin/env bash
# Step 11：创建独立实验 Workspace，发布、固定版本、回读。不会调用模型。
set -euo pipefail
cd "$(dirname "$0")/.."
source lib/common.sh
require_env
step_header 'Step 11 Workspace 文件与版本'
login_as alice alice XBD_TOKEN_ALICE
scope_as "$XBD_TENANT" seashore-main
LIST=$(api GET /api/workspaces '' XBD_TOKEN_ALICE)
WS_ID=$(jq -r '[.[] | select(.name=="xbd-seashore-workspace-lab")][0].id // empty' <<<"$LIST")
if [[ -z "$WS_ID" ]]; then
  WS=$(api POST /api/workspaces '{"name":"xbd-seashore-workspace-lab","description":"独立 Workspace 教学实验","tools":[{"type":"agent_toolset","defaultConfig":{"enabled":false},"configs":[{"name":"read","enabled":true,"permissionPolicy":{"type":"always_allow"}}]}]}' XBD_TOKEN_ALICE)
  WS_ID=$(jq -er '.id' <<<"$WS")
  echo "  + Workspace=$WS_ID"
else echo "  ↺ 复用 Workspace=$WS_ID"; fi
state_set XBD_WORKSPACE_LAB "$WS_ID"
# 同内容不重写草稿；本实验专用资源，不修改主线客服 Agent。
for path in AGENTS.md knowledge/refund-policy.md; do
  CONTENT=$(cat "examples/workspace/$path")
  RAW=$(api_raw GET "/api/workspaces/$WS_ID/file?path=$path" '' XBD_TOKEN_ALICE)
  STATUS=$(head -1 <<<"$RAW")
  if [[ "$STATUS" == 200 ]]; then
    SAVED=$(sed '1d' <<<"$RAW" | jq -r '.content')
    if [[ "$SAVED" == "$CONTENT" ]]; then echo "  ↺ 文件内容一致: $path"; continue; fi
  elif [[ "$STATUS" != 404 ]]; then
    echo "✗ 读取文件失败: HTTP $STATUS" >&2; exit 1
  fi
  api PUT "/api/workspaces/$WS_ID/file" "$(jq -n --arg p "$path" --arg c "$CONTENT" '{path:$p,content:$c}')" XBD_TOKEN_ALICE >/dev/null
  echo "  + 已写入 $path"
done
REV=$(api POST "/api/workspaces/$WS_ID/publish" '{}' XBD_TOKEN_ALICE)
VER=$(jq -er '.version' <<<"$REV"); DIGEST=$(jq -er '.digest' <<<"$REV")
AGAIN=$(api POST "/api/workspaces/$WS_ID/publish" '{}' XBD_TOKEN_ALICE)
assert_eq "$(jq -r '.version' <<<"$AGAIN")" "$VER" '相同内容重复发布复用版本'
assert_eq "$(jq -r '.digest' <<<"$AGAIN")" "$DIGEST" '发布摘要一致'
jq -e '.files["knowledge/refund-policy.md"] | contains("XBD-POLICY-V1")' <<<"$REV" >/dev/null
state_set XBD_WORKSPACE_REV "$VER"
AGENTS=$(api GET "/api/v1/agents$(scope_q "$XBD_TENANT" seashore-main)" '' XBD_TOKEN_ALICE)
ID=$(jq -r '[.items[]? | select(.agentKey=="xbd-workspace-lab")][0].id // empty' <<<"$AGENTS")
if [[ -z "$ID" ]]; then
  MODEL="${XBD_MODEL:-dashscope:deepseek-v4-flash-0731}"
  RES=$(api POST /api/v1/agents "$(jq -n --arg ws "$WS_ID" --argjson v "$VER" --arg m "$MODEL" \
    '{agentKey:"xbd-workspace-lab",displayName:"工作区实验 Agent",binding:{kind:"managed"},definition:{name:"工作区实验 Agent",model:$m,workspaceId:$ws,workspaceBinding:{version:$v,overrides:[],instructions:"仅用于工作区配置实验。"}}}')" XBD_TOKEN_ALICE)
  ID=$(jq -er '.agent.id' <<<"$RES")
else echo "  ↺ 复用实验 Agent=$ID"; fi
state_set XBD_AGENT_WORKSPACE_LAB "$ID"
DEF=$(api GET "/api/v1/agents/$ID/definition" '' XBD_TOKEN_ALICE)
assert_eq "$(jq -r '.definition.workspaceId' <<<"$DEF")" "$WS_ID" 'Agent 绑定正确 Workspace'
# 不自动采纳修改后的新版本；要求读者显式执行文档中的绑定更新。
assert_eq "$(jq -r '.definition.workspaceBinding.version' <<<"$DEF")" "$VER" 'Agent 固定到发布版本（若你修改了样例，按教程显式升级绑定）'
assert_eq "$(jq -r '.definition.workspaceBinding.digest' <<<"$DEF")" "$DIGEST" 'Agent 的绑定摘要与发布内容一致'
echo "$DEF" | jq '.definition | {version,workspaceId,workspaceVersion,workspaceBinding,defaultEnvironmentId}'
echo '配置验收完成；未提交 Turn，不代表运行时已读到资料。运行验收见配套教程。'
