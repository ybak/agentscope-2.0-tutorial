import { test } from 'node:test';
import assert from 'node:assert/strict';
import { resolveBookPaths } from './paths.mjs';
import { BUILDABLE_BOOKS, PLANNED_BOOKS, ALL_BOOKS } from './registry.mjs';

const FAKE_BOOK = { bookId: 'x', chaptersDir: 'books/x/chapters', assetsDir: 'books/x/assets',
  pdfFileName: 'x.pdf' };

test('resolveBookPaths 推导子站与产物路径', () => {
  const p = resolveBookPaths(FAKE_BOOK, '/repo');
  assert.equal(p.siteSubdir, 'x');
  assert.equal(p.chaptersAbs, '/repo/books/x/chapters');
  assert.equal(p.assetsAbs, '/repo/books/x/assets');
  assert.equal(p.siteDir, '/repo/output/site/x');
  assert.equal(p.htmlPath, '/repo/output/x/book.html');
  assert.equal(p.pdfPath, '/repo/output/x/x.pdf');
});

test('registry:仅 published 书持有 legacyRootChapters(旧站点根 chapters/ 所有权)', () => {
  assert.equal(BUILDABLE_BOOKS.length, 1);
  assert.equal(BUILDABLE_BOOKS[0].legacyRootChapters, true);
  for (const b of PLANNED_BOOKS) assert.equal('legacyRootChapters' in b, false);
});

test('registry:bookId 唯一且 agentscope-java 为唯一 published', () => {
  const ids = ALL_BOOKS.map((b) => b.bookId);
  assert.equal(new Set(ids).size, ids.length);
  assert.deepEqual(BUILDABLE_BOOKS.map((b) => b.bookId), ['agentscope-java']);
  for (const id of ['ragflow', 'copilotkit', 'langfuse', 'mcp'])
    assert.ok(PLANNED_BOOKS.some((b) => b.bookId === id));
});
