"""Load study ids and titles from content/studies_public.yml into the Supabase studies table.

Run locally only:  SUPABASE_SERVICE_KEY=... python3 supabase/seed/load_studies.py
The service-role key never leaves this machine.
"""
import json, os, pathlib, sys, urllib.request
import yaml

ROOT = pathlib.Path(__file__).resolve().parents[2]
URL = "https://oghwdaykvxkenpwbtwad.supabase.co"
KEY = os.environ.get("SUPABASE_SERVICE_KEY") or sys.exit("set SUPABASE_SERVICE_KEY")

def upsert(table, rows, conflict):
    req = urllib.request.Request(f"{URL}/rest/v1/{table}?on_conflict={conflict}", data=json.dumps(rows).encode(),
        headers={"apikey": KEY, "Authorization": f"Bearer {KEY}", "Content-Type": "application/json",
                 "Prefer": "resolution=merge-duplicates"}, method="POST")
    with urllib.request.urlopen(req) as r:
        print(table, r.status)

pub = yaml.safe_load((ROOT / "content/studies_public.yml").read_text())["studies"]
upsert("studies", [{"id": s["id"], "display_order": s["display_order"], "public_title": s["public_title"]} for s in pub], "id")
