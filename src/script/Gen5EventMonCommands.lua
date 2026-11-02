-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- CASTELIA'S ZORUA STORY (Z047) AND LOSTLORN FOREST'S ZOROARK (Z385): the
-- picture the reader shows, and the event Pokemon the scenes use up.
--
-- READ FROM CODE (Black):
--   0x227 <species, form, ?, ?> (ov21 0x021D2524, task 0x021D26D1): a window
--         (0x020450F0) with the Pokemon's picture (0x0202D81C.., heap
--         0x8015) until A or B (pad & 3, 0x020362DC), then closed; the
--         script waits ("Have you seen Zorua? ... it looks like this!")
--   0x228 <kind, slot> (ov10 0x0216BEC0): kind - 0xF3 picks the check --
--         0xF3..0xF5 (Raikou, Entei, Suicune) check 2, 0xFB (Celebi)
--         check 0, anything else nothing -- on the party Pokemon at `slot`
--         (0x0201AB28, 0xDC a slot); when it passes (0x0202F498) its met
--         location (field 0x96) is moved on (0x0202F640):
--           check 0: Celebi, met at 30010, fateful, not shiny -> 30011
--           check 2: Raikou / Entei / Suicune, met at 30012, fateful,
--                    shiny -> 30013
--         and the check also wants fields 0x8F, 0x90, 0x91, 0x95 clear
-- INFERRED: those four fields are not kept here and read as clear; 0x227's
-- form and last two operands do not change the picture.

local M = {}

local okCommands, Commands = pcall(require, "src.script.Commands")
if not okCommands then Commands = {} end

local function G4() return require("src.script.Gen4Commands") end
local function val(ctx, v) return math.floor(tonumber(G4().valueOf(ctx, v)) or 0) end

M.KIND = { [0xF3] = 2, [0xF4] = 2, [0xF5] = 2, [0xFB] = 0 }
M.CHECK = {
  [0] = { species = { [251] = true }, from = 30010, to = 30011, shiny = false },
  [2] = { species = { [243] = true, [244] = true, [245] = true }, from = 30012, to = 30013, shiny = true },
}

local function speciesNumber(mon)
  local s = mon and mon.species
  if type(s) == "number" then return s end
  return tonumber(tostring(s or ""):match("(%d+)$"))
end

function M.passes(mon, check)
  local c = M.CHECK[check]
  if not (c and mon) then return false end
  local Party = require("src.pokemon.Party")
  if Party.isEgg(mon) then return false end
  if not c.species[speciesNumber(mon) or -1] then return false end
  if tonumber(mon.metLocation) ~= c.from then return false end
  local fateful = mon.fatefulEncounter
  if fateful == nil then fateful = mon.fateful end
  if not (fateful == true or fateful == 1) then return false end
  local shiny = require("src.pokemon.Pokemon").isShiny(mon) and true or false
  return shiny == c.shiny
end

function Commands.g5_event_mon_used(ctx, kind, slot)
  local check = M.KIND[val(ctx, kind)]
  if not check then return end
  local mon = ((ctx.save and ctx.save.party) or {})[val(ctx, slot) + 1]
  if M.passes(mon, check) then mon.metLocation = M.CHECK[check].to end
end

function Commands.g5_show_mon_picture(ctx, species)
  local ow, game = ctx.overworld, ctx.game
  if not (ow and game and game.stack) then return end
  local id = val(ctx, species)
  local data = game.data
  local key = data and data.pokemon and (data.pokemon[id] and id or (data.pokemon[("SPECIES_%03d"):format(id)] and ("SPECIES_%03d"):format(id)))
  if not key then return end
  local path, trueColor = require("src.pokemon.Sprites").path(data, key, "front", { kind = "pokepic" })
  if not path then return end
  local runner = ctx.runner
  local box = require("src.ui.PicBox").new(game, {
    path = path, trueColor = trueColor and true or false, passive = true, overworld = ow,
    box = { x = 10, y = 3, w = 10, h = 10 }, picTiles = 8,
  })
  box:arm(function() if runner then runner:resume() end end)
  game.stack:push(box)
  if runner then runner:yield() end
end
Commands.meta = Commands.meta or {}
Commands.meta.g5_show_mon_picture = { foreground = true, blocking = true }

-- 0x0DE <mode, species> (ov10 0x0215AEE8): a Pokemon of `species` built
-- (0x020173F0) and, with mode 0, registered as seen in the Pokedex
-- (0x0200CFA0) -- after the reader shows Zorua's picture (Z047); mode 1
-- does nothing more
function Commands.g5_dex_mark_seen(ctx, mode, species)
  if val(ctx, mode) ~= 0 then return end
  local save, data = ctx.save, ctx.game and ctx.game.data
  if not (save and data and data.pokemon) then return end
  local id = val(ctx, species)
  local key = data.pokemon[id] and id or (data.pokemon[("SPECIES_%03d"):format(id)] and ("SPECIES_%03d"):format(id))
  if not key then return end
  save.pokedex = save.pokedex or {}
  save.pokedex.seen = save.pokedex.seen or {}
  save.pokedex.seen[key] = true
end

function M.install(L)
  local function emit(s, row) s.out[#s.out + 1] = row end
  L.bwshowmonpicture = L.bwshowmonpicture or function(ins, s) emit(s, { "g5_show_mon_picture", ins.args[1] }) end
  L.bwdexmarkseen = L.bwdexmarkseen or function(ins, s) emit(s, { "g5_dex_mark_seen", ins.args[1], ins.args[2] }) end
  L.bweventmonused = L.bweventmonused or function(ins, s) emit(s, { "g5_event_mon_used", ins.args[1], ins.args[2] }) end
end

return M
