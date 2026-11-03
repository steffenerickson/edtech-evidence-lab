"""Pre-render step: write _cards.json and the printable packet from content/studies_public.yml.

Only public content passes through here. content/study_reveals.yml is git-ignored and is
loaded into Supabase separately by supabase/seed/load_reveals.py.
"""
import json, pathlib, re, subprocess, sys
import yaml

ROOT = pathlib.Path(__file__).parent
src = ROOT / "content" / "studies_public.yml"
data = yaml.safe_load(src.read_text(encoding="utf-8"))
studies = sorted(data["studies"], key=lambda s: s["display_order"])

banned = (ROOT / "content" / "banned_terms.txt")
if banned.exists():
    terms = [t.strip() for t in banned.read_text().splitlines() if t.strip() and not t.startswith("#")]
    blob = json.dumps(studies)
    hits = [t for t in terms if re.search(r"\b" + re.escape(t) + r"\b", blob, re.I)]
    if hits:
        sys.exit(f"build_cards: identifying terms found in public content: {hits}")

for s_ in studies:
    s_["card_html"] = subprocess.run(["pandoc", "-f", "markdown", "-t", "html"], input=s_["card"],
                                     capture_output=True, text=True, check=True).stdout
(ROOT / "js" / "cards.json").write_text(json.dumps(studies, ensure_ascii=False, indent=1), encoding="utf-8")

# Printable packet (rendered separately: quarto render packet.qmd --to pdf)
lines = ["---", 'title: "Study Packet: Evaluating Evidence on Education Technology"', "format:", "  pdf:",
         "    documentclass: article", "    geometry: margin=1in", "    fontsize: 11pt", "---", "",
         "Read each study assigned to your group. For each, decide the **direction of findings** "
         "(positive, negative, mixed, null, inconclusive) and rate **credibility** from 1 (low) to 5 (high). "
         "Write one reason. Sources are revealed in class.", ""]
for s in studies:
    lines += [f"# Study {s['label']}: {s['public_title']}", "", s["card"].strip(), ""]
    if s.get("figure"):
        lines += [f"![{s['figure'].get('caption','')}]({s['figure']['path']}){{width=80%}}", ""]
    lines += ["**Direction:** positive / negative / mixed / null / inconclusive", "",
              "**Credibility (1–5):** ____  **Reason:** ______________________________________________", "",
              "\\newpage", ""]
(ROOT / "packet.qmd").write_text("\n".join(lines), encoding="utf-8")
print(f"build_cards: {len(studies)} cards")
