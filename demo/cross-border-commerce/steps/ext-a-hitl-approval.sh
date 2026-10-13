#!/usr/bin/env bash
# ext-a: HITL 人工审批
set -euo pipefail
cd "$(dirname "$0")/.."
source lib/common.sh
require_env
step_header "延伸 A HITL 人工审批"

# 工单访问权限独立于 namespace 角色；只共享本工单，保留已有成员。
login_as alice alice XBD_TOKEN_ALICE
login_as "${ADMIN_USER:-admin}" "${ADMIN_PASS:-admin}" XBD_TOKEN_ADMIN
ISSUE_ID=$(state_get XBD_ISSUE_1)
[[ -n "$ISSUE_ID" ]] || { echo "✗ 请先运行 step-06"; exit 1; }
ISSUE=$(api GET "/api/v1/issues/$ISSUE_ID" "" XBD_TOKEN_ALICE)
SHARE=$(jq -c --arg admin "${ADMIN_USER:-admin}" '.issue | {version,access:(.access // {})} | .access.mode="shared" | .access.members[$admin]="contributor"' <<<"$ISSUE")
api PUT "/api/v1/issues/$ISSUE_ID/access" "$SHARE" XBD_TOKEN_ALICE >/dev/null
echo "  ✓ 商家已将指定工单共享给平台运营（contributor）"
AP=$(api POST /api/v1/approvals "$(jq -n \
  --arg t "$XBD_TENANT" --arg ref "$ISSUE_ID" --arg admin "${ADMIN_USER:-admin}" \
  '{tenant:$t, namespace:"seashore-main", targetType:"issue", targetRef:$ref, issueId:$ref,
    approverRef:$admin, reason:"海岸优品订单 OD-2049 部分退款 $18.90，需平台运营复核"}')" XBD_TOKEN_ALICE)
APPROVAL_ID=$(jq -er '.approval.id' <<<"$AP")
state_set XBD_APPROVAL_1 "$APPROVAL_ID"
echo "  + approval=${APPROVAL_ID}（初始 version=$(jq -r '.approval.version' <<<"$AP")，approver=admin）"

# 2. admin 决批（expectedVersion 乐观锁）
VER=$(jq -r '.approval.version' <<<"$AP")
DEC=$(api POST "/api/v1/approvals/$APPROVAL_ID/decide" "$(jq -n --argjson v "$VER" \
  '{status:"approved", expectedVersion:$v, decision:{note:"同意，走部分退款流程"}}')" XBD_TOKEN_ADMIN)
assert_eq "$(jq -r '.approval.status // .status' <<<"$DEC")" "approved" "审批已批准"

# 3. 重复决批应失败（乐观锁演示）
RAW=$(api_raw POST "/api/v1/approvals/$APPROVAL_ID/decide" \
  "$(jq -n --argjson v "$VER" '{status:"approved", expectedVersion:$v, decision:{note:"重复操作"}}')" XBD_TOKEN_ADMIN)
assert_status "$(head -1 <<<"$RAW")" "409" "重复决批被乐观锁拒绝"

# 4. 审批结论以评论同步回商家工单（alice 身份）
login_as alice alice XBD_TOKEN_ALICE
api POST "/api/v1/issues/$ISSUE_ID/comments" \
  "{\"content\":\"平台运营已批准退款（approval=${APPROVAL_ID}），请执行部分退款并回复客户。\"}" XBD_TOKEN_ALICE >/dev/null
echo "  ✓ 审批结论已同步至商家工单"
echo ""
echo "本步产出: XBD_APPROVAL_1=$APPROVAL_ID"
