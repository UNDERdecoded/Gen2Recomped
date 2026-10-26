package.path = "./?.lua;./?/init.lua;" .. package.path
local T, V = require("tests.modkit"), require("src.core.GameVersion")
local F = dofile("tests/pokemon_rolls/fixture.lua")
local P, R, Copy =
  require("src.pokemon.Pokemon"), require("src.mods.Runtime"), require("src.mods.Merge").deepCopy
local old = V.get()
for _, version in ipairs({ "gold", "firered", "emerald" }) do
  for _, mode in ipairs({ { 1, "native" }, { 2, "native" }, { 2, "unified" }, { 3, "unified" } }) do
    local f = F.new(".", "gen2", version, mode[1], mode[2], "delegate")
    local gen = f.gen
    T.eq(f.e.api:supports("hooks", "shiny.roll"), true, "native shiny capability")
    T.eq(f.e.api:supports("hooks", "gender.roll"), true, "native gender capability")
    local mon = f.make(false)
    local genes = { dvs = Copy(mon.dvs), ivs = Copy(mon.ivs), pid = mon.personality, stats = Copy(mon.stats) }
    f.e.mode = "force"
    if gen == 2 then
      P.syncIdentity(f.data, mon)
    end
    T.eq(f.shiny(mon), true, "actual native identity read follows public hook")
    T.eq(f.gender(mon, true), "female", "actual native gender predicate follows public hook")
    T.same(
      { dvs = mon.dvs, ivs = mon.ivs, pid = mon.personality, stats = mon.stats },
      genes,
      "pure steering preserves stats and genetic values"
    )
    local cached = mon.gender
    f.e.mode = "suppress"
    if gen == 3 then
      T.eq(P.genderOf(f.data, mon), cached, "GBA native display retains constructor gender cache")
      T.eq(f.gender(mon, true), "male", "GBA predicate remains a separate live query")
    else
      P.syncIdentity(f.data, mon)
      T.eq(mon.gender, "male", "Gen-2 summary refresh updates gender")
      T.eq(P.isShiny(mon), true, "Gen-2 true shiny remains authoritative at refresh")
    end
    local calls = f.e.calls["shiny.roll"] or 0
    local forced = f.make(false, true)
    T.eq(f.shiny(forced), true, "explicit forced shiny wins over suppressing hook")
    T.eq(f.e.calls["shiny.roll"] or 0, calls, "forced path bypasses shiny callback")
    f.e.stopShiny()
    f.e.stopGender()
    local counts = Copy(f.e.calls)
    if gen == 2 then
      P.syncIdentity(f.data, mon)
    end
    f.shiny(mon)
    f.gender(mon, true)
    T.same(f.e.calls, counts, "retired callbacks stop real producer dispatch")
    f.close()
  end
end
for _, format in ipairs({ { 2, "unified" }, { 3, "unified" } }) do
  local f = F.new(".", "gen2", "gold", format[1], format[2], "delegate")
  local def = f.data.pokemon.SPECIES_004
  local ratio = def.genderRatio
  local captured, nextSaved
  local stop = f.e.api.hooks:wrap("gender.roll", function(next, ctx)
    captured, nextSaved = ctx, next
    ctx.dvs.attack = 0
    ctx.def.genderRatio = 254
    error("intentional pre-next identity transaction failure")
  end, 100)
  local mon = f.make(false)
  T.eq(mon.dvs.attack, 15, "failed unified callback cannot change saved DVs")
  T.eq(def.genderRatio, ratio, "failed unified callback cannot change definition threshold")
  T.eq(mon.gender, "male", "failed unified callback delegates ordinary gender")
  stop()
  captured.def.genderRatio = 0
  captured.dvs.attack = 0
  T.eq(def.genderRatio, ratio, "retained detached context cannot edit engine data later")
  T.eq(mon.dvs.attack, 15, "retained detached DVs cannot edit created mon later")
  T.raises(function()
    nextSaved()
  end, "next is only valid", "late downstream call rejected")
  local stopBad = f.e.api.hooks:wrap("gender.roll", function(next, ctx)
    ctx.def.genderRatio = 256
    return next(ctx)
  end, 100)
  f.gender(mon, true)
  T.eq(def.genderRatio, ratio, "invalid definition threshold rolls back before delegation")
  stopBad()
  f.close()
end
-- A true cartridge-forced wild encounter must skip the birth hook, too.
do
  local f = F.new(".", "gen2", "gold", 3, "unified", "suppress")
  f.game.save.party = { f.make(false) }
  local before = f.e.calls["shiny.roll"] or 0
  local battle = require("src.battle.BattleState").newWild(f.game, "SPECIES_004", 5, { shiny = true })
  T.eq(P.isShiny(battle.enemy.mon), true, "native forced-wild path retains shininess")
  T.eq(f.e.calls["shiny.roll"] or 0, before, "native forced-wild birth bypasses shiny hook")
  f.close()
end
for _, version in ipairs({ "red", "platinum", "black" }) do
  local f = F.new(".", "gen2", version, 3, "unified", "delegate")
  T.eq(f.e.api:supports("hooks", "shiny.roll"), false, "unsupported shiny capability is honest")
  T.eq(f.e.api:supports("hooks", "gender.roll"), false, "unsupported gender capability is honest")
  f.close()
end
V.set(old)
T.finish("identity ownership, cached/native queries, forced wild and rollback")
