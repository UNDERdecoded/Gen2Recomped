"""Run every Lua check in tools/, each with the arguments IT says it takes.

WHY THIS EXISTS.  There are fifty-odd checks and they do not take the same
arguments: some want the ROM, some a cache directory, one wants a dump of the
ARM9 and several want pokeplatinum beside it.  Run one with the wrong input and
it does not say "wrong input" -- it SCANS WHATEVER IT WAS GIVEN AND REPORTS A
FAULT.  `gen4_icon_check` handed the .nds instead of an ARM9 dump found a
plausible byte run at 0x5C6228B and reported that the party-icon palette table
disagreed with every hand-verified species; given the real dump it finds
0xF070A and agrees with all of them.  That mistake was made three times in
three passes, and twice it was believed.

So the point of this file is not convenience.  It is that "is everything
working?" should have one answer, obtained the same way every time.

HOW IT KNOWS WHAT EACH CHECK WANTS, and this is the part that must not rot: it
reads the check's OWN invocation line.  Every check carries one, as a comment:

    -- Run:  texlua tools/gen4_sheet_layout_check.lua <platinum .nds> [cache dir]
    --   lua tools/gen4_ball_throw_check.lua [path/to/platinum/data/generated]

and a few only print one at runtime (`usage: ... <rom> <pokeplatinum dir>`).
Any line that invokes the file's own name is the spec.  A LIST OF ARGUMENTS PER
CHECK, KEPT HERE, WOULD BE THE HARDCODED TWIN OF A FACT IN FIFTY OTHER FILES --
which is this port's recurring bug, and it has already been repaired twice in
`gen4_mining_art_check` and `gen4_moveeffect_check`.  Derived, a new check needs
no edit here, and a check whose line cannot be parsed is REPORTED rather than
guessed at.

WHAT IT WILL NOT DO is pretend.  Four outcomes are kept apart, because
collapsing them is how a missing input becomes a bug report:

    PASS    it ran and nothing failed
    FAIL    it ran and something failed -- the real thing
    SKIP    a required input was not supplied, so it was NOT run
    NOSPEC  no invocation line could be found, so the arguments are unknown
    ERROR   it crashed, or printed no verdict at all

Usage:
    python tools/run_checks.py --rom <platinum.nds> --cache <data/generated>
                               [--pret <pokeplatinum>] [--arm9 <arm9.bin>]
                               [--emerald <emerald/data/generated>]
                               [--interp texlua|love] [--only SUBSTRING]

`--interp love` runs each check through run_lua_check.py, i.e. under the
LuaJIT in the local LOVE install, which is what the engine itself runs on.
`--interp texlua` uses plain Lua 5.3 and is the fallback where LOVE is not
installed.  A check that depends on `bit` guards its own shim either way.
"""

import argparse
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)

# A placeholder's VOCABULARY, mapped to which supplied path it means.  This is
# the one table that lives here rather than in the checks, and it is this
# tool's own job: translating the words the checks use into the paths the
# operator gave.  An unrecognised placeholder is reported, never dropped --
# otherwise a check would quietly run with one argument missing.
VOCAB = (
    ("arm9",            "arm9"),
    ("pokeplatinum",    "pret"),
    ("pret",            "pret"),
    ("emerald",         "emerald"),
    ("nds",             "rom"),
    ("rom",             "rom"),
    ("assets",          "assets"),
    # "game root" means the install -- a platinum/ with data/ and assets/ under
    # it. The two checks that read picture FILES rather than cache tables take
    # one, and both accept the data or assets directory and walk up, so handing
    # them the cache path is correct. Added because
    # `gen4_texture_files_check` took no argument at all and therefore reported
    # SKIP on every suite run since it was written -- a permanently skipped
    # check is not a check.
    ("game root",       "cache"),
    ("dataset",         "cache"),
    ("data/generated",  "cache"),
    ("cache",           "cache"),
)

INVOKE = re.compile(
    r"""(?:^|\s)(?:texlua|lua|python|python3)\s+
        (?:tools/)?(?P<name>[A-Za-z0-9_.-]+\.lua)
        (?P<rest>[^\n"]*)""",
    re.VERBOSE,
)


def classify(placeholder):
    """Which supplied path a placeholder refers to, or None if unrecognised."""
    low = placeholder.lower()
    for word, kind in VOCAB:
        if word in low:
            return kind
    return None


def spec_for(path):
    """The argument spec a check states for itself.

    Returns (args, problem).  `args` is a list of (kind, required) pairs in the
    order the check takes them.  `problem` is set when no line could be found
    or a placeholder could not be classified -- either way the check is not
    run, because a guessed argument is the failure this file exists to stop.
    """
    name = os.path.basename(path)
    try:
        with open(path, "r", encoding="latin-1") as handle:
            text = handle.read()
    except OSError as exc:
        return None, "unreadable: %s" % exc

    # THE RICHEST LINE WINS, not the first.  A file often invokes itself more
    # than once -- a bare example above the full one, a `-- Run:` line below it
    # -- and taking the first found `gen4_command_audit.lua` with no arguments
    # at all, two lines above the line that states its cache path.  A spec that
    # is a prefix of the real one is the worst kind of wrong here: it runs, with
    # an argument missing, and reports whatever that does.
    best = None
    for match in INVOKE.finditer(text):
        if match.group("name") != name:
            continue
        rest = match.group("rest")
        slots = len(re.findall(r"<[^<>]+>|\[[^\[\]]+\]", rest))
        if best is None or slots > best[0]:
            best = (slots, rest)
    if best is None:
        return None, "no line in the file invokes %s" % name
    rest = best[1]

    args, unknown = [], []
    # `<required>` and `[optional]`, in the order written.  Nested forms like
    # `[<dataset dir>]` appear in the tree, so the outer bracket decides.
    for token in re.finditer(r"<([^<>]+)>|\[([^\[\]]+)\]", rest):
        required = token.group(1) is not None
        body = token.group(1) or token.group(2)
        body = body.strip().strip("<>[]").strip()
        kind = classify(body)
        if kind is None:
            unknown.append(body)
        else:
            args.append((kind, required))
    if unknown:
        return None, "unrecognised argument(s): %s" % ", ".join(unknown)
    return args, None


VERDICT = re.compile(r"(\d+)\s+checks?,\s+(\d+)\s+(?:failed|failures)")


def run(path, argv, interp):
    if interp == "love":
        command = [sys.executable, os.path.join(HERE, "run_lua_check.py"), path] + argv
    else:
        command = ["texlua", path] + argv
    try:
        done = subprocess.run(command, cwd=ROOT, capture_output=True,
                              text=True, errors="replace", timeout=900)
    except FileNotFoundError as exc:
        return "ERROR", "cannot run %s: %s" % (interp, exc), ""
    except subprocess.TimeoutExpired:
        return "ERROR", "timed out after 900s", ""
    output = (done.stdout or "") + (done.stderr or "")
    found = VERDICT.findall(output)
    if found:
        total, bad = found[-1]
        status = "PASS" if bad == "0" else "FAIL"
        return status, "%s checks, %s failed" % (total, bad), output
    # EXIT 2 IS THIS TREE'S "I COULD NOT RUN", used by 36 of the checks when a
    # required input is absent.  It is NOT a failure and must not be counted as
    # one: a check that could not look has not found anything.
    if done.returncode == 2:
        last = [line for line in output.splitlines() if line.strip()]
        return "SKIP", (last[-1].strip()[:66] if last else "exit 2"), output
    # No verdict line.  Some tools in tools/ are REPORTS rather than checks --
    # they enumerate findings and have nothing to pass.  Exit status tells the
    # two apart: a report ends cleanly, a crash does not.
    if done.returncode == 0:
        last = [line for line in output.splitlines() if line.strip()]
        return "REPORT", (last[-1].strip()[:60] if last else "no output"), output
    return "ERROR", "exit %d: %s" % (done.returncode,
                                     output.strip().splitlines()[-1][:60]
                                     if output.strip() else "no output"), output


def main():
    parser = argparse.ArgumentParser(add_help=True)
    parser.add_argument("--rom")
    parser.add_argument("--cache")
    parser.add_argument("--pret")
    parser.add_argument("--arm9")
    parser.add_argument("--emerald")
    parser.add_argument("--assets")
    parser.add_argument("--interp", choices=("texlua", "love"), default="texlua")
    parser.add_argument("--only", default=None,
                        help="only checks whose filename contains this")
    parser.add_argument("--verbose", action="store_true",
                        help="print the full output of anything not PASS")
    opts = parser.parse_args()

    supplied = {"rom": opts.rom, "cache": opts.cache, "pret": opts.pret,
                "arm9": opts.arm9, "emerald": opts.emerald,
                "assets": opts.assets}
    for kind, value in supplied.items():
        if value and not os.path.exists(value):
            print("warning: --%s does not exist: %s" % (kind, value))

    names = sorted(entry for entry in os.listdir(HERE)
                   if entry.endswith(".lua")
                   and ("check" in entry or entry in ("gen4_map_reach.lua",
                                                      "gen4_command_audit.lua")))
    if opts.only:
        names = [entry for entry in names if opts.only in entry]

    tally = {}
    failures, worth_showing = [], []
    for name in names:
        path = os.path.join(HERE, name)
        args, problem = spec_for(path)
        if problem is not None:
            status, detail, output = "NOSPEC", problem, ""
        else:
            argv, missing, reduced = [], [], []
            for kind, required in args:
                value = supplied.get(kind)
                if value:
                    argv.append(value)
                elif required:
                    missing.append(kind)
                else:
                    # AN OPTIONAL ARGUMENT NOT SUPPLIED IS NOT FREE. Several
                    # checks run a smaller version of themselves without it and
                    # then pass: `gen4_icon_check` without an ARM9 dump reports
                    # "6 checks, 0 failed" where the full run is nine, and the
                    # three it skipped are the ones that compare the port's
                    # palette table against the cartridge. A green line for a
                    # test that never looked is worse than a red one, so the
                    # omission is carried through to the summary.
                    #
                    # It also ends the list: Lua positional arguments cannot
                    # have a hole in the middle of them.
                    reduced.append(kind)
                    break
            if missing:
                status = "SKIP"
                detail = "needs --%s" % ", --".join(missing)
                output = ""
            else:
                status, detail, output = run(path, argv, opts.interp)
                if reduced and status == "PASS":
                    # Marked, not renamed: it did pass. It just did not run
                    # whole, and the summary has to show the difference.
                    status = "PASS*"
                    detail += "   [reduced: no --%s]" % ", --".join(reduced)
        tally[status] = tally.get(status, 0) + 1
        print("  %-7s %-38s %s" % (status, name[:-4], detail))
        if status == "FAIL":
            failures.append(name)
        if status in ("FAIL", "ERROR", "NOSPEC") and output:
            worth_showing.append((name, output))

    print("\n  " + "  ".join("%s=%d" % (key, tally[key]) for key in sorted(tally)))
    if tally.get("PASS*"):
        print("  PASS* means it passed a REDUCED run: an optional input was not\n"
              "  supplied, so some of its assertions never executed.")
    if opts.verbose:
        for name, output in worth_showing:
            print("\n" + "=" * 72 + "\n" + name + "\n" + "=" * 72)
            print(output.rstrip())
    # A SKIP IS NOT A PASS, and the exit status says so: a run that could not
    # test something has not shown that the something works.
    sys.exit(1 if (failures or tally.get("ERROR") or tally.get("NOSPEC")) else 0)


if __name__ == "__main__":
    main()
