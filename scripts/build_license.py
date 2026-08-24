#!/usr/bin/env python3
"""Generate the plain-text LICENSE from LICENSE.md.

TWO FILES, ONE SOURCE. `LICENSE.md` is what GitHub renders and what a person
reads; `LICENSE` is what tooling looks for and what a plain-text world expects.
Maintaining both by hand is how a project ends up shipping two licences that
disagree -- and a licence that disagrees with itself is worse than either half,
because the reader gets to pick.

So the markdown is the source of truth and this flattens it. tests/
license_consistency_test.lua re-runs the flatten and fails if the committed
LICENSE is not what this produces, which is the part that makes it stick.
"""
import re, sys, pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent


def flatten(md: str) -> str:
    out = []
    for line in md.split("\n"):
        s = line

        # tables -> "path  --  description", which is what the columns meant
        if s.startswith("|"):
            cells = [c.strip() for c in s.strip("|").split("|")]
            if all(set(c) <= set("-: ") for c in cells):
                continue                       # the |---|---| rule row
            cells = [re.sub(r"`([^`]*)`", r"\1", c) for c in cells]
            if cells and cells[0].lower() == "path":
                continue                       # the header row
            out.append("    " + "  --  ".join(c for c in cells if c))
            continue

        s = re.sub(r"^#{1,6}\s*", "", s)       # headings
        s = re.sub(r"\[([^\]]+)\]\([^)]*\)", r"\1", s)   # links -> their text
        s = re.sub(r"\*\*([^*]+)\*\*", r"\1", s)          # bold
        s = re.sub(r"`([^`]*)`", r"\1", s)                # code spans
        s = re.sub(r"^\s*>\s?", "  ", s)                  # block quotes
        s = re.sub(r"^(\s*)[-*]\s+", r"\1  * ", s)        # bullets
        if set(s.strip()) == {"-"} and len(s.strip()) >= 3:
            s = "-" * 70                       # thematic break
        out.append(s.rstrip())

    text = "\n".join(out)
    text = re.sub(r"\n{3,}", "\n\n", text)
    return text.strip() + "\n"


def main() -> int:
    md = (ROOT / "LICENSE.md").read_text(encoding="utf-8")
    txt = flatten(md)
    target = ROOT / "LICENSE"
    if "--check" in sys.argv:
        current = target.read_text(encoding="utf-8") if target.exists() else ""
        if current != txt:
            print("LICENSE is out of date; run scripts/build_license.py")
            return 1
        print("LICENSE matches LICENSE.md")
        return 0
    target.write_text(txt, encoding="utf-8")
    print(f"wrote {target} ({len(txt)} bytes) from LICENSE.md")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
