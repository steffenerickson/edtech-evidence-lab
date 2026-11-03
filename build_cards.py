"""Pre-render step: write js/cards.json and the printable packet from content/studies_public.yml.

Each card ends with its citation and link, appended here so the YAML holds them once.
"""
import json, pathlib, re, subprocess, sys
import yaml
import shutil
PANDOC = ["pandoc"] if shutil.which("pandoc") else ["quarto", "pandoc"]

ROOT = pathlib.Path(__file__).parent
src = ROOT / "content" / "studies_public.yml"
data = yaml.safe_load(src.read_text(encoding="utf-8"))
studies = sorted(data["studies"], key=lambda s: s["display_order"])

for s_ in studies:
    s_["card"] = s_["card"].rstrip() + f"\n\n**Citation.** {s_['citation']} [{s_['url']}]({s_['url']})\n"
    s_["card_html"] = subprocess.run(PANDOC + ["-f", "markdown", "-t", "html"], input=s_["card"],
                                     capture_output=True, text=True, check=True).stdout
(ROOT / "js" / "cards.json").write_text(json.dumps(studies, ensure_ascii=False, indent=1), encoding="utf-8")

# Printable packet (rendered separately: quarto render packet.qmd --to pdf)
lines = ["---", 'title: "Study Packet: Evaluating Evidence on Education Technology"', "format:", "  pdf:",
         "    documentclass: article", "    geometry: margin=1in", "    fontsize: 11pt", "---", "",
         "Read each study assigned to your group. For each, decide the **direction of findings** "
         "(positive, negative, mixed, null, inconclusive) and rate **credibility** from 1 (low) to 5 (high). "
         "Write one reason.", ""]
for s in studies:
    lines += [f"# Source {s['label']}", "", s["card"].strip(), ""]
    if s.get("figure"):
        lines += [f"![{s['figure'].get('caption','')}]({s['figure']['path']}){{width=80%}}", ""]
    lines += ["**Direction:** positive / negative / mixed / null / inconclusive", "",
              "**Credibility (1–5):** ____  **Reason:** ______________________________________________", "",
              "\\newpage", ""]
(ROOT / "packet.qmd").write_text("\n".join(lines), encoding="utf-8")
print(f"build_cards: {len(studies)} cards")
