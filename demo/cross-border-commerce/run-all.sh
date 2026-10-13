#!/usr/bin/env bash
# 一键运行；--list / --dry-run 不连接服务，不读取密钥。
set -euo pipefail
cd "$(dirname "$0")"
source lib/common.sh
MAIN=(step-01-platform-init step-02-tenant-onboarding step-03-agent-matrix step-04-session-api step-05-isolation-check step-06-team-orchestration step-07-workflow-pipeline step-08-endpoint-publish)
EXT=(ext-a-hitl-approval ext-b-automation)
FROM=1 ONLY=0 WITH_EXT=0 DRY=0 LIST=0
usage() { echo '用法: ./run-all.sh [--from 1..10 | --only 1..10] [--with-ext] [--list] [--dry-run]'; }
while [[ $# -gt 0 ]]; do
  case "$1" in
    --from|--only)
      [[ $# -ge 2 && "$2" =~ ^([1-9]|10)$ ]] || { usage; exit 2; }
      if [[ "$1" == --from ]]; then FROM="$2"; else ONLY="$2"; fi
      shift 2;;
    --with-ext) WITH_EXT=1; shift;;
    --dry-run) DRY=1; shift;;
    --list) LIST=1; shift;;
    --help|-h) usage; exit 0;;
    *) usage; exit 2;;
  esac
done
ALL=("${MAIN[@]}")
[[ "$WITH_EXT" == 0 ]] || ALL+=("${EXT[@]}")
if [[ "$LIST" == 1 ]]; then
  for i in "${!ALL[@]}"; do echo "$((i+1)). ${ALL[$i]}"; done
  exit 0
fi
[[ "$FROM" -le "${#ALL[@]}" && "$ONLY" -le "${#ALL[@]}" ]] || { echo '延伸 9/10 需要 --with-ext'; exit 2; }
[[ "$ONLY" == 0 || "$FROM" == 1 ]] || { echo '--from 与 --only 不能同时使用'; exit 2; }
[[ "$DRY" == 1 ]] || require_env
for i in "${!ALL[@]}"; do
  n=$((i+1)); s="${ALL[$i]}"
  if [[ "$ONLY" != 0 ]]; then [[ "$n" == "$ONLY" ]] || continue
  else [[ "$n" -ge "$FROM" ]] || continue; fi
  echo "▶ $n. $s"
  [[ "$DRY" == 0 ]] || continue
  if ! bash "steps/$s.sh"; then
    echo "✗ 第 $n 步失败，状态已保留。修复后: ./run-all.sh --from $n --with-ext"
    exit 1
  fi
done
[[ "$DRY" == 0 ]] || exit 0
echo '════ 平台总览（不输出凭据）════'
for key in XBD_NS_SEASHORE XBD_NS_AURORA XBD_AGENT_SCOUT XBD_AGENT_CS_SEASHORE XBD_AGENT_LOGISTICS XBD_AGENT_CS_AURORA XBD_TEAM_1 XBD_RUN_1 XBD_ENDPOINT_SLUG XBD_APPROVAL_1 XBD_AUTOMATION_1; do
  echo "$key=$(state_get "$key")"
done
echo '完成。配置资源复用；聊天轮次、工单、流程运行、审批按业务增量创建。'
