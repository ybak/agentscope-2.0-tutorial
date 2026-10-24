/**
 * mcp.mjs — 《MCP:跨框架工具接入协议》书配置
 *
 * 第二本 published 书(书架第二格)。结构与 agentscope-java.mjs 一致:
 * - book:书级元数据 + 渲染层文案字段 + chaptersDir/assetsDir 等路径约定
 * - book.PARTS:4 篇 12 章(原创书,无篇导读文件;sources 填官方文档路径示意,
 *   供未来 --check 与溯源用)
 * - book.buildLinkMap():原创书无源文档链接映射,返回空 Map
 * - book.EXCLUDED_SOURCES:空
 * - legacyRootChapters: false(2026-07-28 起为本仓库新增的书,不拥有旧站点根
 *   chapters/ 路径;重定向 stub 只属于 agentscope-java)
 */

export const book = {
  bookId: 'mcp',
  status: 'published',
  title: 'MCP:跨框架工具接入协议',
  subtitle: '从核心协议到中台规模化',
  date: '2026-10-24',
  tagline: 'Model Context Protocol,统一工具接入的跨框架标准',
  sourceNote: '基于 MCP 官方规范 2026-07-28 与官方文档撰写,含团队实测',
  sourceDescription: 'MCP 官方规范仓库 modelcontextprotocol/modelcontextprotocol(2026-07-28 版)与官方教学文档',
  licenseNote: 'MCP 规范与文档以开放许可发布;本书为学习整理稿,遵循本仓库整体许可证分发。',
  trademarkNote: 'Model Context Protocol 及相关商标归其权利人所有;本书与 MCP 项目及 Anthropic 官方无隶属关系。',
  chaptersDir: 'books/mcp/chapters',
  assetsDir: 'books/mcp/assets',
  demoGithubBase: 'https://github.com/ybak/ai-tutorial/blob/main/books/mcp/demo/',
  srcDir: 'books/mcp/openapi',
  pdfFileName: 'MCP-跨框架工具接入协议.pdf',
  legacyRootChapters: false,
};

const PARTS = [
  { id: "part-1", title: "第一篇 入门", chapters: [
    { file: "01-overview.md", chapter: 1, title: "初识 MCP", sources: ["docs/2026-07-28/getting-started/intro.mdx"] },
    { file: "02-core-concepts.md", chapter: 2, title: "协议核心概念", sources: ["docs/specification/2026-07-28/basic/index.mdx", "docs/specification/2026-07-28/server/discover.mdx"] },
    { file: "03-spec-versions.md", chapter: 3, title: "协议版本演进与兼容", sources: ["docs/specification/2026-07-28/changelog.mdx"] },
    { file: "04-quickstart.md", chapter: 4, title: "快速上手", sources: ["docs/2026-07-28/sdk.mdx"] },
  ]},
  { id: "part-2", title: "第二篇 构建.Server", chapters: [
    { file: "05-build-server.md", chapter: 5, title: "构建完整的 Server", sources: ["docs/2026-07-28/develop/build-server.mdx"] },
    { file: "06-tool-authoring.md", chapter: 6, title: "工具接入实战", sources: ["docs/specification/2026-07-28/server/tools.mdx"] },
  ]},
  { id: "part-3", title: "第三篇 规模化与集成", chapters: [
    { file: "07-mcp-at-scale.md", chapter: 7, title: "规模化:业务中台的 MCP 化", sources: [] },
    { file: "08-client-integrations.md", chapter: 8, title: "构建 Client 与跨框架接入", sources: ["docs/2026-07-28/develop/build-client.mdx"] },
    { file: "09-debugging.md", chapter: 9, title: "调试与 Inspector", sources: ["docs/2026-07-28/tools/debugging.mdx"] },
  ]},
  { id: "part-4", title: "第四篇 生产与治理", chapters: [
    { file: "10-deploy-security.md", chapter: 10, title: "部署与安全", sources: ["docs/specification/2026-07-28/basic/authorization/index.mdx", "docs/2026-07-28/tutorials/security/security_best_practices.mdx"] },
    { file: "11-extensions.md", chapter: 11, title: "Agent Skills 与扩展生态", sources: ["docs/extensions/overview.mdx", "docs/2026-07-28/develop/build-with-agent-skills.mdx"] },
    { file: "12-adoption-roadmap.md", chapter: 12, title: "企业落地路线图", sources: [] },
  ]},
];

/**
 * 原创书无源文档链接映射,返回空 Map(接口与 agentscope-java.book.buildLinkMap 对齐)。
 * @returns {Map<string, string>} 空 Map
 */
function buildLinkMap() {
  return new Map();
}

// 构建映射类字段收敛为 book 字段(与 agentscope-java.mjs 同款,所有消费方从 book 出发)
Object.assign(book, { PARTS, EXCLUDED_SOURCES: [], buildLinkMap });
