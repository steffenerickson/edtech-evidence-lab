"""
make_reference.py

Build reference.pptx — the Pandoc reference deck used by build_slides.py —
from Pandoc's built-in default, with all master/layout font sizes scaled down
so that the slide content fits. Font sizes in the OOXML are hundredths of a
point (sz="1800" = 18 pt); every size >= MIN_PT in the slide master and slide
layouts is multiplied by SCALE. Footer/date/slide-number text (9 pt) is left
alone.

Usage: python3 make_reference.py [SCALE]   (default 0.78:
       title 33 -> 26 pt, body 18/15/13.5 -> 14/12/10.5 pt)
"""

import re
import shutil
import subprocess
import sys
import tempfile
import zipfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
OUT = HERE / "reference.pptx"
SCALE = float(sys.argv[1]) if len(sys.argv) > 1 else 0.78
MIN_PT = 12


def scale_sizes(xml: str) -> str:
    def repl(m):
        sz = int(m.group(1))
        if sz < MIN_PT * 100:
            return m.group(0)
        return f'sz="{int(round(sz * SCALE / 50)) * 50}"'
    return re.sub(r'sz="(\d+)"', repl, xml)


with tempfile.TemporaryDirectory() as td:
    td = Path(td)
    default = td / "default.pptx"
    subprocess.run(
        ["pandoc", "-o", str(default), "--print-default-data-file", "reference.pptx"],
        check=True,
    )
    src = td / "unz"
    with zipfile.ZipFile(default) as z:
        z.extractall(src)

    targets = list((src / "ppt" / "slideMasters").glob("*.xml")) + \
        list((src / "ppt" / "slideLayouts").glob("*.xml"))
    for f in targets:
        f.write_text(scale_sizes(f.read_text(encoding="utf-8")), encoding="utf-8")

    # re-zip: [Content_Types].xml must be first for a valid package
    if OUT.exists():
        OUT.unlink()
    with zipfile.ZipFile(OUT, "w", zipfile.ZIP_DEFLATED) as z:
        z.write(src / "[Content_Types].xml", "[Content_Types].xml")
        for p in sorted(src.rglob("*")):
            rel = p.relative_to(src).as_posix()
            if p.is_file() and rel != "[Content_Types].xml":
                z.write(p, rel)

print(f"wrote {OUT} (scale {SCALE})")
