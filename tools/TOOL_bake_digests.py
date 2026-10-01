#!/usr/bin/env python3
"""Write data/bake/CODE_DIGESTS.json: res:// path -> sha256 of every script the
terrain and vegetation bakes are signed against (the `_SOURCES` of
AUTOLOAD_terrain_bake.gd and AUTOLOAD_veg_bake.gd).

An export ships scripts compiled, so the game cannot hash their source to find
its bake; SCRIPT_bake_store.gd reads this table instead. Run it whenever you run
TOOL_bake_world.gd, from the project root. It is what golf's export plugin did.
"""
import hashlib, json, os, re

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
paths = set()
for f in ("scripts/autoload/AUTOLOAD_terrain_bake.gd", "scripts/autoload/AUTOLOAD_veg_bake.gd"):
    src = open(os.path.join(ROOT, f)).read()
    block = re.search(r"const _SOURCES := \[(.*?)\]", src, re.S).group(1)
    paths.update(re.findall(r'"(res://[^"]+)"', block))
table = {}
for p in sorted(paths):
    with open(os.path.join(ROOT, p[len("res://"):]), "rb") as fh:
        table[p] = hashlib.sha256(fh.read()).hexdigest()
os.makedirs(os.path.join(ROOT, "data/bake"), exist_ok=True)
with open(os.path.join(ROOT, "data/bake/CODE_DIGESTS.json"), "w") as fh:
    json.dump(table, fh, indent=1, sort_keys=True)
print("\n".join(f"{v[:12]}  {k}" for k, v in table.items()))
