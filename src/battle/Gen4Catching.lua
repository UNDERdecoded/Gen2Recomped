-- SINNOH CATCHES POKEMON WITH ITS OWN SUM, and until now it used Kanto's.
--
-- Platinum's sixteen balls reach the battle as their ITEM NUMBERS (4 is the
-- Poke Ball; Gen 4 items carry no Gen 1 name key), so `BattleState:ballDef`
-- found no record for any of them and every throw in Sinnoh ran
-- Catching's DEFAULT_BALL -- Gen 1's ItemUseBall, a random byte against 255
-- and Kanto's wobble table. A Quick Ball on turn one was a Poke Ball; a Net
-- Ball on a Magikarp was a Poke Ball; and the odds of everything were Red's.
--
-- `BattleScript_CalcCatchShakes` (pokeplatinum src/battle/battle_script.c):
--
--   species = catch rate                          (Safari Ball: times the
--             sSafariCatchRate[stage] fraction -- see Gen4Safari)
--   ball    = 10, or sBasicBallMod for Ultra 20 / Great 15 / Poke 10 /
--             Safari 15, or the special ball's own rule (below)
--   rate    = (species * ball / 10) * (3*maxHP - 2*curHP) / (3*maxHP)
--   asleep or frozen                   -> rate * 2
--   poisoned, burned, paralysed, toxic -> rate * 15 / 10
--   rate >= 255 -> caught outright
--   else rate = 0xFFFF0 / sqrt(sqrt(0xFF0000 / rate)), and four 16-bit rolls
--        must each come in under it; the Master Ball is always four
--
-- The special balls: Net 30 on Water or Bug; Dive 35 on water terrain; Nest
-- max(10, 40 - level) below level 40; Repeat 30 if the species is owned; Timer
-- 10 + turns, capped at 40; Dusk 35 at night (20:00-03:59) or in a cave; Quick
-- 40 before the first turn ends. Luxury, Premier, Heal and Cherish are 10.

local Gen4Catching = {}

Gen4Catching.MASTER, Gen4Catching.ULTRA, Gen4Catching.GREAT = 1, 2, 3
Gen4Catching.POKE, Gen4Catching.SAFARI, Gen4Catching.NET = 4, 5, 6
Gen4Catching.DIVE, Gen4Catching.NEST, Gen4Catching.REPEAT = 7, 8, 9
Gen4Catching.TIMER, Gen4Catching.LUXURY, Gen4Catching.PREMIER = 10, 11, 12
Gen4Catching.DUSK, Gen4Catching.HEAL, Gen4Catching.QUICK = 13, 14, 15
Gen4Catching.CHERISH = 16

local BASIC = { [2] = 20, [3] = 15, [4] = 10, [5] = 15 }

local function isqrt(x)
  if x <= 0 then return 0 end
  local n = math.floor(math.sqrt(x))
  while n * n > x do n = n - 1 end
  while (n + 1) * (n + 1) <= x do n = n + 1 end
  return n
end

local function hasType(ctx, want)
  for _, t in ipairs((ctx.targetDef and ctx.targetDef.types) or {}) do
    if tostring(t):upper() == want then return true end
  end
  return false
end

-- ballMod(ball, ctx) -> the ball's worth in tenths.
function Gen4Catching.ballMod(ball, ctx)
  ball = tonumber(ball)
  if BASIC[ball] then return BASIC[ball] end
  if ball == Gen4Catching.NET then
    return (hasType(ctx, "WATER") or hasType(ctx, "BUG")) and 30 or 10
  elseif ball == Gen4Catching.DIVE then
    return ctx.terrain == "water" and 35 or 10
  elseif ball == Gen4Catching.NEST then
    local level = math.floor(tonumber(ctx.level) or 100)
    if level < 40 then return math.max(10, 40 - level) end
    return 10
  elseif ball == Gen4Catching.REPEAT then
    return ctx.alreadyCaught and 30 or 10
  elseif ball == Gen4Catching.TIMER then
    return math.min(40, 10 + math.floor(tonumber(ctx.turns) or 0))
  elseif ball == Gen4Catching.DUSK then
    local h = tonumber(ctx.hour)
    local night = h and (h >= 20 or h < 4)
    return (night or ctx.terrain == "cave") and 35 or 10
  elseif ball == Gen4Catching.QUICK then
    return (tonumber(ctx.turns) or 0) < 1 and 40 or 10
  end
  return 10
end

local SLEEPY = { SLP = true, FRZ = true, sleep = true, freeze = true, SLEEP = true, FREEZE = true }
local SOUR = { PSN = true, BRN = true, PAR = true, TOX = true, poison = true, burn = true,
               paralysis = true, toxic = true, POISON = true, BURN = true, PARALYSIS = true,
               TOXIC = true }

-- rate(ball, ctx) -> the number the cartridge compares against 255.
function Gen4Catching.rate(ball, ctx)
  local species = math.max(0, math.floor(tonumber(ctx.catchRate) or 0))
  if ctx.safariStage then
    local f = Gen4Catching.SAFARI_STAGES[ctx.safariStage]
    if f then species = math.floor(species * f[1] / f[2]) end
  end
  local maxHP = math.max(1, math.floor(tonumber(ctx.maxHP) or 1))
  local hp = math.max(0, math.floor(tonumber(ctx.hp) or maxHP))
  local rate = math.floor(species * Gen4Catching.ballMod(ball, ctx) / 10)
  rate = math.floor(rate * (maxHP * 3 - hp * 2) / (maxHP * 3))
  local status = ctx.status
  if status and SLEEPY[status] then
    rate = rate * 2
  elseif status and SOUR[status] then
    rate = math.floor(rate * 15 / 10)
  end
  return rate
end

-- sSafariCatchRate, indexed by the battle's safariCatchStage 0..12.
Gen4Catching.SAFARI_STAGES = {
  [0] = { 10, 40 }, { 10, 35 }, { 10, 30 }, { 10, 25 }, { 10, 20 }, { 10, 15 },
  { 10, 10 }, { 15, 10 }, { 20, 10 }, { 25, 10 }, { 30, 10 }, { 35, 10 }, { 40, 10 },
}

-- attempt(ball, ctx, rng) -> caught, shakes (0..3, the port's convention: 3
-- with caught = true is the cartridge's four).
function Gen4Catching.attempt(ball, ctx, rng)
  rng = rng or math.random
  if tonumber(ball) == Gen4Catching.MASTER then return true, 3 end
  local rate = Gen4Catching.rate(ball, ctx)
  if rate >= 255 then return true, 3 end
  if rate <= 0 then return false, 0 end
  local shake = math.floor(0xFFFF0 / math.max(1, isqrt(isqrt(math.floor(0xFF0000 / rate)))))
  for i = 1, 4 do
    if rng(0, 65535) >= shake then return false, math.min(3, i - 1) end
  end
  return true, 3
end

-- The battle's own context for a throw.
function Gen4Catching.context(battle, mon, def, rateOverride)
  local save = battle and battle.game and battle.game.save
  local owned = save and save.pokedex and save.pokedex.owned
  local terrain
  pcall(function()
    terrain = require("src.battle.Gen4Battle").terrainFor(battle and battle.game)
  end)
  return {
    catchRate = rateOverride or (def and def.catchRate),
    maxHP = mon and mon.stats and mon.stats.hp,
    hp = mon and mon.hp,
    status = mon and mon.status,
    level = mon and mon.level,
    targetDef = def,
    turns = battle and battle.turnCount,
    alreadyCaught = (owned and mon and mon.species and owned[mon.species]) and true or false,
    terrain = terrain,
    hour = tonumber(os.date("%H")),
    safariStage = battle and battle.gen4Safari and battle.gen4Safari.catchStage or nil,
  }
end

-- Registered by Catching.registerInto for a Gen 4 dataset: one record per
-- ball item number, each carrying its own `attempt`. Keyed by the number AS A
-- STRING ("4") because registry ids are strings; `BattleState:ballDef` asks
-- for both spellings.
function Gen4Catching.registerInto(registry, owner)
  for id = 1, 16 do
    local key = tostring(id)
    local write = registry:get(key) ~= nil and registry.override or registry.register
    write(registry, key, {
      randMax = 255, hpFactor = 12, wobbleFactor = 150,
      autoCatch = (id == Gen4Catching.MASTER) or nil,
      tossAnim = (id == Gen4Catching.MASTER or id == Gen4Catching.ULTRA)
                 and "ULTRATOSS_ANIM" or "TOSS_ANIM",
      attempt = function(ctx)
        local c = Gen4Catching.context(ctx.battle, ctx.targetMon, ctx.targetDef, ctx.rateOverride)
        return Gen4Catching.attempt(id, c, ctx.rng)
      end,
    }, owner)
  end
end

return Gen4Catching
