-- RUN MODES: the per-save challenge settings chosen at NEW GAME.
--
--   save.runModes = {
--     v = 1,
--     nuzlocke = bool,        -- rules live in the NUZLOCKE mod (mods/NUZLOCKE)
--     soulLink = bool,        -- needs nuzlocke; paired with a partner online
--     randomWild = bool,      -- wild encounters randomized (src/runmodes/Randomizer.lua)
--     randomStarters = bool,  -- starters randomized
--     seed = int,             -- rolled once at NEW GAME; every random pick hashes it
--     -- nuzlocke bookkeeping (written by the mod, read by the engine):
--     areas = { [areaKey] = { species=, state="caught"|"missed"|"open", tag= } },
--     graveyard = { mon, ... },  -- dead mons, moved out of the party, never deleted
--     runOver = bool, runOverAt = os.time(), rulesOff = bool,
--     soul = { partner=, pairs = { [areaKey] = {...} }, ... },
--   }
--
-- A save without the field -- every save made before this existed -- reads
-- as every mode OFF through RunModes.get, which never writes.  Nothing here
-- deletes or wipes a save: the most a mode ever does is move a dead mon to
-- the graveyard list of THIS save.
--
-- Engine call sites (encounters, starters, link/trade/GTS filters) ask this
-- module; each costs one table read when the save has no runModes.

local RunModes = {}

RunModes.VERSION = 1
RunModes.DEAD = "nuzDead"   -- the flag a dead mon carries (party, link copies)

local OFF = setmetatable({}, { __newindex = function() error("RunModes.OFF is read-only", 2) end })
RunModes.OFF = OFF

local KEYS = { "nuzlocke", "soulLink", "randomWild", "randomStarters" }
RunModes.KEYS = KEYS

local function saveOf(x)
  if type(x) ~= "table" then return nil end
  -- a Game (or anything carrying one): its save, not itself
  if type(x.save) == "table" and x.runModes == nil and x.party == nil then return x.save end
  return x
end

-- the run modes of a save (or Game); OFF (empty, read-only) when none
function RunModes.get(x)
  local save = saveOf(x)
  local rm = save and save.runModes
  if type(rm) ~= "table" then return OFF end
  return rm
end

function RunModes.on(x, key)
  local rm = RunModes.get(x)
  if rm.rulesOff and (key == "nuzlocke" or key == "soulLink") then return false end
  return rm[key] == true
end

function RunModes.any(x)
  local rm = RunModes.get(x)
  for _, k in ipairs(KEYS) do if rm[k] == true then return true end end
  if type(rm.random) == "table" and next(rm.random) ~= nil then return true end
  return false
end

-- a Nuzlocke (or Soul Link) save whose rules are live
function RunModes.nuzlocke(x) return RunModes.on(x, "nuzlocke") end
function RunModes.soulLink(x) return RunModes.on(x, "nuzlocke") and RunModes.on(x, "soulLink") end

local function rollSeed()
  local t = os.time() or 0
  local c = math.floor((os.clock() or 0) * 1000000)
  local r = math.random(0, 0x7fffffff)
  return (t * 2654435761 + c * 40503 + r) % 0x7fffffff
end
RunModes._rollSeed = rollSeed

-- write the NEW GAME choice into a fresh save.  `choice` keys: KEYS + seed.
-- Soul Link implies Nuzlocke.  All-off writes nothing, so a vanilla new game
-- saves exactly what it saved before.
function RunModes.apply(save, choice)
  if type(save) ~= "table" or type(choice) ~= "table" then return save end
  local rm = { v = RunModes.VERSION }
  local any = false
  for _, k in ipairs(KEYS) do
    if choice[k] == true then rm[k] = true; any = true end
  end
  if rm.soulLink then rm.nuzlocke = true end
  -- the full randomizer's options (src/runmodes/RandomOptions.lua)
  if type(choice.random) == "table" then
    for k, v in pairs(choice.random) do
      if v ~= false and v ~= nil then rm.random = rm.random or {}; rm.random[k] = v; any = true end
    end
  end
  if not any then save.runModes = nil; return save end
  rm.seed = tonumber(choice.seed) or rollSeed()
  rm.seed = math.floor(rm.seed) % 0x7fffffff
  rm.startedAt = os.time and os.time() or nil
  if rm.nuzlocke then
    rm.areas = {}
    rm.graveyard = {}
  end
  if rm.soulLink then
    rm.soul = { pairs = {}, partner = choice.partner, code = choice.soulCode }
  end
  save.runModes = rm
  return save
end

-- options-menu toggles for the randomizer after NEW GAME.  Nuzlocke/Soul Link
-- are chosen once and never switched on later (the encounter record would be
-- meaningless); they can be switched OFF only through the run-over screen.
function RunModes.setRandom(save, key, value)
  if key ~= "randomWild" and key ~= "randomStarters" then return false end
  if type(save) ~= "table" then return false end
  local rm = save.runModes
  if type(rm) ~= "table" then
    if not value then return true end
    rm = { v = RunModes.VERSION, seed = rollSeed() }
    save.runModes = rm
  end
  rm[key] = value and true or nil
  if not rm.seed then rm.seed = rollSeed() end
  return true
end

-- ---------------------------------------------------------------- hashing --
-- 31-bit FNV-1a over the seed and any number of parts.  Pure Lua 5.1 math
-- (LuaJIT), no bit library needed: the multiply is split so it stays exact
-- in a double.
local function mulmod(a, b, m)
  local hi = math.floor(b / 65536)
  local lo = b % 65536
  return ((a * hi % m) * 65536 + a * lo) % m
end

function RunModes.hash(seed, ...)
  local M = 2147483647
  local h = (tonumber(seed) or 0) % M
  h = (h + 2166136261) % M
  local n = select("#", ...)
  for i = 1, n do
    local s = tostring((select(i, ...)))
    for j = 1, #s do
      h = (h + s:byte(j)) % M
      h = mulmod(h, 16777619, M)
    end
    h = mulmod((h + 0x9e37) % M, 16777619, M)
  end
  return h
end

-- ----------------------------------------------------------- dead / usable --
function RunModes.isDead(mon)
  return type(mon) == "table" and mon[RunModes.DEAD] == true
end

-- may this mon be used (link battle, trade, GTS)?  false + a reason
function RunModes.usable(mon, save)
  if type(mon) ~= "table" then return false, "none" end
  if mon[RunModes.DEAD] == true then return false, "dead" end
  return true
end

-- copy of a party list without dead mons (link parties)
function RunModes.livingParty(list)
  if type(list) ~= "table" then return list end
  local anyDead = false
  for _, mon in ipairs(list) do if RunModes.isDead(mon) then anyDead = true break end end
  if not anyDead then return list end
  local out = {}
  for _, mon in ipairs(list) do if not RunModes.isDead(mon) then out[#out + 1] = mon end end
  return out
end

-- soul-linked mons stay with their partner (no trades / GTS)
function RunModes.soulBound(mon)
  return type(mon) == "table" and mon.soulPair ~= nil
end

-- the reason a mon cannot leave this save by trade/GTS, or nil
function RunModes.tradeBlock(mon, save)
  if RunModes.isDead(mon) then return "dead" end
  if RunModes.soulBound(mon) and (save == nil or RunModes.soulLink(save)) then return "soul" end
  return nil
end

RunModes.BLOCK_TEXT = {
  dead = "That POKéMON has fainted for good. (NUZLOCKE)",
  soul = "A SOUL LINK POKéMON stays with its partner.",
}

-- what the link hello carries: who you are linking with
function RunModes.summary(x)
  local rm = RunModes.get(x)
  if rm == OFF then return nil end
  local s = {}
  for _, k in ipairs(KEYS) do if rm[k] then s[k] = true end end
  if rm.rulesOff then s.rulesOff = true end
  if rm.runOver then s.runOver = true end
  if type(rm.random) == "table" and next(rm.random) ~= nil then s.randomizer = true end
  return next(s) and s or nil
end

function RunModes.describe(x)
  local rm = RunModes.get(x)
  local parts = {}
  if rm.soulLink then parts[#parts + 1] = "SOUL LINK"
  elseif rm.nuzlocke then parts[#parts + 1] = "NUZLOCKE" end
  if rm.randomWild then parts[#parts + 1] = "RANDOM WILD" end
  if rm.randomStarters then parts[#parts + 1] = "RANDOM STARTERS" end
  if type(rm.random) == "table" and next(rm.random) ~= nil then
    local n = 0
    for _ in pairs(rm.random) do n = n + 1 end
    parts[#parts + 1] = ("RANDOMIZER (%d)"):format(n)
  end
  if rm.rulesOff then parts[#parts + 1] = "(RULES OFF)" end
  return #parts > 0 and table.concat(parts, " + ") or "NORMAL"
end

-- the Nuzlocke rules provider: the NUZLOCKE mod registers itself here when
-- it loads.  Without it the NEW GAME screen greys the Nuzlocke rows out,
-- and a Nuzlocke save still loads (its rules are simply not enforced and
-- the engine-side filters -- dead mons stay out of link/trade/GTS -- hold).
RunModes.provider = nil
function RunModes.registerProvider(p) RunModes.provider = p end

-- the NEW GAME choice waiting to be written into the save SaveData.newGame
-- is about to build (RunSetup sets it; the save.new_game seam consumes it)
RunModes.pending = nil

function RunModes.setPending(choice) RunModes.pending = choice end

function RunModes.consumePending(save)
  local choice = RunModes.pending
  RunModes.pending = nil
  if choice then RunModes.apply(save, choice) end
  return save
end

return RunModes
