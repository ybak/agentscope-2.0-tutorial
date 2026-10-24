#!/usr/bin/env bash
# Step 13：默认只读；--set-model 仅改独立实验 Agent；--probe-* 才请求用户配置的模型网关；
# --session-model 走本机 dev 栈 internal 通道做会话级模型切换（下一 Turn 即生效）。
set -euo pipefail
cd "$(dirname "$0")/.."
source lib/common.sh
MODE="${1:---inspect}"
case "$MODE" in
  --inspect|--probe-text|--probe-tools) [[ $# -le 1 ]] || exit 2;;
  --set-model) [[ $# == 2 && -n "$2" ]] || { echo '用法: step-13-model-channel.sh --set-model merchant-gateway'; exit 2; };;
  --session-model) [[ $# == 2 && -n "$2" ]] || { echo '用法: step-13-model-channel.sh --session-model MODEL_ID|-（- 表示清除覆盖回到 definition.model）'; exit 2; };;
  *) echo '用法: step-13-model-channel.sh [--inspect|--set-model MODEL_ID|--session-model MODEL_ID|-|--probe-text|--probe-tools]'; exit 2;;
esac
if [[ "$MODE" == --probe-* ]]; then
  command -v curl >/dev/null; command -v jq >/dev/null
  load_env
  : "${XBD_MODEL_BASE_URL:?缺少模型网关根地址 XBD_MODEL_BASE_URL}"
  : "${XBD_MODEL_API_KEY:?缺少本地配置 XBD_MODEL_API_KEY}"
  : "${XBD_MODEL_NAME:?缺少上游模型名 XBD_MODEL_NAME}"
  ROOT="${XBD_MODEL_BASE_URL%/}"
  PATH_PART="${XBD_MODEL_ENDPOINT_PATH:-/v1/chat/completions}"
  [[ "$ROOT" =~ ^https?://[^/?#[:space:]]+$ && "$PATH_PART" == /* ]] || { echo '✗ 请使用 http(s) 根地址及以 / 开头的完整接口路径'; exit 2; }
  BODY=$(jq -n --arg m "$XBD_MODEL_NAME" '{model:$m,stream:false,messages:[{role:"user",content:"只回复 XBD_MODEL_OK"}]}')
  if [[ "$MODE" == --probe-tools ]]; then
    BODY=$(jq '.messages=[{role:"user",content:"调用 demo_echo，参数 text 为 XBD_TOOL_OK"}] | .tools=[{type:"function",function:{name:"demo_echo",description:"回显测试，不执行外部操作",parameters:{type:"object",properties:{text:{type:"string"}},required:["text"]}}}] | .tool_choice={type:"function",function:{name:"demo_echo"}}' <<<"$BODY")
  fi
  OUT=$(curl -sS --connect-timeout 10 --max-time 90 -X POST "$ROOT$PATH_PART" \
    -H "Authorization: Bearer $XBD_MODEL_API_KEY" -H 'Content-Type: application/json' \
    -d "$BODY" -w '\n%{http_code}')
  STATUS="${OUT##*$'\n'}"; RESPONSE="${OUT%$'\n'*}"
  [[ "$STATUS" == 200 ]] || { echo "✗ 模型 HTTP ${STATUS}（检查鉴权、模型名、路径、额度）"; exit 1; }
  if [[ "$MODE" == --probe-tools ]]; then
    jq -e '[.choices[0].message.tool_calls[]? | select(.function.name=="demo_echo") | .function.arguments | fromjson | select(.text=="XBD_TOOL_OK")] | length>0' <<<"$RESPONSE" >/dev/null 2>&1 || { echo "✗ 上游未返回符合约定的 demo_echo 工具调用"; exit 1; }
    echo '✓ 上游返回可解析的 tool call；尚未验证 Service 工具执行和流式响应'
  else
    jq -e '.choices[0].message.content | strings | contains("XBD_MODEL_OK")' <<<"$RESPONSE" >/dev/null 2>&1 || { echo "✗ 上游文本响应不符合探针约定"; exit 1; }
    echo '✓ 上游文本请求通过；尚未验证 Service 接入、工具调用和流式响应'
  fi
  exit 0
fi
require_env
step_header 'Step 13 自有模型通道'
login_as alice alice XBD_TOKEN_ALICE
scope_as "$XBD_TENANT" seashore-main
ID=$(state_get XBD_AGENT_WORKSPACE_LAB)
[[ -n "$ID" ]] || { echo '✗ 先运行Step 11'; exit 1; }
DEF=$(api GET "/api/v1/agents/$ID/definition" '' XBD_TOKEN_ALICE)

internal_api() { # METHOD PATH [BODY] —— 本机 dev 栈控制面 internal 通道（绕过会话 owner 校验）
  local method="$1" path="$2" body="${3:-}" out status
  local token="${XBD_INTERNAL_TOKEN:-local-dev-internal-token-at-least-32chars}"
  local owner="${XBD_SESSION_OWNER:-namespace:${XBD_TENANT}:seashore-main}"
  local args=(-sS --connect-timeout 5 --max-time 30 -X "$method" "${XBD_CONTROL_BASE_URL%/}$path"
    -H "X-Builder-Internal-Token: $token" -H "X-Builder-Internal-User: $owner"
    -H 'Content-Type: application/json')
  [[ -n "$body" ]] && args+=(-d "$body")
  out=$(curl "${args[@]}" -w '\n%{http_code}') || { echo "✗ 无法连接 ${XBD_CONTROL_BASE_URL}"; exit 1; }
  status="${out##*$'\n'}"
  if [[ "$status" != 2* ]]; then
    echo "✗ internal API $status [$method $path]：$(head -c 200 <<<"${out%$'\n'*}")" >&2; exit 1
  fi
  printf '%s' "${out%$'\n'*}"
}

if [[ "$MODE" == --session-model ]]; then
  : "${XBD_CONTROL_BASE_URL:?✗ 需在 .env 配置 XBD_CONTROL_BASE_URL（本机 aistiod 控制面地址，如 http://localhost:28081）}"
  echo '--- 1. 定位实验 Agent 最新 Chat'
  LIST=$(api GET "/api/v1/chats$(scope_q "$XBD_TENANT" seashore-main)" '' XBD_TOKEN_ALICE)
  CHAT=$(jq -c --arg a "$ID" '[.items[]? | select(.agentId==$a)] | sort_by(.createdAt // 0) | last // "null"' <<<"$LIST")
  [[ "$CHAT" != "null" ]] || { echo '✗ 实验 Agent 尚无 Chat：先按 Step 11/12 文档创建一个'; exit 1; }
  CHAT_ID=$(jq -r '.id' <<<"$CHAT"); RID=$(jq -r '.runtimeSessionId' <<<"$CHAT")
  V1SID=$(jq -r '.sessionId' <<<"$CHAT")
  echo "  chat=$CHAT_ID runtimeSession=$RID"
  echo '--- 2. 会话级模型覆盖（下一 Turn 即生效，无需新 Chat）'
  if [[ "$2" == "-" ]]; then
    AFTER=$(internal_api PATCH "/api/internal/sessions/$RID/overrides" '{"agentOverrides":{"model":null}}')
    echo '  + 已清除 model 覆盖，回到 definition.model'
  else
    AFTER=$(internal_api PATCH "/api/internal/sessions/$RID/overrides" \
      "$(jq -nc --arg m "$2" '{agentOverrides:{model:$m}}')")
    echo "  + 已写入会话覆盖 model=$2"
  fi
  jq -r --arg d "$(jq -r '.definition.model' <<<"$DEF")" \
    '"  当前生效: " + (if (.agentOverridesJson // "" | fromjson? | .model // "") != "" then .agentOverridesJson | fromjson | "覆盖 \(.model)" else "definition.model（\($d)）" end)' <<<"$AFTER"
  if [[ "$2" == "-" ]]; then
    echo '回滚完成；后续 Turn 用 Agent 定义中的模型。'
    exit 0
  fi
  echo '--- 3. 验证 Turn（真实消耗模型额度）'
  EV=$(api GET "/api/v1/sessions/$V1SID/events?chatId=$CHAT_ID" '' XBD_TOKEN_ALICE)
  BI=$(jq '[.events[]?|select(.eventType=="session.status_idle")]|length' <<<"$EV")
  api POST "/api/v1/chats/$CHAT_ID/turns$(scope_q "$XBD_TENANT" seashore-main)" \
    '{"message":"请只回复两个字：收到"}' XBD_TOKEN_ALICE >/dev/null
  REPLY=""
  for _ in $(seq 1 50); do
    sleep 3
    EV=$(api GET "/api/v1/sessions/$V1SID/events?chatId=$CHAT_ID" '' XBD_TOKEN_ALICE)
    ERR=$(jq -r '[.events[]?|select((.eventType//"")|test("error|fail";"i"))]|last|.content // empty' <<<"$EV")
    [[ -n "$ERR" ]] && { echo "✗ Turn 失败：${ERR:0:200}"; echo '  检查模型 ID 是否可解析（dashscope:名称 或已注册别名）；回滚: --session-model -'; exit 1; }
    REPLY=$(jq -r '[.events[]?|select(.eventType=="agent.message")]|last|.content // empty' <<<"$EV")
    [[ "$(jq '[.events[]?|select(.eventType=="session.status_idle")]|length' <<<"$EV")" -gt "$BI" && -n "$REPLY" ]] && break
    REPLY=""
  done
  [[ -n "$REPLY" ]] || { echo '✗ 150s 内未收到回复（网络或模型通道过慢，可重跑验证）'; exit 1; }
  echo "  ✓ 新模型 Turn 回复（截断）: ${REPLY:0:80}"
  echo '注意：internal 通道仅适用于本机 dev 栈（owner 校验被绕过）；生产需要平台提供面向会话参与者的公开端点。'
  exit 0
fi

if [[ "$MODE" == --set-model ]]; then
  # GET 完整 definition -> 只替换 model -> 带原 version PATCH，保留 Workspace/tools/environment。
  BODY=$(jq -c --arg model "$2" '.definition | .model=$model' <<<"$DEF")
  RES=$(api PATCH "/api/v1/agents/$ID/definition" "$BODY" XBD_TOKEN_ALICE)
  AFTER=$(api GET "/api/v1/agents/$ID/definition" '' XBD_TOKEN_ALICE)
  assert_eq "$(jq -r '.definition.model' <<<"$AFTER")" "$2" '实验 Agent 模型选择已保存'
  assert_eq "$(jq -cS '.definition|{workspaceId,workspaceBinding,tools,defaultEnvironmentId}' <<<"$AFTER")" \
    "$(jq -cS '.definition|{workspaceId,workspaceBinding,tools,defaultEnvironmentId}' <<<"$DEF")" '工作区、工具和环境配置保留'
  DEF="$AFTER"
fi
echo "$DEF" | jq '.definition | {name,version,model,workspaceId,defaultEnvironmentId}'
echo '--- 会话级模型覆盖（尽力读取；需 .env 配置 XBD_CONTROL_BASE_URL）'
if [[ -n "${XBD_CONTROL_BASE_URL:-}" ]]; then
  LIST=$(api GET "/api/v1/chats$(scope_q "$XBD_TENANT" seashore-main)" '' XBD_TOKEN_ALICE)
  CHAT=$(jq -c --arg a "$ID" '[.items[]? | select(.agentId==$a)] | sort_by(.createdAt // 0) | last // "null"' <<<"$LIST")
  if [[ "$CHAT" != "null" ]]; then
    RID=$(jq -r '.runtimeSessionId' <<<"$CHAT")
    OVR=$(internal_api GET "/api/internal/sessions/$RID/overrides" '' 2>/dev/null | jq -r '.agentOverridesJson // ""' || true)
    if [[ -n "$OVR" && "$OVR" != "null" ]]; then
      echo "  最新会话 $RID 覆盖: $OVR（--session-model - 可清除）"
    else
      echo "  最新会话 $RID 无覆盖，生效模型为 definition.model"
    fi
  else
    echo '  实验 Agent 尚无 Chat'
  fi
else
  echo '  未配置 XBD_CONTROL_BASE_URL，跳过（配置后可用 --session-model 会话级切换）'
fi
echo '这里只核对已保存配置。模型别名必须在每个 Dataplane 注册，新 Chat/Turn 的执行才是最终验收。'
echo '适配示例: examples/model-channel/；本步骤不自动切模型、不替你开启付费。'
