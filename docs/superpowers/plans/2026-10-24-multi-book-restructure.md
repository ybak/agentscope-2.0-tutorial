# 多书教程库重构实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 仓库从单书工程重构为多书书架:`books/` 下每本书自包含,构建系统多书化(书架首页 + 各书子站 + 全局搜索按书 filter + 旧路径重定向),四本骨架书立架。

**Architecture:** 数据与流程分离——书级配置抽到 `build/books/<id>.mjs`,构建脚本(`site.mjs`/`build.mjs`)参数化消费书配置;站点从"根即书"变为"根即书架":`output/site/index.html` 书架页,`output/site/<bookId>/` 各书子站,全局 `search.html` + `pagefind/` 留在根。目录搬迁放在构建参数化完成之后,退化为"改配置 + git mv",风险集中到最后一次全链路预演。

**Tech Stack:** Node.js ESM 脚本(现有自研工具链)、markdown-it、mermaid、pagefind 1.5、GitHub Pages(pages.yml 不变)。

**Spec:** `docs/superpowers/specs/2026-10-24-multi-book-restructure-design.md`

## Global Constraints

- 新仓库名:`ai-tutorial`;demo 链接基址:`https://github.com/ybak/ai-tutorial/blob/main/books/agentscope-java/demo/`(合入后立即改名,短暂 404 窗口已在规格 §7 接受)
- 在线阅读新地址:`https://ybak.github.io/ai-tutorial/agentscope-java/`
- CI 链路不变:pages.yml 跑 `npm run site` → `output/site` → upload-pages-artifact;`output/` 不入库
- `chapters/*.md` 正文零改动(纯搬迁);章节内相对引用 `../assets/`、`../demo/` 靠整组移动保持解析
- PDF 构建的 `EDGE_PATH`(Windows)不动;`SRC_DIR`(仓库外源文档)路径不动
- 站点技术栈不换(自研 site.mjs + Pagefind);mermaid/theme 等 `lib.mjs` 渲染件不动
- 跳转 stub 页必须带 `data-pagefind-ignore`,不引站点 CSS/JS
- 每个任务结束时 `cd build && npm test` 必须绿;T7 之前站点可随时构建(中间态均可用)

## Review Focus

- **书子站内相对路径层级**:章节页在 `<id>/chapters/xx.html`,搜索页在站点根——搜索框 action 必须是 `../../search.html` 而非旧语义 `${rootPrefix}search.html`。测试:T2 步骤 1 的 `test_renderShell_searchHref`。
- **重定向 stub 混入搜索索引**:stub 若无 `data-pagefind-ignore` 会污染全局搜索。测试:T5 步骤 1 的 `test_redirect_stub_ignored_by_pagefind`。
- **planned 书卡片可点击**:骨架书无子站,卡片若渲染成 `<a>` 则 404。测试:T2 步骤 1 的 `test_shelf_planned_card_not_link`。
- **rewriteMarkdownLinks 的 GitHub 降级随书配置**:多书后 demo 链接基址来自 `book.demoGithubBase`,硬编码残留即反目标。测试:T2 步骤 1 的 `test_rewrite_links_github_base_injected`。
- **`--site` 总装幂等**:重复跑 `npm run site` 不得残留上一轮的 redirect stub / 书目录。测试:T5 步骤 1 的 `test_site_rebuild_clears_stale_output`(复用 `fs.rmSync` 清场语义)。

---

### Task 1: 书配置模块、注册表与路径推导

**Files:**
- Create: `build/books/agentscope-java.mjs`
- Create: `build/books/registry.mjs`
- Create: `build/books/paths.mjs`
- Test: `build/books/books.test.mjs`
- Modify: `build/manifest.mjs`(整文件改为 re-export)

**Interfaces:**
- Produces: `book` 对象(bookId/status/title/subtitle/date/tagline/chaptersDir/assetsDir/demoGithubBase/srcDir/pdfFileName + 现 manifest 的 BOOK/PARTS/sources 常量与 `buildLinkMap`/`EXCLUDED_SOURCES`)
- Produces: `resolveBookPaths(book, rootDir)` → `{ chaptersAbs, assetsAbs, siteSubdir, siteDir, htmlPath, pdfPath }`,均绝对路径;`siteSubdir = book.bookId`
- Produces: `BUILDABLE_BOOKS`(status:'published' 数组)、`PLANNED_BOOKS`(status:'planned' 元数据数组)、`ALL_BOOKS`

- [ ] **Step 1: 写失败测试 `build/books/books.test.mjs`**

```js
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { resolveBookPaths } from './paths.mjs';
import { BUILDABLE_BOOKS, PLANNED_BOOKS, ALL_BOOKS } from './registry.mjs';

const FAKE_BOOK = { bookId: 'x', chaptersDir: 'books/x/chapters', assetsDir: 'books/x/assets',
  pdfFileName: 'x.pdf' };

test('resolveBookPaths 推导子站与产物路径', () => {
  const p = resolveBookPaths(FAKE_BOOK, '/repo');
  assert.equal(p.siteSubdir, 'x');
  assert.equal(p.chaptersAbs, '/repo/books/x/chapters');
  assert.equal(p.siteDir, '/repo/output/site/x');
  assert.equal(p.htmlPath, '/repo/output/x/book.html');
  assert.equal(p.pdfPath, '/repo/output/x/x.pdf');
});

test('registry:bookId 唯一且 agentscope-java 为唯一 published', () => {
  const ids = ALL_BOOKS.map((b) => b.bookId);
  assert.equal(new Set(ids).size, ids.length);
  assert.deepEqual(BUILDABLE_BOOKS.map((b) => b.bookId), ['agentscope-java']);
  for (const id of ['ragflow', 'copilotkit', 'langfuse', 'mcp'])
    assert.ok(PLANNED_BOOKS.some((b) => b.bookId === id));
});
```

- [ ] **Step 2: 跑测试确认失败**

Run: `cd build && node --test books/books.test.mjs`
Expected: FAIL(模块不存在)

- [ ] **Step 3: 实现三个模块**

`books/agentscope-java.mjs`:现 `manifest.mjs` 的 `BOOK/PARTS/buildLinkMap/EXCLUDED_SOURCES` 原样迁入,外套书级字段:

```js
export const book = {
  bookId: 'agentscope-java', status: 'published',
  title: 'AgentScope Java 2.0:从入门到进阶', subtitle: '由浅入深的智能体开发教程',
  date: '2026-10-11',
  tagline: '7 篇 44 章,从第一个 Agent 到生产级 Agent 平台',
  chaptersDir: 'chapters',            // T7 搬迁后改为 'books/agentscope-java/chapters'
  assetsDir: 'assets',                // T7 搬迁后改为 'books/agentscope-java/assets'
  demoGithubBase: 'https://github.com/ybak/ai-tutorial/blob/main/books/agentscope-java/demo/',
  srcDir: '../agentscope-java/docs/v2/zh',
  pdfFileName: 'AgentScope-Java-2.0-从入门到进阶.pdf',
  // BOOK/PARTS/sources、buildLinkMap、EXCLUDED_SOURCES 原样(BOOK 字段即 title/subtitle/date,保持原结构)
};
```

`books/registry.mjs`:导入 book 为 `BUILDABLE_BOOKS`;内联四本 planned 元数据(bookId/title/tagline/status:'planned',title 分别为「RagFlow:从入门到进阶」「CopilotKit:从前端接入 AI Agent」「Langfuse:LLM 可观测与评估」「MCP:跨框架工具接入协议」);导出 `ALL_BOOKS`。
`books/paths.mjs`:`resolveBookPaths(book, rootDir)` 按 Step 1 断言实现(纯 path.join)。
`manifest.mjs`:整文件替换为从 `./books/agentscope-java.mjs` re-export `BOOK/PARTS/buildLinkMap/EXCLUDED_SOURCES`(旧消费方 `build.mjs`/`clean.mjs` 不动)。

- [ ] **Step 4: 跑全部测试确认通过**

Run: `cd build && npm test`
Expected: books.test + clean.test + site.test 全 PASS

- [ ] **Step 5: Commit**

```bash
git add build/books build/manifest.mjs
git commit -m "feat(build): 书配置模块与注册表,manifest 迁移为书级数据"
```

---

### Task 2: site.mjs 参数化——书子站 + 书架首页

**Files:**
- Modify: `build/site.mjs`
- Modify: `build/build.mjs:533-536`(--site 分支)
- Test: `build/site.test.mjs`

**Interfaces:**
- Consumes: Task 1 的 `resolveBookPaths`、`BUILDABLE_BOOKS`、`ALL_BOOKS`、`book.demoGithubBase`
- Produces: `buildSite(book, rootDir)` → 书子站目录绝对路径;`renderShelfPage(books)` → 书架页 HTML;`rewriteMarkdownLinks(html, githubBase)`(签名加第二参数);`renderShell({ ..., searchHref })`(可选,缺省回退旧语义 `${rootPrefix}search.html`);`runSite(rootDir)` → 总装:逐本 buildSite + 书架页 + search.html

- [ ] **Step 1: 写失败测试(追加到 `site.test.mjs`)**

```js
test('renderShell 支持显式 searchHref(书子站章节页指向站点根搜索)', () => {
  const html = renderShell({ title: 't', content: 'c', rootPrefix: '../', searchHref: '../../search.html' });
  assert.ok(html.includes('action="../../search.html"'));
});

test('rewriteMarkdownLinks 使用注入的 githubBase', () => {
  const html = renderShell; // 占位保持 import 简单
  const out = rewriteMarkdownLinks('<a href="../demo/a.md">x</a>', 'https://github.com/o/r/blob/main/');
  assert.ok(out.includes('https://github.com/o/r/blob/main/demo/a.md'));
});

test('renderShelfPage:published 卡片有链接,planned 卡片无 <a>', () => {
  const html = renderShelfPage([
    { bookId: 'a', status: 'published', title: 'A', tagline: 'ta' },
    { bookId: 'p', status: 'planned', title: 'P', tagline: 'tp' },
  ]);
  assert.ok(html.includes('href="a/index.html"'));
  assert.ok(!/href="p/.test(html));
  assert.ok(html.includes('规划中'));
});
```

- [ ] **Step 2: 跑测试确认失败**

Run: `cd build && node --test site.test.mjs`
Expected: 新增 3 条 FAIL(签名/函数不存在)

- [ ] **Step 3: 实现 site.mjs 参数化**

- 删除模块级 `SITE_DIR/CHAPTERS_DIR/GITHUB_BASE`;`rewriteMarkdownLinks(html, githubBase)` 用参数替换常量(内部 `../demo/` 前缀判断不变)。
- `renderShell` 增加 `searchHref = null`,header 搜索 action 用 `searchHref ?? \`${rootPrefix}search.html\``。
- `renderIndexPage(pages)` → `renderIndexPage(book, pages)`,封面用 `book.title/subtitle/date`;书内页面(书首页 `rootPrefix:''`、章节页 `rootPrefix:'../'`)搜索 action 显式传 `searchHref`(书首页 `'../search.html'`,章节页 `'../../search.html'`,searchUi 页 `'search.html'`)。
- `buildSite(book, rootDir)`:路径全部经 `resolveBookPaths`;站点树 `output/site/<bookId>/`(`chapters/*.html`、书首页 `index.html`、`assets/` cp 自 `book.assetsDir`、`build/assets/vendor/mermaid.min.js`);`auditPage` 的 `siteDir` 参数传书子站目录。
- 新增 `renderShelfPage(books)`:卡片顺序 published 优先(规格 §7 首页软着陆:书架首屏即 agentscope 大卡片),每书一张卡片,published → `<a href="${bookId}/index.html">`,planned → 无链接 + 「规划中」徽标;rootPrefix `''`、searchHref `'search.html'`;title「AI 教程书架」。
- 新增 `runSite(rootDir)`:清空 `output/site` → 逐 `BUILDABLE_BOOKS` 调 `buildSite` → 根 `index.html` = `renderShelfPage(ALL_BOOKS)` → 根 `search.html` = `renderSearchPage()` → 返回站点根。
- `build.mjs` --site 分支(533-536 行)改为调 `runSite`。
- `site.test.mjs` 原有断言中受签名影响处同步更新(`rewriteMarkdownLinks` 调用补第二参数)。

- [ ] **Step 4: 跑测试 + 构建**

Run: `cd build && npm test && node build.mjs --site`
Expected: 测试全 PASS;`output/site/` 出现 `agentscope-java/` 子站(章节页、书首页、assets)+ 根 `index.html`(书架)+ `search.html`

- [ ] **Step 5: 金标准抽查**

Run: `diff <(旧 output/site/chapters/01-overview.html 备份) output/site/agentscope-java/chapters/01-overview.html` 或逐项检查:章节页 mermaid 脚本路径 `../../build/assets/vendor/`、图片 `../assets/images/` 解析、搜索框 action
Expected: 仅域名/前缀差异,结构一致

- [ ] **Step 6: Commit**

```bash
git add build/site.mjs build/build.mjs build/site.test.mjs
git commit -m "feat(build): site 多书化——书子站+书架首页+搜索链接按层级解析"
```

---

### Task 3: 四本骨架书立架

**Files:**
- Create: `books/ragflow/README.md`、`books/copilotkit/README.md`、`books/langfuse/README.md`、`books/mcp/README.md`

**Interfaces:**
- Consumes: Task 1 `registry.mjs` 的 planned 元数据(title/tagline 与 README 一致)
- Produces: 每本 README 含:一句话定位、目标读者、对应缺口地图条目(引用规格附录 A)、章节规划表(5-8 个候选章名)、`> 状态:规划中`

- [ ] **Step 1: 写四本 README**

结构统一(以 ragflow 为例,内容按规格 §8 与附录 A 展开):定位(RAG 平台教程,覆盖知识库运营)、读者(后端/平台/运营)、章节规划(如:初识 RagFlow、部署与配置、知识库构建、切片策略治理、检索与对话、RAG 评估、生产运维、知识库运营流程)。

- [ ] **Step 2: 核对一致性**

Run: `grep -c "规划中" books/*/README.md && node --test books/books.test.mjs`
Expected: 每本 README 各含「规划中」;registry 测试 PASS(planned 四本已在 Task 1 登记)

- [ ] **Step 3: Commit**

```bash
git add books/ragflow books/copilotkit books/langfuse books/mcp
git commit -m "docs(books): ragflow/copilotkit/langfuse/mcp 四本骨架书立架"
```

---

### Task 4: pagefind 全局搜索按书 filter

**Files:**
- Modify: `build/site.mjs`(renderShell + renderSearchPage)
- Test: `build/site.test.mjs`

**Interfaces:**
- Consumes: Task 2 的 renderShell
- Produces: 章节页 `<body data-pagefind-filter="书: <book.title>">`;搜索页 PagefindUI 开启 filter 下拉

- [ ] **Step 1: 写失败测试**

```js
test('章节页 body 携带按书 filter 属性', () => {
  // renderShell 增加可选 pagefindFilter 参数
  const html = renderShell({ title: 't', content: 'c', rootPrefix: '../',
    searchHref: '../../search.html', pagefindFilter: '书: AgentScope Java 2.0:从入门到进阶' });
  assert.ok(html.includes('<body data-pagefind-filter="书: AgentScope Java 2.0:从入门到进阶">'));
});
```

- [ ] **Step 2: 跑测试确认失败**

Run: `cd build && node --test site.test.mjs`
Expected: FAIL

- [ ] **Step 3: 实现**

- `renderShell` 增加 `pagefindFilter = null`:非空时 `<body>` 输出 `data-pagefind-filter="<值>"`(与已有 `<body data-pagefind-ignore>` 互斥场景并存:search 页已用 replace 注入 ignore,不冲突)。
- `renderChapterPage` 传入 `pagefindFilter: \`书: ${book.title}\``(buildSite 作用域内 book 可得)。
- `renderSearchPage` 的 PagefindUI 初始化增加 filters 展示配置(按 pagefind 1.5 文档:`new PagefindUI({ element, showImages: false, filters: { "书": null } })` — 若该版本 API 为自动发现 filter 则保留默认,验收以搜索页出现按书过滤为准)。

- [ ] **Step 4: 跑测试 + 构建 + 索引验证**

Run: `cd build && npm test && node build.mjs --site && npx pagefind --site ../output/site && ls ../output/site/pagefind/`
Expected: 测试 PASS;pagefind 产出索引含 filter 元数据

- [ ] **Step 5: Commit**

```bash
git add build/site.mjs build/site.test.mjs
git commit -m "feat(site): 全局搜索按书 filter"
```

---

### Task 5: 旧章节路径重定向 stub

**Files:**
- Modify: `build/site.mjs`(新增 renderRedirectPage + runSite 集成)
- Test: `build/site.test.mjs`

**Interfaces:**
- Consumes: Task 2 `runSite`、`flattenPages`
- Produces: `renderRedirectPage(toHref)` → 极简 meta-refresh 页;`runSite` 在站点根 `chapters/*.html` 产出全部旧路径 stub

- [ ] **Step 1: 写失败测试**

```js
test('redirect stub:meta-refresh + pagefind ignore + 无站点 CSS', () => {
  const html = renderRedirectPage('agentscope-java/chapters/01-overview.html');
  assert.ok(html.includes('<meta http-equiv="refresh" content="0; url=agentscope-java/chapters/01-overview.html">'));
  assert.ok(html.includes('data-pagefind-ignore'));
  assert.ok(!html.includes('site-header')); // 不引站点外壳
});

test('runSite 产出旧路径 stub 且清场重建无残留', () => {
  // 以临时目录为 rootDir 跑 runSite 后:chapters/01-overview.html 存在且内容含新路径
});
```

- [ ] **Step 2: 跑测试确认失败**

Run: `cd build && node --test site.test.mjs`
Expected: FAIL(renderRedirectPage 不存在)

- [ ] **Step 3: 实现**

- `renderRedirectPage(toHref)`:`<!DOCTYPE html><html lang="zh-CN"><head><meta charset="utf-8"><meta http-equiv="refresh" content="0; url=<toHref>"><link rel="canonical" href="<toHref>"><title>页面已迁移</title></head><body data-pagefind-ignore>本书已迁移至 <a href="<toHref>">新地址</a></body></html>`。
- `runSite` 中:对每本 published 书 `flattenPages(book.PARTS)` 的全部 href,在站点根 `chapters/<同名>.html` 写 stub(旧结构唯一 published 书;多本时旧路径唯一归属 agentscope-java,保持不变)。
- stub 生成在清场之后,天然幂等(Review Focus 第 5 条)。

- [ ] **Step 4: 跑测试 + 构建**

Run: `cd build && npm test && node build.mjs --site`
Expected: PASS;`output/site/chapters/01-overview.html` 存在且含 `agentscope-java/chapters/01-overview.html`

- [ ] **Step 5: Commit**

```bash
git add build/site.mjs build/site.test.mjs
git commit -m "feat(site): 旧章节路径 meta-refresh 重定向 stub"
```

---

### Task 6: build.mjs 全模式 --book 参数化,删除 manifest.mjs

**Files:**
- Modify: `build/build.mjs`
- Modify: `build/clean.mjs`(如 import manifest 则切换来源)
- Delete: `build/manifest.mjs`

**Interfaces:**
- Consumes: Task 1 `BUILDABLE_BOOKS`、`book.srcDir/pdfFileName/chaptersDir/assetsDir`、`resolveBookPaths`
- Produces: CLI 语义 `node build.mjs <--html|--pdf|--pdf-fallback|--check|--site> [--book <bookId>]`;缺省 book = `BUILDABLE_BOOKS` 仅一本时取之,多于一本报错要求显式 `--book`

- [ ] **Step 1: 参数化改造**

- argv 解析支持 `--book <id>`(flag 与值混合解析,现有单 flag 用法不变)。
- `--html`:产物 `output/<bookId>/book.html`;把 `book.assetsDir` cp 到 `output/<bookId>/assets/`(保持正文 `../assets/images/` 解析,见现 build.mjs HTML_PATH 注释的同款设计);`SRC_DIR` 用 `book.srcDir`。
- `--pdf` / `--pdf-fallback`:PDF 产物 `output/<bookId>/<book.pdfFileName>`;书签大纲数据沿用现 `add_outline.py` 链路,输入路径随之移到 `output/<bookId>/`。
- `--check`:消费 `book.PARTS/buildLinkMap/EXCLUDED_SOURCES`。
- 所有 `import ... from './manifest.mjs'`(build.mjs、clean.mjs、site.mjs 残留)切换到 `./books/registry.mjs` / `./books/agentscope-java.mjs`;删除 `build/manifest.mjs`。

- [ ] **Step 2: 验证**

Run: `cd build && npm test && node build.mjs --check && node build.mjs --html && ls ../output/agentscope-java/`
Expected: 测试 PASS;--check 无 error;`book.html` 与 `assets/` 出现在 `output/agentscope-java/`(--pdf 依赖 Edge/Windows,本机不跑,跳过)

- [ ] **Step 3: Commit**

```bash
git add build/build.mjs build/clean.mjs build/site.mjs && git rm build/manifest.mjs
git commit -m "refactor(build): 全模式 --book 参数化,manifest.mjs 退出历史"
```

---

### Task 7: 目录搬迁 + 根/书级 README 拆分(切换配置)

**Files:**
- Move: `chapters/` → `books/agentscope-java/chapters/`;`assets/` → `books/agentscope-java/assets/`;`demo/` → `books/agentscope-java/demo/`;`docs/database/` → `books/agentscope-java/docs/database/`
- Modify: `build/books/agentscope-java.mjs`(chaptersDir/assetsDir 改新路径)
- Modify: `README.md`(重写为书架导航)、`books/agentscope-java/README.md`(新,承接原书内容)
- Modify: `.gitignore`(demo 状态文件路径更新)

**Interfaces:**
- Consumes: Task 1-6 全部;`books/agentscope-java/README.md` 承接现根 README 的书级内容(目录表、本书特色、读者路线)

- [ ] **Step 1: git mv 整组搬迁**

```bash
mkdir -p books/agentscope-java
git mv chapters assets demo books/agentscope-java/
git mv docs/database books/agentscope-java/docs/database  # 先 mkdir books/agentscope-java/docs
```

- [ ] **Step 2: 引用完整性验证(搬迁核心风险)**

Run:
```bash
grep -rn '\.\./assets/' books/agentscope-java/chapters/ | wc -l   # ≈7 处,相对结构不变
grep -rln '\.\./demo/' books/agentscope-java/chapters/ | wc -l    # ≈27 处
grep -rn '\.\./\.\./chapters/\|\.\./\.\./docs/' books/agentscope-java/demo/ | head -3  # demo 反向引用,书内相对关系不变
```
Expected: 均有结果且路径形态与搬迁前一致(整组移动,零重写)

- [ ] **Step 3: 书配置切换**

`books/agentscope-java.mjs`:`chaptersDir: 'books/agentscope-java/chapters'`、`assetsDir: 'books/agentscope-java/assets'`。

- [ ] **Step 4: README 拆分**

- 根 `README.md` 重写:书架定位一句话 → 书列表表(agentscope-java 已发布 + 四本规划中,链接到各书 README)→ 角色学习路线表(开发/测试/运维/产品/运营 → 推荐书与章节,内容取规格附录 A)→ 候选池(ai-platform、spring-ai、dify、vercel-ai-sdk)→ 构建说明指 `build/README.md`。
- 新 `books/agentscope-java/README.md`:原根 README 的书级内容(徽章、本书有什么不同、44 章目录表、读者路线)整体迁移;链接全部改书内相对(`chapters/...`、`demo/...` 与 README 同级即正确);在线阅读链接改 `https://ybak.github.io/ai-tutorial/agentscope-java/`。
- `.gitignore` 尾部 demo 状态段路径更新:`demo/cross-border-commerce/` → `books/agentscope-java/demo/cross-border-commerce/`(两行)。

- [ ] **Step 5: 全链路预演(合入前最终验证)**

Run:
```bash
cd build && npm test && npm run site
# 逐项核对:
# 1) output/site/index.html 为书架页,agentscope 卡片链接可用,四本规划中卡片无链接
# 2) output/site/agentscope-java/index.html 书封面正常
# 3) 抽 3 个章节页:mermaid 脚本/图片/搜索框 action='../../search.html'
# 4) output/site/chapters/01-overview.html 存在跳转 stub
# 5) npx pagefind --site ../output/site 后手动开 output/site/search.html 搜索"ReAct"有结果且可按书过滤
node build.mjs --check
git status  # 确认 .gitignore 覆盖 demo 新路径状态文件
```
Expected: 全部通过;GitHub 网页端抽查 `books/agentscope-java/chapters/04-agent.md` mermaid 渲染正常

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "refactor: 目录搬迁至 books/agentscope-java,根 README 升级为书架导航"
```

---

### Task 8: 合入 main、CI 验证与仓库改名(协作步骤)

**Files:**
- Modify: `.git/config`(remote URL,改名后)
- Verify: `.github/workflows/pages.yml`(预期零改动)

- [ ] **Step 1: 确认 pages.yml 零改动需求**

Run: `git diff main --stat -- .github/`
Expected: 无 diff(CI 跑 `npm run site`,语义已被 runSite 覆盖)

- [ ] **Step 2: 合入 main 并观察 CI(规格 §7:原子单次合入)**

```bash
git push origin main   # 当前分支策略:直接在 main 原子合入(个人仓库,规格已定)
gh run watch            # Pages workflow 绿、部署 URL 可访问
```
Expected: 书架页上线,书子站可读,旧 URL `/chapters/xx.html` 跳转生效

- [ ] **Step 3: GitHub 仓库改名 ai-tutorial(用户网页操作:Settings → General → Rename)**

- [ ] **Step 4: 改名后同步**

```bash
git remote set-url origin https://github.com/ybak/ai-tutorial.git
grep -rn "agentscope-2.0-tutorial" README.md books/ build/ docs/ .github/   # 应仅剩历史文档(specs/plans)
```
Expected: 活文档(README、书 README、demoGithubBase)无旧名残留;历史规格/计划文档不改(如实记录演进)

- [ ] **Step 5: 最终验收 + 收尾报告**

在线核对:`https://ybak.github.io/ai-tutorial/` 书架 → 书子站 → 搜索按书过滤 → 旧章节深链跳转;GitHub 网页端抽查章节 mermaid 渲染。汇报结果与遗留(如 planned 书的启动顺序)。
