#!/usr/bin/env python3
import re
import sys
import zipfile
import json
import html
import xml.etree.ElementTree as ET

report, refdoc = sys.argv[1], sys.argv[2]

zr = zipfile.ZipFile(report)
rparts = {n: zr.read(n) for n in zr.namelist()}
zr.close()
zf = zipfile.ZipFile(refdoc)
fparts = {n: zf.read(n) for n in zf.namelist()}
zf.close()

rs = rparts["word/styles.xml"].decode("utf8")
fs = fparts["word/styles.xml"].decode("utf8")

def block(xml, sid):
    m = re.search(r'<w:style [^>]*w:styleId="%s".*?</w:style>' % re.escape(sid), xml, re.S)
    return m.group(0) if m else None

rids = re.findall(r'<w:style [^>]*w:styleId="([^"]+)"', rs)
fids = re.findall(r'<w:style [^>]*w:styleId="([^"]+)"', fs)

m = re.search(r"<w:docDefaults>.*?</w:docDefaults>", fs, re.S)
if m:
    rs = re.sub(r"<w:docDefaults>.*?</w:docDefaults>", lambda _: m.group(0), rs, flags=re.S)

replaced = added = 0
for sid in fids:
    fb = block(fs, sid)
    if not fb:
        continue
    rb = block(rs, sid)
    if rb:
        rs = rs.replace(rb, fb, 1)
        replaced += 1
    else:
        rs = rs.replace("</w:styles>", fb + "</w:styles>", 1)
        added += 1
rparts["word/styles.xml"] = rs.encode("utf8")

def _ensure_caption_styles(xml):
    cap = block(xml, "Caption")
    if not cap:
        raise SystemExit("no Caption style to derive the caption styles from")
    out = xml
    for sid, nm in (("TableCaption", "Table Caption"), ("FigureCaption", "Figure Caption")):
        if block(out, sid):
            continue
        clone = cap.replace('w:styleId="Caption"', 'w:styleId="%s"' % sid, 1)
        clone = re.sub(r'<w:name w:val="[^"]*"\s*/>', '<w:name w:val="%s"/>' % nm, clone, count=1)
        clone = re.sub(r'<w:link w:val="[^"]*"\s*/>', "", clone, count=1)
        out = out.replace("</w:styles>", clone + "</w:styles>", 1)
    return out

rs = _ensure_caption_styles(rs)
for sid in ("TableCaption", "FigureCaption"):
    assert block(rs, sid), "caption style %s missing after injection" % sid

def _caption_look(xml):
    for sid in ("Caption", "TableCaption", "FigureCaption"):
        b = block(xml, sid)
        if not b:
            continue
        nb = b
        if "<w:rPr>" not in nb:
            nb = nb.replace("</w:style>", "<w:rPr></w:rPr></w:style>", 1)
        if not re.search(r"<w:b/?>", nb):
            nb = nb.replace("<w:rPr>", "<w:rPr><w:b/><w:bCs/>", 1)
        nb = re.sub(r'<w:sz w:val="[0-9]+"\s*/>', '<w:sz w:val="21"/>', nb)
        nb = re.sub(r'<w:szCs w:val="[0-9]+"\s*/>', '<w:szCs w:val="21"/>', nb)
        if '<w:sz w:val="21"/>' not in nb:
            nb = nb.replace("<w:rPr>", '<w:rPr><w:sz w:val="21"/><w:szCs w:val="21"/>', 1)
        xml = xml.replace(b, nb, 1)
    return xml

rs = _caption_look(rs)
rparts["word/styles.xml"] = rs.encode("utf8")

rd = rparts["word/document.xml"].decode("utf8")
fd = fparts["word/document.xml"].decode("utf8")

fsect = re.search(r"<w:sectPr.*?</w:sectPr>", fd, re.S)
if not fsect:
    raise SystemExit("reference has no sectPr - build it with patch_reference.py first")
fsect = fsect.group(0)

# Resolve the reference footer to a numeric relationship id in the destination package.
# Do not reintroduce the legacy named id, or assume ids agree between two DOCX files.
if "word/footer1.xml" in fparts:
    rel_ns = "http://schemas.openxmlformats.org/package/2006/relationships"
    ET.register_namespace("", rel_ns)
    report_rels = ET.fromstring(rparts["word/_rels/document.xml.rels"])
    ref_rels = ET.fromstring(fparts["word/_rels/document.xml.rels"])
    footer_type = "http://schemas.openxmlformats.org/officeDocument/2006/relationships/footer"
    existing = next((e for e in report_rels if e.get("Type") == footer_type and
                     e.get("Target", "").lstrip("/") in ("footer1.xml", "word/footer1.xml")), None)
    used = {e.get("Id", "") for e in report_rels}
    next_id = "rId" + str(max([int(x[3:]) for x in used if re.fullmatch(r"rId[0-9]+", x)] + [0]) + 1)
    if existing is None:
        footer_id = next_id
        ET.SubElement(report_rels, "{" + rel_ns + "}Relationship",
                      Id=footer_id, Type=footer_type, Target="footer1.xml")
    else:
        old_id = existing.get("Id", "")
        footer_id = old_id if re.fullmatch(r"rId[0-9]+", old_id) else next_id
        existing.set("Id", footer_id)
        if old_id != footer_id:
            rd = rd.replace('r:id="' + old_id + '"', 'r:id="' + footer_id + '"')
    for e in ref_rels:
        if e.get("Type") == footer_type and e.get("Target", "").lstrip("/") in ("footer1.xml", "word/footer1.xml"):
            fsect = fsect.replace('r:id="' + e.get("Id", "") + '"', 'r:id="' + footer_id + '"')
    rparts["word/footer1.xml"] = fparts["word/footer1.xml"]
    rparts["word/_rels/document.xml.rels"] = ET.tostring(report_rels, encoding="utf-8", xml_declaration=True)
    ct = rparts["[Content_Types].xml"].decode("utf8")
    if 'PartName="/word/footer1.xml"' not in ct:
        ct = ct.replace("</Types>", '<Override PartName="/word/footer1.xml" ContentType="application/'
                        'vnd.openxmlformats-officedocument.wordprocessingml.footer+xml"/></Types>')
    rparts["[Content_Types].xml"] = ct.encode("utf8")

rdoc = re.search(r"<w:sectPr.*?</w:sectPr>", rd, re.S)
if rdoc:
    keep = re.findall(r"<w:footnotePr>.*?</w:footnotePr>", rdoc.group(0), re.S)
    new = fsect
    for k in keep:
        if k not in new:
            new = new.replace("</w:sectPr>", k + "</w:sectPr>")
    rd = rd[:rdoc.start()] + new + rd[rdoc.end():]
else:
    rd = rd.replace("</w:body>", fsect + "</w:body>")
assert "w:pgSz" in rd, "page geometry missing after patch"
assert "footerReference" in rd, "footer reference missing after patch"
rparts["word/document.xml"] = rd.encode("utf8")

def _toc_field(levels, kind=None):
    instr = ' TOC \\o "' + levels + '" \\h \\z \\u '
    if kind:
        instr = ' TOC \\h \\z \\t "' + kind + ' Caption,1" '
    return (
        '<w:p><w:pPr><w:pStyle w:val="TOC1"/>'
        '<w:tabs><w:tab w:val="right" w:leader="dot" w:pos="7086"/></w:tabs>'
        '<w:spacing w:before="0" w:after="0"/></w:pPr>'
        '<w:r><w:fldChar w:fldCharType="begin" w:dirty="true"/></w:r>'
        '<w:r><w:instrText xml:space="preserve">' + instr + '</w:instrText></w:r>'
        '<w:r><w:fldChar w:fldCharType="separate"/></w:r>'
        '<w:r><w:rPr><w:rFonts w:ascii="Arial" w:hAnsi="Arial"/><w:i/>'
        '<w:color w:val="808080"/><w:sz w:val="18"/></w:rPr>'
        '<w:t xml:space="preserve"> </w:t></w:r>'
        '<w:r><w:fldChar w:fldCharType="end"/></w:r></w:p>')

_bookmark_id = 10000
def _bookmark_caption(m):
    global _bookmark_id
    _bookmark_id += 1
    """Give a caption paragraph a bookmark and its caption style, keeping the text."""
    para = m.group(0)
    txt = re.search(r"<w:t[^>]*>([^<]+)</w:t>", para)
    if not txt:
        return para
    label = txt.group(1)
    if not re.match(r"\s*(Figure|Table)\s+[0-9A-Z]+", label):
        return para
    sid = "TableCaption" if label.strip().startswith("Table") else "FigureCaption"
    if '<w:pStyle w:val="Caption"/>' in para:
        para = para.replace('<w:pStyle w:val="Caption"/>',
                            '<w:pStyle w:val="%s"/>' % sid, 1)
    key = re.sub(r"[^A-Za-z0-9]+", "_", label.strip())[:36]
    bid = "pmx_" + key
    if 'w:name="' + bid + '"' in para:
        return para
    start = '<w:bookmarkStart w:id="' + str(_bookmark_id) + '" w:name="' + bid + '"/>'
    end = '<w:bookmarkEnd w:id="' + str(_bookmark_id) + '"/>'
    if "</w:pPr>" in para:
        para = para.replace("</w:pPr>", "</w:pPr>" + start, 1)
    else:
        para = re.sub(r"^(<w:p(?:\s[^>]*)?>)", lambda m: m.group(1) + start, para, count=1)
    return para.replace("</w:p>", end + "</w:p>", 1)

rd = re.sub(r"<w:p(?:\s[^>]*)?>(?:(?!</w:p>).)*?"
            r"(?:<w:t[^>]*>)"
            r"(?:Figure|Table)\s+[0-9A-Z]+[.:](?:(?!</w:p>).)*?</w:p>",
            _bookmark_caption, rd, flags=re.S)

# Stable asset tokens are resolved against the actual Word-included assets, after filtering.
# Keep XML as text so the reference document's namespace/compatibility declarations survive.
_para = re.compile(r"<w:p(?:\s[^>]*)?>(?:(?!</w:p>).)*?</w:p>", re.S)
def _text(para):
    return html.unescape("".join(re.findall(r"<w:t(?:\s[^>]*)?>(.*?)</w:t>", para, re.S)))
def _normal_body(xml):
    xml = re.sub(r"<w:tbl(?:\s[^>]*)?>.*?</w:tbl>", "", xml, flags=re.S)
    return [m.group(0) for m in _para.finditer(xml)
            if not re.search(r'w:pStyle w:val="(?:TableCaption|FigureCaption|Caption|TOC[^" ]*|[Hh]eading[^" ]*|Title)"', m.group(0))
            and "<w:instrText" not in m.group(0)]
_captions = {}
_caption_anchors = {}
for _p in _para.finditer(rd):
    if re.search(r'w:pStyle w:val="(?:TableCaption|FigureCaption)"', _p.group(0)):
        _label = _text(_p.group(0))
        _match = re.match(r"(Figure|Table)\s+([0-9A-Z]+)[.:]\s*(.*)", _label)
        if _match:
            _captions[(_match[1].lower(), _match[2])] = (_label, _match[3])
            _anchor = re.search(r'<w:bookmarkStart\b[^>]*\bw:name="([^"]+)"', _p.group(0))
            if _anchor:
                _caption_anchors[(_match[1].lower(), _match[2])] = _anchor[1]
_aliases = {}
def _alias(kind, key, label):
    if not key:
        return
    k = (kind, re.sub(r"\s+", " ", key).strip())
    if k in _aliases and _aliases[k] != label:
        _aliases[k] = None  # Ambiguous captions must use the unique asset filename.
    else:
        _aliases[k] = label
for (_kind, _number), (_label, _caption) in _captions.items():
    _alias(_kind, _caption, _kind.title() + " " + _number)
if len(sys.argv) > 3:
    with open(sys.argv[3], encoding="utf-8") as _f:
        _registry = json.load(_f).get("references", [])
    for _entry in _registry:
        _kind, _number = _entry["kind"], str(_entry["number"])
        if (_kind, _number) not in _captions:
            raise SystemExit("WORD_REFERENCE_STOP: registry caption not emitted")
        _alias(_kind, _entry.get("file"), _kind.title() + " " + _number)
_token = re.compile(r"\{\{(figure|table):([^{}]+)\}\}")
def _resolve_text(m):
    def resolve(token):
        key = (token[1], re.sub(r"\s+", " ", html.unescape(token[2])).strip())
        label = _aliases.get(key)
        if not label:
            raise SystemExit("WORD_REFERENCE_STOP: missing/ambiguous/HTML-only asset " + token[0])
        return html.escape(label, quote=False)
    return m[1] + _token.sub(resolve, m[2]) + m[3]
rd = re.sub(r"(<w:t(?:\s[^>]*)?>)(.*?)(</w:t>)", _resolve_text, rd, flags=re.S)
if _token.search(_text(rd)):
    raise SystemExit("WORD_REFERENCE_STOP: unresolved reference split across runs")
_body_text = "\n".join(_text(p) for p in _normal_body(rd))
def _locator(kind, caption):
    c = caption.lower()
    if "demographic" in c or "patient characteristics" in c:
        return "Patient characteristics are summarized in"
    if "disposition" in c or "population" in c or "dataset summary" in c:
        return "Analysis population and data disposition are summarized in"
    if "parameter" in c and kind == "table":
        return "Model parameter estimates are presented in"
    if "covariate" in c and kind == "table":
        return "Covariate analysis results are presented in"
    return "See"
_missing = {}
for (_kind, _number), (_label, _caption) in _captions.items():
    _ref = _kind.title() + " " + _number
    if not re.search(r"\b" + re.escape(_ref) + r"\b", _body_text):
        _missing[_label] = _locator(_kind, _caption) + " " + _ref + "."
def _ensure_reference(m):
    p = m.group(0)
    if re.search(r'w:pStyle w:val="(?:TableCaption|FigureCaption)"', p):
        sentence = _missing.get(_text(p))
        if sentence:
            return ('<w:p><w:pPr><w:pStyle w:val="Normal"/></w:pPr><w:r><w:t>'
                    + html.escape(sentence, quote=False) + '</w:t></w:r></w:p>' + p)
    return p
rd = _para.sub(_ensure_reference, rd)
print("body references resolved; missing asset references supplied:", len(_missing))

# Link both resolved tokens and ordinary Table/Figure references, preserving run typography.
# Consecutive text runs are read together so a bold/italic boundary cannot break a reference.
_inline = re.compile(r'<w:hyperlink\b[^>]*>.*?</w:hyperlink>|<w:r(?:\s[^>]*)?>.*?</w:r>', re.S)
_ref_pattern = re.compile(r'\b(Figure|Table)\s+([0-9]+(?:\.[0-9]+)?|[A-Z](?:\.[0-9]+)?)\b', re.I)
_linked_references = 0
def _link_group(runs):
    global _linked_references
    text = "".join(r["text"] for r in runs)
    matches = [m for m in _ref_pattern.finditer(text)
               if (m[1].lower(), m[2]) in _caption_anchors]
    if not matches:
        return "".join(r["xml"] for r in runs)
    def pieces(start, end, linked=False):
        out = []
        for run in runs:
            a, b = max(start, run["start"]), min(end, run["end"])
            if a >= b:
                continue
            props = run["props"]
            if linked:
                props = re.sub(r'<w:(?:color|u)\b[^>]*/>', '', props)
                props += '<w:color w:val="0563C1"/><w:u w:val="single"/>'
            value = html.escape(run["text"][a-run["start"]:b-run["start"]], quote=False)
            out.append(run["open"] + ('<w:rPr>'+props+'</w:rPr>' if props else '')
                       + '<w:t xml:space="preserve">'+value+'</w:t></w:r>')
        return "".join(out)
    out, pos = [], 0
    for m in matches:
        out.append(pieces(pos, m.start()))
        anchor = _caption_anchors[(m[1].lower(), m[2])]
        out.append('<w:hyperlink w:anchor="'+html.escape(anchor, quote=True)+'" w:history="1">'
                   + pieces(m.start(), m.end(), True) + '</w:hyperlink>')
        _linked_references += 1
        pos = m.end()
    out.append(pieces(pos, len(text)))
    return "".join(out)
def _link_paragraph(m):
    p = m.group(0)
    if re.search(r'w:pStyle w:val="(?:TableCaption|FigureCaption|Caption|TOC[^" ]*|[Hh]eading[^" ]*|Title)"', p) or '<w:instrText' in p:
        return p
    out, runs, pos, length = [], [], 0, 0
    def flush():
        nonlocal runs, length
        if runs:
            out.append(_link_group(runs)); runs, length = [], 0
    for part in _inline.finditer(p):
        gap, raw = p[pos:part.start()], part.group(0)
        if gap.strip():
            flush(); out.append(gap)
        elif not runs:
            out.append(gap)
        op = re.match(r'<w:r(?:\s[^>]*)?>', raw)
        prop = re.search(r'<w:rPr(?:\s[^>]*)?>(.*?)</w:rPr>', raw, re.S)
        value = re.search(r'<w:t(?:\s[^>]*)?>(.*?)</w:t>', raw, re.S)
        residual = re.sub(r'<w:rPr(?:\s[^>]*)?>.*?</w:rPr>|<w:rPr\b[^>]*/>|<w:t(?:\s[^>]*)?>.*?</w:t>', '', raw, flags=re.S)
        residual = re.sub(r'^<w:r(?:\s[^>]*)?>|</w:r>$', '', residual).strip()
        if op and value and not residual and len(re.findall(r'<w:t(?:\s[^>]*)?>', raw)) == 1:
            txt = html.unescape(value[1])
            runs.append(dict(xml=raw, open=op[0], props=prop[1] if prop else '', text=txt,
                             start=length, end=length+len(txt)))
            length += len(txt)
        else:
            flush(); out.append(raw)  # Existing hyperlinks, fields, breaks and drawings remain intact.
        pos = part.end()
    flush(); out.append(p[pos:])
    return "".join(out)
# Never rewrite table cells: references belong to body prose, not parameter values or captions.
rd = "".join(part if part.startswith('<w:tbl') else _para.sub(_link_paragraph, part)
             for part in re.split(r'(<w:tbl(?:\s[^>]*)?>.*?</w:tbl>)', rd, flags=re.S))
print("internal Table/Figure hyperlinks added:", _linked_references)

mk = re.search(r"\[\[PMX_TOC:([0-9-]+)\]\]", rd)
if mk:
    levels = mk.group(1)
    field = (_toc_field(levels) +
             '<w:p><w:pPr><w:pStyle w:val="Heading3"/><w:pageBreakBefore/>'
             '<w:spacing w:before="240" w:after="80"/></w:pPr>'
             '<w:r><w:t>List of Figures</w:t></w:r></w:p>' + _toc_field(levels, "Figure") +
             '<w:p><w:pPr><w:pStyle w:val="Heading3"/><w:pageBreakBefore/>'
             '<w:spacing w:before="240" w:after="80"/></w:pPr>'
             '<w:r><w:t>List of Tables</w:t></w:r></w:p>' + _toc_field(levels, "Table"))
    ms = re.search(r"<w:p(?:\s[^>]*)?>(?:(?!</w:p>).)*\[\[PMX_TOC:[0-9-]+\]\](?:(?!</w:p>).)*?</w:p>", rd, re.S)
    if not ms:
        raise SystemExit("TOC marker paragraph not found")
    rd = rd[:ms.start()] + field + rd[ms.end():]
    assert "[[PMX_TOC" not in rd, "TOC marker not fully replaced"
    rparts["word/document.xml"] = rd.encode("utf8")
    print("TOC + list of figures + list of tables inserted")

rparts["word/document.xml"] = rd.encode("utf8")


if "word/settings.xml" in rparts:
    settings = rparts["word/settings.xml"].decode("utf8")
    settings = re.sub(r"<w:updateFields[^>]*/>", "", settings)
    settings = settings.replace("</w:settings>", '<w:updateFields w:val="true"/></w:settings>')
    rparts["word/settings.xml"] = settings.encode("utf8")

order = ["[Content_Types].xml"] + [n for n in rparts if n != "[Content_Types].xml"]
with zipfile.ZipFile(report, "w", zipfile.ZIP_DEFLATED) as z:
    for n in order:
        z.writestr(n, rparts[n])

print(f"styles: {replaced} replaced, {added} added from the reference")
print("page setup:", "w:pgSz" in rd, "| footer:", "word/footer1.xml" in rparts)
