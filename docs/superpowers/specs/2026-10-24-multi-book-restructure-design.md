# 多书教程库重构设计(书架模式)

- 日期:2026-10-24
- 状态:待评审
- 上一形态:单书工程(《AgentScope Java 2.0:从入门到进阶》,7 篇 44 章,已发布 GitHub Pages)

## 1. 意图与背景

本仓库原为 agentscope-java 单书教程工程:根目录直接是 `chapters/`(书正文)、`assets/`(97 张图)、`demo/`(跨境平台综合实战)、`build/`(自研构建工具链)、`output/site`(Pages 站点产物,CI 构建发布)。

现在扩大教程领域:作者工作需要建设一个**端到端跨境电商智能体多租户平台**,教程库随之升级为**团队赋能书架**——多本"从入门到进阶"完整教程书并排,每本自包含,覆盖平台建设所需技术域(见附录 A 缺口地图)。

## 2. 目标 / 非目标 / 反目标

**目标**
- 仓库结构支持任意多本书并排,每本书自包含(chapters、assets、demo、书级 README)
- `build/` 一步到位改造为多书构建:每本书独立 HTML 站点,PDF 沿用本地构建;站点首页变成书架导航页
- 第一批 5 本书落地:agentscope-java(现有整本搬迁)+ ragflow / copilotkit / langfuse / mcp(骨架:README + 章节规划)
- 根 README 变成书架总导航,内嵌按角色(开发 / 测试 / 运维 / 产品 / 运营)的学习路线
- 现有 agentscope 书的线上阅读不断供:旧 URL 尽量重定向到新路径

**非目标**
- 不写 ragflow / copilotkit / langfuse / mcp 的正文内容(只立骨架)
- 不改 agentscope 书的章节内容本身(纯结构搬迁)
- 不解决 PDF 构建的跨平台问题(EDGE_PATH 仍为 Windows 路径,维持现状)
- 不做站点技术栈更换(仍是自研 site.mjs + Pagefind,不换 VitePress/Docusaurus)

**反目标(什么情况算失败)**
- 搬迁后 agentscope 书在 GitHub 网页端的 mermaid 渲染、相对链接、图片引用任一断链
- Pages 部署失败或站点搜索(Pagefind)失效
- 旧章节 URL 直接 404(无重定向)
- 构建系统出现"agentscope 专属硬编码"残留,加第二本书需要改通用代码

## 3. 约束

- CI(`.github/workflows/pages.yml`)在 push main 时构建并发布,链路不能断
- GitHub 网页端直接渲染 Markdown,是重要的阅读渠道,目录调整必须保持 mermaid/相对链接在 GitHub 上可渲染
- `output/` 不入库(gitignore),构建产物只在 CI 与本地
- 章节源稿 `chapters/` 内部存在 `../assets/images/...`、`../demo/...` 相对引用,搬迁必须整组移动保持相对结构,或同步重写引用
- `build/manifest.mjs` 中的 `SRC_DIR` 指向**仓库外** `../agentscope-java/docs/v2/zh`(官方源文档,只读,用于 `--check` 体检与追溯),搬迁后路径约定需保持可配置

## 4. 已定决策(作者拍板)

| 决策 | 结论 |
|------|------|
| 库定位 | 多本"从入门到进阶"完整书并排(书架),不是个人笔记集 |
| 第一批书 | agentscope-java(存量)+ ragflow、copilotkit、langfuse、mcp(骨架) |
| 构建改造深度 | 一步到位多书化(非"先搬家后改造") |
| 候选池(后续批次) | ai-platform(多租户平台架构,横切书)、spring-ai、dify、vercel-ai-sdk |
| 书单候选逻辑 | 依据附录 A 平台技术缺口地图 |
| 旧 URL 兼容边界 | 兜章节深链(meta-refresh);首页靠书架首屏软着陆;图片直链、GitHub blob 旧路径接受一次性断链(README 内引用随重构更新) |
| 搜索页形态 | 根级全局搜索 `/search.html`,Pagefind 全站索引 + 按书 filter |
| 合入粒度 | 原子单次合入 main(本地全链路预演后一次合入,回滚 git revert 单点) |
| 仓库名 | **改名**(候选 `ai-tutorial`);旧 Pages 域名外链接受失效 |

## 5. 目标目录结构

```
ai-tutorial/
├── README.md                      # 书架总导航:书列表 + 角色学习路线 + 候选池
├── LICENSE / NOTICE.md            # 留在根级(不变)
├── books/
│   ├── agentscope-java/           # 现有整本整体搬入
│   │   ├── README.md              # 书级 README(现根 README 的书相关部分)
│   │   ├── chapters/              # 44 章 + part-intro + preface + 附录
│   │   ├── assets/images/         # 97 张图
│   │   ├── demo/cross-border-commerce/
│   │   └── docs/database/         # 118 张表数据库导览(与 demo 配套,随书走)
│   ├── ragflow/                   # 骨架:README.md(定位/读者/章节规划)
│   ├── copilotkit/                # 同上
│   ├── langfuse/                  # 同上
│   └── mcp/                       # 同上(薄专题册)
├── build/                         # 多书构建工具链(见 §6)
├── docs/
│   ├── superpowers/               # 仓库级规格/计划文档(不变)
│   └── database/ → 移至 books/agentscope-java/docs/database
└── .github/workflows/pages.yml    # 链路不变,构建命令不变
```

**搬迁的完整性要求**:`books/agentscope-java/` 内部相对结构(chapters ↔ assets ↔ demo ↔ docs)保持不变,即整组移动、引用不改;仅根 README 中指向 `chapters/...`、`assets/...` 的链接需要重写为新路径或挪入书级 README。

## 6. 构建系统多书化

现状:`build/manifest.mjs` 是 agentscope 专属书数据(BOOK/PARTS/sources);`build.mjs`(HTML/PDF)与 `site.mjs`(Pages 站点)从仓库根 `chapters/` 读取;`lib.mjs` 通用工具;`clean.mjs` 清洗体检;site/clean 有单测。

目标形态:

- **书注册表**:新增 `build/books/agentscope-java.mjs`(由现 manifest.mjs 演化),导出该书 BOOK/PARTS/sources 及 `bookId`、`srcDir`(仓库外源文档,可配置)、`demoGithubBase` 等书级配置。新骨架书暂不注册构建(见下)。
- **通用化**:`build.mjs` / `site.mjs` 改为接受 book 参数(如 `node site.mjs --book agentscope-java`),内部所有 `ROOT_DIR/chapters`、`OUTPUT_DIR` 路径改为从 book 配置推导:`books/<id>/chapters` → `output/site/<id>/`。
- **书架首页**:site 构建聚合所有已注册书生成 `output/site/index.html`(书卡:封面描述、状态、入口链接);站点 URL 结构从 `/chapters/xx.html` 变为 `/agentscope-java/chapters/xx.html`。
- **搜索**:全局搜索页保留在根 `/search.html`,Pagefind 对整个 `output/site` 建单一索引,结果按书 filter(章节页搜索框 action 仍指向根搜索页;旧路径 `/pagefind/` 与 `/search.html` 因此天然不变,无需重定向)。
- **未完稿书**:骨架书(无 manifest 或标记 `status: "planned"`)只在书架首页显示"规划中"卡片,不生成子站、不进 Pagefind 索引。
- **demo 链接降级**:`GITHUB_BASE` 移入书配置,随搬迁更新为 `books/agentscope-java/demo/...`。
- **测试**:`site.test.mjs` / `clean.test.mjs` 随路径重构同步改写,新增"多书路径推导"用例。

**留给建造者的部分**:book 配置的具体 schema、CLI 参数形态(`--book` vs 位置参数)、manifest 拆分粒度,由建造者依现有代码风格定,不回问作者。

## 7. 发布、旧链接兼容与合入策略

- CI 链路不变:`npm run site` → `output/site` → upload-pages-artifact。改为 site 构建内部产出书架 + 各书子站。
- **重定向边界(已定)**:site 构建时对旧章节路径(`/chapters/*.html`)生成 meta-refresh 跳转页指向新路径(跳转页排除出 Pagefind 索引);`/search.html`、`/pagefind/` 位置不变无需处理。
- **首页软着陆**:新 `/`(书架页)首屏显著放置 agentscope 书大卡片,替代旧首页的直接兼容。
- **接受一次性断链**:旧首页(`/`)、图片直链(`/assets/images/*.png`)、GitHub 网页端 `chapters/*.md` blob 旧路径不做兼容;根 README 与书级 README 内的引用随本次重构全部更新。
- **仓库名(已定:改名)**:候选新名 `ai-tutorial`(与本地目录一致)。影响与执行要点:
  - GitHub 仓库层旧 URL(`github.com/ybak/agentscope-2.0-tutorial`)由 GitHub 自动重定向到新名;Pages 旧域名 `ybak.github.io/agentscope-2.0-tutorial/` **直接失效且无法重定向**,接受已分享旧域名外链丢失。
  - 时机:重构合入 main 并确认 CI 发布成功后立即改名;改名后更新本地 remote、README/文档内所有旧域名链接、书架页展示域名。
- **合入策略(已定:原子单次合入)**:目录搬迁 + 构建多书化 + 重定向页 + README 改写作为一次变更合入 main,不设中间态兼容代码(与 §2 反目标"硬编码残留"一致)。合入前的本地全链路预演为建造者任务:本地跑 `npm run site` 全量构建,逐项核对书架页、agentscope 子站各页、全局搜索与按书 filter、章节页跳转、mermaid 渲染、`build.mjs --check` 体检通过;合入后观察 CI 发布结果,异常即 `git revert` 单点回滚。

## 8. 骨架书定义

每本骨架书包含:`README.md`(定位一句话、目标读者、与平台缺口地图的对应关系、章节规划表、状态:规划中)。章节规划由各书启动时细化,本设计不预设。

- **ragflow**:RAG 平台从入门到进阶;对应缺口:RAG 知识库、知识库运营(切片治理/更新流程/质量巡检)
- **copilotkit**:前端 AI 集成;对应缺口:前端 AI 交互(流式/HITL/工具透明度的前端实现)
- **langfuse**:LLM 可观测与评估;对应缺口:trace/成本监控、数据集与评分、Prompt 版本管理与 A/B(测试+运维+运营三角色共用)
- **mcp**:MCP 协议薄专题;对应缺口:跨框架工具接入标准

## 9. 附录 A:跨境电商智能体多租户平台 · 技术缺口地图

教程库的内容规划依据。✅ 已有覆盖 / 🔜 第一批骨架 / ⭐ 候选池 / — 按需补,不成书。

| 角色 | 技术域 | 具体内容 | 覆盖 |
|------|--------|---------|------|
| 开发 | Agent 编排 | agentscope-java | ✅ agentscope-java 书 |
| 开发 | Java AI 应用 | Spring AI / LangChain4j | ⭐ spring-ai |
| 开发 | RAG 知识库 | RagFlow、pgvector/Milvus | 🔜 ragflow 书 |
| 开发 | 前端 AI 集成 | CopilotKit(React) | 🔜 copilotkit 书 |
| 开发 | 多租户平台架构 | 隔离策略、租户路由、配额计费、网关鉴权 | ⭐ ai-platform(最大缺口) |
| 开发 | 模型层 | 多模型路由、网关、降级、本地 vLLM | 书内 21 章有基础;平台化视角并入 ai-platform |
| 开发 | 协议 | MCP 工具接入 | 🔜 mcp 书 |
| 测试 | Agent 评估 | 轨迹评估、数据集与评分 | ✅ 书内第 39 章 + 🔜 langfuse 书 |
| 测试 | LLM 质量工程 | Prompt 回归、幻觉检测、红队 | 🔜 langfuse 书 |
| 测试 | 性能 | Agent 流式接口压测(JMeter) | — 轻量专题 |
| 运维 | LLM 可观测 | Langfuse trace/成本 | 🔜 langfuse 书 |
| 运维 | 传统运维 | Prometheus/Grafana、K8s、CI/CD | — 团队已有基础,按需 |
| 产品 | AI 产品设计 | 交互模式、意图设计、badcase 管理 | ⭐ 并入 ai-platform 或薄册 |
| 运营 | 知识库运营 | RagFlow 切片治理、更新流程 | 🔜 ragflow 书内章 |
| 运营 | Prompt 运营 | 版本管理、A/B | 🔜 langfuse 书内章 |
| 运营 | 合规 | 跨境数据合规、AI 内容合规 | ⭐ 附录专题 |
