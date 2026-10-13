#!/usr/bin/env bash
# Step 13：默认只读；--set-model 仅改独立实验 Agent；--probe-* 才请求用户配置的模型网关。
set -euo pipefail
cd "$(dirname "$0")/.."
source lib/common.sh
MODE="${1:---inspect}"
case "$MODE" in
  --inspect|--probe-text|--probe-tools) [[ $# -le 1 ]] || exit 2;;
  --set-model) [[ $# == 2 && -n "$2" ]] || { echo '用法: step-13-model-channel.sh --set-model merchant-gateway'; exit 2; };;
  *) echo '用法: step-13-model-channel.sh [--inspect|--set-model MODEL_ID|--probe-text|--probe-tools]'; exit 2;;
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
echo '这里只核对已保存配置。模型别名必须在每个 Dataplane 注册，新 Chat/Turn 的执行才是最终验收。'
echo '适配示例: examples/model-channel/；本步骤不自动切模型、不替你开启付费。'
