/**
 * clean.mjs — 源文档（Mintlify Markdown）清洗管线（Task 2）
 *
 * 职责：md 文本进 → 清洗后 md + report 出。不做渲染（build.mjs 负责）。
 *
 * 清洗内容（对应设计文档 §4 内容清洗规则）：
 * 1. 剥离 frontmatter（title/description 由调用方先行解析，见 build.mjs splitFrontMatter）
 * 2. JSX 组件 → 纯 Markdown：
 *    - 容器壳（Tabs/CardGroup/AccordionGroup）剥外层保留内层
 *    - Tab/Accordion → `**标题**` + 正文；Card → `**[标题](href)**` + 正文（支持自闭合）
 *    - Note/Tip/Warning → `> **注意**：` 等引导语 + 逐行 `> ` 前缀引用块
 *    - Frame → 剥壳保留内容（caption 保留为斜体说明行）
 * 3. `/v2/zh/...` 站内链接 → linkMap 命中改写为「原文（见第 N 章）」；未命中计入 unresolvedLinks 并保留原链
 * 4. 装饰标签剥离（span/br），`<img>` → `![](src)`
 * 5. mermaid 代码块计数并原样透传（渲染由 build.mjs 负责）
 *
 * 所有变换均跳过围栏代码块（占位符保护），避免误伤代码示例里的
 * Java 泛型（`List<String>`）与 mermaid 的 `<br/>`。
 */

/** 已知 Mintlify/HTML 标签名（jsxResidual 检测的允许清单；长名在前避免前缀误配） */
const KNOWN_TAGS = [
  'CardGroup', 'AccordionGroup', 'Accordion',
  'Tabs', 'Tab',
  'Note', 'Tip', 'Warning',
  'Card', 'Frame',
  'span', 'img', 'br',
];

/** 引导语组件 → 中文标签 */
const CALLOUT_LABELS = { Note: '注意', Tip: '提示', Warning: '警告' };

/**
 * 把围栏代码块（``` / ~~~）替换为控制字符占位符，使其免受后续变换影响。
 * @returns {{ masked: string, blocks: string[] }} blocks[i] 为第 i 个代码块的原文（含围栏）
 */
function maskCodeBlocks(text) {
  const blocks = [];
  const masked = text.replace(
    /^([`~]{3,})([^\n]*)\n([\s\S]*?)\n\1[ \t]*$/gm,
    (full) => `\u0000CB${blocks.push(full) - 1}\u0000`,
  );
  return { masked, blocks };
}

/** 从标签属性串中取值，容忍双引号/单引号/JSX 花括号（cols={2}）/裸值四种写法 */
function getAttr(attrs, name) {
  const m = attrs.match(
    new RegExp(`\\b${name}\\s*=\\s*(?:"([^"]*)"|'([^']*)'|\\{([^}]*)\\}|([^\\s>/]+))`),
  );
  if (!m) return undefined;
  const raw = m[1] ?? m[2] ?? m[3] ?? m[4];
  return raw === undefined ? undefined : raw.replace(/^["']|["']$/g, '');
}

/** 循环执行 replace 直至文本不再变化（安全剥开同型嵌套） */
function replaceLoop(text, re, fn) {
  let prev = null;
  let out = text;
  while (out !== prev) {
    prev = out;
    out = out.replace(re, fn);
  }
  return out;
}

/** 多行文本转为引用块：非空行加 `> ` 前缀，空行变为 `>` */
function toBlockquote(label, content) {
  const body = content
    .trim()
    .split('\n')
    .map((line) => (line.trim() ? `> ${line.trim()}` : '>'))
    .join('\n');
  return `> **${label}**：\n${body}`;
}

/** Card（自闭合或带正文）→ `**[title](href)**` + 正文；href 走后续站内链接统一改写 */
function cardToMarkdown(attrs, body) {
  const title = getAttr(attrs, 'title');
  const href = getAttr(attrs, 'href');
  const head = title && href ? `**[${title}](${href})**` : title ? `**${title}**` : '';
  const text = body ? body.trim() : '';
  return [head, text].filter(Boolean).join('\n\n');
}

/** Tab/Accordion → `**标题**` + 正文 */
function sectionToMarkdown(attrs, body) {
  const title = getAttr(attrs, 'title');
  const text = body ? body.trim() : '';
  return [title ? `**${title}**` : '', text].filter(Boolean).join('\n\n');
}

/**
 * 清洗一章源文档。
 * @param {string} mdText 源 Markdown（含 frontmatter 与 Mintlify JSX）
 * @param {{ linkMap?: Map<string, string> }} ctx linkMap："/v2/zh/xxx" → "第 N 章"
 * @returns {{ md: string, report: { jsxResidual: string[], unresolvedLinks: string[], mermaidCount: number, images: string[] } }}
 */
export function cleanMarkdown(mdText, ctx = {}) {
  const linkMap = ctx.linkMap ?? new Map();
  const unresolved = new Set();
  const images = new Set();

  // 0. 行尾归一 + 剥离 frontmatter（title/description 由调用方使用）
  let text = mdText.replace(/\r\n/g, '\n');
  text = text.replace(/^---\n[\s\S]*?\n---\n?/, '');

  // 1. 代码块占位保护，并统计 mermaid
  const { masked: maskedText, blocks } = maskCodeBlocks(text);
  const mermaidCount = blocks.filter((b) => /^(```|~~~)mermaid\b/.test(b)).length;
  let md = maskedText;

  // 2. JSX 组件转换（内层优先：先剥容器壳，再转叶子组件，最后 Note/Frame）
  // 2a. 容器壳：剥外层标签保留内层
  for (const tag of ['CardGroup', 'AccordionGroup', 'Tabs']) {
    md = replaceLoop(
      md,
      new RegExp(`<${tag}\\b[^>]*>([\\s\\S]*?)</${tag}>`, 'g'),
      (_, body) => `\n\n${body}\n\n`,
    );
  }

  // 2b. Card：先处理自闭合 `<Card ... />`，再处理成对标签（顺序不可颠倒，
  //     否则自闭合的开头会被误当作成对标签的开头而错误配对）
  md = replaceLoop(md, /<Card\b([^>]*?)\/>/g, (_, attrs) => `\n\n${cardToMarkdown(attrs)}\n\n`);
  md = replaceLoop(
    md,
    /<Card\b([^>]*)>([\s\S]*?)<\/Card>/g,
    (_, attrs, body) => `\n\n${cardToMarkdown(attrs, body)}\n\n`,
  );

  // 2c. Tab / Accordion → 小节
  for (const tag of ['Tab', 'Accordion']) {
    md = replaceLoop(md, new RegExp(`<${tag}\\b([^>]*?)/>`, 'g'), (_, attrs) => `\n\n${sectionToMarkdown(attrs)}\n\n`);
    md = replaceLoop(
      md,
      new RegExp(`<${tag}\\b([^>]*)>([\\s\\S]*?)</${tag}>`, 'g'),
      (_, attrs, body) => `\n\n${sectionToMarkdown(attrs, body)}\n\n`,
    );
  }

  // 2d. Note/Tip/Warning → 引用块
  for (const [tag, label] of Object.entries(CALLOUT_LABELS)) {
    md = replaceLoop(
      md,
      new RegExp(`<${tag}\\b[^>]*>([\\s\\S]*?)</${tag}>`, 'g'),
      (_, body) => `\n\n${toBlockquote(label, body)}\n\n`,
    );
  }

  // 2e. Frame 剥壳（caption 保留为斜体说明行）
  md = replaceLoop(
    md,
    /<Frame\b([^>]*)>([\s\S]*?)<\/Frame>/g,
    (_, attrs, body) => {
      const caption = getAttr(attrs, 'caption');
      return `\n\n${[caption ? `*${caption}*` : '', body.trim()].filter(Boolean).join('\n\n')}\n\n`;
    },
  );

  // 3. 装饰标签：span 锚点、br 剥离；<img> → ![](src)
  md = md.replace(/<\/?span\b[^>]*>/g, '');
  md = md.replace(/<br\s*\/?>/gi, '');
  md = md.replace(/<img\b([^>]*)>/gi, (_, attrs) => {
    const src = getAttr(attrs, 'src');
    return src ? `![](${src})` : '';
  });

  // 4. 段落间多余空行收敛（代码块仍在占位保护中，不受影响）
  md = md.replace(/\n{3,}/g, '\n\n').trim();

  // 5. 站内链接改写（代码块受占位保护；(?<!!) 排除图片语法）
  md = md.replace(
    /(?<!!)\[([^\]]*)\]\((\/v2\/zh\/[^)\s#]+)(#[^)]*)?\)/g,
    (whole, label, href, hash) => {
      const chapter = linkMap.get(href);
      if (chapter) return `${label}（见${chapter}）`;
      unresolved.add(`${href}${hash ?? ''}`);
      return whole;
    },
  );

  // 6. 收集图片 URL（markdown 图片语法，含上一步由 <img> 转换而来的）
  for (const m of md.matchAll(/!\[[^\]]*\]\(([^)\s]+)(?:\s+"[^"]*")?\)/g)) {
    images.add(m[1]);
  }

  // 7. 还原代码块
  md = md.replace(/\u0000CB(\d+)\u0000/g, (_, i) => blocks[Number(i)]);

  // 8. 残留 JSX 检测（重新遮蔽代码块后扫描已知标签）
  const jsxResidual = [];
  const residualMasked = maskCodeBlocks(md).masked;
  const residualRe = new RegExp(`</?(?:${KNOWN_TAGS.join('|')})\\b[^>\\n]*>`, 'gi');
  for (const m of residualMasked.matchAll(residualRe)) {
    const line = residualMasked.slice(0, m.index).split('\n').length;
    jsxResidual.push(`line ${line}: ${m[0]}`);
  }

  return {
    md,
    report: {
      jsxResidual,
      unresolvedLinks: [...unresolved],
      mermaidCount,
      images: [...images],
    },
  };
}
