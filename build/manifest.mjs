/**
 * manifest.mjs — 旧入口兼容层（Task 1）
 *
 * 单一职责：转发。原「全书章节映射」已迁入 books/agentscope-java.mjs
 * （书配置模块，BOOK/PARTS 等与书级元数据同居一处），此处 re-export
 * 保持旧消费方（build.mjs / site.mjs / site.test.mjs）的 import 路径不变。
 * 新代码请直接从 books/agentscope-java.mjs 或 books/registry.mjs 导入。
 */

export { BOOK, PARTS, buildLinkMap, EXCLUDED_SOURCES } from './books/agentscope-java.mjs';
