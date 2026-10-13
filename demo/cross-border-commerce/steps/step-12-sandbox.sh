#!/usr/bin/env bash
# Step 12：默认只读核对当前环境；--create 仅登记 E2B 环境元数据，不启动云沙箱。
set -euo pipefail
cd "$(dirname "$0")/.."
source lib/common.sh
CREATE=0
case "${1:-}" in '') ;; --create) CREATE=1;; *) echo '用法: step-12-sandbox.sh [--create]'; exit 2;; esac
[[ $# -le 1 ]] || exit 2
require_env
step_header 'Step 12 Environment 与沙箱'
login_as alice alice XBD_TOKEN_ALICE
scope_as "$XBD_TENANT" seashore-main
ID=$(state_get XBD_AGENT_WORKSPACE_LAB)
[[ -n "$ID" ]] || { echo '✗ 先运行Step 11'; exit 1; }
DEF=$(api GET "/api/v1/agents/$ID/definition" '' XBD_TOKEN_ALICE)
ENV_ID=$(jq -er '.definition.defaultEnvironmentId' <<<"$DEF")
ENV=$(api GET "/api/environments/$ENV_ID" '' XBD_TOKEN_ALICE)
echo "$ENV" | jq '{id,name,type,ownerId}'
echo '上面是实验 Agent 当前默认环境；local 表示服务端执行，不能视作容器隔离。'
BODY='{"name":"xbd-seashore-e2b-lab","type":"sandbox","config":{"templateId":"base","workspaceRoot":"/home/user","sandboxTimeoutSeconds":300,"isolationScope":"SESSION"}}'
if [[ "$CREATE" == 0 ]]; then
  echo 'E2B 配置样例（仅展示，未提交）：'; jq . <<<"$BODY"
  echo '如需登记资源: bash steps/step-12-sandbox.sh --create'
  exit 0
fi
LIST=$(api GET /api/environments '' XBD_TOKEN_ALICE)
SID=$(jq -r '[.[]|select(.name=="xbd-seashore-e2b-lab")][0].id // empty' <<<"$LIST")
if [[ -z "$SID" ]]; then
  RES=$(api POST /api/environments "$BODY" XBD_TOKEN_ALICE)
  SID=$(jq -er '.id' <<<"$RES")
  # 创建返回的 apiKey 是 Environment Worker key，不是 E2B key；不打印、不混用。
  echo "  + 登记 sandbox 环境=$SID"
else echo "  ↺ 复用 sandbox 环境=$SID"; fi
state_set XBD_ENV_SANDBOX_LAB "$SID"
CHECK=$(api GET "/api/environments/$SID" '' XBD_TOKEN_ALICE)
assert_eq "$(jq -r '.type' <<<"$CHECK")" sandbox '环境类型已回读'
echo "$CHECK" | jq '{id,name,type,config:(.config|{templateId,workspaceRoot,sandboxTimeoutSeconds,isolationScope})}'
echo '这里只验证控制面登记；未修改 Agent 绑定，未检查 E2B 凭据，未启动云沙箱或验证执行隔离。'
