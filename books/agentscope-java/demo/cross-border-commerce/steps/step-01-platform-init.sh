#!/usr/bin/env bash
# step-01: 平台初始化与身份体系
set -euo pipefail
cd "$(dirname "$0")/.."
source lib/common.sh
require_env
step_header "Step 01 平台初始化与身份体系"

# 1. 栈版本
echo "--- 控制面版本"
api GET /api/v1/version | jq .
echo "  ✓ 栈可达: $BASE_URL"

# 2. admin 登录
echo "--- 平台运营方登录"
login_as "${ADMIN_USER:-admin}" "${ADMIN_PASS:-admin}" XBD_TOKEN_ADMIN \
  || { echo "✗ admin 登录失败"; exit 1; }
echo "  ✓ admin 登录成功"

# 3. 当前身份与作用域
ME=$(api GET /api/auth/me)
ADMIN_ID=$(jq -er '.userId // .id' <<<"$ME") || { echo "✗ /api/auth/me 无 userId 字段:"; echo "$ME"; exit 1; }
assert_eq "$(jq -r '.username // .name' <<<"$ME")" "${ADMIN_USER:-admin}" "admin 身份确认"
state_set XBD_ADMIN_ID "$ADMIN_ID"

SCOPE=$(api GET /api/v1/me/scope)
echo "  ✓ 当前作用域: $(jq -c '{tenant,namespace,mode}' <<<"$SCOPE")"

# 4. 种子账号可用性（缺失则 admin 兜底创建）
echo "--- 商家账号"
for u in alice bob; do
  key="XBD_TOKEN_$(echo "$u" | tr 'a-z' 'A-Z')"
  if login_as "$u" "$u" "$key"; then
    echo "  ✓ 种子账号 $u 可登录"
  else
    api POST /api/admin/users "{\"username\":\"$u\",\"password\":\"$u\"}" >/dev/null \
      && login_as "$u" "$u" "$key" \
      || { echo "✗ 账号 $u 不可用且创建失败"; exit 1; }
    echo "  + 创建商家账号 $u"
  fi
done

echo ""
echo "本步产出: 三个账号 JWT 已缓存（.state.env）；XBD_ADMIN_ID=$ADMIN_ID"
