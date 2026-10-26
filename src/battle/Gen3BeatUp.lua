-- Gen-3 Beat Up uses party species/level, not the user's battle stats.
local Damage = require("src.battle.Damage")
local HelpingHand = require("src.battle.Gen3HelpingHand")
local B = {}
-- The native side party is shared across both trainers. Keep the engine's
-- owning arrays separate, but retain live slot reads rather than copying
-- their members: a public hit callback may replace an upcoming bench mon.
local function partiesFor(ctx)
  local battle, user = ctx.battle, ctx.user
  if user.isPlayer then
    local first = battle.playerParty or (battle.game and battle.game.save and battle.game.save.party) or {}
    return first, battle.ally and battle.ally.party
  end
  return battle.enemyParty or { user.mon }, battle.enemyPartyB
end
local function member(ctx, index)
  if index <= ctx._gen3BeatUpSplit then
    return ctx._gen3BeatUpParty[index]
  end
  local second = ctx._gen3BeatUpSecondParty
  return second and second[index - ctx._gen3BeatUpSplit]
end
local function userIndex(ctx, count)
  for i = 1, count do
    if member(ctx, i) == ctx.user.mon then
      return i
    end
  end
  return ctx.user.partyIndex
end
local function eligible(ctx, mon, index)
  local hp, status = mon.hp, mon.status
  if index == ctx._gen3BeatUpUserIndex then
    hp, status = ctx.user.mon.hp, ctx.user.mon.status
  end
  return (tonumber(hp) or 0) > 0
    and mon.species ~= nil
    and mon.species ~= 0
    and not mon.isEgg
    and (status == nil or status == 0)
end
local function base(ctx, species, stat)
  local def = ctx.data and ctx.data.pokemon and ctx.data.pokemon[species]
  return def and def.baseStats and def.baseStats[stat] or 50
end
function B.prepare(ctx)
  local first, second = partiesFor(ctx)
  ctx._gen3BeatUpParty, ctx._gen3BeatUpSecondParty = first, second
  ctx._gen3BeatUpSplit, ctx._gen3BeatUpCursor = #first, 0
  local count = #first + (second and #second or 0)
  ctx._gen3BeatUpUserIndex = userIndex(ctx, count)
  for i = 1, count do
    local mon = member(ctx, i)
    if not mon then
      break
    end
    if eligible(ctx, mon, i) then
      return true
    end
  end
  return false
end
function B.nextDamage(ctx)
  while true do
    local index = ctx._gen3BeatUpCursor + 1
    ctx._gen3BeatUpCursor = index
    local mon = member(ctx, index)
    if not mon then
      return nil
    end
    if eligible(ctx, mon, index) then
      local amount = Damage.base(
        tonumber(mon.level) or 1,
        ctx.move.power or 10,
        base(ctx, mon.species, "attack"),
        base(ctx, ctx.target.species or ctx.target.mon.species, "defense")
      ) + 2
      amount = HelpingHand.damage(ctx.user, amount)
      local def = ctx.data.pokemon[mon.species]
      local name = mon.nickname or (def and def.name) or tostring(mon.species)
      if not ctx.user.isPlayer then
        name = "Enemy " .. name
      end
      ctx.say(ctx.battle:romText("STRINGID_PKMNATTACK", "%s's attack!", name))
      local critical = require("src.battle.Gen3Critical").roll(
        ctx.battle,
        Damage.critRoll,
        ctx.ruleset,
        ctx.user,
        ctx.move.id,
        ctx.rng,
        false,
        ctx.data
      )
      if critical then
        amount = amount * 2
      end
      amount = math.max(1, math.floor(amount * ctx.rng(85, 100) / 100))
      return amount, { crit = critical, typeMult = 10, eventTypeMult = 10, gbaBeatUp = true }
    end
  end
end
return B
