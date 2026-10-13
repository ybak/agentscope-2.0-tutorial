/**
 * site.mjs — --site 模式的静态站点构建器。
 * 纯函数(链接重写/页面序列)可单测;buildSite() 负责文件总装。
 */
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

import { BOOK, PARTS } from './manifest.mjs';
import { escapeHtml, md, renderMermaidScripts, splitFrontMatter } from './lib.mjs';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const BUILD_DIR = __dirname;
const ROOT_DIR = path.resolve(BUILD_DIR, '..');
const SITE_DIR = path.join(ROOT_DIR, 'output', 'site');
const CHAPTERS_DIR = path.join(ROOT_DIR, 'chapters');

/** demo 目录链接在站点内无对应页面,统一降级到 GitHub 源文件 */
const GITHUB_BASE = 'https://github.com/ybak/agentscope-2.0-tutorial/blob/main/';

/**
 * 站点链接重写:相对 .md 链接 → .html(保留锚点);
 * ../demo/…md → GitHub blob 地址;绝对 URL/协议相对链接与其余 ../ 路径原样。
 */
export function rewriteMarkdownLinks(html) {
  return html.replace(/href="([^"]+\.md)(#[^"]*)?"/g, (full, target, hash = '') => {
    if (target.startsWith('../demo/')) {
      return `href="${GITHUB_BASE}${target.replace(/^\.\.\//, '')}${hash}"`;
    }
    if (target.startsWith('../')) return full;
    if (/^[a-z][a-z0-9+.-]*:/.test(target) || target.startsWith('//')) return full; // 外链
    return `href="${target.replace(/\.md$/, '.html')}${hash}"`;
  });
}

const toPageHref = (mdFile) => `chapters/${mdFile.replace(/\.md$/, '.html')}`;

// ---------- 渲染层 ----------

const readBuildAsset = (...seg) => fs.readFileSync(path.join(BUILD_DIR, ...seg), 'utf8');

/**
 * 整页外壳。rootPrefix:站点根相对前缀(章节页 '../',根页面 '');
 * needMermaid:引 mermaid 页尾脚本(章节页);searchUi:引 pagefind UI(仅搜索页)。
 */
export function renderShell({ title, content, rootPrefix, sidebar = null, needMermaid = false, searchUi = false }) {
  const style = readBuildAsset('assets', 'style.css');
  const siteStyle = readBuildAsset('assets', 'site.css');
  const hljsTheme = readBuildAsset('node_modules', 'highlight.js', 'styles', 'github.css');
  const vendor = `${rootPrefix}build/assets/vendor/`;
  const tail = [
    needMermaid ? renderMermaidScripts(vendor) : '',
    searchUi ? `<script src="${vendor}pagefind-ui.js"></script>
<script>
window.addEventListener('DOMContentLoaded', () => {
  new PagefindUI({ element: '#search', showImages: false });
  const q = new URLSearchParams(location.search).get('q');
  if (q) {
    const input = document.querySelector('#search input');
    input.value = q;
    input.dispatchEvent(new Event('input', { bubbles: true }));
  }
});
</script>` : '',
  ].join('\n');
  return `<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${escapeHtml(title)}${title === BOOK.title ? '' : ` · ${escapeHtml(BOOK.title)}`}</title>
<style>
${style}
</style>
<style>
${hljsTheme}
</style>
<style>
${siteStyle}
</style>
</head>
<body>
<header class="site-header">
<button class="nav-toggle" aria-label="打开目录">☰</button>
<a class="site-title" href="${rootPrefix}index.html">${escapeHtml(BOOK.title)}</a>
<form class="site-search" action="${rootPrefix}search.html"><input type="search" name="q" placeholder="搜索全书…"></form>
</header>
<div class="site-body">
${sidebar ? `<aside class="site-aside">${sidebar}</aside>` : ''}
<main class="site-main">
${content}
</main>
</div>
${tail}
<script>
document.querySelector('.site-header .nav-toggle')?.addEventListener('click',
  () => document.querySelector('.site-aside')?.classList.toggle('open'));
</script>
</body>
</html>
`;
}

/** 左侧两级目录:篇 = <details>(当前篇 open,标题链到篇导读页;无 intro 的篇为纯文本),章 = <a>(当前章高亮) */
export function renderSidebar(parts, currentHref) {
  const items = parts.map((part) => {
    const introHref = part.intro ? toPageHref(part.intro) : null;
    const partActive = introHref != null && introHref === currentHref;
    const isOpen = partActive || part.chapters.some((c) => toPageHref(c.file) === currentHref);
    const links = part.chapters.map((c) => {
      const href = toPageHref(c.file);
      const active = href === currentHref ? ' class="active"' : '';
      const label = c.chapter != null ? `${c.chapter}. ${c.title}` : c.title;
      return `<a href="../${href}"${active}>${escapeHtml(label)}</a>`;
    }).join('');
    const summary = introHref
      ? `<a href="../${introHref}"${partActive ? ' class="active"' : ''}>${escapeHtml(part.title)}</a>`
      : escapeHtml(part.title);
    return `<details${isOpen ? ' open' : ''}><summary>${summary}</summary>${links}</details>`;
  }).join('');
  return `<nav class="site-nav">${items}</nav>`;
}

/** 上一篇/下一篇;链接带 ../ 前缀(仅章节页使用) */
export function renderPager(flat, idx) {
  const link = (p, label) => `<a class="pager-link" href="../${p.href}"><span class="pager-label">${label}</span><span class="pager-title">${escapeHtml(p.title)}</span></a>`;
  const prev = idx > 0 ? link(flat[idx - 1], '← 上一篇') : '<span></span>';
  const next = idx < flat.length - 1 ? link(flat[idx + 1], '下一篇 →') : '<span></span>';
  return `<nav class="pager">${prev}${next}</nav>`;
}

/** 首页:封面信息 + 篇卡片(篇标题 → 首个页面,其下页面链接)。rootPrefix 为 ''(根页面) */
export function renderIndexPage(pages) {
  const byPart = new Map();
  for (const p of pages) {
    if (!byPart.has(p.part)) byPart.set(p.part, []);
    byPart.get(p.part).push(p);
  }
  const cards = [...byPart].map(([partTitle, items]) => `<section class="home-card">
<h3><a href="${items[0].href}">${escapeHtml(partTitle)}</a></h3>
${items.map((p) => `<a href="${p.href}">${escapeHtml(p.title)}</a>`).join('\n')}
</section>`).join('\n');
  const content = `<section class="cover">
<h1 class="cover-title">${escapeHtml(BOOK.title)}</h1>
<p class="cover-subtitle">${escapeHtml(BOOK.subtitle)}</p>
<hr class="cover-rule">
<p class="cover-note">基于 AgentScope Java v2 官方文档整合 · 在线阅读版</p>
<p class="cover-date">${escapeHtml(BOOK.date)}</p>
</section>
<div class="home-cards">
${cards}
</div>`;
  return renderShell({ title: BOOK.title, content, rootPrefix: '' });
}

/** 搜索页:pagefind UI 挂载点;data-pagefind-ignore 防止自身入索引 */
export function renderSearchPage() {
  return renderShell({
    title: '搜索',
    content: '<h1>搜索</h1>\n<div id="search"></div>',
    rootPrefix: '',
    searchUi: true,
  }).replace('<body>', '<body data-pagefind-ignore>');
}

/**
 * 全站页面扁平序列(上一篇/下一篇依据):序言 → 各篇(篇导读 → 各章)→ 附录。
 * part-0 的 intro 即序言章,只在章位置登记一次(kind 仍为 part-intro)。
 */
export function flattenPages(parts) {
  const pages = [];
  for (const part of parts) {
    if (part.intro && !part.chapters.some((c) => c.file === part.intro)) {
      pages.push({ href: toPageHref(part.intro), title: part.title, part: part.title, kind: 'part-intro' });
    }
    for (const ch of part.chapters) {
      const kind = part.intro && ch.file === part.intro ? 'part-intro'
        : ch.chapter != null ? 'chapter' : 'extra';
      pages.push({ href: toPageHref(ch.file), title: ch.title, part: part.title, kind });
    }
  }
  return pages;
}
