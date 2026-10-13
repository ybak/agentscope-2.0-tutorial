#!/usr/bin/env bash
# 一键运行；--list / --dry-run 不连接服务，不读取密钥。
set -euo pipefail
cd "$(dirname "$0")"
source lib/common.sh
ALL=(step-01-platform-init step-02-tenant-onboarding step-03-agent-matrix step-04-session-api step-05-isolation-check step-06-team-orchestration step-07-workflow-pipeline step-08-endpoint-publish step-09-hitl-approval step-10-automation step-11-workspace step-12-sandbox step-13-model-channel)
FROM=1 ONLY=0 DRY=0 LIST=0 SELECTOR=""
usage() { echo '用法: ./run-all.sh [--from 1..13 | --only 1..13] [--list] [--dry-run]'; }
while [[ $# -gt 0 ]]; do
  case "$1" in
    --from|--only)
      [[ $# -ge 2 ]] || { usage; exit 2; }
      [[ -z "$SELECTOR" ]] || { echo '--from 与 --only 只能指定其中一个，且不能重复'; exit 2; }
      SELECTOR="$1"
      [[ "$2" =~ ^(0?[1-9]|1[0-3])$ ]] || { usage; exit 2; }
      SELECT=$((10#$2))
      if [[ "$1" == --from ]]; then FROM="$SELECT"; else ONLY="$SELECT"; fi
      shift 2;;
    --dry-run) DRY=1; shift;;
    --list) LIST=1; shift;;
    --help|-h) usage; exit 0;;
    *) usage; exit 2;;
  esac
done
if [[ "$LIST" == 1 ]]; then
  for i in "${!ALL[@]}"; do echo "$((i+1)). ${ALL[$i]}"; done
  exit 0
fi
[[ "$DRY" == 1 ]] || require_env
for i in "${!ALL[@]}"; do
  n=$((i+1)); s="${ALL[$i]}"
  if [[ "$ONLY" != 0 ]]; then [[ "$n" == "$ONLY" ]] || continue
  else [[ "$n" -ge "$FROM" ]] || continue; fi
  echo "▶ $n. $s"
  [[ "$DRY" == 0 ]] || continue
  if ! bash "steps/$s.sh"; then
    echo "✗ 第 $n 步失败，状态已保留。修复后: ./run-all.sh --from $n"
    exit 1
  fi
done
[[ "$DRY" == 0 ]] || exit 0
echo '════ 平台总览（不输出凭据）════'
for key in XBD_NS_SEASHORE XBD_NS_AURORA XBD_AGENT_SCOUT XBD_AGENT_CS_SEASHORE XBD_AGENT_LOGISTICS XBD_AGENT_CS_AURORA XBD_TEAM_1 XBD_RUN_1 XBD_ENDPOINT_SLUG XBD_APPROVAL_1 XBD_AUTOMATION_1 XBD_WORKSPACE_LAB XBD_AGENT_WORKSPACE_LAB XBD_ENV_SANDBOX_LAB; do
  echo "$key=$(state_get "$key")"
done
echo '完成。配置资源复用；聊天轮次、工单、流程运行、审批按业务增量创建。'
