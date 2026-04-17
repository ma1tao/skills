#!/usr/bin/env python3
"""
党政机关公文标准排版脚本 (GB/T 9704-2012)
支持多种输入格式：Markdown(.md)、纯文本(.txt)、Word(.docx)、直接文本

用法:
    python3 gongwen_format.py --title "标题" --input content.md --output output.docx
    python3 gongwen_format.py --title "标题" --input content.txt --output output.docx --author "XX镇人民政府" --date "2026-04-16"
    python3 gongwen_format.py --title "标题" --input content.txt --output output.docx --print-author "XX镇人民政府办公室" --print-date "2026-04-17"
"""

import re
import argparse
import os
from datetime import datetime
from docx import Document
from docx.shared import Pt, Cm, Emu, RGBColor
from docx.enum.text import WD_ALIGN_PARAGRAPH, WD_LINE_SPACING
from docx.enum.section import WD_ORIENT
from docx.oxml.ns import qn, nsdecls
from docx.oxml import parse_xml

# ========== 字体字号映射 ==========
FONT_TITLE = 'FZXiaoBiaoSong-B05S'
FONT_HEITI = 'SimHei'
FONT_KAITI = 'KaiTi'
FONT_FANGSONG = 'FangSong'
FONT_SONGTI = 'SimSun'
FONT_TNR = 'Times New Roman'

SIZE_ERHAO = Pt(22)
SIZE_SANHAO = Pt(16)
SIZE_SIHAO = Pt(14)

LEVEL1_PATTERNS = [re.compile(r'^[一二三四五六七八九十]+、'), re.compile(r'^第[一二三四五六七八九十]+[部分章节篇]')]
LEVEL2_PATTERNS = [re.compile(r'^[（\(][一二三四五六七八九十]+[）\)]')]
LEVEL3_PATTERNS = [re.compile(r'^\d+[\.．]')]
LEVEL4_PATTERNS = [re.compile(r'^[（\(]\d+[）\)]')]
ATTACHMENT_PATTERN = re.compile(r'^附件[：:]\s*(.*)')


def format_date(date_str):
    date_str = date_str.strip()
    if re.match(r'^\d{4}年\d{1,2}月\d{1,2}日', date_str):
        return date_str
    m = re.match(r'^(\d{4})[-/](\d{1,2})[-/](\d{1,2})', date_str)
    if m:
        return f'{m.group(1)}年{int(m.group(2))}月{int(m.group(3))}日'
    return date_str


def set_page_layout(section):
    section.page_width = Cm(21)
    section.page_height = Cm(29.7)
    section.top_margin = Cm(3.7)
    section.bottom_margin = Cm(3.5)
    section.left_margin = Cm(2.8)
    section.right_margin = Cm(2.6)


def _set_run_font(run, cn_font, size, bold=False):
    run.font.size = size
    run.font.bold = bold
    run.font.name = FONT_TNR
    rpr = run._element.get_or_add_rPr()
    rFonts = rpr.find(qn('w:rFonts'))
    if rFonts is None:
        rFonts = parse_xml(f'<w:rFonts {nsdecls("w")} w:ascii="{FONT_TNR}" w:hAnsi="{FONT_TNR}" w:eastAsia="{cn_font}"/>')
        rpr.insert(0, rFonts)
    else:
        rFonts.set(qn('w:ascii'), FONT_TNR)
        rFonts.set(qn('w:hAnsi'), cn_font)
        rFonts.set(qn('w:eastAsia'), cn_font)


def _set_songti(run):
    run.font.size = SIZE_SIHAO
    run.font.name = FONT_SONGTI
    rpr = run._element.get_or_add_rPr()
    rFonts = rpr.find(qn('w:rFonts'))
    if rFonts is None:
        rFonts = parse_xml(f'<w:rFonts {nsdecls("w")} w:ascii="{FONT_SONGTI}" w:hAnsi="{FONT_SONGTI}" w:eastAsia="{FONT_SONGTI}"/>')
        rpr.insert(0, rFonts)
    else:
        rFonts.set(qn('w:ascii'), FONT_SONGTI)
        rFonts.set(qn('w:hAnsi'), FONT_SONGTI)
        rFonts.set(qn('w:eastAsia'), FONT_SONGTI)


def add_title(doc, title_text):
    p = doc.add_paragraph()
    p.alignment = WD_ALIGN_PARAGRAPH.CENTER
    p.paragraph_format.space_before = Pt(0)
    p.paragraph_format.space_after = Pt(0)
    p.paragraph_format.line_spacing_rule = WD_LINE_SPACING.EXACTLY
    p.paragraph_format.line_spacing = Pt(32)
    p.paragraph_format.first_line_indent = None
    run = p.add_run(title_text)
    _set_run_font(run, FONT_TITLE, SIZE_ERHAO, bold=True)
    return p


def add_body_paragraph(doc, text, level=0):
    p = doc.add_paragraph()
    p.alignment = WD_ALIGN_PARAGRAPH.JUSTIFY
    p.paragraph_format.space_before = Pt(0)
    p.paragraph_format.space_after = Pt(0)
    p.paragraph_format.line_spacing_rule = WD_LINE_SPACING.EXACTLY
    p.paragraph_format.line_spacing = Pt(28)
    p.paragraph_format.first_line_indent = Cm(1.13)
    font_map = {0: FONT_FANGSONG, 1: FONT_HEITI, 2: FONT_KAITI, 3: FONT_FANGSONG, 4: FONT_FANGSONG}
    run = p.add_run(text)
    _set_run_font(run, font_map.get(level, FONT_FANGSONG), SIZE_SANHAO)
    return p


def add_attachment(doc, attachment_text):
    p = doc.add_paragraph()
    p.alignment = WD_ALIGN_PARAGRAPH.JUSTIFY
    p.paragraph_format.space_before = Pt(0)
    p.paragraph_format.space_after = Pt(0)
    p.paragraph_format.line_spacing_rule = WD_LINE_SPACING.EXACTLY
    p.paragraph_format.line_spacing = Pt(28)
    p.paragraph_format.first_line_indent = Cm(1.13)
    run = p.add_run(f'附件：{attachment_text}')
    _set_run_font(run, FONT_FANGSONG, SIZE_SANHAO)
    return p


def add_page_number(doc):
    """添加页码：四号宋体，-1- 格式，居中"""
    for section in doc.sections:
        footer = section.footer
        footer.is_linked_to_previous = False
        for p in footer.paragraphs:
            p.clear()
        p = footer.paragraphs[0]
        p.alignment = WD_ALIGN_PARAGRAPH.CENTER

        # 左横线
        dash1 = p.add_run('-')
        _set_songti(dash1)

        # PAGE 域
        r_begin = p.add_run()
        r_begin._element.append(parse_xml(f'<w:fldChar {nsdecls("w")} w:fldCharType="begin"/>'))
        _set_songti(r_begin)

        r_instr = p.add_run()
        r_instr._element.append(parse_xml(f'<w:instrText {nsdecls("w")} xml:space="preserve"> PAGE </w:instrText>'))
        _set_songti(r_instr)

        r_sep = p.add_run()
        r_sep._element.append(parse_xml(f'<w:fldChar {nsdecls("w")} w:fldCharType="separate"/>'))
        _set_songti(r_sep)

        r_end = p.add_run()
        r_end._element.append(parse_xml(f'<w:fldChar {nsdecls("w")} w:fldCharType="end"/>'))
        _set_songti(r_end)

        # 右横线
        dash2 = p.add_run('-')
        _set_songti(dash2)
        break


# ========== 输入格式处理 ==========

def detect_level_from_text(text):
    text = text.strip()
    if not text:
        return None
    for pat in LEVEL1_PATTERNS:
        if pat.match(text): return 1
    for pat in LEVEL2_PATTERNS:
        if pat.match(text): return 2
    for pat in LEVEL3_PATTERNS:
        if pat.match(text): return 3
    for pat in LEVEL4_PATTERNS:
        if pat.match(text): return 4
    return 0


def detect_level(line):
    line_stripped = line.strip()
    if not line_stripped:
        return None, None
    if line_stripped.startswith('## ') and not line_stripped.startswith('### '):
        text = re.sub(r'\*\*(.+?)\*\*', r'\1', line_stripped[3:].strip())
        return 1, text
    if line_stripped.startswith('### '):
        text = re.sub(r'\*\*(.+?)\*\*', r'\1', line_stripped[4:].strip())
        return 2, text
    clean = re.sub(r'\*\*(.+?)\*\*', r'\1', line_stripped).strip()
    if not clean:
        return None, None
    level = detect_level_from_text(clean)
    return level, clean


def normalize_content(content):
    result, i = [], 0
    while i < len(content):
        if content[i] == '"' and i + 1 < len(content):
            close = content.find('"', i + 1)
            if close != -1:
                result.append('\u201c')
                result.append(content[i+1:close])
                result.append('\u201d')
                i = close + 1
                continue
        result.append(content[i])
        i += 1
    return ''.join(result)


def read_input(filepath):
    ext = os.path.splitext(filepath)[1].lower()
    if ext == '.docx':
        doc = Document(filepath)
        lines = [para.text.strip() for para in doc.paragraphs if para.text.strip()]
        return normalize_content('\n'.join(lines)), False
    with open(filepath, 'r', encoding='utf-8') as f:
        content = f.read()
    return normalize_content(content), (ext == '.md')


def split_heading_and_body(text, level):
    if level != 2:
        return [(text, level)]
    dot_pos = text.find('。')
    if dot_pos == -1:
        return [(text, level)]
    heading, body = text[:dot_pos + 1], text[dot_pos + 1:].strip()
    if not body:
        return [(text, level)]
    return [(heading, level), (body, 0)]


def parse_and_add_content(doc, content):
    lines = content.split('\n')
    for line in lines:
        stripped = line.strip()
        if not stripped:
            continue
        att_match = ATTACHMENT_PATTERN.match(stripped)
        if att_match:
            att_text = att_match.group(1).strip()
            add_attachment(doc, att_text if att_text else '（见附件）')
            continue
        level, text = detect_level(line)
        if level is None or not text:
            continue
        for part_text, part_level in split_heading_and_body(text, level):
            add_body_paragraph(doc, part_text, level=part_level)


def main():
    parser = argparse.ArgumentParser(description='党政机关公文标准排版')
    parser.add_argument('--title', required=True, help='公文标题')
    parser.add_argument('--input', required=True, help='输入文件（.md / .txt / .docx）')
    parser.add_argument('--output', required=True, help='输出Word文件路径')
    parser.add_argument('--author', default='', help='发文机关名称')
    parser.add_argument('--date', default='', help='成文日期（自动格式化）')
    parser.add_argument('--print-author', default='', help='印发机关')
    parser.add_argument('--print-date', default='', help='印发日期（自动格式化）')
    args = parser.parse_args()

    content, _ = read_input(args.input)

    doc = Document()
    set_page_layout(doc.sections[0])

    add_title(doc, args.title)

    spacer = doc.add_paragraph()
    spacer.paragraph_format.space_before = Pt(0)
    spacer.paragraph_format.space_after = Pt(0)
    spacer.paragraph_format.line_spacing_rule = WD_LINE_SPACING.EXACTLY
    spacer.paragraph_format.line_spacing = Pt(28)

    parse_and_add_content(doc, content)

    if args.author or args.date:
        for _ in range(3):
            doc.add_paragraph()
        if args.author:
            p = doc.add_paragraph()
            p.alignment = WD_ALIGN_PARAGRAPH.RIGHT
            p.paragraph_format.right_indent = Cm(1.3)
            p.paragraph_format.line_spacing_rule = WD_LINE_SPACING.EXACTLY
            p.paragraph_format.line_spacing = Pt(28)
            run = p.add_run(args.author)
            _set_run_font(run, FONT_FANGSONG, SIZE_SANHAO)
        if args.date:
            p = doc.add_paragraph()
            p.alignment = WD_ALIGN_PARAGRAPH.RIGHT
            p.paragraph_format.right_indent = Cm(1.3)
            p.paragraph_format.line_spacing_rule = WD_LINE_SPACING.EXACTLY
            p.paragraph_format.line_spacing = Pt(28)
            run = p.add_run(format_date(args.date))
            _set_run_font(run, FONT_FANGSONG, SIZE_SANHAO)

    if args.print_author or args.print_date:
        for _ in range(2):
            doc.add_paragraph()
        print_text = ''
        if args.print_author and args.print_date:
            print_text = f'{args.print_author}            {format_date(args.print_date)}印发'
        elif args.print_author:
            print_text = args.print_author
        elif args.print_date:
            print_text = f'{format_date(args.print_date)}印发'
        if print_text:
            p = doc.add_paragraph()
            p.alignment = WD_ALIGN_PARAGRAPH.CENTER
            p.paragraph_format.line_spacing_rule = WD_LINE_SPACING.EXACTLY
            p.paragraph_format.line_spacing = Pt(28)
            run = p.add_run(print_text)
            _set_run_font(run, FONT_FANGSONG, SIZE_SANHAO)

    add_page_number(doc)

    out_dir = os.path.dirname(os.path.abspath(args.output))
    if out_dir:
        os.makedirs(out_dir, exist_ok=True)
    doc.save(args.output)
    print(f"✅ 公文已生成: {args.output}")


if __name__ == '__main__':
    main()
