#!/usr/bin/env python3
"""Generate Gen2ScriptOps.COMMANDS_POLISHED / TERMINATORS_POLISHED from source.

Polished Crystal's script language is not Crystal's with additions -- it is 224
commands where Crystal has ~120, renumbered from index 3 onward. A Polished
Crystal script walked with Crystal's table desyncs on the first shifted opcode
and never recovers, which is what makes NPC dialogue and map events read as
"mostly working, randomly wrong".

Unlike Prism -- whose table had to be inferred from handler control flow because
there is no usable disassembly -- Polished Crystal ships the whole thing, so BOTH
halves of this file are read rather than guessed:

  NAMES AND OPERAND WIDTHS come from macros/scripts/events.asm. A `const_def`
  block gives the opcode order, and each `MACRO` body is literally what the
  assembler emits, so the widths are the encoder's own.

  TERMINATORS come from engine/overworld/scripting.asm, NOT from the names.
  Names lie in both directions here: `iffalse_jumptext` contains "jump" and
  falls through when the condition is false, while `fruittree` contains nothing
  jump-like and never returns (it ScriptJumps into FruitTreeScript). Getting
  this wrong is the expensive kind of wrong -- a missed terminator walks the
  disassembler off the end of one script into the bytes of the next.

  So the jumptable is parsed, and each handler is followed: a handler TERMINATES
  if control reaches StopScript or ScriptJump without a `ret` first. Conditional
  branches do not count -- `jr z, Script_end` leaves the fall-through path alive.

    python3 tools/gen_polished_ops.py \\
        --src /path/to/polishedcrystal --out tools/polished_ops.lua

Paste the result into src/import/Gen2ScriptOps.lua, or keep it beside
tools/prism_ops.lua as the regenerable record. Do not hand-edit: regenerate.
"""

from __future__ import annotations

import argparse
import os
import re

# ---------------------------------------------------------------- the macros

CONST_DEF = re.compile(r"^const_def\s*(-?\d+)?")
CONST = re.compile(r"^const\s+(\S+)_command\s*$")
MACRO = re.compile(r"^MACRO\s+(\S+)")

# One letter per operand, matching src/import/Gen2ScriptOps.lua's ARG_BYTES.
# The letter carries WIDTH; where the macro's own comment makes the meaning
# unambiguous it carries that too, because the extractor resolves pointers by
# kind (a "t" is followed to its text, a "p" is not).
def kind_for(directive, comment):
    c = (comment or "").lower()
    if directive == "db":
        return "b"
    if directive in ("dr",):
        # rgbds relative byte: the *fwd short-jump family's 1-byte distance.
        # Gen 2 has no equivalent -- these are new commands.
        return "b"
    if directive == "dn":
        return "b"          # two nibbles packed into one byte
    if directive == "dw":
        if "text" in c:
            return "t"
        if "movement" in c or "data" in c:
            return "M"
        if "pointer" in c or "script" in c:
            return "p"
        return "w"
    if directive == "dba":
        return "T" if "text" in c else "f"
    if directive == "dt":
        return "m"          # 24-bit little-endian, the money family
    return None


def parse_commands(path):
    lines = open(path, encoding="utf-8").read().splitlines()

    idx, order = -1, []
    for line in lines:
        s = line.strip()
        m = CONST_DEF.match(s)
        if m:
            idx = int(m.group(1)) - 1 if m.group(1) else -1
            continue
        m = CONST.match(s)
        if m:
            idx += 1
            order.append((idx, m.group(1)))

    bodies, cur = {}, None
    for line in lines:
        s = line.strip()
        m = MACRO.match(s)
        if m:
            cur = m.group(1)
            bodies[cur] = []
            continue
        if s == "ENDM":
            cur = None
            continue
        if cur is not None:
            bodies[cur].append(line)

    out = []
    for op, name in order:
        body = bodies.get(name)
        if body is None:
            raise SystemExit(f"{name}: no MACRO body -- the file changed shape")
        args, first = [], True
        for line in body:
            s = line.strip()
            if not s or s.startswith(";") or s.startswith("assert"):
                continue
            parts = s.split(None, 1)
            directive = parts[0]
            rest = parts[1] if len(parts) > 1 else ""
            operand, _, comment = rest.partition(";")
            if directive not in ("db", "dw", "dba", "dn", "dt", "dr"):
                continue
            # The first `db <name>_command` is the opcode itself, not an operand.
            if first and directive == "db" and operand.strip() == f"{name}_command":
                first = False
                continue
            first = False
            # `db \1, \2` emits one byte per comma-separated value.
            count = len([p for p in operand.split(",") if p.strip()]) or 1
            k = kind_for(directive, comment)
            if k is None:
                raise SystemExit(f"{name}: unhandled directive {directive!r}")
            args.extend([k] * (count if directive in ("db",) else 1))
        out.append((op, name, "".join(args)))
    return out


# ------------------------------------------------------------- the handlers

JUMPTABLE = re.compile(r"^\s*dw\s+([A-Za-z_][\w.]*)\s*;\s*([0-9A-Fa-f]{2})\s*$")
LABEL = re.compile(r"^([A-Za-z_][\w.]*):")
# `jmp X` / `jr X` / `jp X` with NO condition. A condition is a bare cc before
# the comma (z, nz, c, nc), which is exactly what makes the branch optional.
UNCOND = re.compile(r"^(?:jmp|jp|jr)\s+(?!z\s*,|nz\s*,|c\s*,|nc\s*,)([A-Za-z_][\w.]*)\s*$")
RET = re.compile(r"^ret\s*$")
# A CONDITIONAL ret. Usually a real fall-through -- `Script_iffalse_endtext` is
# `ret nz` then `jr Script_endtext`, so when the condition fails the very next
# byte IS the next command. The one exception is a ret that follows a pointer
# move (Script_end's `ret nc` after ExitScriptSubroutine has popped the script
# stack): there, returning resumes at the caller's saved position, not here.
# So this is only ignorable once the pointer has already moved.
COND_RET = re.compile(r"^ret\s+(?:z|nz|c|nc)\s*$")
# A CONDITIONAL branch out of the handler. If its target does not terminate,
# neither does the handler: the other path falls through to the next command,
# which is exactly what `iffalse_jumptext` does when the condition is false.
COND_JUMP = re.compile(r"^(?:jmp|jp|jr)\s+(?:z|nz|c|nc)\s*,\s*([A-Za-z_][\w.]*)\s*$")
# An unconditional CALL to a routine that itself ends the script ends it here
# too: halloffame and credits both `call Script_endall` and then merely yield,
# so following jumps alone misses them.
CALL = re.compile(r"^call\s+(?!z\s*,|nz\s*,|c\s*,|nc\s*,)([A-Za-z_][\w.]*)\s*$")

# STOPSCRIPT IS NOT A SINK, and assuming it was is the trap here. It means
# "stop executing this FRAME", not "stop reading this script": applymovement,
# pokemart, trade, warp and every other command that waits on something calls
# it and then RESUMES at the following byte. Taking it as an ending marked
# applymovement a terminator, which would truncate a script at its first
# scripted walk -- the most common command in the game.
#
# What actually means "the next byte is not the next command" is narrower:
#   * the script POINTER was rewritten -- ScriptJump (far) or
#     ScriptJumpInCurrentBank (near). The near one is easy to miss and sjump,
#     sjumpfwd and stopandsjump reach nothing else.
#   * the script was switched OFF -- see ENDS_SCRIPT below.
SINKS = {"ScriptJump", "ScriptJumpInCurrentBank",
         # Pops the script stack, so execution resumes at the CALLER's saved
         # position. endcallback reaches nothing else and would otherwise be
         # classified as falling through.
         "ExitScriptSubroutine"}

# Writing SCRIPT_OFF to wScriptMode, or clearing wScriptRunning, is how a
# handler really ends the script. Script_end does both; endall and endcallback
# reach it. Detected by content rather than by name so a renamed handler still
# classifies correctly.
ENDS_SCRIPT = ("SCRIPT_OFF", "wScriptRunning")

# HANDLERS WHOSE *FALL-THROUGH* PATH KEEPS RUNNING.
#
# The walk above marks a handler terminating as soon as control can reach
# ScriptJump/StopScript. That is right for an unconditional exit and wrong for
# a handler whose exits are all CONDITIONAL and whose fall-through carries on:
# the common path still returns to the interpreter, so the next byte IS the
# next command.
#
# Script_reloadmapafterbattle (25:$6AF7) is the case that mattered. It reaches
# `jp ScriptJump` only when the player blacked out, and reaches LoadMemScript
# only when a mem-script is queued; otherwise it falls into Script_reloadmap
# (25:$6B3B) and the script continues. Classified as terminating it truncated
# 463 of 4472 scripts -- every trainer and gym-leader script, cut off right
# where it hands out its rewards. BlackthornGymClairScript lost the nine
# commands after it, two of which clear the gramps blocking Dragon's Den, so
# the Den had no entrance at all.
#
# Contrast Script_reloadend (25:$7166), which is `call Script_newloadmap /
# jr Script_end` -- unconditional, and correctly a terminator.
#
# Keep this list tiny and cite the address: every entry is a claim that the
# derivation is wrong, and an entry added in error walks a decoder off the end
# of a script into whatever follows it.
NOT_TERMINATORS = {"reloadmapafterbattle"}


def parse_handlers(path):
    lines = open(path, encoding="utf-8").read().splitlines()

    table = {}          # opcode -> handler label
    for line in lines:
        m = JUMPTABLE.match(line)
        if m:
            table[int(m.group(2), 16)] = m.group(1)

    # label -> (list of body lines, the label that follows it)
    order, bodies = [], {}
    cur = None
    for line in lines:
        s = line.split(";")[0].rstrip()
        m = LABEL.match(s)
        if m and not s.startswith((" ", "\t")):
            cur = m.group(1)
            if cur not in bodies:
                bodies[cur] = []
                order.append(cur)
            continue
        if cur is not None:
            bodies[cur].append(s.strip())
    nxt = {order[i]: (order[i + 1] if i + 1 < len(order) else None)
           for i in range(len(order))}

    # Fixpoint: a label terminates if control leaves it for a terminating label
    # (or a sink) without passing a `ret`.
    term = {name: True for name in SINKS}

    def evaluate(label, seen):
        if label in term:
            return term[label]
        if label in seen or label not in bodies:
            return False        # recursion, or a label defined in another file
        seen = seen | {label}
        if any(tok in line for line in bodies[label] for tok in ENDS_SCRIPT):
            return True
        moved = False   # has the script pointer already been rewritten here?
        for s in bodies[label]:
            if not s:
                continue
            if RET.match(s):
                # Once the pointer has moved, "returning to the interpreter"
                # resumes somewhere else -- not at the byte after this command.
                return moved
            if COND_RET.match(s):
                if not moved:
                    return False        # the other path reads the next command
                continue
            m = CALL.match(s)
            if m and evaluate(m.group(1), seen):
                if m.group(1) in SINKS:
                    moved = True
                    continue
                return True
            m = COND_JUMP.match(s)
            if m:
                # One path leaves, the other walks on. Only a target that also
                # terminates keeps the whole handler terminating.
                if not evaluate(m.group(1), seen):
                    return False
                continue
            m = UNCOND.match(s)
            if m:
                # Same reasoning: endcallback pops the stack and then merely
                # yields (`jmp StopScript`), which is not a fall-through.
                return True if moved else evaluate(m.group(1), seen)
            # A CONDITIONAL ret (`ret nc` in Script_end) is deliberately NOT an
            # exit here. It fires when ExitScriptSubroutine popped a script-stack
            # frame, so execution resumes at the CALLER's saved position -- still
            # not the byte after this command. Treating it as fall-through
            # declassified end, and reloadend behind it.
        follow = nxt.get(label)
        return evaluate(follow, seen) if follow else False

    changed = True
    while changed:
        changed = False
        for label in order:
            if label in term:
                continue
            v = evaluate(label, frozenset())
            if v:
                term[label] = True
                changed = True
    return table, term


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--src", required=True, help="polishedcrystal source tree")
    ap.add_argument("--out", required=True)
    args = ap.parse_args()

    cmds = parse_commands(os.path.join(args.src, "macros/scripts/events.asm"))
    table, term = parse_handlers(
        os.path.join(args.src, "engine/overworld/scripting.asm"))

    missing = [op for op, _, _ in cmds if op not in table]
    if missing:
        print(f"note: {len(missing)} commands have no jumptable entry "
              f"(first {missing[:4]}) -- treated as non-terminating")

    terminators = sorted(
        name for op, name, _ in cmds
        if term.get(table.get(op), False) and name not in NOT_TERMINATORS)

    with open(args.out, "w", encoding="utf-8", newline="\n") as f:
        f.write(
            "-- Polished Crystal's script command table: %d commands where\n"
            "-- Gold/Crystal have ~120, renumbered from index 3 onward -- so a\n"
            "-- Polished Crystal script read with Crystal's table desyncs on the\n"
            "-- first shifted opcode and never recovers.\n"
            "--\n"
            "-- GENERATED by tools/gen_polished_ops.py.  Names and operand widths\n"
            "-- come from the disassembly's macros/scripts/events.asm, where each\n"
            "-- MACRO body is literally what the assembler emits; the terminator\n"
            "-- list is derived from engine/overworld/scripting.asm by following\n"
            "-- each handler to StopScript/ScriptJump rather than from the command\n"
            "-- NAMES, which lie both ways here (`iffalse_jumptext` falls through,\n"
            "-- `fruittree` never returns).  Do not hand-edit: regenerate.\n"
            % len(cmds))
        f.write("Gen2ScriptOps.COMMANDS_POLISHED = {\n")
        for i in range(0, len(cmds), 3):
            row = cmds[i:i + 3]
            f.write("  " + " ".join('{ "%s", "%s" },' % (n, a) for _, n, a in row))
            f.write(" -- %02X\n" % row[0][0])
        f.write("}\n\n")
        f.write("Gen2ScriptOps.TERMINATORS_POLISHED = {\n")
        for i in range(0, len(terminators), 4):
            f.write("  " + " ".join('["%s"] = true,' % n
                                    for n in terminators[i:i + 4]) + "\n")
        f.write("}\n")

    print(f"wrote {args.out}: {len(cmds)} commands, "
          f"{len(terminators)} terminators")
    print("  terminators:", ", ".join(terminators))


if __name__ == "__main__":
    main()
