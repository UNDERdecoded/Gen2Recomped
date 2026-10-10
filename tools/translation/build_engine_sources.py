import importlib.util
import re
from pathlib import Path
repo=Path(__file__).resolve().parents[2]
spec=importlib.util.spec_from_file_location("modkit",repo/"tools/modkit.py")
module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
entries=[];seen=set()
for path in sorted((repo/"src").rglob("*.lua")):
 if path.name=="RomImporter.lua":continue
 body=path.read_text(encoding="utf-8",errors="replace")
 for match in module.STRINGS_CALL.finditer(body):
  literal=match.group(1)
  if literal.startswith(chr(39)):
   literal=chr(34)+literal[1:-1].replace(chr(34),chr(92)+chr(34))+chr(34)
  if literal not in seen:entries.append(literal);seen.add(literal)
# Labels drawn without a Strings() call: menu rows, HUD tags, Font.draw
# literals. Font.draw / Font.width / Font.fit look these up whole at draw
# time (Service.display), so collecting them is enough to translate them.
LITERAL=re.compile(r'(?:\b(?:label|hudLabel|title)\s*=\s*|\bFont\.draw\(\s*|[:.]text\(\s*|\btext\(\s*)("(?:[^"\\\n]|\\.)*")')
SCREENS=("ui","battle","world","script","pokemon","inventory","link","contest","core")
for folder in SCREENS:
 for path in sorted((repo/"src"/folder).rglob("*.lua")):
  if path.name=="RomImporter.lua":continue
  for line in path.read_text(encoding="utf-8",errors="replace").splitlines():
   if line.lstrip().startswith("--"):continue
   for match in LITERAL.finditer(line):
    literal=match.group(1);text=literal[1:-1]
    if not re.search(r'[A-Za-z]{2}',text):continue
    if re.fullmatch(r'[A-Z0-9_]+_[A-Z0-9_]+|[a-z][A-Za-z0-9_]*',text):continue
    if "/" in text and " " not in text:continue
    if literal not in seen:entries.append(literal);seen.add(literal)
out=repo/"data/localization/engine_sources.lua"
out.write_text("-- Engine-authored game text, collected by the existing modkit scanner.\nreturn {\n"+",\n".join(entries)+"\n}\n",encoding="utf-8")
print("Collected",len(entries),"engine text sources")
body=(repo/"src/import/RomImporter.lua").read_text(encoding="utf-8")
# Lex comments and quoted strings together so comment prose is never harvested.
tokens=re.compile(r'--\[\[.*?\]\]|--[^\n]*|\[\[.*?\]\]|"(?:\\.|[^"\\])*"|\x27(?:\\.|[^\x27\\])*\x27',re.S)
launcher=[];seen=set()
for match in tokens.finditer(body):
 literal=match.group()
 if literal.startswith("--") or literal.startswith("[["):continue
 text=literal[1:-1]
 if len(text)<2 or not re.search(r'[A-Za-z]',text):continue
 if "/" in text or "\\" in text or re.search(r'[{}=<>]|^[A-Z0-9_]+_[A-Z0-9_]+$',text):continue
 if not (" " in text or text[0].isupper()):continue
 if literal.startswith(chr(39)):
  literal=chr(34)+literal[1:-1].replace(chr(34),chr(92)+chr(34))+chr(34)
 if literal not in seen:launcher.append(literal);seen.add(literal)
(repo/"data/localization/launcher_sources.lua").write_text("-- Launcher UI source text; original labels remain English.\nreturn {\n"+",\n".join(launcher)+"\n}\n",encoding="utf-8")
print("Collected",len(launcher),"launcher text sources")
