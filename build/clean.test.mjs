import { test } from "node:test";
import assert from "node:assert/strict";
import { cleanMarkdown } from "./clean.mjs";

const linkMap = new Map([["/v2/zh/docs/quickstart", "第 2 章"]]);

test("Note/Tip/Warning 转为 markdown 引用", () => {
  const src = "<Note>\n\n把版本号替换为最新。\n\n</Note>";
  const { md } = cleanMarkdown(src, { linkMap });
  assert.ok(md.includes("> **注意**") || md.includes("> **提示**"));
  assert.ok(!md.includes("<Note>"));
});

test("Card 转 title 链接 + 正文", () => {
  const src = '<Card title="部署服务" icon="server" href="/v2/zh/service/quickstart">\n从 Docker Compose 开始。\n</Card>';
  const { md } = cleanMarkdown(src, { linkMap });
  assert.ok(!md.includes("<Card"));
  assert.ok(md.includes("部署服务"));
});

test("Tabs/Tab 平铺", () => {
  const src = "<Tabs>\n<Tab title=\"Maven\">\n内容 A\n</Tab>\n<Tab title=\"Gradle\">\n内容 B\n</Tab>\n</Tabs>";
  const { md } = cleanMarkdown(src, { linkMap });
  assert.ok(!md.includes("<Tab"));
  assert.ok(md.includes("内容 A") && md.includes("内容 B"));
});

test("Accordion 平铺为小节", () => {
  const src = '<Accordion title="常见问题">\n答案内容。\n</Accordion>';
  const { md } = cleanMarkdown(src, { linkMap });
  assert.ok(!md.includes("<Accordion"));
  assert.ok(md.includes("常见问题") && md.includes("答案内容"));
});

test("站内链接改写为章节引用", () => {
  const src = "见 [快速开始](/v2/zh/docs/quickstart)。";
  const { md, report } = cleanMarkdown(src, { linkMap });
  assert.ok(md.includes("第 2 章"));
  assert.equal(report.unresolvedLinks.length, 0);
});

test("未知站内链接进报告", () => {
  const { report } = cleanMarkdown("见 [x](/v2/zh/docs/unknown)。", { linkMap });
  assert.equal(report.unresolvedLinks.length, 1);
});

test("span 锚点剥离", () => {
  const { md } = cleanMarkdown('<span id="a"></span>\n正文', { linkMap });
  assert.ok(!md.includes("<span"));
});

test("mermaid 块计数并保留原样", () => {
  const src = "```mermaid\nflowchart LR\n  A-->B\n```";
  const { report } = cleanMarkdown(src, { linkMap });
  assert.equal(report.mermaidCount, 1);
});

test("图片 URL 收集进 report.images", () => {
  const src = "![图](https://mmbiz.qpic.cn/x.png)";
  const { report } = cleanMarkdown(src, { linkMap });
  assert.equal(report.images.length, 1);
});

test("Frame 剥壳保留内容", () => {
  const { md } = cleanMarkdown("<Frame>\n内容\n</Frame>", { linkMap });
  assert.ok(!md.includes("<Frame") && md.includes("内容"));
});
