#!/usr/bin/env bash
# lib/common.sh — 跨境电商 demo 公共函数库（依赖 bash/curl/jq）
XBD_DEMO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
XBD_STATE_FILE="$XBD_DEMO_DIR/.state.env"
XBD_ENV_FILE="${XBD_ENV_FILE:-$XBD_DEMO_DIR/.env}"
XBD_SCOPE_TENANT=""; XBD_SCOPE_NS=""

load_env() {
  [[ -f "$XBD_ENV_FILE" ]] && { set -a; source "$XBD_ENV_FILE"; set +a; }
  BASE_URL="${BASE_URL:-http://localhost:18080}"
  XBD_TENANT="${XBD_TENANT:-default}"
}

require_env() {
  command -v curl >/dev/null || { echo "✗ 缺少 curl"; exit 1; }
  command -v jq    >/dev/null || { echo "✗ 缺少 jq"; exit 1; }
  load_env
  curl -sf "$BASE_URL/api/v1/version" >/dev/null 2>&1 \
    || { echo "✗ 服务不可达: $BASE_URL —— 请先启动 agentscope-service dev 栈"; exit 1; }
  touch "$XBD_STATE_FILE"
  # shellcheck disable=SC1090
  source "$XBD_STATE_FILE" 2>/dev/null || true
}

state_get() { local key="$1" def="${2:-}" v
  v=$(grep -E "^${key}=" "$XBD_STATE_FILE" 2>/dev/null | tail -1 | cut -d= -f2-)
  printf '%s' "${v:-$def}"; }

state_set() { local key="$1" val="$2"
  touch "$XBD_STATE_FILE"
  grep -vE "^${key}=" "$XBD_STATE_FILE" > "$XBD_STATE_FILE.tmp" || true
  printf '%s=%s\n' "$key" "$val" >> "$XBD_STATE_FILE.tmp"
  mv "$XBD_STATE_FILE.tmp" "$XBD_STATE_FILE"; }

login_as() { local user="$1" pass="$2" key="$3" resp token
  [[ -n "$(state_get "$key")" ]] && return 0
  resp=$(curl -sS -X POST "$BASE_URL/api/auth/login" -H 'Content-Type: application/json' \
    -d "{\"username\":\"$user\",\"password\":\"$pass\"}") || return 1
  token=$(jq -er '.token' <<<"$resp" 2>/dev/null) || { echo "✗ 登录响应缺 .token: $resp"; return 1; }
  state_set "$key" "$token"; return 0; }

scope_as() { XBD_SCOPE_TENANT="${1:-}"; XBD_SCOPE_NS="${2:-}"; }

scope_q() { # query 作用域通道：v1 协作端点（teams/issues/definitions/automations/approvals）的 GET 必须带
  printf '?tenant=%s&namespace=%s' "${1:-${XBD_TENANT:-default}}" "${2:-}"; }

_xbd_curl() { # 内部：$1=METHOD $2=PATH $3=BODY $4=TOKEN_KEY -> 首行状态码，其余为响应体
  local token; token="$(state_get "$4")"
  local args=(-sS -X "$1" "$BASE_URL$2"
    -H "Authorization: Bearer $token" -H 'Content-Type: application/json')
  [[ -n "$XBD_SCOPE_TENANT" ]] && args+=(-H "X-AgentScope-Tenant: $XBD_SCOPE_TENANT")
  [[ -n "$XBD_SCOPE_NS" ]]     && args+=(-H "X-AgentScope-Namespace: $XBD_SCOPE_NS")
  [[ -n "$3" ]] && args+=(-d "$3")
  local out; out=$(curl "${args[@]}" -w '\n%{http_code}') || { echo "999"; echo "✗ 网络错误: $1 $2"; return 0; }
  printf '%s\n%s' "${out##*$'\n'}" "${out%$'\n'*}"; }

api() { local out status
  out=$(_xbd_curl "$1" "$2" "${3:-}" "${4:-XBD_TOKEN_ADMIN}")
  status=$(head -1 <<<"$out")
  if [[ "$status" -ge 400 ]]; then
    echo "✗ API $status [$1 $2]"; sed '1d' <<<"$out"; exit 1; fi
  sed '1d' <<<"$out"; }

api_raw() { _xbd_curl "$1" "$2" "${3:-}" "${4:-XBD_TOKEN_ADMIN}"; }

find_id() { local list="$1" name="$2"
  jq -r --arg n "$name" '(.items? // .namespaces? // .definitions? // . // [])[]? | select(.name? == $n) | .id? // empty' \
    <<<"$list" 2>/dev/null | tail -1; }

ensure_res() { local key="$1" name="$2" list_path="$3" create_path="$4" body="$5" token_key="${6:-XBD_TOKEN_ADMIN}"
  local existing id created
  existing=$(find_id "$(api GET "$list_path" "" "$token_key")" "$name")
  if [[ -n "$existing" ]]; then state_set "$key" "$existing"; echo "  ↺ 复用 $name ($existing)"; return 0; fi
  created=$(api POST "$create_path" "$body" "$token_key")
  id=$(jq -er '.id // empty' <<<"$created" 2>/dev/null) || { echo "✗ 创建 $name 失败:"; echo "$created"; exit 1; }
  state_set "$key" "$id"; echo "  + 创建 $name ($id)"; }

ensure_namespace() { local name="$1" display="$2" owner="$3" st body
  scope_as "" ""   # v1 API 用 body 作用域通道
  st=$(api_raw GET "/api/v1/namespaces/$name" | head -1)
  if [[ "$st" == "200" ]]; then echo "  ↺ namespace 已存在: $name"; return 0; fi
  body=$(jq -n --arg n "$name" --arg d "$display" --arg o "$owner" --arg t "$XBD_TENANT" \
    '{name:$n, displayName:$d, owner:$o, tenant:$t}')
  api POST /api/v1/namespaces "$body" >/dev/null
  echo "  + 创建 namespace: $name"; }

assert_eq() { [[ "$1" == "$2" ]] || { echo "✗ 断言失败: [$1] != [$2] —— $3"; exit 1; }; echo "  ✓ $3"; }
assert_ne() { [[ "$1" != "$2" ]] || { echo "✗ 断言失败: 值不应为 [$2] —— $3"; exit 1; }; echo "  ✓ $3"; }
assert_contains() { grep -q "$2" <<<"$1" || { echo "✗ 断言失败: 不含 [$2] —— $3"; exit 1; }; echo "  ✓ $3"; }
assert_status() { [[ "$1" == "$2" ]] || { echo "✗ 期望 HTTP $2 实得 $1 —— $3"; exit 1; }; echo "  ✓ HTTP $2 —— $3"; }

idem() { printf 'xbd-%s-%s-001' "$1" "$2"; }
step_header() { echo ""; echo "━━━━ $1 ━━━━"; }
