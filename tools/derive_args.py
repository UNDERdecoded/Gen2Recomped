#!/usr/bin/env python3
"""Derive Prism's script-command argument widths from its own source.

Prism's ScriptCommandTable has 232 entries where Crystal has ~120, diverging
from index 13 onward, so every later opcode is shifted and the disassembler
desyncs.  What the disassembler needs per command is how many BYTES it takes
from the script stream, and that is decided by which primitives the handler
calls:

    GetScriptByte / GetScriptByteOrVar / GetScriptByteOrVar_FF   1
    GetScriptHalfword / _de / OrVar / OrVar_HL                   2
    GetScriptThreeBytes                                          3
    GetScriptPerson / GetHalfwordVar                             0
        (these read a register or a RAM var, NOT the stream)
    SkipTwoScriptBytes                                           2
        (advances wScriptPos directly instead of reading)

Handlers branch -- `if_equal` reads its byte, then either jumps (consuming the
2-byte pointer) or skips those same 2 bytes -- so both arms consume the same
width and the answer is the MAX over paths, not the fall-through.  This walks
the control-flow graph to `ret`, taking that max, with jr/jp followed and calls
counted inline.
"""
import re, sys, json, os
from collections import Counter

READS = {
    'GetScriptByte': 1, 'GetScriptByteOrVar': 1, 'GetScriptByteOrVar_FF': 1,
    'GetScriptHalfword': 2, 'GetScriptHalfword_de': 2,
    'GetScriptHalfwordOrVar': 2, 'GetScriptHalfwordOrVar_HL': 2,
    'GetScriptThreeBytes': 3,
    'GetScriptPerson': 0, 'GetHalfwordVar': 0,
    'SkipTwoScriptBytes': 2,
}
# handlers that transfer control away; nothing after them consumes stream bytes
TERMINAL = {'ScriptJump', 'LocalScriptJump', 'ScriptJump_common', 'ScriptCall'}
# Reaching any of these means the interpreter does NOT come back to read the
# next byte, so the disassembler must stop: the script either jumped away or
# the engine was switched off.  A terminator the walker does not know is what
# sends it off the end of a script into whatever data follows -- which is what
# "opcode FF" desyncs are, byte values past the end of a 232-entry table.
#
# Careful: reaching ScriptJump is only terminal when it is UNCONDITIONAL.  The
# `if_*` commands also end in a jump, but their other arm is
# SkipTwoScriptBytes -> LocalScriptJump, which steps past the pointer and
# CONTINUES with the next command -- so a conditional is not a terminator.
# A handler mentioning SkipTwoScriptBytes anywhere is therefore conditional.
STOPS = {'StopScript', 'ScriptJump', 'ScriptJump_common'}
CONTINUES = 'SkipTwoScriptBytes'

LABEL = re.compile(r'^([A-Za-z_][\w]*):{1,2}\s*$')
LOCAL = re.compile(r'^(\.[\w]+):{0,2}\s*$')
COND = re.compile(r'^(?:jr|jp)\s+(nz|z|nc|c),\s*([A-Za-z_.][\w.]*)$')
UNCOND = re.compile(r'^(?:jr|jp)\s+([A-Za-z_.][\w.]*)$')
CALL = re.compile(r'^call\s+(?:(?:nz|z|nc|c),\s*)?([A-Za-z_.][\w.]*)$')


def load(paths):
    prog, index, cur = [], {}, None
    for path in paths:
        if not os.path.exists(path):
            continue
        for raw in open(path, encoding='utf-8', errors='replace'):
            line = raw.split(';')[0].strip()
            if not line:
                continue
            m = LABEL.match(line)
            if m:
                cur = m.group(1)
                index.setdefault(cur, len(prog))
                continue
            lm = LOCAL.match(line)
            if lm:
                if cur:
                    index.setdefault(cur + lm.group(1), len(prog))
                continue
            prog.append((line, cur))
    return prog, index


def mentions(prog, index, start, needle, seen=None, depth=0):
    seen = seen or set()
    if start is None or start >= len(prog) or start in seen or depth > 4:
        return False
    seen = seen | {start}
    pc = start
    while pc < len(prog):
        text, owner = prog[pc]
        if needle in text:
            return True
        if text in ('ret', 'reti'):
            return False
        m = re.match(r'^(?:jr|jp)\s+([A-Za-z_.][\w.]*)$', text)
        if m:
            n = m.group(1)
            t = (index.get((owner or '') + n) if n.startswith('.')
                 else index.get(n))
            return mentions(prog, index, t, needle, seen, depth + 1)
        pc += 1
    return False


def terminal(prog, index, start, seen=None, depth=0):
    """True when the handler's primary path leaves via StopScript/ScriptJump
    rather than returning to the interpreter loop."""
    seen = seen or set()
    if start is None or start >= len(prog) or start in seen or depth > 6:
        return False
    seen = seen | {start}
    pc = start
    while pc < len(prog):
        text, owner = prog[pc]
        if text in ('ret', 'reti'):
            return False
        m = re.match(r'^(?:call|jr|jp)\s+(?:(?:nz|z|nc|c),\s*)?([A-Za-z_.][\w.]*)$', text)
        if m:
            n = m.group(1)
            if n in STOPS and not text.startswith('call'):
                return True
            if n == 'StopScript':
                return True
            if text.startswith(('jr ', 'jp ')) and not re.match(
                    r'^(?:jr|jp)\s+(?:nz|z|nc|c),', text):
                t = (index.get((owner or '') + n) if n.startswith('.')
                     else index.get(n))
                return terminal(prog, index, t, seen, depth + 1)
        pc += 1
    return False


def walk(prog, index, start, memo, stack):
    if start is None or start >= len(prog):
        return 0
    if start in memo:
        return memo[start]
    if start in stack:
        return 0
    stack = stack | {start}
    pc, total, best = start, 0, 0

    def target(name, owner):
        if name.startswith('.'):
            return index.get((owner or '') + name)
        return index.get(name)

    while pc < len(prog):
        text, owner = prog[pc]
        if text in ('ret', 'reti'):
            return finish(memo, start, max(best, total))
        c = CALL.match(text)
        if c:
            n = c.group(1)
            if n in READS:
                total += READS[n]
            elif n in TERMINAL:
                return finish(memo, start, max(best, total))
            else:
                t = target(n, owner)
                if t is not None:
                    total += walk(prog, index, t, memo, stack)
            pc += 1
            continue
        cd = COND.match(text)
        if cd:
            n = cd.group(2)
            if n in READS:
                best = max(best, total + READS[n])
            elif n in TERMINAL:
                best = max(best, total)
            else:
                t = target(n, owner)
                if t is not None:
                    best = max(best, total + walk(prog, index, t, memo, stack))
            pc += 1
            continue
        u = UNCOND.match(text)
        if u:
            n = u.group(1)
            if n in READS:
                return finish(memo, start, max(best, total + READS[n]))
            if n in TERMINAL:
                return finish(memo, start, max(best, total))
            t = target(n, owner)
            return finish(memo, start,
                          max(best, total + walk(prog, index, t, memo, stack)))
        pc += 1
    return finish(memo, start, max(best, total))


def finish(memo, start, value):
    memo[start] = value
    return value


def main():
    root = sys.argv[1]
    prog, index = load([os.path.join(root, p) for p in (
        'engine/scripting.asm', 'home/map.asm', 'home/audio.asm',
        'home/window.asm', 'home/joypad.asm', 'home/scripting.asm',
        'home/menu.asm')])
    names = re.findall(r'dw Script_([A-Za-z0-9_]+)',
                       open(os.path.join(root, 'engine/scripting.asm'),
                            encoding='utf-8', errors='replace').read())
    memo = {}
    out = []
    for i, n in enumerate(names):
        start = index.get('Script_' + n)
        out.append({'index': i, 'name': n,
                    'bytes': walk(prog, index, start, memo, frozenset())
                             if start is not None else None,
                    'terminal': (terminal(prog, index, start)
                                 and not mentions(prog, index, start,
                                                  CONTINUES))})
    json.dump(out, open('prism_script_args.json', 'w'), indent=1)
    print('commands: %d, unresolved: %d'
          % (len(out), sum(1 for o in out if o['bytes'] is None)))
    print('width histogram:', sorted(Counter(o['bytes'] for o in out).items()))
    terms = [o['name'] for o in out if o['terminal']]
    print('terminators: %d -> %s' % (len(terms), ', '.join(terms[:14])))
    for o in out[:16]:
        print('  %3d %-22s %s' % (o['index'], o['name'], o['bytes']))
    return 0


if __name__ == '__main__':
    sys.exit(main())
