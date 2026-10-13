import { test } from "node:test";
import assert from "node:assert/strict";

import { flattenPages, rewriteMarkdownLinks } from "./site.mjs";
import { PARTS } from "./manifest.mjs";

test("同目录章链接重写为 .html", () => {
  const out = rewriteMarkdownLinks('<a href="30-managed-agents.md">第 30 章</a>');
  assert.equal(out, '<a href="30-managed-agents.html">第 30 章</a>');
});

test("重写保留锚点", () => {
  const out = rewriteMarkdownLinks('<a href="03-concept-map.md#core-ideas">x</a>');
  assert.equal(out, '<a href="03-concept-map.html#core-ideas">x</a>');
});

test("../demo/ 链接降级为 GitHub 源文件地址", () => {
  const out = rewriteMarkdownLinks('<a href="../demo/cross-border-commerce/steps/step-12-sandbox.md">步骤</a>');
  assert.equal(out, '<a href="https://github.com/ybak/agentscope-2.0-tutorial/blob/main/demo/cross-border-commerce/steps/step-12-sandbox.md">步骤</a>');
});

test("其他 ../ 链接与外链、非 .md href 原样保留", () => {
  const src = '<a href="../assets/images/a.png">图</a><a href="https://example.com/x.md">外</a><a href="index.html">内</a>';
  assert.equal(rewriteMarkdownLinks(src), src);
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
