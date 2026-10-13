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
