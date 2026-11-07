-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md).

-- POKERUS IN GEN 4 / GEN 5. The port carried the byte over from save files
-- and did nothing with it: nothing caught it, spread it, cured it or read it.
--
-- READ FROM pokeplatinum src/pokemon.c (HGSS identical); `mon.pokerus` is
-- the cartridge's byte: high nibble = strain, low nibble = days left.
--   Pokemon_ApplyPokerus (after every non-link battle): a u16 random of
--     exactly 0x4000, 0x8000 or 0xC000 (3 in 65536) infects a random party
--     Pokemon that is not an egg and has never had it: a random byte with a
--     non-zero low 3 bits; if any high bits, keep the low 3 only; then
--     byte | byte << 4, & 0xF3, + 1
--   Pokemon_ValidatePokerus (right after): 1 in 3, every infected Pokemon
--     (days left) passes its byte to the neighbour above and below that has
--     never had it (and skips over the one below it just infected)
--   Party_UpdatePokerusStatus (each new day, FieldSystem_HandleDailyEvents):
--     days left -= days passed; past zero, or more than 4 days, it is cured
--     (strain kept, days 0); a byte that would read 0 becomes 0x10
--   the EV doubling (any non-zero byte -- cured counts) lives in
--     src/battle/Gen45Experience.lua
-- Black / White: the same (INFERRED, standard Gen 5 rules).

local M = {}

local function rand16(rng) return (rng or love.math.random)(0, 65535) end
local function isEgg(mon) return mon.isEgg or mon.egg or false end
local function byte(mon) return (tonumber(mon and mon.pokerus) or 0) % 256 end
function M.infected(mon) return byte(mon) % 16 ~= 0 end
function M.cured(mon) local b = byte(mon) return b % 16 == 0 and b >= 16 end
function M.has(mon) return byte(mon) ~= 0 end

-- the byte the strain roll makes from one random byte (or nil to roll again)
function M.strainByte(r)
  if r % 8 == 0 then return nil end
  if r >= 16 then r = r % 8 end
  r = bit.bor(r, bit.lshift(r, 4))
  r = bit.band(r, 0xF3)
  return r + 1
end

-- Pokemon_ApplyPokerus -> the mon infected, or nil
function M.apply(party, rng)
  if type(party) ~= "table" or #party == 0 then return nil end
  local r = rand16(rng)
  if r ~= 0x4000 and r ~= 0x8000 and r ~= 0xC000 then return nil end
  local mon
  for _ = 1, 64 do
    local m = party[rand16(rng) % #party + 1]
    if m and m.species and not isEgg(m) then mon = m break end
  end
  if not mon or M.has(mon) then return nil end
  local b
  repeat b = M.strainByte(rand16(rng) % 256) until b
  mon.pokerus = b
  return mon
end

-- Pokemon_ValidatePokerus
function M.spread(party, rng)
  if type(party) ~= "table" or rand16(rng) % 3 ~= 0 then return 0 end
  local n, i = 0, 1
  while i <= #party do
    local mon = party[i]
    if mon and mon.species and M.infected(mon) then
      local b = byte(mon)
      local up = party[i - 1]
      if up and math.floor(byte(up) / 16) == 0 then up.pokerus = b; n = n + 1 end
      local down = party[i + 1]
      if down and math.floor(byte(down) / 16) == 0 then down.pokerus = b; n = n + 1; i = i + 1 end
    end
    i = i + 1
  end
  return n
end

-- BattleControllerPlayer_EndFight: not after a link battle
function M.afterBattle(save, battle, rng)
  if not (save and save.party) or (battle and battle.link) then return end
  M.apply(save.party, rng)
  M.spread(save.party, rng)
end

-- BattleState:finish, the one exit every battle takes (a demo or tutorial
-- battle never touched the party)
function M.battleFinished(battle)
  local ok, GV = pcall(require, "src.core.GameVersion")
  if not (ok and (GV.isGen4() or GV.isGen5())) then return end
  if not battle or battle.kind == "link" or battle.demo or battle.pokedudeDemo then return end
  M.afterBattle(battle.game and battle.game.save, battle)
end

-- Party_UpdatePokerusStatus
function M.onDays(save, daysPassed)
  daysPassed = math.floor(tonumber(daysPassed) or 0)
  if daysPassed <= 0 or not (save and save.party) then return end
  for _, mon in ipairs(save.party) do
    if mon.species and M.infected(mon) then
      local b = byte(mon)
      if b % 16 < daysPassed or daysPassed > 4 then b = b - b % 16 else b = b - daysPassed end
      if b == 0 then b = 0x10 end
      mon.pokerus = b
    end
  end
end

-- the new-day check, on its own day stamp (Platinum, HGSS and BW alike);
-- the first poll on a save only records the day
function M.poll(save, today)
  if not save then return end
  today = today or require("src.script.Gen4Daily").civilDay()
  local last = tonumber(save.g45PokerusDay)
  save.g45PokerusDay = today
  if last and today > last then M.onDays(save, today - last) end
end

return M
