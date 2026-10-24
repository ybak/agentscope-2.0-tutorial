import { test } from "node:test";
import assert from "node:assert/strict";

import { flattenPages, renderIndexPage, renderPager, renderSearchPage, renderShelfPage, renderShell, renderSidebar, rewriteMarkdownLinks } from "./site.mjs";
import { book, PARTS } from "./books/agentscope-java.mjs";

// 与 buildSite 内的推导一致:rewriteMarkdownLinks 的第二参数是「demo/ 目录的上级」blob 前缀
const demoBase = book.demoGithubBase.replace(/demo\/$/, "");

test("同目录章链接重写为 .html", () => {
  const out = rewriteMarkdownLinks('<a href="30-managed-agents.md">第 30 章</a>', demoBase);
  assert.equal(out, '<a href="30-managed-agents.html">第 30 章</a>');
});

test("重写保留锚点", () => {
  const out = rewriteMarkdownLinks('<a href="03-concept-map.md#core-ideas">x</a>', demoBase);
  assert.equal(out, '<a href="03-concept-map.html#core-ideas">x</a>');
});

test("../demo/ 链接降级为 GitHub 源文件地址(基址随书配置)", () => {
  const out = rewriteMarkdownLinks('<a href="../demo/cross-border-commerce/steps/step-12-sandbox.md">步骤</a>', demoBase);
  assert.equal(out, '<a href="https://github.com/ybak/ai-tutorial/blob/main/books/agentscope-java/demo/cross-border-commerce/steps/step-12-sandbox.md">步骤</a>');
});

test("其他 ../ 链接与外链、非 .md href 原样保留", () => {
  const src = '<a href="../assets/images/a.png">图</a><a href="https://example.com/x.md">外</a><a href="index.html">内</a>';
  assert.equal(rewriteMarkdownLinks(src, demoBase), src);
});

test("flattenPages 全书序列:54 项、首尾与篇导读位置正确", () => {
  const pages = flattenPages(PARTS);
  assert.equal(pages.length, 54); // 47 章文件(含序言/附录) + 7 个篇导读
  assert.equal(pages[0].href, "chapters/preface.html");
  assert.equal(pages[0].kind, "part-intro"); // 序言即 part-0 导读
  assert.equal(pages[1].href, "chapters/part-1-intro.html");
  assert.equal(pages[2].href, "chapters/01-overview.html");
  assert.equal(pages[2].kind, "chapter");
  assert.equal(pages.at(-1).href, "chapters/appendix-b-glossary.html");
  assert.ok(pages.at(-1).title.includes("附录 B")); // 冒号形态以 manifest 为准,不硬写
  // 每篇导读都在其章之前
  for (let i = 1; i < pages.length; i++) {
    if (pages[i].kind === "part-intro" && pages[i - 1].kind === "chapter") {
      assert.notEqual(pages[i].part, pages[i - 1].part);
    }
  }
});

const twoParts = [
  { id: "p0", title: "序言", intro: "preface.md", chapters: [
    { file: "preface.md", chapter: null, title: "序言", sources: [] },
  ]},
  { id: "p1", title: "第一篇", intro: "part-1-intro.md", chapters: [
    { file: "part-1-intro.md", chapter: null, title: "第一篇导读", sources: [] },
    { file: "01-a.md", chapter: 1, title: "章一", sources: [] },
  ]},
];

test("renderSidebar:当前章高亮、当前篇展开、附录(无 intro)为纯文本标题", () => {
  const parts = [...twoParts, { id: "appendix", title: "附录", intro: null, chapters: [
    { file: "appendix-a.md", chapter: null, title: "附录 A", sources: [] },
  ]}];
  const nav = renderSidebar(parts, "chapters/01-a.html");
  assert.ok(nav.includes('<a href="../chapters/01-a.html" class="active">'));
  assert.ok(nav.includes("<details open>")); // 当前篇展开
  assert.ok(nav.includes("附录"));            // 无 intro 的篇仍列出
  assert.ok(nav.includes('<summary>附录</summary>')); // 无 intro 的篇:纯文本 summary
  assert.ok(!nav.match(/<summary><a[^>]*>附录</));     // 且不被链接包裹
});

test("renderPager:首项无上一篇、次项双向", () => {
  const flat = flattenPages(twoParts);
  assert.ok(!renderPager(flat, 0).includes("← 上一篇"));
  const mid = renderPager(flat, 1);
  assert.ok(mid.includes("← 上一篇") && mid.includes("下一篇 →"));
  assert.ok(mid.includes('href="../chapters/preface.html"'));
});

test("renderShell:章节页带侧边栏与 mermaid 脚本,根页面不带 ../ 前缀", () => {
  const chapter = renderShell({ title: "章一", content: "<p>x</p>", rootPrefix: "../",
    sidebar: "<nav></nav>", needMermaid: true });
  assert.ok(chapter.includes('src="../build/assets/vendor/mermaid.min.js"'));
  assert.ok(chapter.includes('action="../search.html"'));
  const home = renderShell({ title: "首页", content: "<p>x</p>", rootPrefix: "" });
  assert.ok(home.includes('action="search.html"'));
  assert.ok(!home.includes("mermaid.min.js"));
});

test("renderSearchPage:排除自身索引并引 pagefind UI", () => {
  const page = renderSearchPage();
  assert.ok(page.includes("data-pagefind-ignore"));
  assert.ok(page.includes("pagefind-ui"));
  assert.ok(page.includes("new PagefindUI"));
});

test("renderIndexPage:封面随书配置,每篇一张卡片,搜索指向站点根", () => {
  const html = renderIndexPage(book, flattenPages(twoParts));
  assert.ok(html.includes("home-card"));
  assert.ok(html.includes('href="chapters/01-a.html"'));
  assert.ok(html.includes(`action="../search.html"`)); // 书首页在 <bookId>/ 下,搜索在站点根
});

test("auditPage:相对 .md 残留被抓,GitHub 降级链接不报", async (t) => {
  const { auditPage } = await import("./site.mjs");
  const warns = [];
  const html = '<a href="30-x.md#s">a</a><a href="https://github.com/ybak/agentscope-2.0-tutorial/blob/main/demo/x.md">b</a>';
  auditPage(html, "/tmp/nonexistent-site", "t.html", warns);
  assert.equal(warns.length, 1);
  assert.ok(warns[0].includes('30-x.md#')); // matchAll 的 m[0] 在 # 处截断
});

test("auditPage:缺失图片告警,存在图片不报", async (t) => {
  const { auditPage } = await import("./site.mjs");
  const fs = await import("node:fs");
  const os = await import("node:os");
  const path = await import("node:path");
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "site-audit-"));
  fs.mkdirSync(path.join(tmp, "assets", "images"), { recursive: true });
  fs.writeFileSync(path.join(tmp, "assets", "images", "ok.png"), "x");
  const warns = [];
  auditPage('<img src="../assets/images/ok.png"><img src="../assets/images/missing.png">', tmp, "t.html", warns);
  assert.equal(warns.length, 1);
  assert.ok(warns[0].includes("missing.png"));
  fs.rmSync(tmp, { recursive: true, force: true });
});

test("renderShell 支持显式 searchHref(书子站章节页指向站点根搜索)", () => {
  const html = renderShell({ title: 't', content: 'c', rootPrefix: '../', searchHref: '../../search.html' });
  assert.ok(html.includes('action="../../search.html"'));
});

test("rewriteMarkdownLinks 使用注入的 githubBase", () => {
  const out = rewriteMarkdownLinks('<a href="../demo/a.md">x</a>', 'https://github.com/o/r/blob/main/');
  assert.ok(out.includes('https://github.com/o/r/blob/main/demo/a.md'));
});

test("renderShelfPage:published 卡片有链接,planned 卡片无 <a>", () => {
  const html = renderShelfPage([
    { bookId: 'a', status: 'published', title: 'A', tagline: 'ta' },
    { bookId: 'p', status: 'planned', title: 'P', tagline: 'tp' },
  ]);
  assert.ok(html.includes('href="a/index.html"'));
  assert.ok(!/href="p/.test(html));
  assert.ok(html.includes('规划中'));
});
