#!/usr/bin/env bash
# step-10: Automation 每日竞品价格监控（仅建工单，不抓取真实价格）
set -euo pipefail
cd "$(dirname "$0")/.."
source lib/common.sh
require_env
step_header "Step 10 Automation 定时任务"
login_as alice alice XBD_TOKEN_ALICE
LIST=$(api GET "/api/v1/automations$(scope_q "$XBD_TENANT" seashore-main)" "" XBD_TOKEN_ALICE)
AU_ID=$(jq -r '[.items[]? | select(.name=="xbd-seashore-price-watch")][0].id // empty' <<<"$LIST")
if [[ -z "$AU_ID" ]]; then
  AU=$(api POST /api/v1/automations "$(jq -n --arg t "$XBD_TENANT" \
    '{tenant:$t,namespace:"seashore-main",name:"xbd-seashore-price-watch",enabled:false,
      triggerType:"cron",triggerConfig:{schedule:"0 9 * * *",timezone:"Asia/Shanghai"},
      actionType:"create_issue",actionConfig:{title:"每日竞品价格监控",description:"请人工收集竞品 SKU 价格并复核。Demo 不含真实价格抓取工具。"}}')" XBD_TOKEN_ALICE)
  AU_ID=$(jq -er '.automation.id' <<<"$AU")
  echo "  + automation=${AU_ID}（默认停用，避免教程运行后持续生成工单）"
else
  echo "  ↺ 复用 automation=$AU_ID"
fi
state_set XBD_AUTOMATION_1 "$AU_ID"
PREVIEW=$(api POST /api/v1/automations/schedule-preview \
  '{"schedule":"0 9 * * *","timezone":"Asia/Shanghai"}' XBD_TOKEN_ALICE)
assert_eq "$(jq '.nextRuns|length' <<<"$PREVIEW")" 5 "未来五次排程已生成"
echo "$PREVIEW" | jq .
# test=true 允许验证停用的规则；仍会实际生成测试工单，并非 dry-run。
# 保留已有测试运行的幂等键，文件改名不应触发重复工单。
TR=$(curl -fsS --connect-timeout 10 --max-time 60 -X POST \
  "$BASE_URL/api/v1/automations/$AU_ID/trigger?test=true" \
  -H "Authorization: Bearer $(state_get XBD_TOKEN_ALICE)" \
  -H 'Content-Type: application/json' -H "Idempotency-Key: $(idem ext-b trigger)" -d '{}')
RUN_ID=$(jq -er '.run.id' <<<"$TR")
for i in $(seq 1 30); do
  TR=$(api GET "/api/v1/automations/$AU_ID/runs/$RUN_ID" "" XBD_TOKEN_ALICE)
  ST=$(jq -er '.run.status' <<<"$TR")
  [[ "$ST" == completed || "$ST" == failed || "$ST" == cancelled ]] && break
  sleep 2
done
assert_eq "$ST" completed "测试触发完成"
ISSUE_ID=$(jq -er '.run.issueId' <<<"$TR")
state_set XBD_AUTOMATION_RUN "$RUN_ID"
state_set XBD_AUTOMATION_ISSUE "$ISSUE_ID"
echo "$TR" | jq '{run:(.run|{id,status,issueId,source})}'
RUNS=$(api GET "/api/v1/automations/$AU_ID/runs" "" XBD_TOKEN_ALICE)
jq -e --arg id "$RUN_ID" 'any(.items[]?; .id==$id)' <<<"$RUNS" >/dev/null
echo "  ✓ 运行记录可查询（相同幂等键复用同一运行）"
