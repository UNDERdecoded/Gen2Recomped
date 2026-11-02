-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- BLACK / WHITE'S PARTY CHECKS that decide an item or a ribbon.
--
-- READ FROM CODE (Black, ov10 / ov21 handlers):
--   0x112 <dest, slotVar> (ov10 0x0215B5BC): the party Pokemon's six effort
--         values summed (fields 0x0D..0x12 through 0x02017E1C) -- the
--         Effort Ribbon's check against 510 (Z129, M0258 S0047)
--   0x236 <dest, slotVar> (ov21 0x021B62C8): the Hidden Power type
--         (0x02018790) if the Pokemon's personal record allows TM10 --
--         item 0x151 -> machine index 9 (arm9 0x0202130C), then that bit of
--         the species / form's compatibility (0x020188AC: fields 5 species
--         and 0x6F form, 0x020188E0) -- else 0xFFFF (Z109, M0218 S014F)
-- The Hidden Power type is BW's order, Fighting 1 .. Dark 16 (no ???). The
-- compatibility bit is the species' `machineBits` (src/import/Gen5Data.lua,
-- TM01..TM95 first, so TM10 is bit 9). INFERRED: a form's own personal
-- record is not looked up (the species' is used).

local M = {}

M.TM10_BIT = 9
M.EV_KEYS = { "hp", "attack", "defense", "speed", "spatk", "spdef" }

local function G4() return require("src.script.Gen4Commands") end

local function mon(ctx, slot)
  local n = math.floor(tonumber(G4().valueOf(ctx, slot)) or 0)
  return (ctx.save and ctx.save.party or {})[n + 1]
end

function M.effortSum(m)
  local evs = m and m.evs or {}
  local sum = 0
  for _, k in ipairs(M.EV_KEYS) do sum = sum + (tonumber(evs[k]) or 0) end
  return sum
end

function M.hiddenPowerType(ivs)
  ivs = ivs or {}
  local function bit(k) return math.floor(tonumber(ivs[k]) or 0) % 2 end
  local n = bit("hp") + 2 * bit("attack") + 4 * bit("defense") + 8 * bit("speed")
            + 16 * bit("spatk") + 32 * bit("spdef")
  return math.floor(n * 15 / 63) + 1
end

-- 0x020188AC: the species' personal compatibility bit
function M.canLearnMachine(data, species, bit)
  local reg = data and data.pokemon
  local def = reg and species and (reg[species] or reg[tostring(species)]
    or (tonumber(species) and reg[("SPECIES_%03d"):format(tonumber(species))]))
  if type(def) ~= "table" or type(def.machineBits) ~= "table" then
    -- (no personal data in this cache: answer as the species list would --
    -- learnable, so the type is shown)
    return def ~= nil or reg == nil
  end
  for _, b in ipairs(def.machineBits) do if b == bit then return true end end
  return false
end

local okCommands, Commands = pcall(require, "src.script.Commands")
if not okCommands then Commands = {} end

function Commands.g5_effort_sum(ctx, dest, slot)
  local m = mon(ctx, slot)
  G4().setVar(ctx.save, dest, m and M.effortSum(m) or 0)
end

function Commands.g5_hidden_power_type(ctx, dest, slot)
  local m = mon(ctx, slot)
  local sp = m and require("src.pokemon.Gen4DayCare").speciesOf(m)
  if not m or m.isEgg or not M.canLearnMachine(ctx.game and ctx.game.data, sp, M.TM10_BIT) then
    G4().setVar(ctx.save, dest, 0xFFFF) return
  end
  G4().setVar(ctx.save, dest, M.hiddenPowerType(m.ivs))
end

function M.install(L)
  local function emit(s, row) s.out[#s.out + 1] = row end
  L.bweffortsum = L.bweffortsum or function(ins, s) emit(s, { "g5_effort_sum", ins.args[1], ins.args[2] }) end
  L.bwhiddenpower = L.bwhiddenpower or function(ins, s) emit(s, { "g5_hidden_power_type", ins.args[1], ins.args[2] }) end
end

return M
