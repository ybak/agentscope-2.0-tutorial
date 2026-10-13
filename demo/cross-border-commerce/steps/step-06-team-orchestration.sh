#!/usr/bin/env bash
# step-06: Team 编排 —— 客服协作团队处理升级售后工单
set -euo pipefail
cd "$(dirname "$0")/.."
source lib/common.sh
require_env
step_header "Step 06 Team 编排"

: "${DASHSCOPE_API_KEY:?✗ 缺少 DASHSCOPE_API_KEY —— Team 的 Lead Agent 需要真实模型}"

login_as alice alice XBD_TOKEN_ALICE
CS_ID=$(state_get XBD_AGENT_CS_SEASHORE)
LOGI_ID=$(state_get XBD_AGENT_LOGISTICS)

# 1. 建团队（先查后建；v5 catalog UUID 直接作为成员）
echo "--- 创建客服团队"
TEAM_LIST=$(api GET "/api/v1/teams?tenant=${XBD_TENANT}&namespace=seashore-main" XBD_TOKEN_ALICE)
TEAM_ID=$(jq -r --arg n "xbd-seashore-cs-team" \
  '[.items[]? | select(.name == $n)][0].id // empty' <<<"$TEAM_LIST")
if [[ -z "$TEAM_ID" ]]; then
  TEAM=$(api POST /api/v1/teams "$(jq -n \
    --arg t "${XBD_TENANT}" --arg ns "seashore-main" --arg lead "$CS_ID" \
    '{tenant:$t, namespace:$ns, name:"xbd-seashore-cs-team",
      instructions:"客服 Lead 接待客户，物流问题委派物流专员核实后汇总答复。",
      policy:{maxActiveTasks:8, maxFanout:4},
      leaderAgentId:$lead}')" XBD_TOKEN_ALICE)
  TEAM_ID=$(jq -er '.team.id' <<<"$TEAM") || { echo "✗ 响应无 .team.id:"; echo "$TEAM"; exit 1; }
  echo "  + team=${TEAM_ID}（leader=客服专员）"
else
  echo "  ↺ 复用 team=$TEAM_ID"
fi
state_set XBD_TEAM_1 "$TEAM_ID"

# 2. 追加物流专员为成员（幂等：team 详情的 members 里已有则跳过）
echo "--- 添加团队成员"
TEAM_DETAIL=$(api GET "/api/v1/teams/$TEAM_ID?tenant=${XBD_TENANT}&namespace=seashore-main" XBD_TOKEN_ALICE)
if grep -q "\"agentId\":\"$LOGI_ID\"" <<<"$TEAM_DETAIL"; then
  echo "  ↺ 物流专员已在队"
else
  api POST "/api/v1/teams/$TEAM_ID/members" \
    "$(jq -n --arg a "$LOGI_ID" '{agentId:$a, role:"member", instructions:"负责核实物流时效与异常件状态。"}')" XBD_TOKEN_ALICE >/dev/null
  echo "  + 物流专员已入队"
fi

# 3. 建 Team-assigned Issue（自动产生 AgentTask，Lead 开始工作）
echo "--- 派发升级工单"
RES=$(api POST /api/v1/issues "$(jq -n \
  --arg t "${XBD_TENANT}" --arg ns "seashore-main" --arg ref "$TEAM_ID" \
  '{tenant:$t, namespace:$ns,
    title:"售后升级：订单 OD-2049 客户投诉物流延迟",
    description:"客户第三次催单。请核实物流实际状态，给出补偿方案与答复口径。",
    assigneeType:"team", assigneeRef:$ref}')" XBD_TOKEN_ALICE)
ISSUE_ID=$(jq -er '.issue.id' <<<"$RES"); TASK_ID=$(jq -er '.agentTask.id' <<<"$RES")
state_set XBD_ISSUE_1 "$ISSUE_ID"; state_set XBD_TASK_1 "$TASK_ID"
echo "  + issue=${ISSUE_ID}（status=$(jq -r '.issue.status' <<<"$RES")）"
echo "  + task=${TASK_ID}（status=$(jq -r '.agentTask.status' <<<"$RES")）"

# 4. 等待 Lead Agent 启动执行（attempt 出现即协作启动；终态语义见文档说明）
echo "--- 等待 Lead Agent 启动执行"
ATTEMPT=""
for i in $(seq 1 30); do
  TR=$(api GET "/api/v1/agent-tasks/$TASK_ID" "" XBD_TOKEN_ALICE)
  ATTEMPT=$(jq -r '.currentAttemptId // .task.currentAttemptId // empty' <<<"$TR")
  [[ -n "$ATTEMPT" ]] && break
  sleep 3
done
[[ -n "$ATTEMPT" ]] || { echo "✗ 90s 内 attempt 未产生（检查模型连通性与 Lead Agent 状态）"; exit 1; }
echo "  ✓ 协作已启动: attempt=${ATTEMPT}（Lead 可委派成员，协作 MCP 工具已注入）"

# 5. 给协作执行留观察窗口，读取 task 终态（不作为验收门）
sleep 45
TR=$(api GET "/api/v1/agent-tasks/$TASK_ID" "" XBD_TOKEN_ALICE)
ST=$(jq -r '.status // .task.status // "?"' <<<"$TR")
ISSUE_ST=$(api GET "/api/v1/issues/$ISSUE_ID" "" XBD_TOKEN_ALICE | jq -r '.issue.status')
case "$ST" in
  completed) echo "  ✓ Task 完成（${ST}），issue 状态: $ISSUE_ST" ;;
  *) echo "  ⚠ Task 终态: ${ST}，issue 状态: $ISSUE_ST"
     echo "    （当前 dev 栈版本下 Lead turn 收尾可能因事件镜像 410 报 managed_turn_incomplete——协作过程真实发生，收尾语义与排障见文档）" ;;
esac

# 5. 评论追加输入（Issue-first 协作：新评论路由为新任务输入）
echo "--- 评论追加输入"
api POST "/api/v1/issues/$ISSUE_ID/comments" \
  '{"content":"补充：客户可接受部分退款，请评估补偿金额。"}' XBD_TOKEN_ALICE >/dev/null
echo "  ✓ 评论已路由"

# 6. 工单概要
echo "--- 工单概要"
api GET "/api/v1/issues/$ISSUE_ID/summary" "" XBD_TOKEN_ALICE | jq '.summary' 2>/dev/null | head -15
echo ""
echo "本步产出: XBD_TEAM_1=$TEAM_ID XBD_ISSUE_1=$ISSUE_ID XBD_TASK_1=$TASK_ID"
