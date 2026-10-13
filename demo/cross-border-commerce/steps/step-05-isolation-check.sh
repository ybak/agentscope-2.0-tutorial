#!/usr/bin/env bash
# step-05: 多租户隔离验证（负向测试）
set -euo pipefail
cd "$(dirname "$0")/.."
source lib/common.sh
require_env
step_header "Step 05 多租户隔离验证"

login_as alice alice XBD_TOKEN_ALICE
login_as bob bob XBD_TOKEN_BOB
AUR_AGENT=$(state_get XBD_AGENT_CS_AURORA)
SEA_AGENT=$(state_get XBD_AGENT_CS_SEASHORE)
CHAT_ID=$(state_get XBD_CHAT_1)
SESSION_ID=$(state_get XBD_SESSION_V5_1)

# 1. 越权读单资源：alice（seashore 作用域）读极光的 Agent
echo "--- 越权读取 Agent"
scope_as "${XBD_TENANT}" "seashore-main"
RAW=$(api_raw GET "/api/v1/agents/$AUR_AGENT" "" XBD_TOKEN_ALICE)
assert_status "$(head -1 <<<"$RAW")" "404" "alice 读极光 Agent 被拒（resource not found in authorized scope）"

# 2. 无角色 namespace：alice 直接以 query 通道列 aurora 的资源
echo "--- 无角色 namespace"
RAW2=$(api_raw GET "/api/v1/agents?tenant=${XBD_TENANT}&namespace=aurora-main" "" XBD_TOKEN_ALICE)
assert_status "$(head -1 <<<"$RAW2")" "404" "alice 列 aurora 资源被拒（namespace 成员关系硬隔离）"

# 3. 跨租户读会话：bob 读海岸的 Chat 与事件流
echo "--- 跨租户会话"
RAW3=$(api_raw GET "/api/v1/chats/$CHAT_ID?tenant=${XBD_TENANT}&namespace=aurora-main" "" XBD_TOKEN_BOB)
assert_status "$(head -1 <<<"$RAW3")" "404" "bob 读海岸 Chat 被拒（Chat not found in scope）"
RAW4=$(api_raw GET "/api/v1/sessions/$SESSION_ID/events?chatId=$CHAT_ID&tenant=${XBD_TENANT}&namespace=aurora-main" "" XBD_TOKEN_BOB)
assert_status "$(head -1 <<<"$RAW4")" "404" "bob 读海岸会话事件流被拒"

# 4. 列表按 namespace 过滤：各自的列表里只有自家
echo "--- 列表过滤"
SEA_LIST=$(api GET "/api/v1/agents?tenant=${XBD_TENANT}&namespace=seashore-main" "" XBD_TOKEN_ALICE)
AUR_LIST=$(api GET "/api/v1/agents?tenant=${XBD_TENANT}&namespace=aurora-main" "" XBD_TOKEN_BOB)
assert_eq "$(jq '[.items[]? | select(.agentKey | startswith("xbd-"))] | length' <<<"$SEA_LIST")" "3" "alice 列表只含海岸的 3 个 Agent"
assert_eq "$(jq '[.items[]? | select(.agentKey | startswith("xbd-"))] | length' <<<"$AUR_LIST")" "1" "bob 列表只含极光的 1 个 Agent"
if grep -q "xbd-aurora" <<<"$SEA_LIST"; then echo "✗ 隔离异常"; exit 1; fi
echo "  ✓ 海岸列表不含极光 Agent"

# 5. 正向对照：自家作用域一切正常
echo "--- 正向对照"
api GET "/api/v1/agents/$SEA_AGENT" "" XBD_TOKEN_ALICE | jq -e '.agent.id' >/dev/null
echo "  ✓ alice 自家 Agent 读取正常"
scope_as "${XBD_TENANT}" "aurora-main"
api GET "/api/v1/agents/$AUR_AGENT" "" XBD_TOKEN_BOB | jq -e '.agent.id' >/dev/null
echo "  ✓ bob 自家 Agent 读取正常"

echo ""
echo "隔离验证全部通过（404 = 资源对无授权作用域不可见，防资源枚举）"
