"""
build_slides.py

Render a slide draft in documents/presentations/drafts/<name>.md to
documents/presentations/output/<name>.pptx with Pandoc. Figures referenced
in the markdown live in documents/presentations/code/figures/ (produced by
prepare_figures.py); paths in the markdown are relative to the drafts
folder, so Pandoc is run with --resource-path pointing there.

Fonts come from reference.pptx (made by make_reference.py; scaled-down
Pandoc default). Math ($...$ / $$...$$) is converted to native PowerPoint equations;
`::: notes` blocks become speaker notes; level-1 headings are slides.

Usage:
  python3 build_slides.py               # builds the highest-numbered sree_slides_v#.md
  python3 build_slides.py --version 2   # builds sree_slides_v2.md
  python3 build_slides.py --figures     # rerun prepare_figures.py first
"""

import argparse
import re
import subprocess
import xml.dom.minidom
import zipfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
PRES = HERE.parent
DRAFTS = PRES / "drafts"
OUT = PRES / "output"
STEM = "edtech_slides_v"


def latest_version():
    versions = [int(m.group(1)) for p in DRAFTS.glob(f"{STEM}*.md")
                if (m := re.fullmatch(rf"{STEM}(\d+)\.md", p.name))]
    if not versions:
        raise SystemExit(f"no {STEM}#.md drafts in {DRAFTS}")
    return max(versions)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--version", type=int)
    ap.add_argument("--figures", action="store_true",
                    help="run prepare_figures.py before building")
    args = ap.parse_args()

    if args.figures:
        subprocess.run(["python3", str(HERE / "prepare_figures.py")], check=True)

    v = args.version or latest_version()
    src = DRAFTS / f"{STEM}{v}.md"
    if not src.exists():
        raise SystemExit(f"missing draft: {src}")
    OUT.mkdir(exist_ok=True)
    dst = OUT / f"{STEM}{v}.pptx"

    ref = HERE / "reference.pptx"
    if not ref.exists():
        subprocess.run(["python3", str(HERE / "make_reference.py")], check=True)
    src_build, pairs = split_paired_images(src)
    cmd = [
        "pandoc", str(src_build), "-o", str(dst),
        "-t", "pptx",
        "--slide-level=1",
        "--reference-doc", str(ref),
        "--resource-path", str(DRAFTS),
    ]
    subprocess.run(cmd, check=True)
    if src_build != src:
        src_build.unlink()
    inject_second_images(dst, pairs)
    color_boxed_math(dst)
    normalize_layout(dst)
    validate_xml(dst)
    print(f"Built {dst}")


PAIR_RE = re.compile(r"^!\[\]\(([^)]+)\)\s+!\[\]\(([^)]+)\)\s*$")


def split_paired_images(src: Path):
    """Pandoc's pptx writer keeps only the first of two images in a paragraph
    (and spills an empty slide). A line `![](a.png) ![](b.png)` is therefore
    rewritten to `![](a.png)` in a temporary copy of the draft, and the second
    image is recorded against the slide title so inject_second_images() can add
    it after Pandoc runs; normalize_layout() then sets the two side by side."""
    lines = src.read_text(encoding="utf-8").splitlines()
    pairs, title, changed = {}, None, False
    for i, line in enumerate(lines):
        if line.startswith("# "):
            title = line[2:].strip()
        m = PAIR_RE.match(line)
        if m and title:
            lines[i] = f"![]({m.group(1)})"
            pairs[title] = (src.parent / m.group(2)).resolve()
            changed = True
    if not changed:
        return src, {}
    tmp = src.with_name(f"_{src.stem}_build.md")
    tmp.write_text("\n".join(lines) + "\n", encoding="utf-8")
    return tmp, pairs


def inject_second_images(pptx: Path, pairs: dict):
    """Add the recorded second image to each paired slide: a new media part, a
    relationship in the slide's rels, and a <p:pic> cloned from the first."""
    if not pairs:
        return
    from PIL import Image
    tmp = pptx.with_suffix(".tmp.pptx")
    with zipfile.ZipFile(pptx) as zin:
        slides = {n: zin.read(n).decode("utf-8") for n in zin.namelist()
                  if re.fullmatch(r"ppt/slides/slide\d+\.xml", n)}
        rels = {n: zin.read(n).decode("utf-8") for n in zin.namelist()
                if re.fullmatch(r"ppt/slides/_rels/slide\d+\.xml\.rels", n)}
        media_new = {}
        for name, xml in slides.items():
            t = re.search(r'<p:ph type="title" />.*?<a:t>([^<]*)</a:t>', xml, re.S)
            if not t or t.group(1).strip() not in pairs:
                continue
            img = pairs[t.group(1).strip()]
            k = len(media_new) + 1
            media_name = f"ppt/media/pair{k}.png"
            media_new[media_name] = img.read_bytes()
            rel_name = name.replace("slides/", "slides/_rels/") + ".rels"
            rid = f"rIdPair{k}"
            rels[rel_name] = rels[rel_name].replace(
                "</Relationships>",
                f'<Relationship Id="{rid}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" Target="../media/pair{k}.png" /></Relationships>')
            first = re.search(r"<p:pic>.*?</p:pic>", xml, re.S).group(0)
            w, h = Image.open(img).size
            second = re.sub(r'r:embed="[^"]+"', f'r:embed="{rid}"', first)
            second = re.sub(r'<p:cNvPr descr="[^"]*" id="\d+" name="[^"]*"',
                            f'<p:cNvPr descr="{img.name}" id="95" name="Picture 2"', second)
            second = re.sub(r'<a:ext cx="\d+" cy="\d+" />', f'<a:ext cx="{w * 9525}" cy="{h * 9525}" />', second, count=1)
            slides[name] = xml.replace(first, first + second, 1)
        with zipfile.ZipFile(tmp, "w", zipfile.ZIP_DEFLATED) as zout:
            for item in zin.infolist():
                data = zin.read(item.filename)
                if item.filename in slides:
                    data = slides[item.filename].encode("utf-8")
                elif item.filename in rels:
                    data = rels[item.filename].encode("utf-8")
                zout.writestr(item, data)
            for mname, blob in media_new.items():
                zout.writestr(mname, blob)
    tmp.replace(pptx)


# --- fixed geometry for every content slide (EMU; slide is 9144000 x 5143500)
BODY_X, BODY_W = 457200, 8229600          # master body placeholder x / width
BULLETS_Y, BULLETS_H = 1200151, 1450000   # bullets: top of the body region
LOWER_Y, LOWER_H = 2900000, 1694623       # equation box or figure: below the bullets
SHORT_H = 800000                          # (legacy) bullets band when the text is only a line or two
LINE_H, CHARS_PER_LINE = 300000, 80       # rendered line height and wrap estimate for the text band
EQ_FILL, EQ_LINE = "D9D9D9", "000000"     # gray fill, black border


def normalize_layout(pptx: Path):
    """Give every content slide the same single-column structure regardless
    of the layout Pandoc picked: Title and Content layout; bullets in the
    body placeholder pinned to the top of the body region; display equations
    moved out of the placeholder into a bordered, gray-filled text box at a
    fixed position below the bullets; any picture scaled and centred into
    that same lower region. Title slide untouched."""
    math_para = re.compile(r"<a:p>(?:(?!</a:p>).)*?<m:oMathPara.*?</a:p>", re.S)
    alt = re.compile(r"<mc:AlternateContent[^>]*>\s*<mc:Choice[^>]*>(.*?)</mc:Choice>\s*"
                     r"(?:<mc:Fallback>.*?</mc:Fallback>\s*)?</mc:AlternateContent>", re.S)
    body_ph = re.compile(r'<p:ph idx="[12]"[^/]*/>')
    pic_xfrm = re.compile(r'(<p:pic>.*?<a:off x=")(\d+)(" y=")(\d+)(" ?/><a:ext cx=")(\d+)(" cy=")(\d+)("[^>]*/>)', re.S)

    def fix_slide(text: str) -> str:
        if 'type="title"' not in text or 'type="ctrTitle"' in text:
            return text                                  # title slide, or no title at all
        text = alt.sub(r"\1", text)                     # unwrap math-carrying shapes
        if "a14:m" in text and 'xmlns:a14=' not in text[:400]:
            text = text.replace("<p:sld ", '<p:sld xmlns:a14="http://schemas.microsoft.com/office/drawing/2010/main" ', 1)
        # title inherits the layout geometry (Pandoc pins a narrow title on caption layouts)
        text = re.sub(r'(<p:ph type="title" /></p:nvPr></p:nvSpPr>)<p:spPr>.*?</p:spPr>', r"\1<p:spPr />", text, count=1, flags=re.S)
        # body placeholder -> idx 1, explicit geometry
        text = body_ph.sub('<p:ph idx="1" />', text, count=1)
        text = re.sub(r'(<p:ph idx="1" /></p:nvPr></p:nvSpPr>)<p:spPr ?/>',
                      rf'\1<p:spPr><a:xfrm><a:off x="{BODY_X}" y="{BULLETS_Y}" /><a:ext cx="{BODY_W}" cy="{BULLETS_H}" /></a:xfrm></p:spPr>',
                      text, count=1)
        # equations -> gray box
        maths = math_para.findall(text)
        if maths:
            text = math_para.sub("", text)
            paras = "".join(m.replace("<a:p>", '<a:p><a:pPr algn="ctr"><a:buNone /></a:pPr>', 1)
                            .replace('<a:pPr lvl="0" indent="0" marL="0"><a:buNone /></a:pPr>', "")
                            for m in maths)
            box = (f'<p:sp><p:nvSpPr><p:cNvPr id="90" name="Equation Box" /><p:cNvSpPr txBox="1" /><p:nvPr /></p:nvSpPr>'
                   f'<p:spPr><a:xfrm><a:off x="{BODY_X}" y="{LOWER_Y}" /><a:ext cx="{BODY_W}" cy="{LOWER_H}" /></a:xfrm>'
                   f'<a:prstGeom prst="rect"><a:avLst /></a:prstGeom><a:solidFill><a:srgbClr val="{EQ_FILL}" /></a:solidFill>'
                   f'<a:ln w="19050"><a:solidFill><a:srgbClr val="{EQ_LINE}" /></a:solidFill></a:ln></p:spPr>'
                   f'<p:txBody><a:bodyPr wrap="square" anchor="ctr" /><a:lstStyle />{paras}</p:txBody></p:sp>')
            text = text.replace("</p:spTree>", box + "</p:spTree>", 1)
        # pictures -> lower region, aspect preserved, centred; a slide with no
        # bullet text gives the picture the whole body region instead
        body = re.search(r'<p:sp>(?:(?!</p:sp>).)*?<p:ph idx="1" />.*?</p:sp>', text, re.S)
        has_text = bool(body and re.search(r"<(?:a|m):t>[^<]*\S[^<]*</(?:a|m):t>", body.group(0)))
        if not has_text and body:
            text = text.replace(body.group(0), "", 1)      # drop the empty placeholder
        n_paras = len(re.findall(r"<a:p>(?:(?!</a:p>).)*?<(?:a|m):t>[^<]*\S", body.group(0), re.S)) if body else 0
        if has_text and n_paras <= 5 and "Equation Box" not in text:
            # a caption-length text block: shrink its band so the figure gets more room
            # estimate rendered lines: each paragraph wraps at roughly CHARS_PER_LINE
            paras_txt = re.findall(r"<a:p>(.*?)</a:p>", body.group(0), re.S)
            n_lines = 0
            for ptxt in paras_txt:
                chars = len("".join(re.findall(r"<(?:a|m):t>([^<]*)</(?:a|m):t>", ptxt)))
                if chars:
                    n_lines += max(1, -(-chars // CHARS_PER_LINE))
            band = LINE_H * n_lines + 250000
            text = text.replace(f'cy="{BULLETS_H}"', f'cy="{band}"', 1)
            region_y, region_h = BULLETS_Y + band + 100000, LOWER_Y + LOWER_H - (BULLETS_Y + band + 100000)
        elif has_text and "<p:pic>" not in text and "Equation Box" not in text:
            # text only: the placeholder takes the whole body region
            text = text.replace(f'cy="{BULLETS_H}"', f'cy="{LOWER_Y + LOWER_H - BULLETS_Y}"', 1)
            region_y, region_h = LOWER_Y, LOWER_H
        else:
            region_y, region_h = (LOWER_Y, LOWER_H) if has_text else (BULLETS_Y, LOWER_Y + LOWER_H - BULLETS_Y)

        n_pics = len(re.findall(r"<p:pic>", text))
        gap = 250000
        slot_w = (BODY_W - gap * (n_pics - 1)) // n_pics if n_pics else BODY_W
        counter = {"k": 0}

        def place(m):
            k = counter["k"]; counter["k"] += 1
            cx, cy = int(m.group(6)), int(m.group(8))
            scale = min(slot_w / cx, region_h / cy)
            ncx, ncy = int(cx * scale), int(cy * scale)
            slot_x = BODY_X + k * (slot_w + gap)
            nx = slot_x + (slot_w - ncx) // 2
            ny = region_y + (region_h - ncy) // 2
            return f"{m.group(1)}{nx}{m.group(3)}{ny}{m.group(5)}{ncx}{m.group(7)}{ncy}{m.group(9)}"
        text = pic_xfrm.sub(place, text)   # several pictures share the band side by side
        return text

    tmp = pptx.with_suffix(".tmp.pptx")
    with zipfile.ZipFile(pptx) as zin, zipfile.ZipFile(tmp, "w", zipfile.ZIP_DEFLATED) as zout:
        for item in zin.infolist():
            data = zin.read(item.filename)
            if re.fullmatch(r"ppt/slides/slide\d+\.xml", item.filename):
                data = fix_slide(data.decode("utf-8")).encode("utf-8")
            elif re.fullmatch(r"ppt/slides/_rels/slide\d+\.xml\.rels", item.filename):
                # every content slide uses the Title and Content layout (slideLayout2)
                txt = data.decode("utf-8")
                if "slideLayout1.xml" not in txt:
                    data = re.sub(r"slideLayout\d+\.xml", "slideLayout2.xml", txt).encode("utf-8")
            zout.writestr(item, data)
    tmp.replace(pptx)


BOX_COLOR = "C00000"   # hex RGB applied to the contents of every \boxed{...}


def color_boxed_math(pptx: Path):
    """Pandoc renders \boxed{} as an OMML <m:borderBox>. OMML has no border
    colour, but each run inside the box may carry a DrawingML <a:rPr>, so we
    colour (and bold) the boxed contents to make the highlighted term stand
    out. Applied in place by rewriting the slide XML parts."""
    rpr = (f'<a:rPr b="1"><a:solidFill><a:srgbClr val="{BOX_COLOR}"/>'
           f'</a:solidFill></a:rPr>')
    box_re = re.compile(r"<m:borderBox>.*?</m:borderBox>", re.S)

    def colour_box(m):
        return re.sub(r"<m:t>", rpr + "<m:t>", m.group(0))

    tmp = pptx.with_suffix(".tmp.pptx")
    with zipfile.ZipFile(pptx) as zin, zipfile.ZipFile(tmp, "w", zipfile.ZIP_DEFLATED) as zout:
        for item in zin.infolist():
            data = zin.read(item.filename)
            if item.filename.startswith("ppt/slides/slide") and item.filename.endswith(".xml"):
                text = data.decode("utf-8")
                if "<m:borderBox>" in text:
                    text = box_re.sub(colour_box, text)
                    data = text.encode("utf-8")
            zout.writestr(item, data)
    tmp.replace(pptx)


def validate_xml(pptx: Path):
    """Parse every XML part; PowerPoint's 'repair' prompt comes from malformed
    parts. Known Pandoc trigger: math inside a table cell (undeclared a14:
    namespace) -- keep $...$ out of tables."""
    bad = []
    with zipfile.ZipFile(pptx) as z:
        for name in z.namelist():
            if name.endswith((".xml", ".rels")):
                try:
                    xml.dom.minidom.parseString(z.read(name))
                except Exception as e:  # noqa: BLE001
                    bad.append(f"{name}: {e}")
    if bad:
        raise SystemExit("malformed XML in output:\n  " + "\n  ".join(bad))


if __name__ == "__main__":
    main()
