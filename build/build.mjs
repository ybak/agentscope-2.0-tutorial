#!/usr/bin/env node
/**
 * build.mjs — AgentScope Java 2.0 中文书籍构建脚本
 *
 * 链路：Markdown → HTML → Edge headless PDF →（PyMuPDF 补写书签/元数据）
 * 结构来源：manifest.mjs（Task 3 全书映射）；清洗体检用 clean.mjs（Task 2）。
 *
 * 用法（在 build/ 下执行）：
 *   node build.mjs --html           只产出 output/book.html（含 Paged.js 分页）
 *   node build.mjs --pdf            产出 HTML 与 output/AgentScope-Java-2.0-从入门到进阶.pdf
 *   node build.mjs --pdf-fallback   退化方案：不用 Paged.js，Edge 默认分页 + 默认页脚页码
 *   node build.mjs --check          全源清洗体检（JSX 残留 / 内链 / 图片 / mermaid / 覆盖率）
 *
 * 打印链路（--pdf / --pdf-fallback）：Edge headless + CDP Page.printToPDF。
 * 不用 --print-to-pdf CLI 的原因：CLI 恒按 Letter 纸出图且不支持 preferCSSPageSize，
 * Paged.js 的 A4 页面盒（297mm 高）会被 Letter 纸（279mm）拦腰截断；
 * CDP 路径用 preferCSSPageSize:true 让 PDF 纸张跟随 CSS @page size:A4，
 * 并以页面内 __BOOK_READY 信号替代 --virtual-time-budget 猜等（mermaid 渲染完 → Paged.js 分页完 → 才打印）。
 */

import { spawn, spawnSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

import { BOOK, PARTS, buildLinkMap, EXCLUDED_SOURCES } from './manifest.mjs';
import { cleanMarkdown } from './clean.mjs';
import { runSite } from './site.mjs';
import {
  escapeHtml, md, renderMermaidScripts, splitFrontMatter, syncVendorAssets, toPosix,
} from './lib.mjs';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const BUILD_DIR = __dirname;                   // .../build（构建工具链目录）
const ROOT_DIR = path.resolve(BUILD_DIR, '..'); // 仓库根（chapters/、assets/、output/ 在此）
const OUTPUT_DIR = path.join(ROOT_DIR, 'output');
const HTML_PATH = path.join(OUTPUT_DIR, 'book.html'); // output/ 下的 book.html 使章节里的 ../assets/images/ 恰好解析到仓库 assets/
const PDF_PATH = path.join(OUTPUT_DIR, 'AgentScope-Java-2.0-从入门到进阶.pdf');
const SRC_DIR = path.join(ROOT_DIR, '..', 'agentscope-java', 'docs', 'v2', 'zh'); // 源文档（只读，位于仓库外同级目录）

// PDF 后处理（书签/元数据）：add_outline.py 消费的大纲 JSON 与脚本本体
const OUTLINE_PATH = path.join(OUTPUT_DIR, '.outline.json');
const ADD_OUTLINE_PY = path.join(BUILD_DIR, 'add_outline.py');

const EDGE_PATH = 'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe';

/** CDP 排版完成等待上限（毫秒）：mermaid 渲染 + Paged.js 千页级分页的保守上限 */
const READY_TIMEOUT_MS = 540_000;

/** 封面页：书名 + 副标题 + 整合说明 + 日期 */
function renderCover() {
  return `<section class="cover">
<h1 class="cover-title">${escapeHtml(BOOK.title)}</h1>
<p class="cover-subtitle">${escapeHtml(BOOK.subtitle)}</p>
<hr class="cover-rule">
<p class="cover-note">基于 AgentScope Java v2 官方文档整合</p>
<p class="cover-date">${escapeHtml(BOOK.date)}</p>
</section>`;
}

/** 出版说明页：来源与许可证声明（按 agentscope-java 仓库实际 LICENSE：Apache License 2.0） */
function renderColophon() {
  return `<section class="colophon">
<h2 class="colophon-title">出版说明</h2>
<p>本书《${escapeHtml(BOOK.title)}》整理自 AgentScope 官方仓库 agentscope-java 的中文文档（docs/v2/zh 目录），整合日期 ${escapeHtml(BOOK.date)}。</p>
<p>原项目以 Apache License 2.0 许可证发布（见 agentscope-java/LICENSE）；本书作为该文档的学习整理稿，遵循同一许可证分发。</p>
<p>AgentScope 及相关商标归其权利人所有；本书与 Apache 项目官方无隶属关系。</p>
<p><strong>软件与文档持续演进中，本书内容以官方在线文档为准。</strong></p>
</section>`;
}

/** 总目录：从 manifest 生成，篇分组、章链接 #ch-N，页码由 Paged.js target-counter 填充 */
function renderToc() {
  const rows = [];
  for (const part of PARTS) {
    rows.push(`<p class="toc-part">${escapeHtml(part.title)}</p>`);
    for (const ch of part.chapters) {
      const anchor = ch.chapter != null ? `ch-${ch.chapter}` : path.basename(ch.file, '.md');
      const label = ch.chapter != null ? `第 ${ch.chapter} 章　${ch.title}` : ch.title;
      rows.push(`<p class="toc-entry"><a href="#${anchor}">${escapeHtml(label)}</a></p>`);
    }
  }
  return `<nav class="toc" id="toc">
<h2 class="toc-title">目录</h2>
${rows.join('\n')}
</nav>`;
}

/**
 * 页尾脚本（顺序即执行顺序，保证「先渲染图、后分页」）：
 * 1. mermaid.min.js（同步加载，暴露全局 mermaid）
 * 2. 内联初始化：mermaid.initialize(startOnLoad:false) —— 关闭 mermaid 自带的 DOMContentLoaded
 *    自动渲染（与 Paged.js 自动分页并发会竞态改 DOM），改由 PagedConfig.before 钩子先 await
 *    mermaid.run() 渲染全部图为 SVG；PagedConfig.after 置 window.__BOOK_READY=true，
 *    构建脚本据此判断可以开始打印。
 * 3. paged.polyfill.js（最后加载，读到上方 PagedConfig 后才启动分页）
 * 退化模式（usePaged=false）：无 Paged.js，DOMContentLoaded 后直接 mermaid.run()，完成即置 READY。
 */
function renderTailScripts(usePaged) {
  // book.html 落在 output/，vendor 脚本在 build/assets/vendor/，故引用带 ../build/ 前缀
  if (!usePaged) return renderMermaidScripts('../build/assets/vendor/');
  return `<script src="../build/assets/vendor/mermaid.min.js"></script>
<script>
window.__BOOK_ERRORS=[];
mermaid.initialize({ startOnLoad: false, theme: "neutral", flowchart: { htmlLabels: false } });
window.PagedConfig = {
  auto: true,
  before: async () => {
    // 注意必须显式 querySelector：mermaid v12 的 run() 一旦传入 options 对象
    // 就不再用默认 '.mermaid'，缺省时静默跳过（"Nodes and querySelector are both undefined"）
    try {
      await window.mermaid.run({ querySelector: '.mermaid', suppressErrors: true });
      const failed = document.querySelectorAll('.mermaid:not(:has(svg))').length;
      if (failed) window.__BOOK_ERRORS.push('mermaid: ' + failed + ' 张图未渲染为 SVG');
    } catch (err) { window.__BOOK_ERRORS.push('mermaid: ' + (err && err.message || err)); }
  },
  after: () => { window.__BOOK_READY = true; },
};
</script>
<script src="../build/assets/vendor/paged.polyfill.js"></script>`;
}

/**
 * 渲染整本书为 book.html，返回其绝对路径。
 * 结构：封面 → 出版说明 → 总目录 → 按 PARTS 顺序渲染篇导读（part.intro → chapters/<intro>，
 * 含篇名扉页标题）与各章（chapters/<file>）；文件缺失时跳过并记 warn。
 * 注意：chapters/*.md 已是人工整理稿，此处不跑 cleanMarkdown（clean 只用于 --check 体检源文件）。
 * @param {boolean} usePaged true=Paged.js 分页版（默认）；false=退化版（Edge 默认分页）
 */
function renderBook(usePaged = true, manifest = { BOOK, PARTS }) {
  const chaptersDir = path.join(ROOT_DIR, 'chapters');
  const sections = [];
  const warns = [];

  for (const part of manifest.PARTS) {
    // 篇导读；part-0 的 intro 即序言章文件本身，此时只按章渲染一次
    if (part.intro && !part.chapters.some((c) => c.file === part.intro)) {
      const introPath = path.join(chaptersDir, part.intro);
      if (fs.existsSync(introPath)) {
        const { meta, body } = splitFrontMatter(fs.readFileSync(introPath, 'utf8'));
        sections.push(
          `<section class="part-intro" id="${part.id}">\n<h1 class="part-title">${escapeHtml(meta.title ?? part.title)}</h1>\n<hr class="part-rule">\n${md.render(body)}\n</section>`,
        );
      } else {
        warns.push(`[build][warn] 篇导读缺失，跳过: chapters/${part.intro}（${part.title}）`);
      }
    }

    for (const ch of part.chapters) {
      const chapterPath = path.join(chaptersDir, ch.file);
      if (!fs.existsSync(chapterPath)) {
        warns.push(`[build][warn] 章节文件缺失，跳过: chapters/${ch.file}（${ch.title}）`);
        continue;
      }
      const { meta, body } = splitFrontMatter(fs.readFileSync(chapterPath, 'utf8'));
      const anchor = ch.chapter != null ? `ch-${ch.chapter}` : path.basename(ch.file, '.md');
      sections.push(
        `<section class="chapter" id="${anchor}" data-title="${escapeHtml(meta.title ?? ch.title)}">\n${md.render(body)}\n</section>`,
      );
    }
  }

  if (sections.length === 0) {
    warns.push('[build][warn] 本书暂无可渲染章节（chapters/ 尚未编写，整合任务逐篇补齐）');
  }
  for (const w of warns) console.log(w);

  const style = fs.readFileSync(path.join(BUILD_DIR, 'assets', 'style.css'), 'utf8');
  const hljsTheme = fs.readFileSync(
    path.join(BUILD_DIR, 'node_modules', 'highlight.js', 'styles', 'github.css'),
    'utf8',
  );

  const html = `<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<title>${escapeHtml(manifest.BOOK.title)}</title>
<style>
${style}
</style>
<style>
/* highlight.js github 主题（代码高亮配色） */
${hljsTheme}
</style>
</head>
<body>
${renderCover()}
${renderColophon()}
${renderToc()}
<div id="book">
${sections.join('\n')}
</div>
${renderTailScripts(usePaged)}
</body>
</html>
`;
  fs.mkdirSync(path.dirname(HTML_PATH), { recursive: true });
  fs.writeFileSync(HTML_PATH, html, 'utf8');
  return HTML_PATH;
}

/** 递归收集 dir 下全部 .md 的相对路径（正斜杠，按名排序） */
function walkMarkdown(dir, prefix = '') {
  const out = [];
  const entries = fs.readdirSync(dir, { withFileTypes: true }).sort((a, b) => a.name.localeCompare(b.name));
  for (const ent of entries) {
    const rel = prefix ? `${prefix}/${ent.name}` : ent.name;
    if (ent.isDirectory()) out.push(...walkMarkdown(path.join(dir, ent.name), rel));
    else if (ent.isFile() && ent.name.endsWith('.md')) out.push(rel);
  }
  return out;
}

/**
 * --check：全源内链体检。
 * 遍历 manifest 全部 sources → cleanMarkdown(src, { linkMap: buildLinkMap() }) →
 * 汇总打印 JSX 残留 / 未解析站内链接（分三类：指向排除文件、目标存在但未入书、真未解析）/
 * 图片总数 / mermaid 总数 / 未被 manifest 覆盖的源文件清单（对照源目录全量 .md）。
 */
function runCheck() {
  const linkMap = buildLinkMap();
  const sources = [...new Set(PARTS.flatMap((p) => p.chapters.flatMap((c) => c.sources)))].sort();

  let jsxTotal = 0;
  const jsxSamples = [];
  let mermaidTotal = 0;
  let imageTotal = 0;
  const imageUrls = new Set();
  const unresolved = new Map(); // href(含锚点，去重) -> 出现它的源文件列表
  let readCount = 0;
  const missingSources = [];

  for (const src of sources) {
    const file = path.join(SRC_DIR, ...src.split('/'));
    if (!fs.existsSync(file)) {
      missingSources.push(src);
      continue;
    }
    readCount += 1;
    const { report } = cleanMarkdown(fs.readFileSync(file, 'utf8'), { linkMap });
    if (report.jsxResidual.length > 0) {
      jsxTotal += report.jsxResidual.length;
      for (const r of report.jsxResidual.slice(0, 3)) jsxSamples.push(`${src}: ${r}`);
    }
    mermaidTotal += report.mermaidCount;
    imageTotal += report.images.length;
    for (const u of report.images) imageUrls.add(u);
    for (const link of report.unresolvedLinks) {
      if (!unresolved.has(link)) unresolved.set(link, []);
      unresolved.get(link).push(src);
    }
  }

  // 未被 manifest 覆盖的源文件（对照源目录全量 .md）
  const allFiles = walkMarkdown(SRC_DIR);
  const covered = new Set(sources);
  const uncovered = allFiles.filter((f) => !covered.has(f));
  const excluded = new Set(EXCLUDED_SOURCES);
  const extra = uncovered.filter((f) => !excluded.has(f)); // 未覆盖且不在排除清单 → 需人工裁决

  // 未解析链接分类（href 去锚点/尾斜杠/.md 后比对相对路径）
  const excludedNoMd = new Set(EXCLUDED_SOURCES.map((s) => s.replace(/\.md$/, '')));
  const toExcluded = [];
  const targetExists = [];
  const broken = [];
  for (const href of [...unresolved.keys()].sort()) {
    const rel = href
      .split('#')[0]
      .replace(/\/+$/, '')
      .replace(/^\/v2\/zh\//, '')
      .replace(/\.md$/, '');
    if (excludedNoMd.has(rel)) toExcluded.push(href);
    else if (fs.existsSync(`${path.join(SRC_DIR, ...rel.split('/'))}.md`)) targetExists.push(href);
    else broken.push(href);
  }

  console.log('[check] === 清洗体检报告 ===');
  console.log(`[check] manifest sources: ${sources.length} 个（已读 ${readCount}，磁盘缺失 ${missingSources.length}）`);
  for (const s of missingSources) console.log(`[check]   - 磁盘缺失: ${s}`);
  console.log(`[check] JSX 残留: ${jsxTotal} 处`);
  for (const s of jsxSamples) console.log(`[check]   - ${s}`);
  if (jsxTotal > jsxSamples.length) console.log(`[check]   - ……其余 ${jsxTotal - jsxSamples.length} 处略`);
  console.log(`[check] mermaid 代码块: ${mermaidTotal} 个`);
  console.log(`[check] 图片引用: ${imageTotal} 处（去重 URL ${imageUrls.size} 个）`);
  console.log(`[check] 未解析站内链接: ${unresolved.size} 个（去重）`);
  const group = (label, hrefs) => {
    console.log(`[check]   ${label}: ${hrefs.length}`);
    for (const href of hrefs) console.log(`[check]     - ${href}  ← ${[...new Set(unresolved.get(href))].join(', ')}`);
  };
  group('指向排除文件（预期内，不算失败）', toExcluded);
  group('目标存在但未入 manifest（网站可解析）', targetExists);
  group('真未解析（目标文件不存在）', broken);
  console.log(`[check] 未被 manifest 覆盖的源文件: ${uncovered.length} 个（源目录共 ${allFiles.length} 个 .md）`);
  for (const f of uncovered) {
    console.log(`[check]   - ${f}${excluded.has(f) ? '（排除清单内）' : '（不在排除清单！）'}`);
  }
  if (extra.length === 0) {
    console.log('[check] 未覆盖清单与排除清单完全一致');
  } else {
    console.log(`[check] 注意: ${extra.length} 个未覆盖文件不在排除清单中——需确认是否补映射或补排除`);
  }
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function fetchJson(url, opts) {
  const res = await fetch(url, opts);
  if (!res.ok) throw new Error(`${url} → HTTP ${res.status}`);
  return res.json();
}

/** 启动 Edge headless（独立临时 profile），等 DevToolsActivePort 出端口 */
async function launchEdge() {
  const os = await import('node:os');
  const userDataDir = fs.mkdtempSync(path.join(os.tmpdir(), 'edge-book-pdf-'));
  const child = spawn(EDGE_PATH, [
    '--headless',
    '--disable-gpu',
    '--no-first-run',
    '--no-default-browser-check',
    '--remote-debugging-port=0',
    `--user-data-dir=${userDataDir}`,
    'about:blank',
  ], { stdio: 'ignore' });
  const portFile = path.join(userDataDir, 'DevToolsActivePort');
  let port = null;
  for (let i = 0; i < 100; i += 1) {
    if (fs.existsSync(portFile)) {
      port = fs.readFileSync(portFile, 'utf8').split(/\r?\n/)[0]?.trim();
      if (port) break;
    }
    await sleep(100);
  }
  if (!port) {
    child.kill();
    fs.rmSync(userDataDir, { recursive: true, force: true });
    throw new Error('Edge DevTools 调试端口未就绪（DevToolsActivePort 未生成）');
  }
  return { child, port, userDataDir };
}

/** 极简 CDP WebSocket 会话：send(method, params) 返回结果 Promise；on(method, handler) 收事件 */
function connectCdp(wsUrl) {
  return new Promise((resolve, reject) => {
    const ws = new WebSocket(wsUrl);
    let seq = 0;
    const pending = new Map();
    const listeners = new Map();
    ws.onopen = () => resolve(api);
    ws.onerror = () => reject(new Error(`CDP WebSocket 连接失败: ${wsUrl}`));
    ws.onmessage = (ev) => {
      const msg = JSON.parse(ev.data);
      if (msg.id != null && pending.has(msg.id)) {
        const { resolve: res, reject: rej } = pending.get(msg.id);
        pending.delete(msg.id);
        if (msg.error) rej(new Error(`CDP ${msg.error.message}`));
        else res(msg.result);
      } else if (msg.method) {
        for (const h of listeners.get(msg.method) ?? []) h(msg.params);
      }
    };
    const api = {
      send(method, params = {}) {
        return new Promise((res, rej) => {
          const id = (seq += 1);
          pending.set(id, { resolve: res, reject: rej });
          ws.send(JSON.stringify({ id, method, params }));
        });
      },
      on(method, handler) {
        if (!listeners.has(method)) listeners.set(method, []);
        listeners.get(method).push(handler);
      },
      close() { try { ws.close(); } catch { /* 忽略 */ } },
    };
  });
}

/**
 * 用 Edge headless + CDP 把 HTML 打印为 PDF。
 * @param {boolean} paged true=Paged.js 版：preferCSSPageSize 跟随 @page A4，
 *                        等页面内 __BOOK_READY（mermaid 渲染完 + 分页完）再打印；
 *                        false=退化版：显式 A4 纸 + Edge 页脚页码（displayHeaderFooter）。
 */
async function printViaCdp(htmlPath, pdfPath, { paged }) {
  const { child, port, userDataDir } = await launchEdge();
  try {
    const targets = await fetchJson(`http://127.0.0.1:${port}/json/list`);
    const page = targets.find((t) => t.type === 'page');
    if (!page?.webSocketDebuggerUrl) throw new Error('未找到 Edge 页面调试目标');

    const cdp = await connectCdp(page.webSocketDebuggerUrl);
    await cdp.send('Page.enable');
    const loaded = new Promise((r) => cdp.on('Page.loadEventFired', r));
    await cdp.send('Page.navigate', { url: `file:///${toPosix(htmlPath)}` });
    await loaded;

    // 等排版完成（__BOOK_READY 由页内脚本在 mermaid 渲染 + Paged.js 分页后置位）
    const deadline = Date.now() + READY_TIMEOUT_MS;
    let ready = false;
    let lastPages = -1;
    while (Date.now() < deadline) {
      const { result } = await cdp.send('Runtime.evaluate', {
        expression: `JSON.stringify({ready: window.__BOOK_READY === true, pages: document.querySelectorAll('.pagedjs_page').length})`,
        returnByValue: true,
      });
      const st = JSON.parse(result.value);
      if (st.pages !== lastPages) {
        console.log(`[pdf] 分页进度: ${st.pages} 页${paged ? '' : '（退化模式不分页）'}`);
        lastPages = st.pages;
      }
      if (st.ready) { ready = true; break; }
      await sleep(1000);
    }

    const { result: errJson } = await cdp.send('Runtime.evaluate', {
      expression: 'JSON.stringify(window.__BOOK_ERRORS || [])',
      returnByValue: true,
    });
    for (const e of JSON.parse(errJson.value)) console.log(`[build][warn] ${e}`);

    if (!ready) throw new Error(`等待排版完成超时（${READY_TIMEOUT_MS / 1000}s）——Paged.js 可能卡死，可改用 --pdf-fallback`);

    const pdfParams = paged
      ? { printBackground: true, preferCSSPageSize: true, displayHeaderFooter: false }
      : {
          printBackground: true,
          displayHeaderFooter: true,
          headerTemplate: '<span></span>',
          footerTemplate: '<div style="width:100%;text-align:center;font-size:8px;color:#666;font-family:sans-serif;"><span class="pageNumber"></span></div>',
          marginTop: 0.5, marginBottom: 0.5, marginLeft: 0.63, marginRight: 0.63,
          paperWidth: 8.268, paperHeight: 11.693, // A4（退化版无 @page 分页信息，显式给纸）
        };
    // 用默认回传（单条 WS 消息 base64）。不用 transferMode:ReturnAsStream——
    // 实测 Chromium 的 DevTools 文件流在 10 MiB 处截断（本书 PDF ≈50 MiB，两次复现）。
    const res = await cdp.send('Page.printToPDF', pdfParams);
    if (!res.data) throw new Error('Page.printToPDF 未返回数据');
    const pdf = Buffer.from(res.data, 'base64');
    // 完整性守卫：PDF 末尾必须有 %%EOF（防静默截断）
    if (!pdf.subarray(-2048).includes('%%EOF')) {
      throw new Error('打印结果缺少 %%EOF——PDF 疑似被截断');
    }
    fs.writeFileSync(pdfPath, pdf);
    cdp.close();
  } finally {
    child.kill();
    await sleep(200);
    fs.rmSync(userDataDir, { recursive: true, force: true });
  }
}

/**
 * 从 manifest 生成两级书签大纲（文档顺序）：
 *   level 1：序言 / 第一篇…第七篇（篇扉页）/ 附录（无独立扉页，锚在附录 A 页）
 *   level 2：第 1…44 章；附录 A / 附录 B
 * 序言部的章条目即序言自身（与 level 1 同页），不重复出书签。
 * key 由 add_outline.py 解释：preface / part:<标题> / ch:<N> / appendix / appendix-a|b。
 */
function buildOutline() {
  const outline = [];
  for (const part of PARTS) {
    if (part.id === 'part-0') {
      outline.push({ level: 1, title: '序言', key: 'preface' });
    } else if (part.id === 'appendix') {
      outline.push({ level: 1, title: '附录', key: 'appendix' });
    } else {
      outline.push({ level: 1, title: part.title, key: `part:${part.title}` });
    }
    for (const ch of part.chapters) {
      if (ch.chapter != null) {
        outline.push({ level: 2, title: `第 ${ch.chapter} 章 ${ch.title}`, key: `ch:${ch.chapter}` });
      } else if (part.id === 'appendix') {
        const m = ch.title.match(/附录\s*([AB])/);
        if (!m) throw new Error(`附录章标题无法识别（应为「附录 A/B：…」）: ${ch.title}`);
        outline.push({ level: 2, title: ch.title, key: `appendix-${m[1].toLowerCase()}` });
      }
    }
  }
  return outline;
}

/**
 * PDF 后处理：写侧边栏书签与元数据（Edge 打印不生成 outline）。
 * manifest → output/.outline.json → spawnSync python build/add_outline.py；
 * 任何失败（python 不可用 / 章节页定位失败 / PyMuPDF 异常）都抛错，
 * 使整体构建以非零码退出（与 %%EOF 守卫同标准）。
 */
function addPdfOutline(pdfPath) {
  const outline = buildOutline();
  fs.writeFileSync(OUTLINE_PATH, `${JSON.stringify(outline, null, 2)}\n`, 'utf8');
  const res = spawnSync('python', [ADD_OUTLINE_PY, pdfPath, OUTLINE_PATH], { stdio: 'inherit' });
  if (res.error) throw new Error(`无法启动 python（PyMuPDF 写书签）: ${res.error.message}`);
  if (res.status !== 0) throw new Error(`add_outline.py 退出码 ${res.status}——PDF 书签写入失败`);
  console.log(`[build] PDF 书签已写入（${outline.length} 条）+ 元数据: ${pdfPath}`);
}

async function main() {
  const flag = process.argv[2];
  switch (flag) {
    case '--html': {
      syncVendorAssets();
      const html = renderBook(true);
      console.log(`[build] HTML 已生成（Paged.js 版）: ${html}`);
      break;
    }
    case '--pdf': {
      syncVendorAssets();
      const html = renderBook(true);
      console.log(`[build] HTML 已生成（Paged.js 版）: ${html}`);
      fs.mkdirSync(OUTPUT_DIR, { recursive: true });
      await printViaCdp(html, PDF_PATH, { paged: true });
      if (!fs.existsSync(PDF_PATH)) {
        throw new Error('打印结束但未生成 PDF（请检查 Edge 路径与参数）');
      }
      addPdfOutline(PDF_PATH); // 打印成功后补写书签/元数据；失败 → 构建失败
      console.log(`[build] PDF 已生成: ${PDF_PATH}`);
      break;
    }
    case '--pdf-fallback': {
      syncVendorAssets();
      const html = renderBook(false);
      console.log(`[build] HTML 已生成（退化版，无 Paged.js）: ${html}`);
      fs.mkdirSync(OUTPUT_DIR, { recursive: true });
      await printViaCdp(html, PDF_PATH, { paged: false });
      if (!fs.existsSync(PDF_PATH)) {
        throw new Error('打印结束但未生成 PDF（请检查 Edge 路径与参数）');
      }
      addPdfOutline(PDF_PATH); // 打印成功后补写书签/元数据；失败 → 构建失败
      console.log(`[build] PDF 已生成（退化方案）: ${PDF_PATH}`);
      break;
    }
    case '--site': {
      runSite(ROOT_DIR);
      console.log(`[build] 站点已生成: ${path.join(OUTPUT_DIR, 'site')}（搜索索引: cd build && npm run site）`);
      break;
    }
    case '--check':
      runCheck();
      break;
    default:
      console.error('用法: node build/build.mjs --html | --pdf | --pdf-fallback | --site | --check');
      process.exitCode = 1;
  }
}

main().catch((err) => {
  console.error(`[build] 失败: ${err.message}`);
  process.exitCode = 1;
});
