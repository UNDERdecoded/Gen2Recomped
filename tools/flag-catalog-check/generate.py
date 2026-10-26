#!/usr/bin/env python3
"""Reproduce/check flag identifier catalogs against the clean pinned reference.

Exports identifiers only. No Gen1 engine code or cartridge ROM is vendored.
"""
import argparse
import json
from pathlib import Path
import subprocess

PIN = "79ea62f45fb2ea8f65d081a109431e4eb1bbdb36"
EXPORT = r"""
package.path = './?.lua;./?/init.lua;' .. package.path
local out = { reference = '79ea62f45fb2ea8f65d081a109431e4eb1bbdb36', catalogs = {} }
for _, version in ipairs({'red','yellow'}) do
  local suffix = version == 'yellow' and '_yellow' or ''
  local names=require('src.save_convert.data.event_flags'..suffix).byBit
  local encoded={} for k,v in pairs(names) do encoded['n'..k]=v end
  out.catalogs[version] = { names=encoded }
end
for _, version in ipairs({'firered','emerald'}) do
  require('src.core.GameVersion').set(version)
  local t = require('src.core.game3.scripting.flags').forVersion(version)
  local ids,names,count={},{},t.FLAGS_COUNT or 0x900
  for k,v in pairs(t.IDS) do
    if type(k)=='string' and type(v)=='number' and v>=1 and v<count and v%1==0 then ids[k]=v end
  end
  for k,v in pairs(t.NAMES) do if type(k)=='number' and k>=1 and k<count then names['n'..k]=v end end
  out.catalogs[version] = { ids=ids,names=names,limit=count }
end
out.gold = require('src.core.gen2.FlagNames').events
print(require('src.link.Json').encode(out))
"""

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--gen1", required=True, type=Path)
    parser.add_argument("--lua", default="luajit")
    parser.add_argument("--write", action="store_true")
    args = parser.parse_args()
    def git(*values):
        return subprocess.check_output(["git", "-C", str(args.gen1), *values], text=True).strip()
    if git("rev-parse", "HEAD") != PIN or git("status", "--porcelain", "--untracked-files=normal"):
        parser.error("reference must be clean and pinned to " + PIN)
    result = subprocess.run([args.lua, "-e", EXPORT], cwd=args.gen1,
                            capture_output=True, text=True, check=True, timeout=60)
    exported = json.loads(result.stdout)
    engine = Path(__file__).resolve().parents[2]
    host = subprocess.run([args.lua, "-e", 'print(require("src.link.Json").encode(require("src.script.Gen2Flags").EVENT_FLAG_INDEX))'],
                          cwd=engine, capture_output=True, text=True, check=True, timeout=60)
    host_ids = json.loads(host.stdout)
    mismatches = {name: number for name, number in exported["gold"].items()
                  if host_ids.get(name) != number}
    if mismatches:
        raise SystemExit("host Gold flag identifiers differ: " + repr(mismatches))
    print("PASS gold/silver: " + str(len(exported["gold"])) + " native identifiers")
    root = engine / "src/mods/flag_names"
    for version, data in sorted(exported["catalogs"].items()):
        rows = {int(key[1:]): [value] for key, value in data["names"].items()}
        for alias, number in sorted(data.get("ids", {}).items()):
            row = rows.setdefault(number, [False])
            if alias not in row:
                row.append(alias)
        lines = ["-- Generated flag identifiers only; no engine implementation.",
                 "-- Source: bryanthaboi/gen1recomp@" + PIN,
                 "-- Regenerate with tools/flag-catalog-check/generate.py.", "return {"]
        if "limit" in data:
            lines.append("  limit = " + str(data["limit"]) + ",")
        lines.append("  records = {")
        for number, row in sorted(rows.items()):
            values = ", ".join("false" if value is False else json.dumps(value) for value in row)
            lines.append("    [" + str(number) + "] = { " + values + " },")
        lines.extend(["  },", "}"])
        expected = "\n".join(lines) + "\n"
        target = root / (version + ".lua")
        if args.write:
            target.write_text(expected)
        elif target.read_text() != expected:
            raise SystemExit("catalog differs from reference: " + str(target))
        print("PASS " + version + ": " + str(len(rows)) + " identifier rows")

if __name__ == "__main__":
    main()
