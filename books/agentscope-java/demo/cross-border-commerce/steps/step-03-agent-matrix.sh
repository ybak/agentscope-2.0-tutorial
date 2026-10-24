#!/usr/bin/env bash
# step-03: 商家 Agent 矩阵 —— 同能力不同租户配置
set -euo pipefail
cd "$(dirname "$0")/.."
source lib/common.sh
require_env
step_header "Step 03 商家 Agent 矩阵"

: "${DASHSCOPE_API_KEY:?✗ 缺少 DASHSCOPE_API_KEY —— Agent 无法真实运行，请重启 dev 栈并注入}"
MODEL="${XBD_MODEL:-dashscope:deepseek-v4-flash-0731}"

# v5 Agent Catalog 的先查后建（按 agentKey 全局唯一匹配）
ensure_catalog_agent() { local skey="$1" akey="$2" ns="$3" display="$4" system="$5" token_key="$6"
  local existing body created id
  scope_as "${XBD_TENANT}" "$ns"
  # 列表按 query 通道过滤（header 通道仅对创建等写操作生效）
  existing=$(jq -r --arg k "$akey" \
    '[.items[]? | select(.agentKey == $k)][0].id // empty' \
    <<<"$(api GET "/api/v1/agents$(scope_q "${XBD_TENANT}" "$ns")" "" "$token_key")")
  if [[ -n "$existing" ]]; then
    state_set "$skey" "$existing"; echo "  ↺ 复用 $akey ($existing)"; return 0
  fi
  body=$(jq -n --arg k "$akey" --arg d "$display" --arg s "$system" --arg m "$MODEL" \
    '{agentKey:$k, displayName:$d, binding:{kind:"managed"},
      definition:{name:$k, system:$s, model:$m}}')
  created=$(api POST /api/v1/agents "$body" "$token_key")
  id=$(jq -er '.agent.id // empty' <<<"$created") || { echo "✗ 创建 $akey 失败:"; echo "$created"; exit 1; }
  state_set "$skey" "$id"
  echo "  + 创建 $akey ($id)  环境: $(jq -r '.definition.defaultEnvironmentId // "?"' <<<"$created")"
}

# 1. 海岸优品：三个 Agent（选品/客服/物流）——首个 Agent 自动 provision default-local 环境
login_as alice alice XBD_TOKEN_ALICE
echo "--- 海岸优品（seashore-main）"
ensure_catalog_agent XBD_AGENT_SCOUT      "xbd-seashore-product-scout" "seashore-main" "海岸优品·选品专员" "你是海岸优品的跨境选品专员，负责市场调研与选品建议，输出简明中文结论。" XBD_TOKEN_ALICE
ensure_catalog_agent XBD_AGENT_CS_SEASHORE "xbd-seashore-cs-agent"     "seashore-main" "海岸优品·客服专员" "你是海岸优品店铺客服，语气亲切专业，只回答与订单、物流、售后相关的问题。" XBD_TOKEN_ALICE
ensure_catalog_agent XBD_AGENT_LOGISTICS  "xbd-seashore-logistics-agent" "seashore-main" "海岸优品·物流专员" "你是海岸优品物流专员，负责查询物流状态与异常件处理，输出简洁事实。" XBD_TOKEN_ALICE

# 2. 极光数码：同名能力、不同租户配置（只建客服）
login_as bob bob XBD_TOKEN_BOB
echo "--- 极光数码（aurora-main）"
ensure_catalog_agent XBD_AGENT_CS_AURORA  "xbd-aurora-cs-agent"        "aurora-main"   "极光数码·客服专员" "你是极光数码店铺客服，风格活泼年轻化，专注 3C 配件售前售后。" XBD_TOKEN_BOB

# 3. 平台公共 Agent：admin 落在唯一的 global namespace（default），所有商户自动可见可用
#    global 区对全部登录用户授予 member/developer/operator 角色，无需逐一授权
login_as admin admin XBD_TOKEN_ADMIN
echo "--- 平台公共 Agent（global namespace: default）"
ensure_catalog_agent XBD_AGENT_PLATFORM "xbd-platform-shared-agent" "default" "平台公共·跨境小助手" "你是星帆出海平台的公共助手，为所有入驻商家解答平台功能、入驻流程与规则问题，不涉及任何单一商家的私有数据。" XBD_TOKEN_ADMIN

echo "--- 平台公共 Agent 可见性（两家商户各自验证）"
for u in alice bob; do
  key="XBD_TOKEN_$(echo "$u" | tr 'a-z' 'A-Z')"
  if [[ "$u" == "alice" ]]; then own="seashore-main"; else own="aurora-main"; fi
  login_as "$u" "$u" "$key"
  scope_as "" ""
  NS_DIR=$(api GET /api/v1/me/namespaces "" "$key")
  assert_eq "$(jq -r '[.items[]? | select(.kind=="global" and .name=="default")] | length' <<<"$NS_DIR")" "1" \
    "$u 的 namespace 目录自动含 global 公共区（default）"
  scope_as "${XBD_TENANT}" "default"
  GLOBAL_LIST=$(api GET "/api/v1/agents$(scope_q "${XBD_TENANT}" default)" "" "$key")
  assert_contains "$(jq -r '[.items[]? | .agentKey] | join(",")' <<<"$GLOBAL_LIST")" "xbd-platform-shared-agent" \
    "$u 在 default 列表可见平台公共 Agent"
  scope_as "${XBD_TENANT}" "$own"
  OWN_LIST=$(api GET "/api/v1/agents$(scope_q "${XBD_TENANT}" "$own")" "" "$key")
  assert_ne "$(jq -r '[.items[]? | select(.agentKey=="xbd-platform-shared-agent")] | length' <<<"$OWN_LIST")" "1" \
    "$u 自家（${own}）列表不混合出现公共 Agent（列表按单 namespace 过滤）"
  assert_status "$(api_raw GET "/api/v1/agents/$(state_get XBD_AGENT_PLATFORM)" "" "$key" | head -1)" "404" \
    "$u 带自家作用域单资源读取公共 Agent 得 404（作用域头须匹配存储作用域）"
done

echo "--- 公共区会话私有性（Agent 公共、会话私有）"
login_as alice alice XBD_TOKEN_ALICE
scope_as "${XBD_TENANT}" "default"
CHAT_LIST=$(api GET "/api/v1/chats$(scope_q "${XBD_TENANT}" default)" "" XBD_TOKEN_ALICE)
CHAT_ID=$(jq -r --arg t "xbd-step03-平台公共助手体验" \
  '[.items[]? | select(.title == $t)][0].id // empty' <<<"$CHAT_LIST")
if [[ -z "$CHAT_ID" ]]; then
  CHAT=$(api POST "/api/v1/chats$(scope_q "${XBD_TENANT}" default)" \
    "$(jq -n --arg a "$(state_get XBD_AGENT_PLATFORM)" '{agentId:$a, title:"xbd-step03-平台公共助手体验"}')" XBD_TOKEN_ALICE)
  CHAT_ID=$(jq -er '.chat.id' <<<"$CHAT") || { echo "✗ 公共区建会话失败:"; echo "$CHAT"; exit 1; }
  echo "  + alice 以商家身份在公共区建会话 ($CHAT_ID)——member 角色允许 use"
else
  echo "  ↺ 复用 alice 的公共区会话 ($CHAT_ID)"
fi
state_set XBD_CHAT_PLATFORM "$CHAT_ID"
login_as bob bob XBD_TOKEN_BOB
scope_as "${XBD_TENANT}" "default"
BOB_CHATS=$(api GET "/api/v1/chats$(scope_q "${XBD_TENANT}" default)" "" XBD_TOKEN_BOB)
assert_eq "$(jq -r --arg c "$CHAT_ID" '[.items[]? | select(.id==$c)] | length' <<<"$BOB_CHATS")" "0" \
  "bob 看不到 alice 与公共 Agent 的会话（工作对象按创建者过滤）"

# 4. 归属验证：各商家在自家作用域读取（跨租户单资源读取直接 404，详见 step-05）
echo "--- 归属验证"
login_as alice alice XBD_TOKEN_ALICE
scope_as "${XBD_TENANT}" "seashore-main"
OWN=$(api GET "/api/v1/agents/$(state_get XBD_AGENT_CS_SEASHORE)" "" XBD_TOKEN_ALICE)
assert_eq "$(jq -r '.agent.namespace // .namespace' <<<"$OWN")" "seashore-main" "海岸客服 Agent 归属 seashore-main"
login_as bob bob XBD_TOKEN_BOB
scope_as "${XBD_TENANT}" "aurora-main"
AUR=$(api GET "/api/v1/agents/$(state_get XBD_AGENT_CS_AURORA)" "" XBD_TOKEN_BOB)
assert_eq "$(jq -r '.agent.namespace // .namespace' <<<"$AUR")" "aurora-main" "极光客服 Agent 归属 aurora-main"

echo ""
echo "本步产出: SCOUT=$(state_get XBD_AGENT_SCOUT) CS=$(state_get XBD_AGENT_CS_SEASHORE) LOGI=$(state_get XBD_AGENT_LOGISTICS) AUR_CS=$(state_get XBD_AGENT_CS_AURORA)"
