#!/usr/bin/env bash
# step-02: 商家入驻 —— namespace 即租户单元
set -euo pipefail
cd "$(dirname "$0")/.."
source lib/common.sh
require_env
step_header "Step 02 商家入驻"

login_as "${ADMIN_USER:-admin}" "${ADMIN_PASS:-admin}" XBD_TOKEN_ADMIN

# 1. 平台为两家商家开立 namespace（先查后建）
echo "--- 创建商家 namespace"
ensure_namespace "seashore-main" "海岸优品（家居出海）" "alice"
ensure_namespace "aurora-main"   "极光数码（3C 配件出海）" "bob"
state_set XBD_NS_SEASHORE seashore-main
state_set XBD_NS_AURORA   aurora-main

# 2. 商家视角验证：只见自己的租户单元
echo "--- 商家视角验证"
for u in alice bob; do
  key="XBD_TOKEN_$(echo "$u" | tr 'a-z' 'A-Z')"
  login_as "$u" "$u" "$key"
  if [[ "$u" == "alice" ]]; then own="seashore-main"; other="aurora-main"; else own="aurora-main"; other="seashore-main"; fi
  NS=$(api GET /api/v1/me/namespaces "" "$key")
  assert_contains "$NS" "$own" "$u 可见自己的 namespace（${own}）"
  if grep -q "$other" <<<"$NS"; then
    echo "✗ 隔离异常：$u 竟可见 $other"; echo "$NS"; exit 1
  fi
  echo "  ✓ $u 不可见 $other"
done

# 3. owner 信息回读
scope_as "" ""
NS_DETAIL=$(api GET "/api/v1/namespaces/seashore-main")
echo "$NS_DETAIL" | jq '.namespace | {name, displayName, owner, kind}'
echo ""
echo "本步产出: XBD_NS_SEASHORE=$(state_get XBD_NS_SEASHORE) / XBD_NS_AURORA=$(state_get XBD_NS_AURORA)"
