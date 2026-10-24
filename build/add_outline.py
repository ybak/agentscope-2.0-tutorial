#!/usr/bin/env python3
"""
add_outline.py — 给构建出的 PDF 写侧边栏书签（outline/TOC）与元数据。

背景：Edge headless 打印（CDP Page.printToPDF）不生成 PDF outline，
纸面目录页之外需要程序化补写书签，阅读软件侧边栏才有目录。

用法：
    python build/add_outline.py <pdf_path> <outline.json>

outline.json 由 build.mjs 从书配置的章节映射（book.PARTS，books/<bookId>.mjs）生成，形如：
    [{"level": 1, "title": "序言", "key": "preface"},
     {"level": 1, "title": "第一篇 起步", "key": "part:第一篇 起步"},
     {"level": 2, "title": "第 1 章 初识 AgentScope 2.0", "key": "ch:1"},
     {"level": 2, "title": "附录 A：Release Notes（v2）", "key": "appendix-a"}]
条目按文档顺序排列；key 取值：
    preface      序言章（大字标题以「序言」开头）
    part:<标题>  篇扉页（从标题提取「第 X 篇」中文数字匹配）
    ch:<N>       章首页（「第 N 章」大字标题）
    appendix     附录部（锚在第一个附录条目页，附录无独立扉页）
    appendix-a/b 附录 A / 附录 B

定位规则（防误匹配）：
- 章页 H1 为 19pt 大字、篇扉页 22pt；页眉 8pt、目录条目 10.5pt、节标题 14.5pt。
  因此只在 >= HEADING_MIN_PT 的文本里匹配（页眉逐页重复章标题、篇导读正文
  与交叉引用也会出现「第 N 章」字样，纯文本匹配必误报）。
- 目录页本身虽无大字条目，仍先定位目录页范围（含「目录」大标题的页起、
  至下一个含大字标题的页止），从其后一页开始搜索（双保险）。
- 顺序单调：按 JSON 顺序从上一个命中页起向后找，取首次出现页。
- 任何目标定位失败 → 列出缺失清单，exit 1（fail-loud，与 %%EOF 守卫同标准）。

保存：写临时文件后 os.replace 原子替换；落盘前复查 %%EOF 完整性。
"""

import json
import os
import re
import sys
import time

import fitz  # PyMuPDF

# 章页 H1 19pt / 篇扉页 22pt；节标题 14.5pt、页眉 8pt、目录条目 10.5pt 均低于此阈值
HEADING_MIN_PT = 16.0
# 保存后复查完整性的窗口大小（字节）
EOF_WINDOW = 2048
# os.replace 遇目标被占用（阅读器/杀软短暂锁定）时的重试
REPLACE_RETRIES = 3
REPLACE_WAIT_S = 3

BOOK_TITLE = "AgentScope Java 2.0：从入门到进阶"
BOOK_AUTHOR = "AgentScope Java 官方文档整合"
BOOK_CREATOR = "book pipeline"

CN_NUM = r"[一二三四五六七八九十]+"


def fail(msg):
    print(f"[outline] 错误: {msg}", file=sys.stderr)
    sys.exit(1)


_heading_cache = {}  # 页下标 → 大字标题文本（全文扫描只解析一遍）


def page_heading_text(doc, i):
    """拼接一页中所有 >= HEADING_MIN_PT 的 span 文本（行内直接相连、行间补空格），
    用于匹配章/篇/序言/附录的大字标题（标题跨行/跨 span 时仍能命中章号前缀）。"""
    if i not in _heading_cache:
        chunks = []
        for block in doc[i].get_text("dict")["blocks"]:
            for line in block.get("lines", []):
                t = "".join(
                    s["text"] for s in line["spans"] if s["size"] >= HEADING_MIN_PT
                )
                if t.strip():
                    chunks.append(t.strip())
        _heading_cache[i] = " ".join(chunks)
    return _heading_cache[i]


def key_pattern(key):
    """outline key → 在大字文本上匹配的正则（均可匹配空格/全角空格分隔）。"""
    if key == "preface":
        return re.compile(r"序言")
    if key == "appendix":
        return re.compile(r"附录\s*[AB]")
    m = re.fullmatch(r"appendix-([ab])", key)
    if m:
        return re.compile(rf"附录\s*{m.group(1).upper()}")
    m = re.fullmatch(r"ch:(\d+)", key)
    if m:
        return re.compile(rf"第\s*{m.group(1)}\s*章")
    m = re.fullmatch(rf"part:(第({CN_NUM})篇.*)", key)
    if m:
        # 优先按「第 X 篇」中文数字匹配扉页，篇标题文字可能与 book.PARTS 配置略异
        return re.compile(rf"第\s*{m.group(2)}\s*篇")
    fail(f"无法识别的大纲 key: {key!r}")


def locate_toc_start(doc):
    """定位目录页范围：从含「目录」大标题的页起，连续向后吞掉无大字标题的页
    （目录延续页），返回搜索起始页下标（目录范围之后一页）。"""
    titled = [
        i
        for i in range(doc.page_count)
        if re.fullmatch(r"\s*目录\s*", page_heading_text(doc, i))
    ]
    if not titled:
        fail("未找到含「目录」大标题的目录页——页面结构可能已变化")
    start = titled[0]
    end = start
    while end + 1 < doc.page_count and not page_heading_text(doc, end + 1).strip():
        end += 1
    return end + 1


def main():
    if len(sys.argv) != 3:
        print(f"用法: python {sys.argv[0]} <pdf_path> <outline.json>", file=sys.stderr)
        sys.exit(1)
    pdf_path, outline_path = sys.argv[1], sys.argv[2]

    try:
        with open(outline_path, encoding="utf-8") as f:
            outline = json.load(f)
    except (OSError, json.JSONDecodeError) as e:
        fail(f"读取大纲 JSON 失败 {outline_path}: {e}")
    if not isinstance(outline, list) or not outline:
        fail(f"大纲 JSON 为空或不是数组: {outline_path}")

    for i, item in enumerate(outline):
        if not isinstance(item, dict) or not {"level", "title", "key"} <= item.keys():
            fail(f"大纲第 {i + 1} 条缺少 level/title/key 字段: {item!r}")

    try:
        doc = fitz.open(pdf_path)
    except Exception as e:  # noqa: BLE001 — PyMuPDF 异常统一 fail-loud
        fail(f"打开 PDF 失败 {pdf_path}: {e}")

    t0 = time.monotonic()
    search_from = locate_toc_start(doc)
    print(f"[outline] 目录页之后开始定位，起始页: p{search_from + 1}（1-based）")

    entries = []  # PyMuPDF toc: [level(1-based), title, page(1-based)]
    resolved = []
    missing = []
    cursor = search_from
    for item in outline:
        pat = key_pattern(item["key"])
        hit = None
        for i in range(cursor, doc.page_count):
            if pat.search(page_heading_text(doc, i)):
                hit = i
                break
        if hit is None:
            missing.append(f"level {item['level']} «{item['title']}» (key={item['key']})")
            continue
        cursor = hit  # 同页允许多个条目（如 level1 附录与附录 A）
        entries.append([item["level"], item["title"], hit + 1])
        resolved.append((item["level"], item["title"], hit + 1))

    if missing:
        print(f"[outline] {len(missing)} 个目标未在文本层定位到（搜索起点 p{search_from + 1}）:",
              file=sys.stderr)
        for m in missing:
            print(f"[outline]   - {m}", file=sys.stderr)
        doc.close()
        sys.exit(1)

    try:
        doc.set_toc(entries)
        doc.set_metadata(
            {
                "title": BOOK_TITLE,
                "author": BOOK_AUTHOR,
                "creator": BOOK_CREATOR,
            }
        )
    except Exception as e:  # noqa: BLE001
        fail(f"写入书签/元数据失败: {e}")

    # 原子替换：写临时文件 → 复查 %%EOF → os.replace（目标被阅读器/杀软短暂
    # 锁定时按 REPLACE_RETRIES 重试，仍失败则放弃——原文件保持不动）
    tmp_path = f"{pdf_path}.tmp"
    try:
        doc.save(tmp_path, garbage=3, deflate=True)
        doc.close()
        with open(tmp_path, "rb") as f:
            f.seek(0, os.SEEK_END)
            size = f.tell()
            f.seek(max(0, size - EOF_WINDOW))
            if b"%%EOF" not in f.read():
                raise RuntimeError("保存结果缺少 %%EOF——疑似截断，放弃替换")
        print(f"[outline] 定位+保存耗时 {time.monotonic() - t0:.1f}s"
              f"（garbage=3 对大文件较慢），开始替换")
        for attempt in range(1, REPLACE_RETRIES + 1):
            try:
                os.replace(tmp_path, pdf_path)
                break
            except PermissionError:
                if attempt == REPLACE_RETRIES:
                    raise
                print(f"[outline] 目标被占用（阅读器/杀软锁定？），{REPLACE_WAIT_S}s 后重试"
                      f"（{attempt + 1}/{REPLACE_RETRIES}）", file=sys.stderr)
                time.sleep(REPLACE_WAIT_S)
    except Exception as e:  # noqa: BLE001
        try:
            doc.close()
        except Exception:  # noqa: BLE001
            pass
        if os.path.exists(tmp_path):
            os.unlink(tmp_path)
        fail(f"保存 PDF 失败: {e}")

    print(f"[outline] 书签 {len(entries)} 条 + 元数据已写入（原子替换，"
          f"总耗时 {time.monotonic() - t0:.1f}s）: {pdf_path}")
    for lvl, title, pg in resolved:
        indent = "  " * (lvl - 1)
        print(f"[outline]   {indent}L{lvl} p{pg:>4}  {title}")


if __name__ == "__main__":
    main()
