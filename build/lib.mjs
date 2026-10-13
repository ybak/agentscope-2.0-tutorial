/**
 * lib.mjs — 构建共享件(build.mjs 与 site.mjs 共用)。
 * 只放与输出形态无关的渲染件:markdown-it 实例、转义/元数据小工具、
 * vendor 同步、mermaid 页尾脚本。
 */
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

import hljs from 'highlight.js';
import markdownIt from 'markdown-it';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const BUILD_DIR = __dirname;
const ROOT_DIR = path.resolve(BUILD_DIR, '..');

export const md = markdownIt({
  html: true,
  linkify: true,
  highlight(str, lang) {
    if (lang && hljs.getLanguage(lang)) {
      try {
        return hljs.highlight(str, { language: lang }).value;
      } catch {
        /* 高亮失败时退回默认转义 */
      }
    }
    return ''; // 交给 markdown-it 默认转义
  },
});

/** ```mermaid 围栏 → <div class="mermaid">(由页内 mermaid.min.js 渲染为 SVG,其余围栏走默认规则) */
const defaultFence = md.renderer.rules.fence;
md.renderer.rules.fence = (tokens, idx, options, env, self) => {
  const token = tokens[idx];
  if (token.info.trim().split(/\s+/)[0] === 'mermaid') {
    return `<div class="mermaid">\n${token.content}</div>\n`;
  }
  return defaultFence(tokens, idx, options, env, self);
};

/** Windows 路径 → 正斜杠路径(供 file:// URL 与 Edge 参数使用) */
export const toPosix = (p) => p.split(path.sep).join('/');

export function escapeHtml(s) {
  return String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
}

export function splitFrontMatter(raw) {
  const m = raw.match(/^---\r?\n([\s\S]*?)\r?\n---\r?\n?/);
  if (!m) return { meta: {}, body: raw };
  const meta = {};
  for (const line of m[1].split(/\r?\n/)) {
    const kv = line.match(/^([A-Za-z_][\w-]*):\s*(.*)$/);
    if (kv) meta[kv[1]] = kv[2].trim();
  }
  return { meta, body: raw.slice(m[0].length) };
}

/** 构建时复制到 assets/vendor/ 的第三方脚本,HTML 以相对路径引用(file:// 可直接加载) */
export const VENDOR_SCRIPTS = [
  { from: 'node_modules/mermaid/dist/mermaid.min.js', to: 'assets/vendor/mermaid.min.js' },
  { from: 'node_modules/pagedjs/dist/paged.polyfill.js', to: 'assets/vendor/paged.polyfill.js' },
];

/** 把 vendor 脚本从 node_modules 复制到 assets/vendor/ */
export function syncVendorAssets() {
  for (const v of VENDOR_SCRIPTS) {
    const from = path.join(BUILD_DIR, ...v.from.split('/'));
    const to = path.join(BUILD_DIR, ...v.to.split('/'));
    fs.mkdirSync(path.dirname(to), { recursive: true });
    fs.copyFileSync(from, to);
  }
}

/**
 * 无 Paged.js 的页尾脚本(站点页与 --pdf-fallback 共用):
 * DOMContentLoaded 后渲染全部 .mermaid 为 SVG,完成置 window.__BOOK_READY=true。
 * @param {string} vendorPrefix mermaid.min.js 相对当前页面的目录前缀,含尾斜杠
 */
export function renderMermaidScripts(vendorPrefix) {
  return `<script src="${vendorPrefix}mermaid.min.js"></script>
<script>
window.__BOOK_ERRORS=[];
mermaid.initialize({ startOnLoad: false, theme: "neutral", flowchart: { htmlLabels: false } });
document.addEventListener('DOMContentLoaded', () => {
  window.mermaid.run({ querySelector: '.mermaid', suppressErrors: true })
    .catch((err) => { window.__BOOK_ERRORS.push('mermaid: ' + (err && err.message || err)); })
    .finally(() => {
      const failed = document.querySelectorAll('.mermaid:not(:has(svg))').length;
      if (failed) window.__BOOK_ERRORS.push('mermaid: ' + failed + ' 张图未渲染为 SVG');
      window.__BOOK_READY = true;
    });
});
</script>`;
}
