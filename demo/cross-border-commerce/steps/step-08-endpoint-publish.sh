#!/usr/bin/env bash
# step-08: Endpoint 发布与对外调用
set -euo pipefail
cd "$(dirname "$0")/.."
source lib/common.sh
require_env
step_header "Step 08 Endpoint 发布与对外调用"

: "${DASHSCOPE_API_KEY:?✗ 缺少 DASHSCOPE_API_KEY —— 对外调用需要真实模型}"

login_as alice alice XBD_TOKEN_ALICE
CS_ID=$(state_get XBD_AGENT_CS_SEASHORE)

# 1. 创建 Endpoint（先查后建；body 作用域决定归属）
echo "--- 创建 Endpoint"
EPS=$(api GET "/api/v1/endpoints?tenant=${XBD_TENANT}&namespace=seashore-main" XBD_TOKEN_ALICE)
EP_ID=$(jq -r --arg n "xbd-seashore-cs-endpoint" \
  '[.items[]? | select(.name == $n)][0].id // empty' <<<"$EPS")
if [[ -z "$EP_ID" ]]; then
  EP=$(api POST /api/v1/endpoints "$(jq -n \
    --arg t "${XBD_TENANT}" --arg ns "seashore-main" --arg agent "$CS_ID" \
    '{tenant:$t, namespace:$ns, name:"xbd-seashore-cs-endpoint", slug:"xbd-seashore-cs",
      description:"海岸优品店铺客服对外 API",
      targetType:"agent", targetRef:$agent, invocationMode:"conversation",
      inputSchema:{type:"object",properties:{message:{type:"string"}},required:["message"]}}')" XBD_TOKEN_ALICE)
  EP_ID=$(jq -er '.id // .endpoint.id' <<<"$EP") || { echo "✗ 创建响应无 id:"; echo "$EP"; exit 1; }
  echo "  + endpoint=${EP_ID}（status=$(jq -r '.status // .endpoint.status' <<<"$EP")）"
else
  echo "  ↺ 复用 endpoint=$EP_ID"
fi

# 2. 发布（body 携带当前 version 乐观锁；已发布则幂等返回）
echo "--- 发布"
EP_DETAIL=$(api GET "/api/v1/endpoints/$EP_ID?tenant=${XBD_TENANT}&namespace=seashore-main" XBD_TOKEN_ALICE)
EP_VER=$(jq -r '.version // .endpoint.version' <<<"$EP_DETAIL")
PUB=$(api POST "/api/v1/endpoints/$EP_ID/publish" "{\"version\":$EP_VER}" XBD_TOKEN_ALICE)
SLUG=$(jq -er '.endpoint.slug // .slug' <<<"$PUB") || { echo "✗ publish 响应无 slug:"; echo "$PUB"; exit 1; }
assert_eq "$(jq -r '.endpoint.status // .status' <<<"$PUB")" "published" "Endpoint 已发布"
state_set XBD_ENDPOINT_SLUG "$SLUG"
echo "  ✓ slug=$SLUG"

# 3. 签发对外凭据（明文 secret 只在创建响应出现一次）
echo "--- 签发 API Key"
CRED_LIST=$(api GET "/api/v1/endpoints/$EP_ID/credentials?tenant=${XBD_TENANT}&namespace=seashore-main" XBD_TOKEN_ALICE)
if jq -e --arg n "xbd-demo-key" '[.items[]? // .credentials[]? | select(.name == $n)] | length > 0' <<<"$CRED_LIST" >/dev/null 2>&1; then
  echo "  ↺ 凭据已存在（明文仅签发时可见——如丢失请 rotate 或新建）"
  KEY=$(state_get XBD_ENDPOINT_KEY)
  [[ -n "$KEY" ]] || { echo "✗ state 中无已存明文，请新建一个凭据名（如 xbd-demo-key-2）"; exit 1; }
else
  KEY=$(api POST "/api/v1/endpoints/$EP_ID/credentials" \
    '{"name":"xbd-demo-key"}' XBD_TOKEN_ALICE | jq -er '.secret')
  state_set XBD_ENDPOINT_KEY "$KEY"
  echo "  + key 已签发（明文仅存本地 .state.env，不在日志打印）"
fi

# 4. 外部视角调用（Bearer = endpoint secret，无平台 JWT）
#    幂等键固定：invoke 侧同键幂等复用（返回原 invocation），重跑直接读既有会话结果
echo "--- 外部系统调用"
CONV_RESP=$(curl -sS -X POST "$BASE_URL/invoke/v1/endpoints/$SLUG/conversations" \
  -H "Authorization: Bearer $KEY" -H 'Content-Type: application/json' \
  -H "Idempotency-Key: $(idem step-08 conv)" \
  -d '{"message":"你们的海绵收纳盒支持海外仓发货吗？发货到德国一般几天？"}')
CID=$(jq -er '.conversationId' <<<"$CONV_RESP") || { echo "✗ 会话响应解析失败:"; echo "$CONV_RESP" | head -c 400; exit 1; }
echo "  + conversation=${CID}（invocation status=$(jq -r '.status' <<<"$CONV_RESP")）"

# 5. 轮询会话直到拿到真实回复（turns[0].status=completed 时 result 即回复）
echo "--- 等待回复（至多 120s）"
REPLY=""
for i in $(seq 1 40); do
  DET=$(curl -sS "$BASE_URL/invoke/v1/conversations/$CID" -H "Authorization: Bearer $KEY")
  ST=$(jq -r '.turns[0].status // ""' <<<"$DET" 2>/dev/null)
  [[ "$ST" == "completed" ]] && REPLY=$(jq -r '.turns[0].result // empty' <<<"$DET")
  [[ "$ST" == "failed" ]] && { echo "✗ Turn 失败:"; echo "$DET" | head -c 400; exit 1; }
  [[ -n "$REPLY" ]] && break
  sleep 3
done
[[ -n "$REPLY" ]] || { echo "✗ 未取到回复，会话详情:"; echo "$DET" | head -c 500; exit 1; }
echo "  ✓ 回复（截断）: ${REPLY:0:90}…"

echo ""
echo "本步产出: XBD_ENDPOINT_SLUG=${SLUG}（secret 已存 state，不打印）"
