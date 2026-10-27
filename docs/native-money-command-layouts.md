# Native money-window script layouts

`updatemoneybox` ($95) consumes three bytes (x, y, ignore) in all five GBA
editions. Treating it as operand-free decodes those bytes as commands.
`hidemoneybox` ($94) consumes x/y in Ruby/Sapphire, whereas the later games
removed both reads. Resolve this distinction per extractor, without mutating
the shared command table or duplicating manifests. Discovery uses the corrected common
update width. Only GBA import markers change; save schemas and files do not.

Primary references:

- https://github.com/pret/pokefirered/blob/master/src/scrcmd.c
- https://github.com/pret/pokeemerald/blob/master/src/scrcmd.c
- https://github.com/pret/pokeruby/blob/master/src/scrcmd.c

`tools/script-command-widths/check.lua` decodes sentinel streams for every
edition and switches RS/later tables in both directions. It checks both
following assignments and the final terminator, not only the declared widths.
