-- Copyright (c) 2026 Roxas2712. See https://github.com/Roxas2712/Gen2Recomped/blob/main/LICENSE-ROXAS2712.md.
-- This process deliberately has no LÖVE stub. Model construction must not
-- silently allocate pictures, animations or a battle screen.
package.path = './?.lua;./?/init.lua;' .. package.path
local T = require('tests.harness')
T.eq(_G.love, nil, 'fresh plain-Lua process has no rendering runtime')
for _, name in ipairs({
  'src.battle.BattleState', 'src.pokemon.Sprites', 'src.pokemon.PicAnim',
  'src.pokemon.MonAnim', 'src.render.Assets',
}) do
  package.preload[name] = function() error('data constructor loaded presentation: ' .. name) end
end
local Battler = require('src.battle.Battler')
local Version = require('src.core.GameVersion')
local initial = Version.get()
local function copy(t)
  if type(t) ~= 'table' then return t end
  local r = {}; for k, v in pairs(t) do r[k] = copy(v) end; return r
end

for _, edition in ipairs(Version.ORDER) do
  Version.set(edition)
  local label = edition .. ': '
  local types, moves = {'NORMAL'}, {{id='QA_MOVE', pp=8}}
  local stats = {hp=40, attack=20, defense=21, speed=22, special=23, spatk=24, spdef=25}
  local def = {name='SPECIES', types=types}
  local data = {pokemon={QA_MON=def}, statuses={PSN={}}, items={QA_BERRY={}},
    constants={gen=Version.generation(), natures={}, badgeBoosts={
      {badge='QA_BADGE', stat='speed', num=2, den=1},
      {badge='QA_MISSING', stat='attack', num=2, den=1},
    }}}
  local mon = {species='QA_MON', nickname='NICK', hp=17, status='PSN', toxic=true,
    stats=stats, moves=moves, item='QA_BERRY'}
  local save = {inventory={QA_BADGE=1, BOULDERBADGE=1}, party={mon}}
  local beforeMon, beforeSave, beforeData = copy(mon), copy(save), copy(data)
  local player = Battler.new(data, mon, true, save)
  local opponent = Battler.new(data, mon, false, save)
  local link = Battler.new(data, mon, true, nil)
  T.eq(player.mon, mon, label .. 'original party member is retained')
  T.eq(player.def, def, label .. 'species registry row is retained')
  T.eq(player.name, 'NICK', label .. 'nickname is displayed')
  T.eq(player.curStats, stats, label .. 'stats are a live native view')
  T.eq(player.curTypes, types, label .. 'types are a live registry view')
  T.eq(player.curMoves, moves, label .. 'PP-bearing move slots retain identity')
  T.eq(player.items, data.items, label .. 'item registry retains identity')
  T.eq(player.statuses, data.statuses, label .. 'status registry retains identity')
  T.eq(player.natures, data.constants.natures, label .. 'nature registry retains identity')
  T.eq(player.badgeBoosts, data.constants.badgeBoosts, label .. 'merged badge rows retain identity')
  T.same(player.badges, {QA_BADGE=true}, label .. 'only merged possessed badges are captured')
  T.eq(opponent.badges, nil, label .. 'opponent does not inherit player badges')
  T.eq(link.badges, nil, label .. 'link construction without save has no badge boosts')
  T.neq(player.stages, opponent.stages, label .. 'each battler owns transient stages')
  T.eq(player.shownHP, 17, label .. 'HUD starts at actual HP')
  T.eq(player.shownStatus, 'PSN', label .. 'HUD starts at actual condition')
  T.eq(player.toxicCounter, nil, label .. 'older host retains native poison defaults')
  for _, battler in ipairs({player, opponent, link}) do
    for _, key in ipairs({'sprite', 'picAnim', 'monAnim'}) do
      T.eq(battler[key], nil, label .. 'data construction has no ' .. key)
    end
  end
  T.same(mon, beforeMon, label .. 'construction cannot change a Pokemon')
  T.same(save, beforeSave, label .. 'construction cannot change a save')
  T.same(data, beforeData, label .. 'construction cannot change registries')
  mon.hp, mon.status = 3, 'SLP'; mon.sleepTurns = 4; mon.nickname = nil
  T.eq(player.shownHP, 17, label .. 'native HUD snapshot waits for refresh')
  T.eq(player.shownStatus, 'PSN', label .. 'native condition snapshot waits for refresh')
  moves[1].pp = 7; T.eq(player.curMoves[1].pp, 7, label .. 'real PP writes remain visible')
  local asleep = Battler.new(data, mon, true, save)
  T.eq(asleep.name, def.name, label .. 'unnamed Pokemon uses species name')
  T.eq(asleep.sleepTurns, 4, label .. 'outside-battle sleep count survives')
  T.eq(asleep.toxicCounter, nil, label .. 'sleep does not acquire a toxic counter')
  T.neq(asleep.badges, player.badges, label .. 'badge snapshots are per battler')
  data.constants.badgeBoosts = nil
  local fallback = Battler.new(data, mon, true, save)
  T.same(fallback.badges, {BOULDERBADGE=true}, label .. 'unmerged badges use actual native Damage defaults')
  T.eq(_G.love, nil, label .. 'construction never installs a fake rendering runtime')
end

Version.set('platinum')
local base = {name='DEOXYS', types={'PSYCHIC'}, baseStats={attack=1}}
local attack = {types={'FIGHTING'}, baseStats={attack=180}}
local data = {constants={gen=4}, pokemon={[386]=base, [496]=attack}}
local mon = {species=386, form=1, hp=1, stats={}, moves={}}
local form = Battler.new(data, mon, false)
T.eq(form.species, 386, 'form construction keeps actual species identity')
T.eq(form.name, 'DEOXYS', 'form construction keeps base display name')
T.eq(form.curTypes, attack.types, 'form construction uses native personal-record types')
T.eq(form.def.baseStats, attack.baseStats, 'form construction uses native personal-record stats')
T.eq(data.pokemon[386], base, 'form view does not replace registry row')
T.same(base.types, {'PSYCHIC'}, 'alternate form does not mutate base types')
Version.set(initial)
T.finish('native battler data without LÖVE or presentation resources')
