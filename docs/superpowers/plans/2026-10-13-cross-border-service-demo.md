# 跨境电商 Service 控制面 Demo 实施计划

> 编号已同步为 Step 01–13。本文保留早期设计与实施过程；当前可执行命令、API 和验收范围以 [Demo README](../../../demo/cross-border-commerce/README.md) 与 [验证记录](../../../demo/cross-border-commerce/verification.md) 为准。

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在教程仓库根目录新建 `demo/cross-border-commerce/`，用 REST API 编排循序渐进演示构建跨境电商 Agent 多租户平台（01–13 连续编号，共 13 步），全程实测。

**Architecture:** 每步 Markdown 教程 + 同名 bash 脚本成对；`lib/common.sh` 提供 api 封装/先查后建/断言原语；`.state.env` 在步骤间传递资源 ID；`run-all.sh` 一键编排支持断点续跑。所有文档示例响应回填真实运行输出。

**Tech Stack:** bash + curl + jq（零其他依赖）；被测系统为本地 agentscope-service dev 栈（Gateway 18080，Go 控制面 aistiod + Java 数据面/调度面）。

**Spec:** `docs/superpowers/specs/2026-10-13-cross-border-service-demo-design.md`

## 2026-10-13 续接状态

- Task 11：人工审批脚本/教程完成，多次实测通过；采用工单显式共享。
- Task 12：Automation 脚本/教程完成，异步测试触发与幂等验证通过；默认停用。
- Task 13：运行入口与可逆停用入口完成，参数检查和停用/恢复实测通过。保留历史与配置，未执行全量归档。
- Task 14：**未完成**。第一遍 Step 07 明确遇到模型 `AllocationQuota.FreeTierOnly`；用户选择保留额度阻塞，未跑第二遍。不能按本计划的预期结果宣称全绿。
- Task 15：Demo 总览、根 README 挂接与验证记录完成。
- 详细证据：[verification.md](../../../demo/cross-border-commerce/verification.md)。下方任务框和命令是原计划，实际结果以该记录为准。

## Global Constraints

- **实测铁律**：文档中每个示例响应必须来自真实运行输出（截断超长 ID、脱敏 token）；实测与预期不符时以实测为准，并在该步 `.md` 用 `> **注意**` 记录差异。
- **资源命名**：统一 `xbd-` 前缀（如 `xbd-seashore-cs-agent`）；幂等键 `xbd-{step}-{purpose}-001`（重试沿用同键）。
- **认证约定**：平台用户 JWT（`Authorization: Bearer`，登录响应取 `.token` 字段）；多租户作用域：product API（`/api/agents`、`/api/environments`、`/api/sessions`）用 `X-AgentScope-Tenant/Namespace` 请求头；v1 协作 API（teams/issues/orchestration-definitions/automations）沿用官方 smoke.sh 模式在 body 中带 `"tenant":"default","namespace":"<ns>"` 字段。demo 中 tenant 固定 `default`（部署级配置）。
- **作用域冲突禁令**：同一请求不得同时通过 header 和 body 传递不一致的 tenant/namespace（服务端 400）。v1 body 带作用域时，脚本先 `scope_as "" ""` 清空 header。
- **脚本骨架**（每步脚本统一）：

```bash
#!/usr/bin/env bash
# step-NN: <主题>
set -euo pipefail
cd "$(dirname "$0")/.."
source lib/common.sh
require_env
```

- **文档模板**（每步 `.md` 统一结构）：YAML frontmatter（`step`/`title`）→ `# Step NN · 标题` → `> 本步导读：…` → mermaid 图（导览或时序，下配 `*图 N-M：…*` 斜体图题）→ 正文小节（问题式 H2，curl 命令与脚本一致，响应回填实测）→ 需要处 `> **注意**` 框 → `## 本步小结`（编号要点）→ `**验收清单**`（`- ☐` 列表）。
- **提交格式**：`demo: 中文描述` + 尾行 `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`。
- **可移植性**：不使用 GNU 专属选项（`sed -i` 用重建文件法，SSE 用 `curl --max-time`）；jq 缺失字段用 `// empty` 显式失败而不是静默空值。
- **模型依赖**：step-04/06/07/08 与延伸步的 Agent 真实回复依赖 `DASHSCOPE_API_KEY`（dev 栎启动时已注入）；脚本在模型轮次前检查该变量，缺失时明确报错提示而非静默挂起。

## Review Focus

1. **响应字段名与假设不符**（如 `.id` vs `.team.id`）：所有字段提取用 `jq -er`，解析失败即报错退出；每个任务的实测步骤逐项核对字段名并以实测为准修正。
2. **DASHSCOPE_API_KEY 缺失导致 Agent 轮次静默不执行**（官方 smoke.sh 的行为是跳过）：依赖真实回复的步骤必须在脚本开头显式检查该变量并给出人话报错。
3. **作用域通道混用**：header 与 body 同时传不一致的作用域会 400；遵守上方认证约定的通道分工，`scope_as "" ""` 在调 v1 body 作用域 API 前清空。
4. **重复执行产生重复资源**：一切创建走 `ensure_*` 先查后建；每任务实测时必须连跑两遍脚本验证第二遍全部 `↺ 复用`。
5. **macOS/Linux 工具差异**：禁用 `sed -i` 原地编辑与 GNU `timeout`；ci 无关但读者环境未知。

---

### Task 1: 环境启动与栈健康验证

**Files:**
- 无仓库文件改动（产出可运行的本地 dev 栈与验证记录）

**Interfaces:**
- Produces: 运行中的 agentscope-service 栈（http://localhost:18080）、已验证的种子账号（admin/alice/bob）、`DASHSCOPE_API_KEY` 已注入的环境

- [ ] **Step 1: 检查前置条件**

```bash
docker info >/dev/null && echo "docker OK"
printenv DASHSCOPE_API_KEY >/dev/null && echo "key OK" || echo "需要 export DASHSCOPE_API_KEY=sk-xxx（问用户要）"
```

缺 `DASHSCOPE_API_KEY` 时停下向用户索取，不得继续（step-04 起依赖真实模型回复）。

- [ ] **Step 2: 启动 dev 栈**

```bash
cd /Users/ybak/work/code/agentscope/agentscope-java/agentscope-service
scripts/dev-down.sh && BUILDER_REBUILD=1 scripts/dev-up.sh
```

预期：脚本自检 cp/rt/dp 三 schema 后报告成功；`.dev-stack/` 出现日志。首次构建可能 10-30 分钟。

- [ ] **Step 3: 验证栈与种子账号**

```bash
BASE=http://localhost:18080
curl -sf $BASE/api/v1/version | jq .            # 栈版本可达
for u in admin alice bob; do
  curl -sf -X POST $BASE/api/auth/login -H 'Content-Type: application/json' \
    -d "{\"username\":\"$u\",\"password\":\"$u\"}" | jq -r .token | head -c 20 && echo " <- $u 登录 OK"
done
```

三个账号均能取到 token 才算通过。

- [ ] **Step 4: 跑官方 smoke 确认端到端健康**

```bash
cd /Users/ybak/work/code/agentscope/agentscope-java/agentscope-service && scripts/smoke.sh
```

预期末行 `==> smoke OK`。失败先修环境，不带病进入后续任务。

- [ ] **Step 5: 记录实测基线**

把 `/api/v1/version` 真实响应、登录响应完整 JSON 记入工作笔记（后续文档回填用）。

---

### Task 2: demo 目录骨架与 lib/common.sh

**Files:**
- Create: `demo/cross-border-commerce/lib/common.sh`
- Create: `demo/cross-border-commerce/.env.example`
- Create: `demo/cross-border-commerce/steps/.gitkeep`
- Modify: `.gitignore`（追加两行）

**Interfaces:**
- Produces（后续所有任务依赖的 common.sh 契约）:
  - `require_env` — 检查 curl/jq、服务可达（`GET /api/v1/version`）、加载 `.env` 与 `.state.env`
  - `login_as USER PASS STATE_KEY` — 登录缓存 JWT；失败 `return 1`
  - `scope_as TENANT NS` — 设置后续 `api` 的作用域请求头；`scope_as "" ""` 清空
  - `api METHOD PATH [BODY] [TOKEN_KEY]` — 成功输出响应体；≥400 打印状态与响应后 `exit 1`
  - `api_raw METHOD PATH [BODY] [TOKEN_KEY]` — 首行状态码、其余为响应体；永不退出（负向断言用）
  - `state_get KEY [DEFAULT]` / `state_set KEY VAL` — `.state.env` 读写
  - `find_id LIST_JSON NAME` — 在列表 JSON 中按 `.name` 匹配取 `.id`（宽容 `.items`/数组两种结构）
  - `ensure_res STATE_KEY NAME LIST_PATH CREATE_PATH BODY [TOKEN_KEY]` — 先查后建
  - `ensure_namespace NAME DISPLAY OWNER` — namespace 级先查后建
  - `assert_eq A B LABEL` / `assert_ne A B LABEL` / `assert_contains HAY LABEL…` / `assert_status GOT WANT LABEL`
  - `idem STEP PURPOSE` — 输出 `xbd-{step}-{purpose}-001`
  - 约定 TOKEN key：`XBD_TOKEN_ADMIN` / `XBD_TOKEN_ALICE` / `XBD_TOKEN_BOB`

- [ ] **Step 1: 写 .env.example 与 .gitignore**

`.env.example` 内容：

```bash
# 复制为 .env 并按需修改；.env 已被 .gitignore 忽略
BASE_URL=http://localhost:18080
ADMIN_USER=admin
ADMIN_PASS=admin
# 商家种子账号密码与用户名相同（alice/alice、bob/bob），脚本内置
```

`.gitignore` 追加：

```
demo/cross-border-commerce/.env
demo/cross-border-commerce/.state.env
```

- [ ] **Step 2: 写 lib/common.sh 完整实现**

```bash
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

_xbd_curl() { # 内部：拼 curl 参数；$1=是否带 body $2=METHOD $3=PATH $4=BODY $5=TOKEN_KEY -> 输出"状态码\n响应体"
  local token; token="$(state_get "$5")"
  local args=(-sS -X "$2" "$BASE_URL$3"
    -H "Authorization: Bearer $token" -H 'Content-Type: application/json')
  [[ -n "$XBD_SCOPE_TENANT" ]] && args+=(-H "X-AgentScope-Tenant: $XBD_SCOPE_TENANT")
  [[ -n "$XBD_SCOPE_NS" ]]     && args+=(-H "X-AgentScope-Namespace: $XBD_SCOPE_NS")
  [[ -n "$4" ]] && args+=(-d "$4")
  local out; out=$(curl "${args[@]}" -w '\n%{http_code}') || { echo "999"; echo "✗ 网络错误: $2 $3"; return 0; }
  printf '%s\n%s' "${out##*$'\n'}" "${out%$'\n'*}"; }

api() { local out status
  out=$(_xbd_curl x "$1" "$2" "${3:-}" "${4:-XBD_TOKEN_ADMIN}")
  status=$(head -1 <<<"$out")
  if [[ "$status" -ge 400 ]]; then
    echo "✗ API $status [$1 $2]"; sed '1d' <<<"$out"; exit 1; fi
  sed '1d' <<<"$out"; }

api_raw() { _xbd_curl x "$1" "$2" "${3:-}" "${4:-XBD_TOKEN_ADMIN}"; }

find_id() { local list="$1" name="$2"
  jq -r --arg n "$name" '(.items? // .namespaces? // . // [])[]? | select(.name? == $n) | .id? // empty' \
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
```

- [ ] **Step 3: 实测冒烟验证 common.sh**

```bash
cd demo/cross-border-commerce
bash -c 'source lib/common.sh; require_env; login_as admin admin XBD_TOKEN_ADMIN; \
  api GET /api/auth/me | jq -r .username; scope_as default default; \
  api_raw GET /api/v1/namespaces/nonexistent | head -1'
```

预期输出 `admin` 和一个 4xx 状态码。同时核对：`GET /api/auth/me` 的用户名字段名、`me/scope`、`GET /api/environments` 与 `GET /api/agents`、`GET /api/sessions` 的列表 JSON 结构（数组还是 `{items:[]}`，供 `find_id` 修正）、namespace 404 的真实状态码。**字段名不符则修 `find_id`/`_xbd_curl` 后复测。**

- [ ] **Step 4: 提交**

```bash
git add demo .gitignore
git commit -m "demo: 新增跨境电商 demo 目录骨架与 common.sh 公共库

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 3: step-01 平台初始化与身份体系

**Files:**
- Create: `demo/cross-border-commerce/steps/step-01-platform-init.sh`
- Create: `demo/cross-border-commerce/steps/step-01-platform-init.md`

**Interfaces:**
- Consumes: Task 2 全部 common.sh 契约
- Produces: state `XBD_TOKEN_ADMIN/XBD_TOKEN_ALICE/XBD_TOKEN_BOB`（JWT）、`XBD_ADMIN_ID`（admin userId）

- [ ] **Step 1: 写脚本**

```bash
#!/usr/bin/env bash
# step-01: 平台初始化与身份体系
set -euo pipefail
cd "$(dirname "$0")/.."
source lib/common.sh
require_env
step_header "Step 01 平台初始化与身份体系"

# 1. 栈版本
echo "--- 控制面版本"
api GET /api/v1/version | jq .
echo "  ✓ 栈可达: $BASE_URL"

# 2. admin 登录
echo "--- 平台运营方登录"
login_as "${ADMIN_USER:-admin}" "${ADMIN_PASS:-admin}" XBD_TOKEN_ADMIN \
  || { echo "✗ admin 登录失败"; exit 1; }
echo "  ✓ admin 登录成功"

# 3. 当前身份与作用域
ME=$(api GET /api/auth/me)
ADMIN_ID=$(jq -er '.userId // .id' <<<"$ME") || { echo "✗ /api/auth/me 无 userId 字段:"; echo "$ME"; exit 1; }
assert_eq "$(jq -r '.username // .name' <<<"$ME")" "${ADMIN_USER:-admin}" "admin 身份确认"
state_set XBD_ADMIN_ID "$ADMIN_ID"

SCOPE=$(api GET /api/v1/me/scope)
echo "  ✓ 当前作用域: $(jq -c . <<<"$SCOPE")"

# 4. 种子账号可用性（缺失则 admin 兜底创建）
echo "--- 商家账号"
for u in alice bob; do
  key="XBD_TOKEN_$(echo "$u" | tr 'a-z' 'A-Z')"
  if login_as "$u" "$u" "$key"; then
    echo "  ✓ 种子账号 $u 可登录"
  else
    api POST /api/admin/users "{\"username\":\"$u\",\"password\":\"$u\"}" >/dev/null \
      && login_as "$u" "$u" "$key" \
      || { echo "✗ 账号 $u 不可用且创建失败"; exit 1; }
    echo "  + 创建商家账号 $u"
  fi
done

echo ""
echo "本步产出: 三个账号 JWT 已缓存（.state.env）；XBD_ADMIN_ID=$ADMIN_ID"
```

- [ ] **Step 2: 实测执行与字段核对**

```bash
bash steps/step-01-platform-init.sh && echo "第一遍 OK" && bash steps/step-01-platform-init.sh && echo "第二遍幂等 OK"
```

实测确认点：`/api/auth/me` 身份字段名（`userId`/`id`、`username`/`name`）；`/api/v1/me/scope` 响应结构；种子账号创建 body 字段（`POST /api/admin/users` 是否需要 `roles`/`displayName`，409 已存在时如何表现）。不符则修脚本，连跑两遍全绿。

- [ ] **Step 3: 写文档**

frontmatter `step: "01"`、`title: 平台初始化与身份体系`。内容要点：导读（平台运营方视角：开平台第一件事是确认地基与身份体系）；mermaid `flowchart LR` 导览图（你的需求→平台初始化→{健康检查/登录认证/作用域概念/账号准备}→可编排的起点）；正文四节（问题式标题）：「平台起来了吗：版本与健康」「运营方是谁：登录与身份」「我的请求作用域是谁：tenant 与 namespace」「商家账号就位：种子账号与兜底创建」——curl 命令与脚本一致，响应回填 Task 1/本步实测输出；`> **注意**` 框说明 tenant 为部署级配置（`AISTIO_DEFAULT_TENANT`）与教程 31 章 API 差异；小结 3-4 条；验收清单（栈版本可查/admin 登录/me 返回身份/三账号可登录/连跑幂等）。

- [ ] **Step 4: 提交**

```bash
git add steps/step-01-platform-init.*
git commit -m "demo: step-01 平台初始化与身份体系（实测通过）

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 4: step-02 商家入驻

**Files:**
- Create: `demo/cross-border-commerce/steps/step-02-tenant-onboarding.sh`
- Create: `demo/cross-border-commerce/steps/step-02-tenant-onboarding.md`

**Interfaces:**
- Consumes: `ensure_namespace`、`XBD_TOKEN_ADMIN/ALICE/BOB`
- Produces: state `XBD_NS_SEASHORE=seashore-main`、`XBD_NS_AURORA=aurora-main`

- [ ] **Step 1: 写脚本**

```bash
#!/usr/bin/env bash
# step-02: 商家入驻 —— namespace 即租户单元
set -euo pipefail
cd "$(dirname "$0")/.."
source lib/common.sh
require_env
step_header "Step 02 商家入驻"

login_as "${ADMIN_USER:-admin}" "${ADMIN_PASS:-admin}" XBD_TOKEN_ADMIN

# 1. 平台为两家商家开立 namespace（先查后建）
echo "--- 创建商家 namespace"
ensure_namespace "seashore-main" "海岸优品（家居出海）" "alice"
ensure_namespace "aurora-main"   "极光数码（3C 配件出海）" "bob"
state_set XBD_NS_SEASHORE seashore-main
state_set XBD_NS_AURORA   aurora-main

# 2. 商家视角验证：只见自己的租户单元
echo "--- 商家视角验证"
for u in alice bob; do
  key="XBD_TOKEN_$(echo "$u" | tr 'a-z' 'A-Z')"
  login_as "$u" "$u" "$key"
  NS=$(api GET /api/v1/me/namespaces "" "$key")
  own="$u-main"
  assert_contains "$NS" "$own" "$u 可见自己的 namespace（$own）"
  other=$([[ "$u" == "alice" ]] && echo aurora-main || echo seashore-main)
  if grep -q "$other" <<<"$NS"; then
    echo "✗ 隔离异常：$u 竟可见 $other"; echo "$NS"; exit 1
  fi
  echo "  ✓ $u 不可见 $other"
done

# 3. owner 信息回读
scope_as "" ""
NS_DETAIL=$(api GET "/api/v1/namespaces/seashore-main")
echo "$NS_DETAIL" | jq '.namespace | {name, displayName, owner, kind}'
echo ""
echo "本步产出: XBD_NS_SEASHORE=$(state_get XBD_NS_SEASHORE) / XBD_NS_AURORA=$(state_get XBD_NS_AURORA)"
```

- [ ] **Step 2: 实测执行与字段核对**

```bash
bash steps/step-02-tenant-onboarding.sh && bash steps/step-02-tenant-onboarding.sh && echo "幂等 OK"
```

实测确认点：`POST /api/v1/namespaces` 的 owner 字段取 username 还是 userId、members 结构（`{user:[roles]}`）、重复创建的状态码（409/200）；`GET /api/v1/me/namespaces` 响应结构（personal namespace 是否同时列出——文档如实呈现）；namespace 详情响应 `.namespace` 包裹层级。不符则修 `ensure_namespace`。

- [ ] **Step 3: 写文档**

要点：导读（「入驻」在平台上的含义：namespace=租户工作区）；mermaid 时序图（admin→控制面：创建两个 namespace；alice/bob→控制面：登录并各自只看到自己的）；正文三节：「开立租户单元：POST namespaces」「隔离的第一课：me/namespaces 的可见性」「回读租户档案」；`> **注意**` 框：当前版本 tenant 为部署级配置、多租户隔离由 namespace+成员角色实现（spec §2.2）；小结；验收清单（两 namespace 存在/隔离断言通过/连跑幂等）。

- [ ] **Step 4: 提交**

```bash
git add steps/step-02-tenant-onboarding.*
git commit -m "demo: step-02 商家入驻 namespace 即租户单元（实测通过）

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 5: step-03 商家 Agent 矩阵

**Files:**
- Create: `demo/cross-border-commerce/steps/step-03-agent-matrix.sh`
- Create: `demo/cross-border-commerce/steps/step-03-agent-matrix.md`

**Interfaces:**
- Consumes: `ensure_res`、state `XBD_NS_SEASHORE/XBD_NS_AURORA`、商家 JWT
- Produces: state `XBD_ENV_SEASHORE`（环境 ID）、`XBD_AGENT_SCOUT`（选品）、`XBD_AGENT_CS_SEASHORE`（海岸客服）、`XBD_AGENT_LOGISTICS`（海岸物流，Task 8 Team 成员用）、`XBD_AGENT_CS_AURORA`（极光客服）

- [ ] **Step 1: 写脚本**

```bash
#!/usr/bin/env bash
# step-03: 商家 Agent 矩阵 —— 同能力不同租户配置
set -euo pipefail
cd "$(dirname "$0")/.."
source lib/common.sh
require_env
step_header "Step 03 商家 Agent 矩阵"

: "${DASHSCOPE_API_KEY:?✗ 缺少 DASHSCOPE_API_KEY —— Agent 无法真实运行，请重启 dev 栈并注入}"
MODEL="${XBD_MODEL:-qwen-plus}"

# 1. 海岸优品：环境 + 三 Agent（选品/客服/物流）
login_as alice alice XBD_TOKEN_ALICE
scope_as "${XBD_TENANT}" "seashore-main"
echo "--- 海岸优品（seashore-main）"
ensure_res XBD_ENV_SEASHORE "xbd-seashore-env" /api/environments /api/environments \
  '{"name":"xbd-seashore-env","type":"local"}' XBD_TOKEN_ALICE
ensure_res XBD_AGENT_SCOUT "xbd-seashore-product-scout" /api/agents /api/agents \
  "{\"name\":\"xbd-seashore-product-scout\",\"system\":\"你是海岸优品的跨境选品专员，负责市场调研与选品建议，输出简明中文结论。\",\"model\":\"$MODEL\"}" \
  XBD_TOKEN_ALICE
ensure_res XBD_AGENT_CS_SEASHORE "xbd-seashore-cs-agent" /api/agents /api/agents \
  "{\"name\":\"xbd-seashore-cs-agent\",\"system\":\"你是海岸优品店铺客服，语气亲切专业，只回答与订单、物流、售后相关的问题。\",\"model\":\"$MODEL\"}" \
  XBD_TOKEN_ALICE
ensure_res XBD_AGENT_LOGISTICS "xbd-seashore-logistics-agent" /api/agents /api/agents \
  "{\"name\":\"xbd-seashore-logistics-agent\",\"system\":\"你是海岸优品物流专员，负责查询物流状态与异常件处理，输出简洁事实。\",\"model\":\"$MODEL\"}" \
  XBD_TOKEN_ALICE

# 2. 极光数码：同名能力、不同租户配置（只建客服）
login_as bob bob XBD_TOKEN_BOB
scope_as "${XBD_TENANT}" "aurora-main"
echo "--- 极光数码（aurora-main）"
ensure_res XBD_AGENT_CS_AURORA "xbd-aurora-cs-agent" /api/agents /api/agents \
  "{\"name\":\"xbd-aurora-cs-agent\",\"system\":\"你是极光数码店铺客服，风格活泼年轻化，专注 3C 配件售前售后。\",\"model\":\"$MODEL\"}" \
  XBD_TOKEN_BOB

# 3. 归属验证：alice 列表里应能看到自家 3 个 Agent，看不到极光的
login_as alice alice XBD_TOKEN_ALICE
scope_as "${XBD_TENANT}" "seashore-main"
LIST=$(api GET /api/agents)
assert_contains "$LIST" "xbd-seashore-cs-agent" "alice 可见自家客服 Agent"
if grep -q "xbd-aurora-cs-agent" <<<"$LIST"; then
  echo "✗ 隔离异常：seashore 作用域下出现 aurora Agent"; exit 1; fi
echo "  ✓ aurora Agent 不在 seashore 作用域内"
echo ""
echo "本步产出: ENV=$(state_get XBD_ENV_SEASHORE) CS=$(state_get XBD_AGENT_CS_SEASHORE)"
```

- [ ] **Step 2: 实测执行与字段核对**

```bash
bash steps/step-03-agent-matrix.sh && bash steps/step-03-agent-matrix.sh && echo "幂等 OK"
```

实测确认点：`/api/agents` 创建与列表是否吃 `X-AgentScope-*` 请求头（若资源仍落 personal namespace，改用 body 通道 `tenant/namespace` 字段或查询参数，以实测为准）；Agent 响应 `.id` 字段名；`type:"local"` 环境在本地是否要求 `BUILDER_ALLOW_LOCAL_ENVIRONMENT`（若 4xx 读 `.dev-stack/` 日志定位）。连跑两遍全绿。

- [ ] **Step 3: 写文档**

要点：导读（同一平台、按租户定制的 Agent 矩阵）；mermaid 图（两家商家的 Agent 矩阵对照）；正文三节：「工具执行环境：Environment」「创建你的第一个租户 Agent」「同名能力、不同人设：跨租户配置对比」（展示两家客服 system 差异与归属验证）；`> **注意**` 框：与教程 30 章 definition 字段差异以实测为准；小结；验收清单。

- [ ] **Step 4: 提交**

```bash
git add steps/step-03-agent-matrix.*
git commit -m "demo: step-03 商家 Agent 矩阵（实测通过）

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 6: step-04 Session 调用面

**Files:**
- Create: `demo/cross-border-commerce/steps/step-04-session-api.sh`
- Create: `demo/cross-border-commerce/steps/step-04-session-api.md`

**Interfaces:**
- Consumes: state `XBD_AGENT_CS_SEASHORE`、`XBD_ENV_SEASHORE`、`XBD_TOKEN_ALICE`
- Produces: state `XBD_SESSION_1`（客服演示 session ID）

- [ ] **Step 1: 写脚本**

```bash
#!/usr/bin/env bash
# step-04: Session 调用面 —— 创建、发消息、事件流
set -euo pipefail
cd "$(dirname "$0")/.."
source lib/common.sh
require_env
step_header "Step 04 Session 调用面"

: "${DASHSCOPE_API_KEY:?✗ 缺少 DASHSCOPE_API_KEY —— 本步需要真实模型回复}"

login_as alice alice XBD_TOKEN_ALICE
scope_as "${XBD_TENANT}" "seashore-main"
AGENT_ID=$(state_get XBD_AGENT_CS_SEASHORE)
ENV_ID=$(state_get XBD_ENV_SEASHORE)

# 1. 创建 Session
echo "--- 创建 Session"
SID=$(api POST /api/sessions "{\"agent\":\"$AGENT_ID\",\"environmentId\":\"$ENV_ID\"}" | jq -er '.id') \
  || { echo "✗ session 创建响应无 .id"; exit 1; }
state_set XBD_SESSION_1 "$SID"
echo "  + session=$SID"

# 2. 提交客户咨询
echo "--- 提交 user.message"
api POST "/api/sessions/$SID/events" \
  '{"events":[{"type":"user.message","payload":{"text":"订单 OD-2049 为什么还没到？预期三天前送达的。"}}]}' >/dev/null
echo "  ✓ 已提交咨询"

# 3. SSE 收流（限时 90s，落盘供文档引用）
echo "--- SSE 事件流（至多 90s）"
curl -sN --max-time 90 "$BASE_URL/api/sessions/$SID/events/stream" \
  -H "Authorization: Bearer $(state_get XBD_TOKEN_ALICE)" \
  -H "X-AgentScope-Tenant: ${XBD_TENANT}" -H "X-AgentScope-Namespace: seashore-main" \
  > /tmp/xbd-step04-sse.log || true
wc -l < /tmp/xbd-step04-sse.log | xargs -I{} echo "  收到 {} 行 SSE"

# 4. 轮询事件终态（完成类事件类型以实测为准，先按常见命名探测）
echo "--- 轮询终态"
FINAL=""
for i in $(seq 1 60); do
  EV=$(api GET "/api/sessions/$SID/events")
  FINAL=$(jq -r '[.[]? // .events[]? | (.type // "")] | map(select(test("complete|finish|idle|turn"))) | .[0] // empty' <<<"$EV" 2>/dev/null || true)
  [[ -n "$FINAL" ]] && break
  sleep 2
done
[[ -n "$FINAL" ]] && echo "  ✓ 终态事件: $FINAL" || echo "  ⚠ 120s 内未探测到终态事件（检查模型连通性）"

# 5. 回合消息回读
MSGS=$(api GET "/api/sessions/$SID/messages" 2>/dev/null || api GET "/api/sessions/$SID/events")
REPLY=$(jq -r '[.[]? // .events[]? // .messages[]? | (.payload.text // .text // empty)] | last // empty' <<<"$MSGS" 2>/dev/null || true)
[[ -n "$REPLY" ]] && { echo "  ✓ Agent 回复（截断）: ${REPLY:0:80}…"; } || echo "  ⚠ 未能提取回复文本（字段名以实测为准修正 jq）"
echo ""
echo "本步产出: XBD_SESSION_1=$SID；SSE 原文在 /tmp/xbd-step04-sse.log"
```

- [ ] **Step 2: 实测执行与字段核对**

```bash
bash steps/step-04-session-api.sh
```

实测确认点（本步不确定度最高，逐一核对并修脚本）：session 创建 body 字段（`agent`/`environmentId` 已由 smoke 证实）；`POST /events` 的响应（202? 结构?）；SSE 事件类型命名（`user.message` 的应答侧叫什么、终态事件名）；`GET /events` 与 `GET /messages` 的响应包裹结构与回复文本字段；session 重复创建的幂等锚（`external_key` 字段可否作业务幂等键——若可行，给 session 创建加 `external_key: xbd-step04-001` 先查后建）。修正后重跑至拿到真实 Agent 回复。

- [ ] **Step 3: 写文档**

要点：导读（从"配好 Agent"到"真的对话"）；mermaid 时序图（alice→gateway：create session→post events→SSE 流→快照回读）；正文四节：「开一个会话」「把客户咨询交给 Agent」「旁听事件流：SSE」「回读：消息与终态」；回填真实 SSE 片段与回复文本（截断展示）；`> **注意**` 框：本步 API 与教程 31 章 `/api/v1/agent-sessions` 的差异说明（版本演进，spec §2.3）；小结（202≠完成等语义以实测结论写）；验收清单（拿到真实回复/SSE 可回放/事件可查询）。

- [ ] **Step 4: 提交**

```bash
git add steps/step-04-session-api.*
git commit -m "demo: step-04 Session 调用面（实测通过）

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 7: step-05 多租户隔离验证

**Files:**
- Create: `demo/cross-border-commerce/steps/step-05-isolation-check.sh`
- Create: `demo/cross-border-commerce/steps/step-05-isolation-check.md`

**Interfaces:**
- Consumes: state `XBD_AGENT_CS_AURORA`、`XBD_AGENT_CS_SEASHORE`、双方 JWT
- Produces: 无新资源（纯负向断言）

- [ ] **Step 1: 写脚本**

```bash
#!/usr/bin/env bash
# step-05: 多租户隔离验证（负向测试）
set -euo pipefail
cd "$(dirname "$0")/.."
source lib/common.sh
require_env
step_header "Step 05 多租户隔离验证"

login_as alice alice XBD_TOKEN_ALICE

# 1. 越权：alice（seashore 作用域）读极光数码的 Agent
echo "--- 越权访问"
scope_as "${XBD_TENANT}" "aurora-main"
RAW=$(api_raw GET "/api/agents/$(state_get XBD_AGENT_CS_AURORA)" "" XBD_TOKEN_ALICE)
ST=$(head -1 <<<"$RAW"); BODY=$(sed '1d' <<<"$RAW")
echo "  alice 读 aurora Agent -> HTTP $ST"
assert_status "$ST" "404" "越权被拒（若实测为 403，改断言并记录差异）" # 实测定 403/404
assert_contains "$BODY" - "响应体有内容"

# 2. 无作用域：回落 personal namespace，商家资源不可见
echo "--- 无作用域回落"
scope_as "" ""
RAW2=$(api_raw GET "/api/agents/$(state_get XBD_AGENT_CS_SEASHORE)" "" XBD_TOKEN_ALICE)
ST2=$(head -1 <<<"$RAW2")
echo "  alice 无作用域读 seashore Agent -> HTTP $ST2"
assert_status "$ST2" "404" "无作用域看不到商家资源"

# 3. 正向对照：正确作用域可读
echo "--- 正向对照"
scope_as "${XBD_TENANT}" "seashore-main"
api GET "/api/agents/$(state_get XBD_AGENT_CS_SEASHORE)" | jq -e '.id' >/dev/null
echo "  ✓ 正确作用域读取成功"

# 4. 商家 session 互不可见（列表级隔离）
scope_as "${XBD_TENANT}" "seashore-main"
SLIST=$(api GET /api/sessions)
if grep -q "$(state_get XBD_SESSION_1)" <<<"$SLIST"; then echo "  ✓ 自家 session 可见"; fi
scope_as "${XBD_TENANT}" "aurora-main"
BLIST=$(api GET /api/sessions "" XBD_TOKEN_BOB)
if grep -q "$(state_get XBD_SESSION_1)" <<<"$BLIST"; then
  echo "✗ 隔离异常：bob 可见 seashore session"; exit 1; fi
echo "  ✓ bob 的 session 列表不含 seashore 会话"
echo ""
echo "隔离验证全部通过（结果以实测状态码为准记录）"
```

- [ ] **Step 2: 实测执行与状态码定准**

```bash
bash steps/step-05-isolation-check.sh
```

实测确认点：越权读取的真实状态码（403 还是 404，源码 `namespaceAccessMiddleware` 返回 `ErrNotFound` 疑似 404——以实测为准改断言）；无作用域回落行为；`GET /api/sessions` 列表是否随作用域过滤。**所有断言必须真实失败路径验证过**（可临时把 scope 改错验证断言会红，再改回）。

- [ ] **Step 3: 写文档**

要点：导读（多租户平台的信任基础靠负向测试证明）；mermaid 图（三行对照：越权/无作用域/正确作用域）；正文四节对应脚本四段，每段给真实状态码与响应体；`> **注意**` 框记录 403/404 实测结论与源码依据；小结（隔离三层：作用域解析→namespace 访问→资源归属）；验收清单（四条断言全绿+故意改错 scope 能看到断言红）。

- [ ] **Step 4: 提交**

```bash
git add steps/step-05-isolation-check.*
git commit -m "demo: step-05 多租户隔离验证（实测通过）

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 8: step-06 Team 编排

**Files:**
- Create: `demo/cross-border-commerce/steps/step-06-team-orchestration.sh`
- Create: `demo/cross-border-commerce/steps/step-06-team-orchestration.md`

**Interfaces:**
- Consumes: state `XBD_AGENT_CS_SEASHORE`、`XBD_AGENT_LOGISTICS`、`XBD_TOKEN_ALICE`
- Produces: state `XBD_TEAM_1`、`XBD_ISSUE_1`、`XBD_TASK_1`

- [ ] **Step 1: 写脚本**

```bash
#!/usr/bin/env bash
# step-06: Team 编排 —— 客服协作团队处理升级售后工单
set -euo pipefail
cd "$(dirname "$0")/.."
source lib/common.sh
require_env
step_header "Step 06 Team 编排"

: "${DASHSCOPE_API_KEY:?✗ 缺少 DASHSCOPE_API_KEY —— Team 的 Lead Agent 需要真实模型}"

login_as alice alice XBD_TOKEN_ALICE
scope_as "" ""   # v1 API 用 body 作用域
CS_ID=$(state_get XBD_AGENT_CS_SEASHORE)
LOGI_ID=$(state_get XBD_AGENT_LOGISTICS)

# 1. 建团队（先查后建）
echo "--- 创建客服团队"
TEAM_LIST=$(api GET "/api/v1/teams")
TEAM_ID=$(find_id "$TEAM_LIST" "xbd-seashore-cs-team")
if [[ -z "$TEAM_ID" ]]; then
  TEAM=$(api POST /api/v1/teams "$(jq -n \
    --arg t "${XBD_TENANT}" --arg ns "seashore-main" --arg lead "$CS_ID" \
    '{tenant:$t, namespace:$ns, name:"xbd-seashore-cs-team",
      instructions:"客服 Lead 接待客户，物流问题委派物流专员核实后汇总答复。",
      policy:{maxActiveTasks:8, maxFanout:4},
      leaderAgentRef:$lead}')" )
  TEAM_ID=$(jq -er '.team.id' <<<"$TEAM") || { echo "✗ 响应无 .team.id:"; echo "$TEAM"; exit 1; }
  echo "  + team=$TEAM_ID"
else
  echo "  ↺ 复用 team=$TEAM_ID"
fi
state_set XBD_TEAM_1 "$TEAM_ID"

# 2. 追加物流专员为成员（成员接口字段以实测为准）
echo "--- 添加团队成员"
api POST "/api/v1/teams/$TEAM_ID/members" "$(jq -n --arg a "$LOGI_ID" \
  '{agentId:$a, role:"member", instructions:"负责核实物流时效与异常件状态。"}')" >/dev/null 2>&1 \
  && echo "  + 物流专员已入队" || echo "  ⚠ 成员接口字段不符（实测修正 body）"

# 3. 建 Team-assigned Issue（自动产生 AgentTask）
echo "--- 派发升级工单"
RES=$(api POST /api/v1/issues "$(jq -n \
  --arg t "${XBD_TENANT}" --arg ns "seashore-main" --arg ref "$TEAM_ID" \
  '{tenant:$t, namespace:$ns,
    title:"售后升级：订单 OD-2049 客户投诉物流延迟",
    description:"客户第三次催单。请核实物流实际状态，给出补偿方案与答复口径。",
    assigneeType:"team", assigneeRef:$ref}')")
ISSUE_ID=$(jq -er '.issue.id' <<<"$RES"); TASK_ID=$(jq -er '.agentTask.id' <<<"$RES")
state_set XBD_ISSUE_1 "$ISSUE_ID"; state_set XBD_TASK_1 "$TASK_ID"
echo "  + issue=$ISSUE_ID task=$TASK_ID"

# 4. 轮询 AgentTask 获得执行尝试（照 smoke 模式，至多 60s）
echo "--- 等待 Agent 领取任务"
ATTEMPT=""
for i in $(seq 1 30); do
  TR=$(api GET "/api/v1/agent-tasks/$TASK_ID")
  ATTEMPT=$(jq -r '.task.currentAttemptId // empty' <<<"$TR")
  [[ -n "$ATTEMPT" ]] && break
  sleep 2
done
[[ -n "$ATTEMPT" ]] && echo "  ✓ attempt=$ATTEMPT" \
  || { echo "✗ 60s 内 Agent 未领取任务（检查模型连通性与 Leader Agent 状态）"; exit 1; }

# 5. 追加输入经评论路由（Issue-first 协作）
echo "--- 评论追加输入"
api POST "/api/v1/issues/$ISSUE_ID/comments" \
  '{"content":"补充：客户可接受部分退款，请评估。"}' >/dev/null
echo "  ✓ 评论已路由"

# 6. 概要回读
api GET "/api/v1/issues/$ISSUE_ID/summary" | jq '.summary' | head -20
echo ""
echo "本步产出: XBD_TEAM_1=$TEAM_ID XBD_ISSUE_1=$ISSUE_ID XBD_TASK_1=$TASK_ID"
```

- [ ] **Step 2: 实测执行与字段核对**

```bash
bash steps/step-06-team-orchestration.sh && bash steps/step-06-team-orchestration.sh && echo "幂等 OK"
```

实测确认点：`POST /api/v1/teams` 是否接受 `instructions` 字段（smoke 未带）；成员接口真实路径与 body 字段（`/members` 的 `agentId`/`agentRef`/`role` 枚举）；重复添加成员的幂等表现；Issue→AgentTask→attempt 轮询时间（模型慢时放宽到 120s）；评论路由响应结构（`.Routes[0].taskId`，smoke 证实）。第二遍重点：Issue 是新建的（每工单唯一，符合业务）——文档说明本步幂等语义是"团队幂等、工单增量"。

- [ ] **Step 3: 写文档**

要点：导读（团队不是聊天室：任务可派发、评论可路由）；mermaid 时序图（alice→team Issue→AgentTask→Lead Agent→物流成员→summary）；正文五节照脚本；`> **注意**` 框：教程 31 章 `target:{type:"team"}` session 写法在当前版本由 **Issue-first 路径**实现（ADR-0001），两者对照说明；小结；验收清单。

- [ ] **Step 4: 提交**

```bash
git add steps/step-06-team-orchestration.*
git commit -m "demo: step-06 Team 编排 Issue-first 协作（实测通过）

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 9: step-07 Workflow 编排

**Files:**
- Create: `demo/cross-border-commerce/steps/step-07-workflow-pipeline.sh`
- Create: `demo/cross-border-commerce/steps/step-07-workflow-pipeline.md`

**Interfaces:**
- Consumes: state `XBD_AGENT_SCOUT`、`XBD_TOKEN_ALICE`
- Produces: state `XBD_DEF_1`、`XBD_RUN_1`

- [ ] **Step 1: 写脚本**

```bash
#!/usr/bin/env bash
# step-07: Workflow 编排 —— 选品上架流水线
set -euo pipefail
cd "$(dirname "$0")/.."
source lib/common.sh
require_env
step_header "Step 07 Workflow 编排"

login_as alice alice XBD_TOKEN_ALICE
scope_as "" ""
SCOUT_ID=$(state_get XBD_AGENT_SCOUT)

# 1. 定义（先查后建）—— signal 门控最小流水线：调研完成后等人工放行
echo "--- 定义流水线"
DEFS=$(api GET "/api/v1/orchestration-definitions")
DEF_ID=$(find_id "$DEFS" "xbd-seashore-listing-pipeline")
if [[ -z "$DEF_ID" ]]; then
  DEF=$(api POST /api/v1/orchestration-definitions "$(jq -n \
    --arg t "${XBD_TENANT}" --arg ns "seashore-main" --arg agent "$SCOUT_ID" \
    '{tenant:$t, namespace:$ns, name:"xbd-seashore-listing-pipeline",
      description:"选品上架流水线：市场调研 -> 人工放行",
      draftSpec:{nodes:[
        {key:"research", type:"agent", agentRef:$agent},
        {key:"release", type:"signal", signalName:"release"}]}')}")
  DEF_ID=$(jq -er '.definition.id' <<<"$DEF") || { echo "✗ 无 .definition.id:"; echo "$DEF"; exit 1; }
  echo "  + definition=$DEF_ID"
else
  echo "  ↺ 复用 definition=$DEF_ID"
fi
state_set XBD_DEF_1 "$DEF_ID"

# 2. 校验 -> 发布（revision 不可变）
echo "--- 校验与发布"
VAL=$(api POST "/api/v1/orchestration-definitions/$DEF_ID/validate" '{}')
jq -e '.valid == true' <<<"$VAL" >/dev/null && echo "  ✓ 校验通过"
REV_ID=$(api POST "/api/v1/orchestration-definitions/$DEF_ID/publish" | jq -er '.revision.id')
echo "  ✓ 已发布 revision=$REV_ID（不可变）"

# 3. 启动 Run（挂在独立 Issue 上）
echo "--- 启动 Run"
RUN_ROOT=$(api POST /api/v1/issues "$(jq -n \
  --arg t "${XBD_TENANT}" --arg ns "seashore-main" \
  '{tenant:$t, namespace:$ns,
    title:"选品任务：北欧风收纳盒市场调研",
    description:"调研欧美市场北欧风收纳盒的竞争与定价，产出上架建议。"}')")
RUN_ISSUE=$(jq -er '.issue.id' <<<"$RUN_ROOT")
RUN=$(api POST "/api/v1/orchestration-definitions/$DEF_ID/runs" "$(jq -n \
  --arg k "$(idem step-07 run)" --arg issue "$RUN_ISSUE" \
  '{idempotencyKey:$k, issueId:$issue, input:{market:"US", category:"storage-box"}}')")
RUN_ID=$(jq -er '.run.id' <<<"$RUN")
state_set XBD_RUN_1 "$RUN_ID"
echo "  + run=$RUN_ID（research 执行中）"

# 4. 等待 research 完成、Run 进入 waiting（等 signal）
echo "--- 等待人工放行窗口"
for i in $(seq 1 60); do
  ST=$(api GET "/api/v1/orchestration-runs/$RUN_ID" | jq -r '.run.state')
  [[ "$ST" == "waiting" || "$ST" == "succeeded" || "$ST" == "failed" ]] && break
  sleep 3
done
echo "  run.state=$ST"

# 5. 人工放行 -> 完成
if [[ "$ST" == "waiting" ]]; then
  api POST "/api/v1/orchestration-runs/$RUN_ID/signals/release" \
    "$(jq -n --arg k "$(idem step-07 signal)" '{idempotencyKey:$k, payload:{approved:true}}')" >/dev/null
  echo "  ✓ 已放行"
fi
for i in $(seq 1 40); do
  ST=$(api GET "/api/v1/orchestration-runs/$RUN_ID" | jq -r '.run.state')
  [[ "$ST" != "waiting" && "$ST" != "running" ]] && break
  sleep 3
done
assert_eq "$ST" "succeeded" "Run 成功终态"

# 6. 运行轨迹
echo "--- Run 图与事件"
api GET "/api/v1/orchestration-runs/$RUN_ID/graph" | jq '{mode:.run.mode, nodes:[.nodes[]?.key], tasks:(.tasks|length)}'
api GET "/api/v1/orchestration-runs/$RUN_ID/events" | jq '.events | length' | xargs -I{} echo "  事件数: {}"
echo ""
echo "本步产出: XBD_DEF_1=$DEF_ID XBD_RUN_1=$RUN_ID"
```

- [ ] **Step 2: 实测执行与字段核对**

```bash
bash steps/step-07-workflow-pipeline.sh
```

实测确认点：`draftSpec.nodes` 中 agent 节点的字段名（`agentRef`/`agentId`/`binding`？smoke 只证实了 signal 节点；若 agent 节点结构不同，按 validate 报错信息与源码 `orchestration` 包修正，实在不行退化为双 signal 流水线并记录）；validate/publish/runs 响应结构（smoke 证实 `.definition.id`/`.revision.id`/`.run.id`）；node→waiting 的真实流转时长。失败读 `.dev-stack/` 中 aistiod 日志。

- [ ] **Step 3: 写文档**

要点：导读（固定流程用 Workflow：定义→校验→发布→运行）；mermaid 时序图（alice→definitions→validate→publish→runs→signal→succeeded）；正文六节照脚本，附真实 Run 图 JSON（截断）；`> **注意**` 框：节点类型全表见教程 32 章，本步用 agent+signal 最小组合，approval 节点留作读者练习（给出探索提示）；小结；验收清单。

- [ ] **Step 4: 提交**

```bash
git add steps/step-07-workflow-pipeline.*
git commit -m "demo: step-07 Workflow 选品流水线（实测通过）

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 10: step-08 Endpoint 发布与对外调用

**Files:**
- Create: `demo/cross-border-commerce/steps/step-08-endpoint-publish.sh`
- Create: `demo/cross-border-commerce/steps/step-08-endpoint-publish.md`

**Interfaces:**
- Consumes: state `XBD_AGENT_CS_SEASHORE`、`XBD_TOKEN_ALICE`
- Produces: state `XBD_ENDPOINT_SLUG`、`XBD_ENDPOINT_KEY`（对外 API Key 明文，仅存本地 state）

- [ ] **Step 1: 写脚本**

```bash
#!/usr/bin/env bash
# step-08: Endpoint 发布与对外调用
set -euo pipefail
cd "$(dirname "$0")/.."
source lib/common.sh
require_env
step_header "Step 08 Endpoint 发布与对外调用"

: "${DASHSCOPE_API_KEY:?✗ 缺少 DASHSCOPE_API_KEY —— 对外调用需要真实模型}"

login_as alice alice XBD_TOKEN_ALICE
scope_as "" ""
CS_ID=$(state_get XBD_AGENT_CS_SEASHORE)

# 1. 创建 Endpoint（绑定客服 Agent；字段以实测为准）
echo "--- 创建 Endpoint"
EPS=$(api GET "/api/v1/endpoints")
EP_ID=$(find_id "$EPS" "xbd-seashore-cs-endpoint")
if [[ -z "$EP_ID" ]]; then
  EP=$(api POST /api/v1/endpoints "$(jq -n \
    --arg agent "$CS_ID" \
    '{name:"xbd-seashore-cs-endpoint",
      description:"海岸优品店铺客服对外 API",
      inputSchema:{type:"object",properties:{question:{type:"string"}},required:["question"]},
      targetRef:$agent}')" )
  EP_ID=$(jq -er '.id // .endpoint.id' <<<"$EP") || { echo "✗ 创建响应无 id:"; echo "$EP"; exit 1; }
  echo "  + endpoint=$EP_ID"
else
  echo "  ↺ 复用 endpoint=$EP_ID"
fi

# 2. 发布
echo "--- 发布"
SLUG=$(api POST "/api/v1/endpoints/$EP_ID/publish" "$(jq -n --arg r "demo 上线" \
  '{reason:$r}')" | jq -er '.slug // .release.slug // .endpoint.slug') \
  || { echo "✗ publish 响应无 slug（实测修正）"; exit 1; }
state_set XBD_ENDPOINT_SLUG "$SLUG"
echo "  ✓ 已发布 slug=$SLUG"

# 3. 签发对外凭据（明文只在创建响应出现一次）
echo "--- 签发 API Key"
KEY=$(api POST "/api/v1/endpoints/$EP_ID/credentials" \
  '{"name":"xbd-demo-key","scopes":["invoke"]}' | jq -er '.key // .apiKey // .credential.key // .secret') \
  || { echo "✗ 凭据响应无明文 key 字段（实测修正：可能需要 reveal 流程）"; exit 1; }
state_set XBD_ENDPOINT_KEY "$KEY"
echo "  ✓ key 已签发（仅存本地 .state.env）"

# 4. 外部视角调用（Bearer = endpoint key，不带平台 JWT）
echo "--- 外部系统调用"
CONV=$(curl -sS -X POST "$BASE_URL/invoke/v1/endpoints/$SLUG/conversations" \
  -H "Authorization: Bearer $KEY" -H 'Content-Type: application/json' \
  -H "Idempotency-Key: $(idem step-08 conv)" \
  -d '{"title":"店铺首页客服入口","input":{"question":"你们的海绵收纳盒支持海外仓发货吗？"}}')
CID=$(jq -er '.id // .conversation.id' <<<"$CONV") || { echo "✗ 会话响应无 id:"; echo "$CONV"; exit 1; }
echo "  + conversation=$CID"

TURN=$(curl -sS -X POST "$BASE_URL/invoke/v1/conversations/$CID/turns" \
  -H "Authorization: Bearer $KEY" -H 'Content-Type: application/json' \
  -H "Idempotency-Key: $(idem step-08 turn)" \
  -d '{"input":{"question":"发货到德国一般几天？"}}')
echo "$TURN" | jq -c '{id, status}' 2>/dev/null || echo "$TURN" | head -c 200

# 5. 轮询拿到回复
echo "--- 等待回复"
REPLY=""
for i in $(seq 1 60); do
  DET=$(curl -sS "$BASE_URL/invoke/v1/conversations/$CID" -H "Authorization: Bearer $KEY")
  REPLY=$(jq -r '[.messages[]? | (.text // .content // empty)] | last // empty' <<<"$DET" 2>/dev/null || true)
  [[ -n "$REPLY" ]] && break
  sleep 3
done
[[ -n "$REPLY" ]] && echo "  ✓ 回复（截断）: ${REPLY:0:100}…" \
  || { echo "✗ 未取到回复，响应结构如下供修正:"; echo "$DET" | head -c 600; exit 1; }
echo ""
echo "本步产出: slug=$SLUG（key 已存 state，不在日志打印）"
```

- [ ] **Step 2: 实测执行与字段核对**

```bash
bash steps/step-08-endpoint-publish.sh
```

实测确认点（本步 smoke 未覆盖，全部以实测为准）：创建 body 的 target 字段（`targetRef` 出现在源码 update 类请求中，创建时的绑定字段名待定）；publish 请求体（是否需要 targetRef+version，源码 747 行 `{targetRef, version, reason}`）与 slug 返回位置；凭据明文 key 的返回字段（`.key`/`.secret`，或需 `reveal` 二次调用）；`/invoke/v1` 会话与 turn 的请求/响应结构（源码 1435 行 job 为 `{title, description, input}`，conversation 可能同构）；回复文本字段。逐步用 `api_raw`/curl 裸调探明后修脚本至绿。

- [ ] **Step 3: 写文档**

要点：导读（平台闭环的最后一块：把内部 Agent 变成受治理的对外 API）；mermaid 时序图（alice→endpoints→publish→credentials；外部系统→invoke/v1→回复）；正文五节照脚本，突出「与 step-04 的调用面对比」（平台用户 JWT vs Endpoint API Key 两套身份）；`> **注意**` 框：凭据明文只在签发时出现一次的语义、教程 31 章 Application API key 与当前 Endpoint key 的差异；小结；验收清单。

- [ ] **Step 4: 提交**

```bash
git add steps/step-08-endpoint-publish.*
git commit -m "demo: step-08 Endpoint 发布与 invoke 对外调用（实测通过）

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 11: Step 09 —— HITL 人工审批

**Files:**
- Create: `demo/cross-border-commerce/steps/step-09-hitl-approval.sh`
- Create: `demo/cross-border-commerce/steps/step-09-hitl-approval.md`

**Interfaces:**
- Consumes: state `XBD_ISSUE_1`、`XBD_TOKEN_ADMIN`/`XBD_TOKEN_ALICE`
- Produces: state `XBD_APPROVAL_1`

- [ ] **Step 1: 写脚本**

```bash
#!/usr/bin/env bash
# step-09: HITL 人工审批
set -euo pipefail
cd "$(dirname "$0")/.."
source lib/common.sh
require_env
step_header "Step 09 HITL 人工审批"

# 1. alice 发起审批请求（退款需运营审批）
login_as alice alice XBD_TOKEN_ALICE
scope_as "" ""
ISSUE_ID=$(state_get XBD_ISSUE_1)
AP=$(api POST /api/v1/approvals "$(jq -n \
  --arg t "${XBD_TENANT}" --arg ns "seashore-main" --arg ref "$ISSUE_ID" \
  '{tenant:$t, namespace:$ns, targetType:"issue", targetRef:$ref, issueId:$ref,
    approverRef:"admin", reason:"订单 OD-2049 部分退款 $18.90，需平台运营复核"}')")
APPROVAL_ID=$(jq -er '.approval.id' <<<"$AP")
state_set XBD_APPROVAL_1 "$APPROVAL_ID"
echo "  + approval=$APPROVAL_ID（初始版本 $(jq -r '.approval.version' <<<"$AP")）"

# 2. admin 决批（expectedVersion 乐观锁）
login_as "${ADMIN_USER:-admin}" "${ADMIN_PASS:-admin}" XBD_TOKEN_ADMIN
VER=$(api GET "/api/v1/approvals/$APPROVAL_ID" | jq -r '.approval.version')
DEC=$(api POST "/api/v1/approvals/$APPROVAL_ID/decide" "$(jq -n --argjson v "$VER" \
  '{status:"approved", expectedVersion:$v, decision:{note:"同意，走部分退款流程"}}')")
assert_eq "$(jq -r '.approval.status' <<<"$DEC")" "approved" "审批已批准"

# 3. 重复决批应失败（乐观锁演示）
RAW=$(api_raw POST "/api/v1/approvals/$APPROVAL_ID/decide" \
  '{"status":"approved","expectedVersion":1,"decision":{"note":"重复操作"}}')
assert_status "$(head -1 <<<"$RAW")" "409" "重复决批被乐观锁拒绝"

# 4. 回到业务：审批结果以评论同步到工单
login_as alice alice XBD_TOKEN_ALICE
api POST "/api/v1/issues/$ISSUE_ID/comments" \
  '{"content":"退款审批已通过（approval='"$APPROVAL_ID"'），请执行部分退款并回复客户。"}' >/dev/null
echo "  ✓ 审批结论已同步至工单"
echo ""
echo "本步产出: XBD_APPROVAL_1=$APPROVAL_ID"
```

- [ ] **Step 2: 实测执行**

```bash
bash steps/step-09-hitl-approval.sh && bash steps/step-09-hitl-approval.sh
```

实测确认点：approvals 创建/decide 的字段（smoke 证实 `approverRef:"admin"`、`{status, expectedVersion, decision}`、`.approval.status`）；重复决批状态码（409?）；version 字段位置。第二遍会再建一个新 approval（审批请求天然增量，文档说明语义）。工具级 runtime-approvals（Agent 执行中挂起）依赖 Agent 侧工具确认配置，本步不覆盖，文档给探索指引（`/api/v1/agent-tasks/{id}/runtime-approvals` 三段协议：request→decision→ack）。

- [ ] **Step 3: 写文档**

要点：导读（敏感动作留一道人工闸门）；mermaid 时序图（alice 请求→admin 决批→乐观锁拒绝重复→评论回写）；正文四节照脚本；`> **注意**` 框：本步为审批中心路径，工具执行级 HITL（runtime-approvals）见教程 31/33 章与源码协议；小结；验收清单。

- [ ] **Step 4: 提交**

```bash
git add steps/step-09-hitl-approval.*
git commit -m "demo: Step 09 HITL 人工审批（实测通过）

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 12: Step 10 —— Automation 定时任务

**Files:**
- Create: `demo/cross-border-commerce/steps/step-10-automation.sh`
- Create: `demo/cross-border-commerce/steps/step-10-automation.md`

**Interfaces:**
- Consumes: `XBD_TOKEN_ALICE`
- Produces: state `XBD_AUTOMATION_1`

- [ ] **Step 1: 写脚本**

```bash
#!/usr/bin/env bash
# step-10: Automation —— 每日竞品价格监控
set -euo pipefail
cd "$(dirname "$0")/.."
source lib/common.sh
require_env
step_header "Step 10 Automation 定时任务"

login_as alice alice XBD_TOKEN_ALICE
scope_as "" ""

# 1. 创建 Automation（先查后建；cron 触发）
echo "--- 创建自动化"
AUS=$(api GET "/api/v1/automations")
AU_ID=$(find_id "$AUS" "xbd-seashore-price-watch")
if [[ -z "$AU_ID" ]]; then
  AU=$(api POST /api/v1/automations "$(jq -n \
    --arg t "${XBD_TENANT}" --arg ns "seashore-main" \
    '{tenant:$t, namespace:$ns,
      name:"xbd-seashore-price-watch",
      triggerType:"cron", triggerConfig:{schedule:"0 9 * * *"},
      actionType:"create_issue",
      actionConfig:{title:"每日竞品价格监控", description:"汇总竞品 SKU 价格变化并 @ 选品专员复核。"}}')")
  AU_ID=$(jq -er '.automation.id' <<<"$AU")
  echo "  + automation=$AU_ID"
else
  echo "  ↺ 复用 automation=$AU_ID"
fi
state_set XBD_AUTOMATION_1 "$AU_ID"

# 2. 排程预览（cron 语义确认）
echo "--- 排程预览"
api POST "/api/v1/automations/$AU_ID/schedule-preview" '{}' | jq '.nextRuns? // .' | head -10

# 3. 手动触发验证（不影响 cron）
echo "--- 手动触发"
TR=$(api POST "/api/v1/automations/$AU_ID/trigger" -H "Idempotency-Key: $(idem ext-b trigger)" -d '{}' 2>/dev/null \
  || api POST "/api/v1/automations/$AU_ID/trigger?test=true" "$(jq -n --arg k "$(idem ext-b trigger)" '{idempotencyKey:$k}')")
echo "$TR" | jq -c '.run | {status, issueId}' 2>/dev/null || echo "$TR" | head -c 300
assert_contains "$(jq -r '.run.status // ""' <<<"$TR" 2>/dev/null || echo)" "completed" "触发运行完成"

# 4. 运行记录查询
echo "--- 运行记录"
api GET "/api/v1/automations/$AU_ID/runs" | jq '[.runs[]? | {id, status}] | .[0:3]'
echo ""
echo "本步产出: XBD_AUTOMATION_1=$AU_ID"
```

- [ ] **Step 2: 实测执行**

```bash
bash steps/step-10-automation.sh && bash steps/step-10-automation.sh && echo "幂等 OK"
```

实测确认点：`triggerType:"cron"` 的配置字段名（`schedule`/`cron` 表达式；smoke 只证实 webhook 形态）——若 cron 形态报 4xx，读 aistiod 日志修正，仍不通则主体改用 smoke 证实的 webhook 形态、cron 语义用 schedule-preview 输出讲解并记录差异；trigger 的幂等键传递方式（header vs body，smoke 用 header）；`/runs` 与 `/deliveries` 响应结构。

- [ ] **Step 3: 写文档**

要点：导读（让平台自己长出节律：每天 9 点的竞品监控）；mermaid 图（cron→automation→issue→选品专员）；正文四节照脚本；`> **注意**` 框：入站 webhook 自动化与出站 Session webhook 的区别（教程 33 章）；小结；验收清单。

- [ ] **Step 4: 提交**

```bash
git add steps/step-10-automation.*
git commit -m "demo: Step 10 Automation 每日价格监控（实测通过）

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 13: run-all.sh 与 teardown.sh

**Files:**
- Create: `demo/cross-border-commerce/run-all.sh`
- Create: `demo/cross-border-commerce/teardown.sh`

**Interfaces:**
- Consumes: 全部 step 脚本与 common.sh
- Produces: 一键编排入口；清理入口

- [ ] **Step 1: 写 run-all.sh**

```bash
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
```

- [ ] **Step 2: 写 teardown.sh**

```bash
#!/usr/bin/env bash
# teardown.sh — 尽力逆序清理 demo 资源（namespace 与账号保留）
set -euo pipefail
cd "$(dirname "$0")"
source lib/common.sh
require_env
login_as "${ADMIN_USER:-admin}" "${ADMIN_PASS:-admin}" XBD_TOKEN_ADMIN
scope_as "" ""
archive() { local path="$1" label="$2" id="$3"
  [[ -z "$id" || "$id" == "None" ]] && return 0
  api POST "$path" '{}' >/dev/null 2>&1 || api DELETE "$path" >/dev/null 2>&1 \
    || { echo "  ⚠ 清理失败（可手动处理）: $label $id"; return 0; }
  echo "  - 已清理 $label $id"; }

echo "--- 逆序清理 demo 资源"
archive "/api/v1/endpoints/$(state_get XBD_ENDPOINT_SLUG 2>/dev/null || true)/disable" "endpoint" "$(state_get XBD_ENDPOINT_SLUG)"
archive "/api/v1/automations/$(state_get XBD_AUTOMATION_1)" "automation" "$(state_get XBD_AUTOMATION_1)"
archive "/api/v1/orchestration-runs/$(state_get XBD_RUN_1)/cancel" "run" "$(state_get XBD_RUN_1)"
archive "/api/sessions/$(state_get XBD_SESSION_1)/archive" "session" "$(state_get XBD_SESSION_1)"
for a in XBD_AGENT_SCOUT XBD_AGENT_CS_SEASHORE XBD_AGENT_LOGISTICS XBD_AGENT_CS_AURORA; do
  archive "/api/agents/$(state_get "$a")/archive" "agent" "$(state_get "$a")"; done
archive "/api/environments/$(state_get XBD_ENV_SEASHORE)/archive" "environment" "$(state_get XBD_ENV_SEASHORE)"
echo ""
echo "说明: namespace（seashore-main/aurora-main）与账号已保留；Team/Workflow 定义如需删除见各步文档手动路径。"
echo "如需完全重置平台: cd agentscope-service && scripts/dev-down.sh && rm -rf .dev-stack && BUILDER_REBUILD=1 scripts/dev-up.sh"
```

- [ ] **Step 3: 实测（dry-run 与单步）**

```bash
./run-all.sh --list && ./run-all.sh --dry-run && ./run-all.sh --only 1
```

预期：列表 13 行、dry-run 逐条打印不执行、`--only 1` 幂等通过（此时 1-8 步应已完成，跑任意单步都应绿）。

- [ ] **Step 4: 提交**

```bash
chmod +x run-all.sh teardown.sh steps/*.sh
git add run-all.sh teardown.sh
git commit -m "demo: run-all 一键编排与 teardown 清理

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 14: 全量回归（连跑两遍）

**Files:**
- 无新增（回归验证 + 修复）

- [ ] **Step 1: 清场后第一遍全量**

```bash
./teardown.sh && ./run-all.sh
```

预期：13 步全部通过（目标，实际结果见验证记录），末尾打印平台总览。

- [ ] **Step 2: 第二遍幂等回归**

```bash
./run-all.sh
```

预期：所有 ensure 类资源输出 `↺ 复用`；step-04 session 与 step-06 Issue、step-09 approval 为业务增量（文档已注明语义），其余无重复创建。若出现意外重复资源，回对应任务修 `ensure` 匹配逻辑。

- [ ] **Step 3: 记录回归结果**

两遍的输出摘要（各步通过状态、总览）记入工作笔记，供 demo README「验证记录」小节引用。

---

### Task 15: demo README 与根 README 挂接

**Files:**
- Create: `demo/cross-border-commerce/README.md`
- Modify: `README.md`（目录表之后新增「配套动手 Demo」小节）

- [ ] **Step 1: 写 demo README**

结构（对齐全书风格）：徽章行（步骤 13 / 图表 12+ / 零依赖 bash+curl+jq）→ 一句话定位（"书讲原理，demo 动手：用 REST API 循序渐进搭建跨境电商 Agent 多租户平台"）→ mermaid 总览图（平台→两商家→各自 Agent 矩阵→Team/Workflow/Endpoint，节点配色区分租户）→ 场景与角色表（三方角色/账号映射，spec §3）→ 步骤目录表（13 行：文件/主题/API 面）→ 步骤依赖图（mermaid：01→02→03→{04→05, 06, 07, 08}；09–13 按前置依赖执行）→ 前置条件（Docker/JDK/Maven/Go 按官方 README、DASHSCOPE_API_KEY、curl+jq）→ 快速开始（三段代码块：启动栈、cp .env.example .env、./run-all.sh）→ 常用操作（--from/--only/teardown）→ 与教程的关系（第五篇对照表：步骤↔章节；31 章 API 差异声明）→ 验证记录（Task 14 的两遍回归摘要）→ FAQ（栈没起来？key 没设？403/404 差异？重复执行？）。

- [ ] **Step 2: 根 README 挂接**

在根 `README.md` 目录表之后、学习路线表之前插入小节（保持现有中文文案风格）：

```markdown
## 🧪 配套动手 Demo

不想只看书？[demo/cross-border-commerce](demo/cross-border-commerce/README.md)
提供了一个可运行的跨境电商 Agent 多租户平台教学目录：01–13 连续编号，共 13 步，
每步一篇教程配一个可执行脚本，`./run-all.sh` 一键跑通。与第五篇
（第 29-34 章）配套，所有命令基于 agentscope-service 本地栈实测验证。
```

- [ ] **Step 3: 链接与格式自检**

```bash
# 相对链接可达、mermaid 语法渲染检查（VS Code/GitHub 预览）、frontmatter 齐全
ls demo/cross-border-commerce/steps/*.md | wc -l   # 预期 10
grep -L '^---$' demo/cross-border-commerce/steps/*.md   # 预期无输出
```

- [ ] **Step 4: 提交**

```bash
git add demo/cross-border-commerce/README.md README.md
git commit -m "demo: demo README 总览与根 README 挂接

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

## 与 Spec 的两处偏差声明（已按实际约束修正）

1. **step-06 Team 协作路径**：spec §4 沿教程 32 章写"team session"；当前代码 Team 协作真实路径是 **Issue-first**（smoke.sh 证实：`assigneeType:"team"` → 自动 AgentTask），本计划 Task 8 采用实测可跑路径，文档注明与教程写法的对照。
2. **step-03 增建物流专员**：spec 的 Agent 矩阵未含物流角色，Team 编排需要 member Agent，step-03 增建 `xbd-seashore-logistics-agent`（共 4 个 Agent）。
