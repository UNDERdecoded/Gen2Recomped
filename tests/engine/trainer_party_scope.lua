package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.modkit")
local Fixture = dofile("tests/trainer_preparation/fixture.lua")
local Version = require("src.core.GameVersion")
local Battle = require("src.battle.BattleState")
local Scope = require("src.battle.PlayerPartyScope")
local Runtime = require("src.mods.Runtime")
local originalVersion = Version.get()
for _, version in ipairs(Version.ORDER) do
  local f = Fixture.new(".", "gen2", version, 3, "unified")
  local game = f.game
  local original, members = game.save.party, { game.save.party[1], game.save.party[2], game.save.party[3] }
  f.start()
  f.exports.continue({ playerPartyIndices = { 3, 2 } })
  local b = f.battle()
  T.eq(b.game, game, "battle keeps original Game")
  T.eq(b:playerPartyView()[1], members[3], "scope holds original first reference")
  T.eq(b:benchFor(true)[2], members[2], "bench only contains scope")
  T.eq(#b:benchFor(true), 2, "excluded mon absent from switch eligibility")
  b.double = true
  b:sendOutSecondPair()
  T.eq(b:battlerAt(Battle.POS.PLAYER_RIGHT).mon, members[2], "double partner uses scoped eligible mon")
  local id = require("src.battle.Gen4Battle").partyScreenId(b) or "PartyMenu"
  local menu = b:buildScreen(id, { battle = b, onSwitch = function() end })
  local party = type(menu.party) == "function" and menu:party() or menu.party
  T.eq(party, b.playerParty, "actual native party menu uses scope")
  T.eq(#party, 2, "native menu cannot select excluded mon")
  -- Native EXP eligibility ignores an excluded mon even if old participant
  -- bookkeeping contains it. EXP.ALL cannot pay the excluded bench either.
  b.queue = {}
  b.participants = { [members[1]] = true, [members[2]] = true, [members[3]] = true }
  game.save.inventory.EXP_ALL = 1
  local excludedExp = members[1].exp
  local seen
  local off = f.result.loader.hooks:wrap("battle.exp_award", function(next, ctx)
    seen = ctx
    return next(ctx)
  end)
  b:awardExp(b.enemy)
  T.eq(seen.participants, 2, "native EXP counts selected participants")
  T.eq(#seen.alive, 2, "native EXP contains selected living mons")
  T.eq(members[1].exp, excludedExp, "excluded mon receives no EXP")
  off()
  members[2].hp, members[3].hp = 0, 0
  T.check(members[1].hp > 0, "excluded bench stays healthy")
  b.result = nil
  b:playerMonFainted()
  T.eq(b.result, "lose", "scope exhaustion loses despite healthy excluded bench")
  T.eq(game.save.party, original, "native loss never swaps save party")
  T.same(game.save.party, members, "native loss never reorders save party")
  for _, invalid in ipairs({
    {},
    { 1, 1 },
    { 0 },
    { 4 },
    { 1.5 },
    { [1] = 1, [3] = 2 },
    { 1, unexpected = true },
    "bad",
  }) do
    local selected, indices = Scope.select(game, invalid)
    T.eq(selected, nil, "invalid scope falls back to full party")
    T.eq(indices, nil, "invalid scope keeps no remap")
  end
  f.close()
end
Version.set(originalVersion)
T.finish("trainer battle-local player party scope")
