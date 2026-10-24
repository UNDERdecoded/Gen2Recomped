package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.modkit")
local rows = dofile("tests/rom_text/format_cases.lua").run()
local byName = {}
for _, row in ipairs(rows) do
  byName[row.name] = row.text
end
T.eq(byName["one-slot"], "GOLD wakes!", "native ordinal slot substitution")
T.eq(byName["defer-player"], "{PLAYER} watches GOLD", "player token remains for textbox")
T.eq(byName.done, "GOLD wakes!{DONE}", "ending marker is not an argument slot")
T.eq(byName.prompt, "GOLD wakes!{PROMPT}", "prompt marker is not an argument slot")
T.eq(byName.named, "{PLAYER} GOLD {RIVAL}", "native named values substitute only supplied tokens")
T.eq(byName["printf-is-not-a-slot"], "GOLD fallback", "printf-shaped prose retains native fallback policy")
local b = setmetatable(
  { data = { text = { TEST = "{USER}{PROMPT}" } } },
  { __index = require("src.battle.BattleState") }
)
T.eq(b:romText("TEST", "%s fallback", "GOLD"), "GOLD{PROMPT}", "actual battle reader uses common formatter")
T.finish("native label-prose formatter")
