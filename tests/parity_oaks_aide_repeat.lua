-- Parity: after a reward, each Oak's Aide repeats its item explanation
-- instead of the pre-reward "come back" text (engine/events/oaks_aide.asm).
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end
local S = require("tests.harness").suite("parity Oak's Aide repeat text")
local eq = S.eq
local Data = require("src.core.Data")
if not Data.maps then Data:load() end
local Font = require("src.render.Font")
Font.load(Data)

local scripts = require("data.scripts.init")
local CASES = {
  { map = "ROUTE_2_GATE", text = "TEXT_ROUTE2GATE_OAKS_AIDE",
    item = "HM_FLASH", label = "_Route2GateOaksAideFlashExplanationText",
    value = "FLASH" },
  { map = "ROUTE_11_GATE_2F", text = "TEXT_ROUTE11GATE2F_OAKS_AIDE",
    item = "ITEMFINDER", label = "_Route11Gate2FOaksAideItemfinderDescriptionText",
    value = "FINDER" },
  { map = "ROUTE_15_GATE_2F", text = "TEXT_ROUTE15GATE2F_OAKS_AIDE",
    item = "EXP_ALL", label = "_Route15Gate2FOaksAideExpAllText",
    value = "EXP" },
}

for _, case in ipairs(CASES) do
  local pushed = {}
  local game = {
    data = { items = { [case.item] = { name = case.item } },
             text = { [case.label] = case.value } },
    save = { flags = { ["EVENT_GOT_" .. case.item] = true },
             player = { name = "RED" }, pokedex = { owned = {} } },
    stack = { push = function(_, state) pushed[#pushed + 1] = state end },
  }
  scripts.talkScript(case.map, case.text)(game, {}, nil, function() end)
  eq(pushed[1] and pushed[1].pages[1][1], case.value,
    case.item .. " aide repeats its item explanation")
end

S.finish()
