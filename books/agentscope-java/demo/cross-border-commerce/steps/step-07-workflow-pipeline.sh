#!/usr/bin/env bash
# step-07: Workflow 编排 —— 选品上架流水线
set -euo pipefail
cd "$(dirname "$0")/.."
source lib/common.sh
require_env
step_header "Step 07 Workflow 编排"

: "${DASHSCOPE_API_KEY:?✗ 缺少 DASHSCOPE_API_KEY —— 流水线的 agent 节点需要真实模型}"

login_as alice alice XBD_TOKEN_ALICE
SCOUT_ID=$(state_get XBD_AGENT_SCOUT)

# 1. 定义（先查后建）：市场调研（agent 节点）→ 人工放行（signal 节点）
echo "--- 定义流水线"
DEF_LIST=$(api GET "/api/v1/orchestration-definitions?tenant=${XBD_TENANT}&namespace=seashore-main" "" XBD_TOKEN_ALICE)
DEF_ID=$(jq -r --arg n "xbd-seashore-listing-pipeline" \
  '[.definitions[]? | select(.name == $n)][0].id // empty' <<<"$DEF_LIST")
if [[ -z "$DEF_ID" ]]; then
  DEF=$(api POST /api/v1/orchestration-definitions "$(jq -n \
    --arg t "${XBD_TENANT}" --arg ns "seashore-main" --arg agent "$SCOUT_ID" \
    '{tenant:$t, namespace:$ns, name:"xbd-seashore-listing-pipeline",
      description:"选品上架流水线：市场调研 -> 人工放行",
      draftSpec:{
        nodes:[
          {key:"research", type:"agent", agentId:$agent,
           input:{task:"\"调研欧美市场北欧风收纳盒的竞争格局与定价带，输出 200 字内的上架建议。\""}},
          {key:"release", type:"signal", signalName:"release"}
        ],
        edges:[{from:"research", to:"release"}]}}')" XBD_TOKEN_ALICE)
  DEF_ID=$(jq -er '.definition.id' <<<"$DEF") || { echo "✗ 无 .definition.id:"; echo "$DEF"; exit 1; }
  echo "  + definition=$DEF_ID"
else
  echo "  ↺ 复用 definition=$DEF_ID"
fi
state_set XBD_DEF_1 "$DEF_ID"

# 2. 校验 -> 发布（revision 不可变）
echo "--- 校验与发布"
VAL=$(api POST "/api/v1/orchestration-definitions/$DEF_ID/validate" "{}" XBD_TOKEN_ALICE)
assert_eq "$(jq -r '.valid // false' <<<"$VAL")" "true" "draftSpec 校验通过"
REV_ID=$(api POST "/api/v1/orchestration-definitions/$DEF_ID/publish" "" XBD_TOKEN_ALICE | jq -er '.revision.id')
echo "  ✓ 已发布 revision=${REV_ID}（不可变）"

# 3. 启动 Run（挂独立 Issue；幂等键序号自增——同键重复启动会被 409 拒绝，Run 是业务增量）
echo "--- 启动 Run"
RUN_ROOT=$(api POST /api/v1/issues "$(jq -n \
  --arg t "${XBD_TENANT}" --arg ns "seashore-main" \
  '{tenant:$t, namespace:$ns,
    title:"选品任务：北欧风收纳盒市场调研",
    description:"由流水线自动驱动：调研后等人工放行。"}')" XBD_TOKEN_ALICE)
RUN_ISSUE=$(jq -er '.issue.id' <<<"$RUN_ROOT")
SEQ=$(printf '%03d' $(( $(state_get XBD_RUN_SEQ 0) + 1 )))
state_set XBD_RUN_SEQ "$((10#$SEQ))"
RUN=$(api POST "/api/v1/orchestration-definitions/$DEF_ID/runs" "$(jq -n \
  --arg k "xbd-step-07-run-$SEQ" --arg issue "$RUN_ISSUE" \
  '{idempotencyKey:$k, issueId:$issue, input:{market:"US", category:"storage-box"}}')" XBD_TOKEN_ALICE)
RUN_ID=$(jq -er '.run.id' <<<"$RUN")
state_set XBD_RUN_1 "$RUN_ID"
echo "  + run=${RUN_ID}（mode=$(jq -r '.run.mode' <<<"$RUN")，幂等键=xbd-step-07-run-${SEQ}）"

# 4. 等待 research 节点执行完成（事件流出现 node.succeeded）
echo "--- 等待 research 节点执行（至多 180s）"
DONE=0
for i in $(seq 1 36); do
  EV=$(api GET "/api/v1/orchestration-runs/$RUN_ID/events" "" XBD_TOKEN_ALICE)
  DONE=$(echo "$EV" | jq '[.events[]? | select((.type // .eventType) == "node.succeeded")] | length')
  [[ "${DONE:-0}" -ge 1 ]] && break
  FAILED=$(echo "$EV" | jq '[.events[]? | select((.type // .eventType) == "run.failed")] | length')
  [[ "${FAILED:-0}" -ge 1 ]] && { echo "✗ Run 失败:"; echo "$EV" | jq -c '.events'; exit 1; }
  sleep 5
done
assert_eq "$DONE" "1" "research 节点执行完成（node.succeeded）"

# 5. 人工放行 -> Run 完成
ST=$(api GET "/api/v1/orchestration-runs/$RUN_ID" "" XBD_TOKEN_ALICE | jq -r '.run.state // .state')
echo "  Run 当前状态: ${ST}（等待 release 信号）"
api POST "/api/v1/orchestration-runs/$RUN_ID/signals/release" \
  "$(jq -n --arg k "xbd-step-07-signal-$SEQ" '{idempotencyKey:$k, payload:{approved:true}}')" XBD_TOKEN_ALICE >/dev/null
echo "  ✓ 已放行（POST signals/release）"
for i in $(seq 1 40); do
  ST=$(api GET "/api/v1/orchestration-runs/$RUN_ID" "" XBD_TOKEN_ALICE | jq -r '.run.state // .state')
  [[ "$ST" == "succeeded" || "$ST" == "failed" ]] && break
  sleep 3
done
assert_eq "$ST" "succeeded" "Run 成功终态"

# 6. 运行轨迹
echo "--- Run 图与事件"
GRAPH=$(api GET "/api/v1/orchestration-runs/$RUN_ID/graph" "" XBD_TOKEN_ALICE)
echo "$GRAPH" | jq -c '{mode:.run.mode, nodes:[.nodes[]?.key], tasks:(.tasks|length), attempts:(.attempts|length)}'
EVN=$(api GET "/api/v1/orchestration-runs/$RUN_ID/events" "" XBD_TOKEN_ALICE | jq '.events | length')
echo "  事件数: $EVN"
echo ""
echo "本步产出: XBD_DEF_1=$DEF_ID XBD_RUN_1=$RUN_ID revision=$REV_ID"
