#!/usr/bin/env bash
# Step 12：Environment 与沙箱（阿里云沙箱 = E2B 兼容 API）。
#   无参      只读核对：当前默认环境、阿里云沙箱配置体检、绑定状态。
#   --create  控制面初始化沙箱环境：POST/PATCH /api/environments，端点与凭据写入
#             environment config（config.apiKey 优先级最高），Dataplane 进程无需配置。
#   --bind    实验 Agent 默认环境切换到沙箱（原环境存入 state，--restore 可恢复）。
#   --run     真实执行验收：开 write 工具→发布→采纳→写文件读回→SESSION 隔离对照。
#   --restore 恢复实验 Agent 的原默认环境。
set -euo pipefail
cd "$(dirname "$0")/.."
source lib/common.sh
require_env

ENV_NAME='xbd-seashore-e2b-lab'
CHAT_A_TITLE='xbd-step12-沙箱写入'
CHAT_B_TITLE='xbd-step12-沙箱隔离'
PROOF_PATH="/workspace/xbd-sandbox-proof.txt"

case "${1:-}" in ''|--create|--bind|--run|--restore) CMD="${1:-}";; *)
  echo '用法: step-12-sandbox.sh [--create|--bind|--run|--restore]'; exit 2;; esac
[[ $# -le 1 ]] || exit 2

step_header 'Step 12 Environment 与阿里云沙箱'
login_as alice alice XBD_TOKEN_ALICE
scope_as "$XBD_TENANT" seashore-main

mask_key() { local v="${1:-}"; if [[ -n "$v" ]]; then echo "${v:0:9}…（已配置，脱敏）"; else echo '（未配置）'; fi; }

cfg_ready() {
  local miss=0
  for v in SANDBOX_API_BASE_URL SANDBOX_DOMAIN SANDBOX_TEMPLATE_ID SANDBOX_API_KEY; do
    if [[ -n "${!v:-}" ]]; then
      [[ "$v" == SANDBOX_API_KEY ]] && echo "  ✓ $v=$(mask_key "${!v}")" || echo "  ✓ $v=${!v}"
    else
      echo "  ✗ $v 未配置（见 demo/.env.example 的 Step 12 段）"; miss=1
    fi
  done
  return "$miss"
}

sandbox_id() { # 已登记沙箱环境 id：state 优先，其次按名查列表
  local sid; sid=$(state_get XBD_ENV_SANDBOX_LAB)
  if [[ -n "$sid" ]]; then echo "$sid"; return; fi
  api GET /api/environments '' XBD_TOKEN_ALICE \
    | jq -r --arg n "$ENV_NAME" '[.[]|select(.name==$n)][0].id // empty'
}

show_env() { # 脱敏展示环境（config.apiKey 不回显明文）
  jq '.config as $orig
      | {id,name,type,ownerId,
         config:((.config // {}) | del(.apiKey)
           + (if (($orig // {}) | has("apiKey")) then {apiKey:"<已写入 config，脱敏>"} else {} end))}'
}

require_lab_agent() {
  AGENT_ID=$(state_get XBD_AGENT_WORKSPACE_LAB)
  [[ -n "$AGENT_ID" ]] || { echo '✗ 先运行 Step 11 创建实验 Agent'; exit 1; }
}

# turn_and_wait CHAT_ID SESSION_ID 消息 —— 提交 Turn 并轮询到本轮结束，输出最终回复。
# 复用旧 Chat 时按事件计数差判断本轮新增，避免旧 idle/回复/错误误判。
turn_and_wait() {
  local chat="$1" sid="$2" msg="$3" ev bi bm be reply mn errn
  ev=$(api GET "/api/v1/sessions/$sid/events?chatId=$chat" '' XBD_TOKEN_ALICE)
  bi=$(jq '[.events[]?|select(.eventType=="session.status_idle")]|length' <<<"$ev")
  bm=$(jq '[.events[]?|select(.eventType=="agent.message")]|length' <<<"$ev")
  be=$(jq '[.events[]?|select((.eventType//"")|test("error|fail";"i"))]|length' <<<"$ev")
  api POST "/api/v1/chats/$chat/turns$(scope_q "$XBD_TENANT" seashore-main)" \
    "$(jq -n --arg m "$msg" '{message:$m}')" XBD_TOKEN_ALICE >/dev/null
  for _ in $(seq 1 90); do
    sleep 3
    ev=$(api GET "/api/v1/sessions/$sid/events?chatId=$chat" '' XBD_TOKEN_ALICE)
    errn=$(jq '[.events[]?|select((.eventType//"")|test("error|fail";"i"))]|length' <<<"$ev")
    if [[ "$errn" -gt "$be" ]]; then
      echo "✗ 本轮出现错误事件，最后一条：" >&2
      jq -c '[.events[]?|select((.eventType//"")|test("error|fail";"i"))]|last' <<<"$ev" >&2
      exit 1
    fi
    mn=$(jq '[.events[]?|select(.eventType=="agent.message")]|length' <<<"$ev")
    reply=$(jq -r '[.events[]?|select(.eventType=="agent.message")]|last|.content // empty' <<<"$ev")
    if [[ "$(jq '[.events[]?|select(.eventType=="session.status_idle")]|length' <<<"$ev")" -gt "$bi" \
          && "$mn" -gt "$bm" && -n "$reply" ]]; then
      echo "$reply"; return 0
    fi
  done
  echo "✗ 270s 内未收到本轮回复，最后 5 个事件：" >&2
  jq -r '.events[-5:][]? | "\(.eventType) \(.content // .error // "")"' <<<"$ev" >&2
  exit 1
}

# ensure_chat 标题 —— 按标题幂等创建/复用 Chat，输出 CHAT_ID 与 SESSION_ID 两行。
ensure_chat() {
  local title="$1" list chat sid
  list=$(api GET "/api/v1/chats$(scope_q "$XBD_TENANT" seashore-main)" '' XBD_TOKEN_ALICE)
  chat=$(jq -r --arg t "$title" '[.items[]?|select(.title==$t)][0].id // empty' <<<"$list")
  if [[ -z "$chat" ]]; then
    chat=$(api POST "/api/v1/chats$(scope_q "$XBD_TENANT" seashore-main)" \
      "$(jq -n --arg a "$AGENT_ID" --arg t "$title" '{agentId:$a,title:$t}')" XBD_TOKEN_ALICE | jq -er '.chat.id')
    echo "  + chat=$chat" >&2
  else
    echo "  ↺ 复用 chat=$chat" >&2
  fi
  sid=$(jq -r --arg c "$chat" '[.items[]?|select(.id==$c)][0].sessionId // empty' <<<"$list")
  [[ -z "$sid" ]] && sid=$(api GET "/api/v1/chats/$chat$(scope_q "$XBD_TENANT" seashore-main)" '' XBD_TOKEN_ALICE | jq -r '.chat.sessionId // empty')
  if [[ -z "$sid" ]]; then
    echo "✗ 未取得 chat=$chat 的 sessionId" >&2
    return 1
  fi
  printf '%s\n%s\n' "$chat" "$sid"
}

case "$CMD" in
'')
  # ---------- 只读核对 ----------
  require_lab_agent
  DEF=$(api GET "/api/v1/agents/$AGENT_ID/definition" '' XBD_TOKEN_ALICE)
  ENV_ID=$(jq -r '.definition.defaultEnvironmentId // empty' <<<"$DEF")
  if [[ -n "$ENV_ID" ]]; then
    api GET "/api/environments/$ENV_ID" '' XBD_TOKEN_ALICE | jq -c '{id,name,type}'
  else
    echo '实验 Agent 未绑定默认环境'
  fi
  echo '上面是实验 Agent 当前默认环境；local 表示服务端执行，type=sandbox 才是独立沙箱边界。'
  echo '--- 阿里云沙箱配置体检（demo/.env）'
  cfg_ready || true
  SID=$(sandbox_id)
  if [[ -n "$SID" ]]; then
    echo '--- 已登记沙箱环境（config 脱敏）'
    api GET "/api/environments/$SID" '' XBD_TOKEN_ALICE | show_env
    [[ "$ENV_ID" == "$SID" ]] \
      && echo "绑定状态：实验 Agent 默认环境已是沙箱，可直接 --run 真实验收" \
      || echo "绑定状态：实验 Agent 仍在 ${ENV_ID}，--bind 切换后 --run 真实验收"
  else
    echo '尚未登记沙箱环境：bash steps/step-12-sandbox.sh --create'
  fi
  ;;

--create)
  echo '--- 阿里云沙箱配置（读 demo/.env，凭据不进 Git）'
  cfg_ready || exit 1
  BODY=$(jq -n --arg n "$ENV_NAME" --arg b "$SANDBOX_API_BASE_URL" --arg d "$SANDBOX_DOMAIN" \
    --arg t "$SANDBOX_TEMPLATE_ID" --arg k "$SANDBOX_API_KEY" \
    '{name:$n, type:"sandbox",
      config:{apiBaseUrl:$b, domain:$d, templateId:$t, workspaceRoot:"/home/user",
              sandboxTimeoutSeconds:300, isolationScope:"SESSION", apiKey:$k}}')
  SID=$(sandbox_id)
  if [[ -z "$SID" ]]; then
    RES=$(api POST /api/environments "$BODY" XBD_TOKEN_ALICE)
    SID=$(jq -er '.id' <<<"$RES")
    echo "  + 登记沙箱环境=$SID"
  else
    # PATCH 的 config 是全量替换；始终以 .env 当前值整体覆盖。
    RES=$(api PATCH "/api/environments/$SID" "$(jq -c '{name,config}' <<<"$BODY")" XBD_TOKEN_ALICE)
    echo "  ↺ 更新沙箱环境=${SID}（config 全量替换为 .env 当前值）"
  fi
  state_set XBD_ENV_SANDBOX_LAB "$SID"
  CHECK=$(api GET "/api/environments/$SID" '' XBD_TOKEN_ALICE)
  assert_eq "$(jq -r '.type' <<<"$CHECK")" sandbox '环境类型已回读'
  assert_eq "$(jq -r '.config.templateId' <<<"$CHECK")" "$SANDBOX_TEMPLATE_ID" '阿里云模板已写入'
  show_env <<<"$CHECK"
  echo '端点与凭据已通过控制面写入 environment config；Dataplane 构建 Agent 时拉取，无需配置或重启。'
  echo '下一步: bash steps/step-12-sandbox.sh --bind'
  ;;

--bind)
  SID=$(sandbox_id)
  [[ -n "$SID" ]] || { echo '✗ 先运行 --create 登记沙箱环境'; exit 1; }
  require_lab_agent
  CURRENT=$(api GET "/api/v1/agents/$AGENT_ID/definition" '' XBD_TOKEN_ALICE)
  CUR=$(jq -r '.definition.defaultEnvironmentId // empty' <<<"$CURRENT")
  if [[ "$CUR" == "$SID" ]]; then
    echo "  ↺ 默认环境已是沙箱=$SID"
  else
    # 首次切换前保存原环境；重复执行不覆盖，保证 --restore 仍回到 local。
    [[ -n "$(state_get XBD_ENV_LAB_PREVIOUS)" ]] || state_set XBD_ENV_LAB_PREVIOUS "$CUR"
    PATCH=$(jq -c --arg env "$SID" '.definition | .defaultEnvironmentId=$env' <<<"$CURRENT")
    api PATCH "/api/v1/agents/$AGENT_ID/definition" "$PATCH" XBD_TOKEN_ALICE >/dev/null
    echo "  + 默认环境 $CUR → ${SID}（原环境已存 XBD_ENV_LAB_PREVIOUS）"
  fi
  CHECK=$(api GET "/api/v1/agents/$AGENT_ID/definition" '' XBD_TOKEN_ALICE)
  assert_eq "$(jq -r '.definition.defaultEnvironmentId' <<<"$CHECK")" "$SID" '默认环境已切换'
  echo '旧 Session 不迁移；沙箱执行发生在 --run 创建的新 Chat 中。'
  echo '下一步: bash steps/step-12-sandbox.sh --run'
  ;;

--run)
  cfg_ready || exit 1
  : "${DASHSCOPE_API_KEY:?✗ 缺少 DASHSCOPE_API_KEY —— 本步需要真实模型回复}"
  SID=$(sandbox_id)
  [[ -n "$SID" ]] || { echo '✗ 先运行 --create 登记沙箱环境'; exit 1; }
  require_lab_agent
  WS_ID=$(state_get XBD_WORKSPACE_LAB)
  [[ -n "$WS_ID" ]] || { echo '✗ 先运行 Step 11 创建实验 Workspace'; exit 1; }
  CUR=$(api GET "/api/v1/agents/$AGENT_ID/definition" '' XBD_TOKEN_ALICE \
    | jq -r '.definition.defaultEnvironmentId // empty')
  [[ "$CUR" == "$SID" ]] || { echo "✗ 实验 Agent 默认环境=${CUR}，先 --bind 切到 $SID"; exit 1; }

  # 1. 实验 Workspace 开启 read+write（其它工具组与 MCP 配置原样保留）
  echo '--- 1. 开启实验 Workspace 的 read/write 工具'
  TOOLS=$(api GET "/api/workspaces/$WS_ID/tools" '' XBD_TOKEN_ALICE)
  HAS_WRITE=$(jq -r '[.tools[]? | select(.type=="agent_toolset")
    | .configs[]? | select(.name=="write" and .enabled==true)] | length > 0' <<<"$TOOLS")
  if [[ "$HAS_WRITE" == "true" ]]; then
    echo '  ↺ write 工具已开启'
  else
    TOOLS_PATCH=$(jq -c '.tools |= map(if .type=="agent_toolset" then
      .configs = ((.configs // [] | map(select(.name!="read" and .name!="write"))) +
        [{name:"read",enabled:true,permissionPolicy:{type:"always_allow"}},
         {name:"write",enabled:true,permissionPolicy:{type:"always_allow"}}])
      else . end)' <<<"$TOOLS")
    api PUT "/api/workspaces/$WS_ID/tools" "$TOOLS_PATCH" XBD_TOKEN_ALICE >/dev/null
    echo '  + read/write 已开启（草稿）'
  fi

  # 2. 发布为版本（内容一致时幂等复用），并让实验 Agent 采纳
  echo '--- 2. 发布并采纳 Workspace 新版本'
  REV=$(api POST "/api/workspaces/$WS_ID/publish" '{}' XBD_TOKEN_ALICE)
  VER=$(jq -er '.version' <<<"$REV"); DIGEST=$(jq -er '.digest' <<<"$REV")
  DEF_JSON=$(api GET "/api/v1/agents/$AGENT_ID/definition" '' XBD_TOKEN_ALICE)
  CURV=$(jq -r '.definition.workspaceBinding.version // 0' <<<"$DEF_JSON")
  if [[ "$CURV" == "$VER" ]]; then
    echo "  ↺ 实验 Agent 已在版本=$VER"
  else
    PATCH=$(jq -c --argjson v "$VER" --arg d "$DIGEST" \
      '.definition | .workspaceBinding.version=$v | .workspaceBinding.digest=$d' <<<"$DEF_JSON")
    api PATCH "/api/v1/agents/$AGENT_ID/definition" "$PATCH" XBD_TOKEN_ALICE >/dev/null
    echo "  + 采纳版本=${VER}（原 ${CURV}）"
  fi
  state_set XBD_WORKSPACE_REV "$VER"

  # 3. Chat A：沙箱内真实写文件并读回
  # 每次验收用全新 Chat/Session：definition（环境、模型、Workspace 版本）只在
  # 新会话构建时生效，复用旧 Chat 会沿用旧配置（见正文"旧 Session 不迁移"）。
  echo '--- 3. Chat A 在沙箱内写入标记文件并读回'
  MARK="XBD-SANDBOX-$(date +%s)"
  mapfile -t IDS_A < <(ensure_chat "${CHAT_A_TITLE}-${MARK}")
  CHAT_A="${IDS_A[0]:-}" SESSION_A="${IDS_A[1]:-}"
  [[ -n "$CHAT_A" && -n "$SESSION_A" ]] || { echo '✗ Chat A 未就绪（缺 chat/sessionId）'; exit 1; }
  echo "  标记: ${MARK}（文件 ${PROOF_PATH}）"
  echo "  chat: ${CHAT_A}"
  REPLY_A=$(turn_and_wait "$CHAT_A" "$SESSION_A" \
    "请用 write_file 工具创建文件 ${PROOF_PATH}，内容恰好为一行：${MARK}。写完后再用 read_file 工具读取该文件，并在最终回复中原样给出文件内容。")
  if [[ "$REPLY_A" == *"$MARK"* ]]; then
    echo '  ✓ 沙箱真实执行：write 后 read 回读到本轮标记'
  else
    echo "✗ Chat A 回复未包含标记，实际回复（截断）: ${REPLY_A:0:200}"; exit 1
  fi

  # 4. Chat B：新会话读同一路径，验证 SESSION 隔离
  echo '--- 4. Chat B 新会话读同一路径（SESSION 隔离对照）'
  mapfile -t IDS_B < <(ensure_chat "${CHAT_B_TITLE}-${MARK}")
  CHAT_B="${IDS_B[0]:-}" SESSION_B="${IDS_B[1]:-}"
  [[ -n "$CHAT_B" && -n "$SESSION_B" ]] || { echo '✗ Chat B 未就绪（缺 chat/sessionId）'; exit 1; }
  REPLY_B=$(turn_and_wait "$CHAT_B" "$SESSION_B" \
    "请用 read_file 工具读取文件 ${PROOF_PATH}，并在最终回复中原样输出文件内容；如果文件不存在或读取失败，请直接说明，不要猜测内容。")
  if [[ "$REPLY_B" != *"$MARK"* ]]; then
    echo '  ✓ SESSION 隔离生效：Chat B 读不到 Chat A 刚写入的标记'
    echo "  Chat B 回复（截断）: ${REPLY_B:0:120}"
  else
    echo "✗ Chat B 读到了 Chat A 的标记，isolationScope 未按 SESSION 隔离"; exit 1
  fi

  echo ''
  echo '本步产出: XBD_ENV_SANDBOX_LAB='"$SID"'  写入/隔离验收已通过（标记 '"$MARK"'）'
  echo '恢复 Agent 原环境: bash steps/step-12-sandbox.sh --restore'
  ;;

--restore)
  PREV=$(state_get XBD_ENV_LAB_PREVIOUS)
  [[ -n "$PREV" ]] || { echo '没有需要恢复的原环境记录'; exit 0; }
  require_lab_agent
  CURRENT=$(api GET "/api/v1/agents/$AGENT_ID/definition" '' XBD_TOKEN_ALICE)
  PATCH=$(jq -c --arg env "$PREV" '.definition | .defaultEnvironmentId=$env' <<<"$CURRENT")
  api PATCH "/api/v1/agents/$AGENT_ID/definition" "$PATCH" XBD_TOKEN_ALICE >/dev/null
  state_set XBD_ENV_LAB_PREVIOUS ''
  echo "  + 默认环境已恢复为 $PREV"
  ;;
esac
