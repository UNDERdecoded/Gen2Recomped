-- Parity: the S.S. Anne passenger's Snorlax description opens the Pokédex
-- entry and records Snorlax as seen (pokered/scripts/SSAnne2FRooms.asm).
package.path = "./?.lua;./?/init.lua;" .. package.path
local S = require("tests.harness").suite("parity ss anne Snorlax dex")
local check, eq = S.check, S.eq

local scripts = require("data.scripts.init")
local script = scripts.talkScript("SS_ANNE_2F_ROOMS",
  "TEXT_SSANNE2FROOMS_GENTLEMAN3")

check(script ~= nil, "the S.S. Anne passenger has a talk script")
eq(script[2][1], "show_text", "the passenger's line appears first")
eq(script[3][1], "mark_seen", "the Pokédex preview marks Snorlax seen")
eq(script[3][2], "SNORLAX", "the preview marks Snorlax seen")
eq(script[4][1], "push_screen", "the Pokédex entry opens after the line")
eq(script[4][2], "DexEntryMenu", "the Pokédex entry uses DexEntryMenu")
eq(script[4][3], "SNORLAX", "the Pokédex entry is for Snorlax")

local save = { pokedex = { seen = {}, owned = {} } }
require("src.script.Commands").mark_seen({ save = save }, "SNORLAX")
check(save.pokedex.seen.SNORLAX, "the preview records Snorlax as seen")
check(not save.pokedex.owned.SNORLAX, "the preview does not mark Snorlax owned")

S.finish()
