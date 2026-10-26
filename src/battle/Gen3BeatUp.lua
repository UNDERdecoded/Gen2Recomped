-- Gen-3 Beat Up uses party species/level, not the user's battle stats.
local Damage = require("src.battle.Damage")
local HelpingHand = require("src.battle.Gen3HelpingHand")
local B = {}
local function partyFor(ctx)
  local battle, user = ctx.battle, ctx.user
  if user.isPlayer then
    if battle.playerParty then
      return battle.playerParty
    end
    if battle.ally and user.position == 2 then
      return battle.ally.party or {}
    end
    return battle.game and battle.game.save and battle.game.save.party or {}
  end
  if user.position == 3 and battle.enemyPartyB then
    return battle.enemyPartyB
  end
  return battle.enemyParty or { user.mon }
end
local function userIndex(ctx, party)
  for i, mon in ipairs(party) do
    if mon == ctx.user.mon then
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
  local party = partyFor(ctx)
  ctx._gen3BeatUpParty, ctx._gen3BeatUpCursor = party, 0
  ctx._gen3BeatUpUserIndex = userIndex(ctx, party)
  for i, mon in ipairs(party) do
    if eligible(ctx, mon, i) then
      return true
    end
  end
  return false
end
function B.nextDamage(ctx)
  local party = ctx._gen3BeatUpParty
  while true do
    local index = ctx._gen3BeatUpCursor + 1
    ctx._gen3BeatUpCursor = index
    local mon = party[index]
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
      local critical = Damage.critRoll(ctx.ruleset, ctx.user, ctx.move.id, ctx.rng, false, ctx.data)
      if critical then
        amount = amount * 2
      end
      amount = math.max(1, math.floor(amount * ctx.rng(85, 100) / 100))
      return amount, { crit = critical, typeMult = 10, eventTypeMult = 10, gbaBeatUp = true }
    end
  end
end
return B
