#!/usr/bin/env bash
# 可逆清理：停用本 demo 入口和定时规则；保留配置、业务历史与共享环境。
set -euo pipefail
cd "$(dirname "$0")"
source lib/common.sh
case "${1:---dry-run}" in
  --dry-run) APPLY=0;; --apply) APPLY=1;;
  *) echo '用法: ./teardown.sh [--dry-run|--apply]'; exit 2;;
esac
[[ $# -le 1 ]] || exit 2
echo '范围：停用 xbd-seashore-cs-endpoint 与 xbd-seashore-price-watch。'
echo '保留：namespace、账号、Agent、Team、Workflow、聊天/工单/审批历史、共享环境及凭据。'
if [[ "$APPLY" == 0 ]]; then echo '预览结束。执行停用请传 --apply；run-all.sh 可重新发布 Endpoint。'; exit 0; fi
require_env
login_as alice alice XBD_TOKEN_ALICE
# 通过精确名称查找并确认作用域，不把 slug 当 UUID，不删除其他资源。
EPS=$(api GET "/api/v1/endpoints$(scope_q "$XBD_TENANT" seashore-main)" "" XBD_TOKEN_ALICE)
EP=$(jq -c '[.items[]? | select(.name=="xbd-seashore-cs-endpoint" and .namespace=="seashore-main")][0] // empty' <<<"$EPS")
if [[ -n "$EP" && "$(jq -r '.status' <<<"$EP")" == published ]]; then
  ID=$(jq -er '.id' <<<"$EP")
  api POST "/api/v1/endpoints/$ID/disable" "$(jq '{version}' <<<"$EP")" XBD_TOKEN_ALICE >/dev/null
  DETAIL=$(api GET "/api/v1/endpoints/$ID" "" XBD_TOKEN_ALICE)
  assert_eq "$(jq -r '.endpoint.status // .status' <<<"$DETAIL")" disabled 'Endpoint 已停用'
else echo '  ↺ Endpoint 不存在或已停用'; fi
AUS=$(api GET "/api/v1/automations$(scope_q "$XBD_TENANT" seashore-main)" "" XBD_TOKEN_ALICE)
AU=$(jq -c '[.items[]? | select(.name=="xbd-seashore-price-watch" and .namespace=="seashore-main")][0] // empty' <<<"$AUS")
if [[ -n "$AU" ]]; then
  ID=$(jq -er '.id' <<<"$AU")
  if [[ "$(jq -r '.enabled' <<<"$AU")" == true ]]; then
    api PATCH "/api/v1/automations/$ID" "$(jq '{expectedVersion:.version,enabled:false}' <<<"$AU")" XBD_TOKEN_ALICE >/dev/null
  fi
  DETAIL=$(api GET "/api/v1/automations/$ID" "" XBD_TOKEN_ALICE)
  assert_eq "$(jq -r '.automation.enabled' <<<"$DETAIL")" false 'Automation 已停用'
else echo '  ↺ Automation 不存在'; fi
echo '可逆清理完成；此脚本不宣称数据库已清空。'
