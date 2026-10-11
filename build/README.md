# build/ — 构建工具链

本仓库（agentscope-2.0-tutorial）是全书的**唯一事实源**：`chapters/` 是 7 篇 44 章 + 序言 + 附录的人工整理稿，`assets/images/` 是全部本地化图片。`build/` 只负责把 Markdown 变成 PDF，不含内容。

## 目录角色

| 路径 | 角色 |
| --- | --- |
| `chapters/` | 书稿正文（图片引用 `../assets/images/…`，相对 `output/book.html` 解析到仓库 `assets/`） |
| `assets/images/` | 本地化图片（`fetch-images.mjs` 下载落位） |
| `build/*.mjs` `add_outline.py` | 构建管线（本目录） |
| `build/assets/style.css` | 书籍排版样式（构建时内联进 HTML） |
| `build/assets/vendor/` | mermaid/pagedjs 运行时，构建时自动从 `node_modules` 同步，不入库 |
| `output/` | 构建产物：`book.html`、PDF、`.outline.json`（已 gitignore） |

## 三条命令（在 `build/` 下）

```bash
npm install            # 首次：装 markdown-it / highlight.js / mermaid / pagedjs
pip install pymupdf    # 首次：书签步骤 add_outline.py 依赖 PyMuPDF（import fitz）
node build.mjs --check # 全源体检：JSX 残留 / 站内链接 / 覆盖率（不写文件）
node build.mjs --html  # 只产出 output/book.html（浏览器可直接打开）
node build.mjs --pdf   # HTML + Edge headless 打印 → output/*.pdf + PyMuPDF 补书签，约 10-20 分钟（含书签保存）
```

辅助：`node --test clean.test.mjs` 跑清洗规则单测；`node fetch-images.mjs` 把章节里的远程图片下载到 `assets/images/` 并改写引用。

## 上游更新流程

上游文档在只读仓库 `../agentscope-java/docs/v2/zh`（`--check` 依赖它，位置由 `build.mjs` 的 `SRC_DIR` 推导）。上游变更后：

1. 重新整合/校对受影响章节 → 直接改本仓库 `chapters/*.md`；
2. `node build.mjs --check` 确认体检仍绿（未覆盖清单 == 排除清单，JSX 残留 0）；
3. 提交 `chapters/`；
4. `node build.mjs --pdf` 出新 PDF，连同变更一起发布。

新增章节需同步登记 `manifest.mjs`（篇/章/源文件映射 + 书签大纲的数据源）。

## 机制一句话

- **图片**：章节统一写 `../assets/images/…`——因为 `book.html` 落在 `output/`，该相对路径恰好解析到仓库 `assets/`，构建零路径改写；`fetch-images.mjs` 负责把微信图床外链换成本地哈希文件名。
- **书签**：Edge 打印不生成 PDF outline，`build.mjs` 从 manifest 生成大纲写到 `output/.outline.json`，再调 `add_outline.py`（PyMuPDF）按「大字标题」定位各章页码写入书签与元数据；任何一章定位失败即整体构建失败。

## 机器相关常量

`build.mjs` 的 `EDGE_PATH` 硬编码本机 Edge 路径（`C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe`），换机器需按实际安装位置调整；打印走 CDP `Page.printToPDF`（`preferCSSPageSize` 跟随 A4），不用 `--print-to-pdf` CLI（纸张恒为 Letter 会截断页面盒）。
