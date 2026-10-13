#!/usr/bin/env bash
# step-03: 商家 Agent 矩阵 —— 同能力不同租户配置
set -euo pipefail
cd "$(dirname "$0")/.."
source lib/common.sh
require_env
step_header "Step 03 商家 Agent 矩阵"

: "${DASHSCOPE_API_KEY:?✗ 缺少 DASHSCOPE_API_KEY —— Agent 无法真实运行，请重启 dev 栈并注入}"
MODEL="${XBD_MODEL:-qwen-plus}"

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

# 3. 归属验证：各商家在自家作用域读取（跨租户单资源读取直接 404，详见 step-05）
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
