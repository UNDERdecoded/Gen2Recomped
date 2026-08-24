#!/usr/bin/env python3
"""Generate Gen2ScriptOps.COMMANDS_PRISM from Prism's own macros/event.asm.

The previous version of this script DERIVED operand widths by walking each
handler's control flow to `ret` and taking the max over branches.  That is a
guess, and it guessed badly: it made `random` seven bytes wide, `givemoney`
twelve and `setevent` eight, where the real answers are one, four and two.  A
command that is read too wide swallows the next command's opcode, so the
disassembler lands in the middle of the stream and never recovers -- 1047
scripts desynced, and every failing opcode was >= 236 (the table has 236
entries) because the reader had walked clean off the end.

macros/event.asm is not a guess.  It is the encoder: `enum <name>_command`
gives the opcode in ScriptCommandTable order, and the MACRO body that follows
gives the exact bytes the assembler emits.  This is the same method the Crystal
table in src/import/Gen2ScriptOps.lua was built with, against pokecrystal's
macros/scripts/events.asm.

Usage:
    python3 tools/gen_prism_ops.py <path-to-prism-src> [-o tools/prism_ops.lua]

Spec letters (see src/import/Gen2ScriptOps.lua):
    b byte   w word   p script pointer   t text pointer   d data pointer
    f far script      T far text         D far data       m 3-byte money
    M movement pointer
"""
import argparse
import os
import re
import sys

# Directive -> byte width.  dt is pokecrystal's three-byte big-endian money;
# dn packs two nibbles into ONE byte, which is exactly the trap that makes a
# hand-written table drift.
# `map X` is macros/map.asm's `db GROUP_X, MAP_X` -- TWO bytes, not a
# directive this table can afford to skip: every warp / blackoutmod /
# warpfacing carries one, and reading them as zero-width put the walker two
# bytes short on each, which is a desync per warp in the game.
WIDTH = {'db': 1, 'dw': 2, 'dba': 3, 'dt': 3, 'dn': 1, 'dbw': 3, 'dl': 4,
         'map': 2}

# A `dw`/`dba` is two or three bytes whatever it points at, but the letter
# tells the disassembler whether to FOLLOW it as a script, queue it as text, or
# leave it alone -- so the semantic still has to be right.  Taken from the
# operand comment the macro carries ("; pointer", "; text pointer") and, where
# the comment is silent, from the command name.
TEXT_CMDS = {
    'writetext', 'repeattext', 'jumptext', 'jumptextfaceplayer', 'trainertext',
    'farwritetext', 'farjumptext', 'farjumptextfaceplayer', 'phonecall',
    'battletext', 'yesnotext', 'repeattextfaceplayer',
    # Prism's own.  Script_showtext is `Script_opentext / Script_writetext /
    # Script_closetext` -- the operand is a TEXT pointer, and derived as a bare
    # word it reached show_text as a NUMBER, which then indexed the text table
    # with it and threw (Data.lua textEntry, `textConst:gsub`).
    'showtext',
    # Script_winlosstext copies FOUR script bytes into wWinTextPointer: two
    # text pointers, not two words.
    'winlosstext',
}
SCRIPT_CMDS = {
    'scall', 'farscall', 'ptcall', 'jump', 'farjump', 'ptjump', 'if_equal',
    'if_not_equal', 'iffalse', 'iftrue', 'if_greater_than', 'if_less_than',
    'sdefer', 'sjump', 'stopandsjump', 'farsjump', 'priorityjump',
    # Script_ptpriorityjump is `call StopScript / jp Script_jump` -- a plain
    # local jump despite the `pt` prefix, so its operand IS a script pointer.
    # Missing from this set it derived as a bare word, and the alias onto
    # sjump then had a number where it needed a label and dropped the jump.
    'ptpriorityjump',
}
MOVEMENT_CMDS = {'applymovement', 'applymovementlasttalked', 'applymovement2'}

# Commands whose operands the enum walk cannot see, because one MACRO emits
# several opcodes.  `sif` is the whole family:
#
#     sif = 5, then   ->  db sifeq_command / db 5 / db then_command
#     sif true, then  ->  db siftrue_command / db then_command
#
# so the four COMPARING forms carry a value byte and the two boolean ones do
# not.  There is no `MACRO sifeq`, so the generator saw no body and emitted no
# operands -- one byte short on every comparison in the game.
SPEC_OVERRIDES = {
    'sifeq': 'b', 'sifne': 'b', 'sifgt': 'b', 'siflt': 'b',
    # `scriptjumptable` is the MACRO; `jumptable` is the enum and the name the
    # ops table carries, so the generator found no body and gave it no
    # operands.  It takes a two-byte pointer to a table of script pointers --
    # read as zero-width, the walker ate the pointer's low byte as the next
    # opcode.  `d` rather than `p`: the target is a POINTER TABLE, not a
    # script, so it must not be queued as one.
    'jumptable': 'd',
    # ptcall / ptjump name a THREE-BYTE far pointer, not a script:
    # `GetScriptHalfword / ld b, [hl] / ld e, [hl] / ld d, [hl]`.  Read as a
    # script pointer ('p') the walker queued the pointer bytes themselves as
    # code -- 'd' keeps the address raw so the extractor can dereference it.
    'ptcall': 'd',
    'ptjump': 'd',
}

# `then_command EQU scriptstartasm_command` (macros/event.asm) -- Prism's own
# comment is "we can't use scriptstartasm with conditionals, so...".  The
# opcode is REUSED as the `then` marker that opens a `sif` block, and the
# interpreter tests for it explicitly (engine/script_conditionals.asm `cp
# then_command`).  Treating it as scriptstartasm's terminator stopped the
# decoder dead on the third byte of every structured conditional in the game --
# and `sif` is how Prism writes nearly all of its map events.
# scriptstartasm: `then_command EQU scriptstartasm_command`, so $CF is the
# conditional marker far more often than it is an asm call.
#
# jumptable: Script_scriptjumptable is `GetScriptHalfword / ld b, 1 / jr
# ScriptJumptable`, and ScriptJumptable branches on b -- `jp z, LocalScriptJump`
# for b=0, falling into ScriptCall otherwise.  b is 1 here, so it CALLS the
# selected case and comes back; only anonjumptable (b=0) actually jumps away.
# The derivation cannot see the difference -- both reach ScriptJumptable -- so
# the shared handler's terminator verdict has to be overridden for this one.
# MiningScript is `scriptjumptable .MiningModes` followed by twenty more
# commands, all of which were being thrown away.
#
# end_if_just_battled: `ld a, [wRunningTrainerBattleScript] / and a / ret z /
# jp Script_end`.  The conditional RET is the ordinary path -- it is the whole
# point of the command -- but a conditional ret cannot be told apart from
# Script_end's own `call ExitScriptSubroutine / ret nc`, where returning means
# the script really has left.  Route85 is `end_if_just_battled / opentext`.
NON_TERMINATORS = {'scriptstartasm', 'jumptable', 'scriptjumptable',
                   'end_if_just_battled'}


def parse_event_macros(path):
    """[(opcode, name, spec)] in ScriptCommandTable order."""
    text = open(path, encoding='utf-8', errors='replace').read()
    lines = text.splitlines()

    # enum order first.  EVERY `enum` line consumes an opcode slot, including
    # the four bare `enum skip` placeholders Prism leaves for retired commands.
    # Skipping those shifts every command after them down by one -- which is
    # the same "desyncs and never recovers" failure this table exists to
    # prevent, just moved from the ROM into the generator.  236 enum lines =
    # 236 entries in ScriptCommandTable; the two counts are checked below.
    order = []
    for line in lines:
        m = re.match(r'\s*enum\s+(\w+)\s*(?:;.*)?$', line)
        if not m:
            continue
        name = m.group(1)
        if name.endswith('_command'):
            order.append(name[:-len('_command')])
        else:
            order.append(None)   # `enum skip`: a hole, but still a slot

    # then each MACRO body
    bodies, name, body = {}, None, []
    for line in lines:
        m = re.match(r'\s*MACRO\s+(\w+)\s*$', line)
        if m:
            if name is not None:
                bodies[name] = body
            name, body = m.group(1), []
            continue
        if re.match(r'\s*ENDM\b', line):
            if name is not None:
                bodies[name] = body
            name, body = None, []
            continue
        if name is not None:
            body.append(line)
    if name is not None:
        bodies[name] = body

    out, conditional = [], []
    for index, cmd in enumerate(order):
        if cmd is None:
            # a retired slot: no name, no operands, and no handler worth
            # following.  It still has to occupy its opcode.
            out.append((index, 'unused_%02X' % index, '', False))
            continue
        body = bodies.get(cmd)
        if body is None:
            # a command with a handler but no macro of its own: SPEC_OVERRIDES
            # is where the shared-macro families (sif...) get their operands
            out.append((index, cmd, SPEC_OVERRIDES.get(cmd, ''), False))
            continue

        has_if = any(re.match(r'\s*(if|elif|else|endc)\b', l, re.I) for l in body)
        spec, skipped_opcode = [], False
        depth_skip = False
        for line in body:
            code = line.split(';')[0].strip()
            if not code:
                continue
            # Only the FIRST branch of a conditional macro is measured; those
            # commands are listed below so a human checks them rather than the
            # table silently encoding one arm.
            #
            # CASE-INSENSITIVELY.  Prism writes its assembler directives in
            # UPPERCASE (`IF _NARG >= 4` / `ELSE` / `ENDC`) and these tests
            # were lowercase-only, so for every conditional macro BOTH arms
            # were counted and the command came out one byte too wide -- and
            # has_if never fired either, so none of them was flagged for
            # review.  showemote is the one that shows: read five bytes
            # instead of four it swallows the next opcode, and the Route 69
            # rival cutscene lost its dialogue AND its `dotrigger`.
            if re.match(r'^(elif|else)\b', code, re.I):
                depth_skip = True
                continue
            if re.match(r'^endc\b', code, re.I):
                depth_skip = False
                continue
            if re.match(r'^if\b', code, re.I):
                continue
            if depth_skip:
                continue
            d = re.match(r'^(\w+)\b', code)
            if not d or d.group(1) not in WIDTH:
                continue
            directive = d.group(1)
            if not skipped_opcode and directive == 'db' \
                    and re.search(r'\b%s_command\b' % re.escape(cmd), code):
                skipped_opcode = True   # the opcode byte itself
                continue
            spec.append(letter_for(cmd, directive, code, WIDTH[directive]))
        if has_if:
            conditional.append(cmd)
        out.append((index, cmd, SPEC_OVERRIDES.get(cmd, ''.join(spec)), has_if))
    return out, conditional


def letter_for(cmd, directive, code, width):
    comment = code.lower()
    if width == 1:
        return 'b'
    if directive == 'dt':
        return 'm'
    if width == 3:
        if cmd in TEXT_CMDS or 'text' in comment:
            return 'T'
        if cmd in SCRIPT_CMDS or 'script' in comment:
            return 'f'
        return 'D'
    if directive == 'map':
        return 'bb'          # map group, map number
    if width == 2:
        if cmd in MOVEMENT_CMDS or 'movement' in comment:
            return 'M'
        if cmd in TEXT_CMDS or 'text' in comment:
            return 't'
        if cmd in SCRIPT_CMDS or 'pointer' in comment:
            return 'p'
        return 'w'
    return 'b' * width


# ---------------------------------------------------------------- terminators
# A command is a terminator for a LINEAR walker when the byte after its
# operands is not the next command -- either the handler stops the script, or
# it unconditionally rewrites the script pointer (every `jump`, and everything
# that jumps to a canned script such as `fruittree` or `jumpstd`).
#
# The distinction that matters is UNCONDITIONAL.  Script_if_equal reaches
# ScriptJump too, but only through `jr z, Script_jump`, and its other arm falls
# through to the next command -- marking it a terminator would truncate every
# conditional script in the game.  So the walk below follows plain `jp`/`jr`
# and fallthrough only, and stops at a bare `ret`.
#
# WriteMapEntryMethodLoadMapStatusEnterMapAndStopScript is deliberately NOT
# here despite the name.  It sets wMapStatus and stops the script so the map
# can be re-entered; wScriptPos is untouched, so the script picks up at the
# next byte once the new map is up.  Counting it truncated `warp`, `warpfacing`,
# `warpcheck`, `newloadmap`, `reloadmap` and `reloadmapafterbattle`, every one
# of which Prism's own maps follow with more commands -- AcaniaGym's
# `reloadmapafterbattle / opentext`, BattleArcadeLobby's `warp / applymovement`,
# HeathInn's `reloadmap / takemoney`.  The commands that really do end through
# this path (`reloadandreturn`) reach Script_end on their own afterwards.
STOPPERS = {
    'StopScript',
    'ScriptJump', 'LocalScriptJump', 'ScriptFarJump', 'ScriptPtJump',
    'FarScriptJump', 'ScriptJumptable', 'ScriptJumpTable',
}
# Prism spells it ScriptJumptable, pokecrystal ScriptJumpTable.  One letter of
# case cost `scriptjumptable` its terminator flag and 57 desyncs, so match
# these case-insensitively rather than relying on getting the spelling right.
STOPPERS_LOWER = {name.lower() for name in STOPPERS}

COND = ('z', 'nz', 'c', 'nc')

# Routines that ADVANCE past the operands and resume: reaching one means the
# next byte IS the next command.  SkipTwoScriptBytes is how every `if_*` takes
# its false arm -- it steps over the 2-byte pointer and jumps to the new
# position -- so without this the six conditionals all looked like jumps and
# would have truncated every branching script in the game.
CONTINUERS = {
    'SkipTwoScriptBytes', 'SkipOneScriptByte', 'SkipThreeScriptBytes',
    # Sets wMapStatus and stops so the map can be re-entered; wScriptPos is
    # untouched, so the script picks up at the next byte once the new map is
    # up.  Reached through plain StopScript, so it has to be named here rather
    # than left out of STOPPERS.  Counting it a stopper truncated `warp`,
    # `warpfacing`, `warpcheck`, `newloadmap`, `reloadmap` and
    # `reloadmapafterbattle`, every one of which Prism's own maps follow with
    # more commands -- AcaniaGym's `reloadmapafterbattle / opentext`,
    # BattleArcadeLobby's `warp / applymovement`, HeathInn's `reloadmap /
    # takemoney`.  The ones that really do finish (`reloadandreturn`) reach
    # Script_end on their own afterwards.
    'WriteMapEntryMethodLoadMapStatusEnterMapAndStopScript',
}


# The handlers are not all in engine/scripting.asm: Script_endtext lives in
# home/joypad.asm, and a handler this walk cannot see falls to the
# conservative "continues" answer -- which cost endtext its terminator flag.
HANDLER_FILES = [
    ('engine', 'scripting.asm'),
    ('home', 'joypad.asm'),
    ('home', 'map.asm'),
    ('engine', 'events.asm'),
]


def _handler_bodies(path):
    """label -> (body lines, next label in file order)"""
    paths = path if isinstance(path, list) else [path]
    lines = []
    for one in paths:
        if os.path.exists(one):
            lines.extend(open(one, encoding='utf-8',
                              errors='replace').read().splitlines())
            lines.append('__FILE_BREAK__:')   # no fallthrough across files
    order, bodies, cur, body = [], {}, None, []
    for line in lines:
        m = re.match(r'^([A-Za-z_][\w]*)::?', line)
        if m:
            if cur:
                bodies[cur] = body
            cur, body = m.group(1), []
            order.append(cur)
            continue
        if cur is not None:
            body.append(line)
    if cur:
        bodies[cur] = body
    nxt = {name: (order[i + 1] if i + 1 < len(order) else None)
           for i, name in enumerate(order)}
    return bodies, nxt


def _terminates(name, bodies, nxt, memo, stack):
    if name in CONTINUERS:
        return False
    if name.lower() in STOPPERS_LOWER:
        return True
    if name not in bodies:
        # a routine this file does not define (jpba into another bank) comes
        # back through the interpreter as far as we can tell -- and guessing
        # "terminator" here silently truncates a script, where guessing
        # "continues" merely leaves a desync we can see and chase
        return False
    if name in memo:
        return memo[name]
    # StopScript on its own is NOT the end of a script -- it clears the
    # running bit and the interpreter picks up again from wScriptPos, which
    # has already stepped past this command's operands.  Only the SCRIPT_OFF
    # path (Script_end's `xor a`) really finishes.  A handler that parks
    # wScriptMode at SCRIPT_WAIT or SCRIPT_WAIT_MOVEMENT first is WAITING, and
    # the next byte is still the next command:
    #
    #     ApplyMovement:  ... ld a, SCRIPT_WAIT_MOVEMENT
    #                         ld [wScriptMode], a
    #                         jp StopScript
    #
    # Marked a terminator, `applymovement` truncated every cutscene at its
    # first movement -- IntroMomLeavingDialogue stopped on the step that walks
    # the player's mother over, so it never reached the `dotrigger 2` that
    # arms the landslide, and the rocks never fell.
    if any('SCRIPT_WAIT' in line.split(';')[0] for line in bodies[name]):
        memo[name] = False
        return False
    if name in stack:
        return False           # unresolved recursion: assume it continues
    stack.add(name)
    result = False
    for line in bodies[name]:
        code = line.split(';')[0].strip()
        if not code:
            continue
        # jpba/jpab/farjp are far-jump MACROS, not `jp` -- they leave this
        # file, so they fall to the not-a-terminator answer above
        m = re.match(r'^(jp|jr)\s+([A-Za-z_][\w.]*)\s*$', code)
        if m:                                   # unconditional transfer
            result = _terminates(m.group(2).split('.')[0], bodies, nxt, memo, stack)
            break
        m = re.match(r'^(?:jp|jr)\s+(?:%s)\s*,\s*([A-Za-z_][\w.]*)\s*$'
                     % '|'.join(COND), code)
        if m:
            # An optional branch whose TARGET comes back means this handler can
            # come back, so the byte after its operands really is the next
            # command.  Ignoring the target entirely is what made
            # `reloadmapafterbattle` a terminator: its common arm is
            # `jr nz, Script_reloadmap` and only the white-out arm jumps away,
            # yet Prism follows it with more script all over the game
            # (AcaniaGym's `reloadmapafterbattle / opentext`).
            if not _terminates(m.group(1).split('.')[0], bodies, nxt, memo, stack):
                result = False
                break
            continue                            # that arm ends; keep walking
        if re.match(r'^ret\s+(%s)\s*$' % '|'.join(COND), code):
            continue                            # optional return, keep walking
        if re.match(r'^ret\s*$', code):
            result = False                      # back to the interpreter
            break
        # jpba / jpab / farjp / predef_jump are far-jump MACROS: the routine
        # ENDS here, into a bank this file does not cover, so the answer is
        # the same "assume it comes back" the unknown-routine case gives.
        # Without this the walk fell out of the loop and inherited the verdict
        # of whatever label happened to be defined next.
        if re.match(r'^(jpba|jpab|farjp|predef_jump)\b', code):
            result = False
            break
    else:
        follow = nxt.get(name)                  # fell off the end into the next label
        result = _terminates(follow, bodies, nxt, memo, stack) if follow else False
    stack.discard(name)
    memo[name] = result
    return result


def parse_terminators(src, order_names):
    """Opcode indices whose handler never returns to the following byte."""
    bodies, nxt = _handler_bodies(
        [os.path.join(src, *parts) for parts in HANDLER_FILES])
    memo = {}
    out = set()
    for index, handler in enumerate(order_names):
        if not handler:
            continue
        name = handler[len('Script_'):] if handler.startswith('Script_') else handler
        if name in NON_TERMINATORS:
            continue
        if _terminates(handler, bodies, nxt, memo, set()):
            out.add(index)
    return out


def command_table_order(src):
    """The handler label per opcode, straight from ScriptCommandTable."""
    path = os.path.join(src, 'engine', 'scripting.asm')
    text = open(path, encoding='utf-8', errors='replace').read()
    table = text[text.index('ScriptCommandTable:'):text.index('ScriptCommandTableEnd:')]
    return re.findall(r'^\s*dw\s+(\w+)', table, re.M)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('src', help='path to the Prism disassembly root')
    ap.add_argument('-o', '--out', default='tools/prism_ops.lua')
    args = ap.parse_args()

    macro_path = os.path.join(args.src, 'macros', 'event.asm')
    if not os.path.exists(macro_path):
        sys.exit('not found: %s' % macro_path)
    rows, conditional = parse_event_macros(macro_path)

    # Cross-check against ScriptCommandTable itself.  The macro file and the
    # handler table are two independent statements of the same list; if they
    # disagree on LENGTH then the enum walk missed a slot (the four bare `enum
    # skip` placeholders are exactly the kind of thing that gets missed), and
    # every opcode after the gap is wrong.  Refuse rather than emit a table
    # that is off by one.
    handlers = command_table_order(args.src)
    if len(handlers) != len(rows):
        sys.exit('macros/event.asm gives %d commands, ScriptCommandTable has %d'
                 % (len(rows), len(handlers)))
    terminators = parse_terminators(args.src, handlers)

    # Name-by-name, not just count.  Four `enum` lines in macros/event.asm sit
    # INSIDE macro bodies, so "the counts match" is not proof the two lists are
    # aligned -- a phantom slot and a missing one cancel out in a count and
    # leave every opcode after them wrong.  Compare the actual names.
    drift = []
    for index, (_, name, _, _) in enumerate(rows):
        want = handlers[index]
        want = want[len('Script_'):] if want.startswith('Script_') else want
        if name.startswith('unused_'):
            continue
        # The macro name and the handler label are allowed to differ in case
        # and in a `script` prefix -- `jumptable` is Script_scriptjumptable,
        # `givetm` is Script_giveTM.  Anything else is real drift.
        if name.lower() != want.lower() \
                and name.lower() != want.lower().replace('script', '', 1):
            drift.append('%02X: macros say %s, table says %s' % (index, name, want))
    if drift:
        sys.exit('macros/event.asm and ScriptCommandTable disagree:\n  '
                 + '\n  '.join(drift[:20])
                 + ('\n  ...and %d more' % (len(drift) - 20) if len(drift) > 20 else ''))

    lines = [
        "-- Prism's ScriptCommandTable (engine/scripting.asm): %d commands where"
        % len(rows),
        '-- Gold/Crystal have ~120, diverging from index 13 onward -- so a Prism',
        '-- script read with Crystal\'s table desyncs on the first shifted opcode',
        '-- and never recovers.',
        '--',
        '-- GENERATED by tools/gen_prism_ops.py from the Prism disassembly\'s own',
        '-- macros/event.asm.  `enum <name>_command` gives the order and each',
        '-- MACRO body gives the exact bytes the assembler emits, so these widths',
        '-- are the encoder\'s, not an inference from handler control flow.  Do not',
        '-- hand-edit: regenerate.',
        'Gen2ScriptOps.COMMANDS_PRISM = {',
    ]
    for start in range(0, len(rows), 3):
        chunk = rows[start:start + 3]
        parts = ['{ "%s", "%s" }' % (name, spec) for _, name, spec, _ in chunk]
        lines.append('  %s, -- %02X' % (', '.join(parts), chunk[0][0]))
    lines.append('}')

    if conditional:
        lines.append('')
        lines.append('-- Macros whose byte count depends on their argument count'
                     ' (`if _NARG`).')
        lines.append('-- The first branch is what the table above encodes; these are'
                     ' the ones')
        lines.append('-- to check by hand if a script desyncs at one of them:')
        for cmd in conditional:
            lines.append('--   %s' % cmd)

    lines.append('')
    lines.append('-- Commands after which the interpreter never reads the next byte:')
    lines.append('-- the handler either stops the script or UNCONDITIONALLY rewrites the')
    lines.append('-- script pointer.  Derived from engine/scripting.asm by following only')
    lines.append('-- plain jp/jr and fallthrough -- `if_equal` reaches ScriptJump too, but')
    lines.append('-- through `jr z`, and its other arm falls through, so it is not one.')
    lines.append('--')
    lines.append('-- A terminator the walker does not know is what runs it off the end of a')
    lines.append('-- script into whatever follows, which is where every remaining desync')
    lines.append('-- came from: the failing opcode was always >= %d, i.e. past the end of'
                 % len(rows))
    lines.append('-- the table, so it had never been a command at all.')
    lines.append('Gen2ScriptOps.TERMINATORS_PRISM = {')
    row = []
    # Named with the MACRO name, because that is what the ops table above emits
    # and what the walker looks up.  Keying these off the HANDLER label instead
    # is why `jumptable` -- Script_scriptjumptable -- was never recognised as a
    # terminator and desynced 41 scripts on its own.
    termNames = sorted({rows[i][1] for i in terminators if i < len(rows)})
    for name in termNames:
        key = '["%s"]' % name if name in ('end', 'return', 'repeat', 'and', 'or',
                                          'not', 'nil', 'true', 'false', 'function',
                                          'local', 'then', 'do', 'while', 'for',
                                          'if', 'else', 'elseif', 'in', 'break') \
            else name
        row.append('%s = true' % key)
        if len(row) == 4:
            lines.append('  ' + ', '.join(row) + ',')
            row = []
    if row:
        lines.append('  ' + ', '.join(row) + ',')
    lines.append('}')

    with open(args.out, 'w') as fh:
        fh.write('\n'.join(lines) + '\n')
    print('wrote %s (%d commands, %d conditional, %d terminators)'
          % (args.out, len(rows), len(conditional), len(terminators)))


if __name__ == '__main__':
    main()
