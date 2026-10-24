#!/usr/bin/env bash
# step-04: Session 调用面 —— 创建会话、发消息、事件流
set -euo pipefail
cd "$(dirname "$0")/.."
source lib/common.sh
require_env
step_header "Step 04 Session 调用面"

: "${DASHSCOPE_API_KEY:?✗ 缺少 DASHSCOPE_API_KEY —— 本步需要真实模型回复}"

login_as alice alice XBD_TOKEN_ALICE
AGENT_ID=$(state_get XBD_AGENT_CS_SEASHORE)

# 1. 创建会话（Chat）：v5 catalog Agent 与运行时会话之间的桥
echo "--- 创建会话"
scope_as "${XBD_TENANT}" "seashore-main"
CHAT_LIST=$(api GET "/api/v1/chats$(scope_q "${XBD_TENANT}" seashore-main)" "" XBD_TOKEN_ALICE)
CHAT_ID=$(jq -r --arg t "xbd-step04-客服演示" \
  '[.items[]? | select(.title == $t)][0].id // empty' <<<"$CHAT_LIST")
if [[ -z "$CHAT_ID" ]]; then
  CHAT=$(api POST "/api/v1/chats$(scope_q "${XBD_TENANT}" seashore-main)" \
    "$(jq -n --arg a "$AGENT_ID" '{agentId:$a, title:"xbd-step04-客服演示"}')" XBD_TOKEN_ALICE)
  CHAT_ID=$(jq -er '.chat.id' <<<"$CHAT") || { echo "✗ chat 响应无 .chat.id:"; echo "$CHAT"; exit 1; }
  echo "  + chat=$CHAT_ID  runtimeSession=$(jq -r '.chat.runtimeSessionId' <<<"$CHAT")"
else
  echo "  ↺ 复用 chat=$CHAT_ID"
fi
state_set XBD_CHAT_1 "$CHAT_ID"
SESSION_ID=$(jq -r --arg c "$CHAT_ID" '[.items[]? | select(.id == $c)][0].sessionId // empty' <<<"$CHAT_LIST")
[[ -z "$SESSION_ID" ]] && SESSION_ID=$(api GET "/api/v1/chats/$CHAT_ID$(scope_q "${XBD_TENANT}" seashore-main)" "" XBD_TOKEN_ALICE | jq -r '.chat.sessionId')
state_set XBD_SESSION_V5_1 "$SESSION_ID"

# 记录本轮前的事件数，重跑时不能用旧回复/旧 idle 误判成功。
BEFORE=$(api GET "/api/v1/sessions/$SESSION_ID/events?chatId=$CHAT_ID" "" XBD_TOKEN_ALICE)
IDLE_BEFORE=$(jq '[.events[]? | select(.eventType=="session.status_idle")]|length' <<<"$BEFORE")
REPLY_BEFORE=$(jq '[.events[]? | select(.eventType=="agent.message")]|length' <<<"$BEFORE")

# 2. 提交客户咨询（Turn）
echo "--- 提交客户咨询"
TURN=$(api POST "/api/v1/chats/$CHAT_ID/turns$(scope_q "${XBD_TENANT}" seashore-main)" \
  '{"message":"订单 OD-2049 为什么还没到？预期三天前就该送达了。"}' XBD_TOKEN_ALICE)
assert_eq "$(jq -r '.status' <<<"$TURN")" "running" "Turn 已受理并开始执行"

# 3. 旁听事件流（SSE，限时收流供文档展示；真实驱动以轮询为准）
echo "--- SSE 事件流（至多 90s）"
curl -sN --max-time 90 "$BASE_URL/api/v1/sessions/$SESSION_ID/events/stream?chatId=$CHAT_ID" \
  -H "Authorization: Bearer $(state_get XBD_TOKEN_ALICE)" \
  -H "X-AgentScope-Tenant: ${XBD_TENANT}" -H "X-AgentScope-Namespace: seashore-main" \
  > /tmp/xbd-step04-sse.log || true
grep -c '^event:' /tmp/xbd-step04-sse.log | xargs -I{} echo "  收到 {} 个事件"

# 4. 轮询终态（session.status_idle = 本轮结束）
echo "--- 轮询终态"
FINAL="" REPLY=""
for i in $(seq 1 60); do
  EV=$(api GET "/api/v1/sessions/$SESSION_ID/events?chatId=$CHAT_ID" "" XBD_TOKEN_ALICE)
  FINAL=$(jq -r '[.events[]? | select(.eventType == "session.status_idle")] | length' <<<"$EV")
  REPLY=$(jq -r '[.events[]? | select(.eventType == "agent.message")] | last | .content // empty' <<<"$EV")
  REPLY_COUNT=$(jq '[.events[]? | select(.eventType=="agent.message")]|length' <<<"$EV")
  [[ "${FINAL:-0}" -gt "$IDLE_BEFORE" && "$REPLY_COUNT" -gt "$REPLY_BEFORE" && -n "$REPLY" ]] && break
  sleep 3
done
[[ "${FINAL:-0}" -gt "$IDLE_BEFORE" && "$REPLY_COUNT" -gt "$REPLY_BEFORE" && -n "$REPLY" ]] || { echo "✗ 本轮未收到新的回复与 idle 事件"; exit 1; }
echo "  ✓ 本轮已结束且收到新的 Agent 回复"
TOKENS=$(jq -r '[.events[]? | select(.eventType == "span.model_request_end") | .frameworkMeta.usage] | last | "输入 \(.inputTokens) / 输出 \(.outputTokens) tokens"' <<<"$EV" 2>/dev/null || echo "usage 不可得")
echo "  ✓ 模型用量: $TOKENS"
echo "  ✓ Agent 回复（截断）: ${REPLY:0:80}…"

echo ""
echo "本步产出: XBD_CHAT_1=$CHAT_ID  XBD_SESSION_V5_1=${SESSION_ID}；SSE 原文在 /tmp/xbd-step04-sse.log"
