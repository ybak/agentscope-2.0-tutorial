# 站点模式(`--site`)设计文档

日期:2026-10-13
状态:待评审

## 背景与目标

`chapters/` 的 7 篇 44 章教程此前只有两种消费形态:GitHub 上的 Markdown 渲染,与 `build/build.mjs --html` 产出的单文件 `output/book.html`(2.3MB,浏览器打开后 Paged.js 全书分页需 1-2 分钟才完整可读)。已上线的 GitHub Pages 单页版暴露了体验问题:文件大、首屏慢、无导航。

本设计为构建工具链新增 **`--site` 模式**:每章一个 HTML 的多页面静态站点,带侧边栏目录、上一篇/下一篇与全文搜索,作为 GitHub Pages 的发布形态。

**成功标准**:任意章节页首屏秒开;目录/跨章链接/图片/mermaid 图全部正常;中文全文搜索可用;`--html`/`--pdf` 既有行为逐字节不变;push 到 main 后 CI 自动发布。

## 非目标

- 不改动 `chapters/*.md` 内容与图片引用写法(`../assets/images/…` 保持原样);
- 不改动 `--check`/`--html`/`--pdf` 的现有行为(共享模块提取为纯重构,输出不变);
- 不做:深色主题、评论系统、阅读进度、移动端 App 式交互、服务端渲染;
- PDF 流程不受影响,仍走本地 `--pdf`(依赖本机 Edge)。

## 架构

### 文件布局

```
build/lib.mjs         新增:共享模块
build/site.mjs        新增:站点构建器(纯实现,不自行解析 argv)
build/build.mjs       修改:改从 lib.mjs import 共享件;main() 增加 --site 分发
build/assets/site.css 新增:仅站点布局样式(顶栏/侧边栏/响应式)
output/site/          产物(gitignore 已覆盖 output/):
  ├── index.html              首页:书名/简介 + 七篇卡片目录 + 搜索入口
  ├── search.html             搜索结果页(pagefind UI)
  ├── chapters/<file>.html    44 章 + 序言 + 6 篇导读 + 2 附录 ≈ 53 页
  ├── assets/…                仓库 assets/ 原样拷入
  ├── build/assets/vendor/mermaid.min.js
  └── pagefind/               pagefind 索引与运行时
```

### 共享模块提取(`build/lib.mjs`)

从 `build.mjs` 迁出并 `export`:markdown-it 实例 `md`(含 hljs 高亮与 mermaid fence 重写)、`escapeHtml`、`splitFrontMatter`、`toPosix`、`renderMermaidScripts()`(现 `renderTailScripts` 的无 Paged.js 分支,参数化 vendor 相对前缀)。`build.mjs` 改为 import,`--html`/`--pdf` 产物经 diff 验证不变。

### 页面结构

- 布局:顶栏(书名 + 搜索框)+ 左侧目录 + 正文 + 底部翻页。
- 目录:两级(篇 → 章),用 `<details open>` 折叠,**无 JS**;当前章 `<a>` 加高亮类,当前篇保持展开。篇标题链接到该篇导读页。
- 正文排版:复用 `assets/style.css` + highlight.js github 主题(内联,与 book.html 同源);`site.css` 只负责布局,不重复定义排版。
- mermaid:每页引 `../build/assets/vendor/mermaid.min.js`,DOMContentLoaded 后渲染(复用 `renderMermaidScripts`,站点页面位于 `chapters/` 下,该相对路径解析到 `output/site/build/assets/vendor/`,由构建器拷贝落位)。
- 首页 `index.html`:封面信息(书名/副标题/日期/整合说明)+ 七篇卡片(篇名 + 章列表)+ 搜索框。

### 导航与链接

- **扁平序列**(上一篇/下一篇依据):按 PARTS 顺序展开 = 序言 → 各篇(篇导读 → 各章)→ 附录 A → 附录 B;首页不进序列,`search.html` 不进序列。
- **章间链接重写**:渲染后的 HTML 中 `href="…md"` 形式的相对链接(同目录章节引用)重写为同名 `.html`;仅处理以 `.md` 结尾的相对 href,不碰锚点(`xx.md#sec` → `xx.html#sec`)、不碰外链与 `../assets`。
- **构建期校验**(告警不失败,与 `--check` 的体检风格一致):
  - 重写后仍残留的 `.md` href;
  - 引用的 `../assets/images/…` 文件不存在;
  - 章文件在 manifest 中缺失(复用现有「跳过 + warn」行为)。

### 搜索(pagefind)

- 构建后执行 `npx pagefind --site output/site`(CI)或 `npm run site`(本地,见下);pagefind 内置 CJK 分词,无需配置。
- `search.html` 引 pagefind 官方 UI(`@pagefind/default-ui`,作为 build/ 的 npm devDependency,构建时拷入 vendor),顶栏搜索框跳转该页并带 `?q=`。
- pagefind 索引仅覆盖 `chapters/*.html` 与 `index.html`。

### 构建入口与命令

- `node build.mjs --site`:产出 `output/site/`(页面与资源,不含 pagefind 索引);
- `build/package.json` 增加 script:`"site": "node build.mjs --site && pagefind --site output/site"`(`pagefind` 进 devDependencies,避免 CI 依赖 npx 网络拉取;路径相对 `build/` 执行,`output/site` 即 `../output/site`,由 npm 在 build/ 目录运行保证);
- vendor 同步扩展:`VENDOR_SCRIPTS` 增加 mermaid 项保持不变,site 构建额外拷贝 `@pagefind/default-ui` 产物至 `output/site/build/assets/vendor/`。

## CI/发布

`.github/workflows/pages.yml` 修改:

```
npm ci
npm run site        # 在 build/ 下执行 = node build.mjs --site + pagefind 索引
上传 artifact:output/site(产物自包含,原「组装站点目录」步骤删除)
deploy-pages
```

`.github/pages-index.html` 删除(真首页替代跳转页)。README 的「在线阅读全书」链接保持不变(URL 不变)。

## 错误处理

- 构建期告警(残留 `.md` 链接、缺图)打印到 stdout,不中断;与现有 `[build][warn]` 风格一致;
- chapter 文件缺失:跳过并 warn(现有行为);
- pagefind 失败:CI 步骤失败(搜索是承诺功能,不允许静默缺失);
- 站点页对 JS 关闭的降级:目录/正文/翻页全部可用(mermaid 图不渲染,正文不受影响)。

## 测试与验收

1. **回归**:`node build.mjs --html` 重跑,`output/book.html` 与重构前 diff 为空;
2. **单测**(`build/site.test.mjs`,`node --test`):链接重写函数、扁平序列生成、href 校验;
3. **本地验收**:http.server 起 `output/site/`,浏览器验证——首页卡片/侧边栏高亮与折叠/上一篇下一篇/图片(7 张)/mermaid(抽 3 章)/搜索「工作区」有结果/禁 JS 时目录可导航;
4. **CI**:Actions 绿;线上 `https://ybak.github.io/agentscope-2.0-tutorial/` 抽查同上。

## 风险与权衡

- **自建 vs 文档生成器**:已评审,MkDocs/VitePress 与现有目录约定、排版风格、工具链冲突,自建扩展复用度最高;
- **pagefind 依赖体积**:索引约数 MB,远低于 Pages 限制;
- **style.css 复用风险**:书籍排版样式含 print/分页规则,站点页可能出现无关样式副作用——以正文容器类名约定(`.chapter` 内排版)隔离,发现冲突在 `site.css` 以更高特异性覆盖。
