-- Copyright (c) 2026 Roxas2712. See https://github.com/Roxas2712/Gen2Recomped/blob/main/LICENSE-ROXAS2712.md.
-- Exercise the actual native constructor and switches, including real sprite
-- selection and animation factories. No replacement art or cloned battle loop.
package.path = './?.lua;./?/init.lua;' .. package.path
local T = require('tests.modkit')
local Version = require('src.core.GameVersion')
local Battler = require('src.battle.Battler')
local Screen = require('src.battle.BattleState')
local Pokemon = require('src.pokemon.Pokemon')
local Save = require('src.core.SaveData')
local Sprites = require('src.pokemon.Sprites')
local PicAnim = require('src.pokemon.PicAnim')
local MonAnim = require('src.pokemon.MonAnim')
local initial = Version.get()
local make, path, pic, anim = Battler.new, Sprites.path, PicAnim.forMon, MonAnim.new
local builds, paths, pics, anims
Battler.new = function(...)
  local b = make(...)
  T.eq(b.sprite, nil, 'shared native factory does not hydrate a sprite')
  T.eq(b.picAnim, nil, 'shared native factory does not hydrate a pic animation')
  T.eq(b.monAnim, nil, 'shared native factory does not hydrate a procedural animation')
  local fields = {}; for key, value in pairs(b) do fields[key] = value end
  builds[#builds+1] = {battler=b, fields=fields}
  return b
end
Sprites.path = function(data, species, side, opts)
  paths[#paths+1] = {species=species, side=side, mon=opts.mon, kind=opts.kind}
  return path(data, species, side, opts)
end
PicAnim.forMon = function(data, mon, side)
  local value = pic(data, mon, side)
  pics[#pics+1] = {mon=mon, side=side, value=value}
  return value
end
MonAnim.new = function(data, species)
  local value = anim(data, species)
  anims[#anims+1] = {species=species, value=value}
  return value
end

for _, edition in ipairs(Version.ORDER) do
  Version.set(edition)
  builds, paths, pics, anims = {}, {}, {}, {}
  local data = T.fixtures.fresh(); data.constants.gen = Version.generation()
  require('src.render.Font').load(data)
  local save = Save.newGame()
  save.party = {Pokemon.new(data, 'FIXMON_A', 25), Pokemon.new(data, 'FIXMON_B', 20)}
  local game = {data=data, save=save, stack={top=function() end}}
  local battle = Screen.newWild(game, 'FIXMON_C', 15)
  T.eq(#builds, 2, edition .. ' real wild constructor uses shared data factory for both sides')
  T.eq(builds[1].battler, battle.player, 'player uses the actual constructed table')
  T.eq(builds[2].battler, battle.enemy, 'enemy uses the actual constructed table')
  T.eq(battle.player.mon, save.party[1], 'native player retains save identity')
  T.eq(#paths, 2, 'one actual battle picture selection per side')
  T.eq(paths[1].side, 'back', 'player keeps native back picture')
  T.eq(paths[2].side, 'front', 'enemy keeps native front picture')
  T.eq(paths[1].mon, battle.player.mon, 'player picture sees actual form/shiny-bearing Pokemon')
  T.eq(paths[2].mon, battle.enemy.mon, 'enemy picture sees actual form/shiny-bearing Pokemon')
  T.eq(paths[1].kind, 'battle', 'actual sprite selector retains battle context')
  T.eq(#pics, 1, 'ordinary player back picture does not acquire a front animation')
  T.eq(pics[1].mon, battle.enemy.mon, 'native picture animation owns actual opponent')
  T.eq(pics[1].value, battle.enemy.picAnim, 'native picture animation result is retained')
  T.eq(#anims, 1, 'only the opponent gets native procedural animation construction')
  T.eq(anims[1].value, battle.enemy.monAnim, 'native procedural animation result is retained')
  for _, row in ipairs(builds) do
    for key, value in pairs(row.fields) do
      T.eq(row.battler[key], value, edition .. ' hydration preserves native field ' .. key)
    end
  end
  local incoming = save.party[2]
  battle:switchPlayerInto(Screen.POS.PLAYER_LEFT, incoming)
  T.eq(#builds, 3, 'actual switch constructs a fresh transient battler')
  T.eq(battle.player, builds[3].battler, 'actual switch uses shared factory result')
  T.eq(battle.player.mon, incoming, 'actual switch retains live bench Pokemon')
  T.eq(paths[3].mon, incoming, 'switched sprite selector receives live bench Pokemon')
  T.eq(paths[3].side, 'back', 'switch retains native player picture direction')
  T.eq(#pics, 1, 'ordinary back-picture switch does not allocate front animation')
  T.eq(#anims, 1, 'player switch does not allocate opponent procedural animation')
end
Battler.new, Sprites.path, PicAnim.forMon, MonAnim.new = make, path, pic, anim
Version.set(initial)
T.finish('shared native battler construction and actual art hydration across editions')
