-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
-- A read-only formatter over the current native text/data owners. Battle
-- placeholder bytes have their own edition-specific namespace, not field IDs.
local Native=require('src.compat.gen1.NativeSession')
local Version=require('src.core.GameVersion')
local Text=require('src.core.game3.rom_text')
local Ids=require('src.compat.gen1.BattleIds')
local Profiles=require('src.import.Gen3BattleTextCatalog')
local M={}
local function key(id)
 if type(id)=='string'then return id end
 local profile=Profiles.profile(Version.get())
 if profile then for name,value in pairs(profile.ids)do if value==id then return name end end end
 error('unknown native battle string: '..tostring(id),3)
end
function M.has(id)
 local ok,label=pcall(key,id);return ok and Text.has(label)or false
end
function M.get(id,fill)
 local game=assert(Native.game(),'no native GBA text session')
 fill=fill or{};assert(type(fill)=='table','native battle text fill must be a table')
 local profile=assert(Profiles.profile(Version.get()),'no native battle text profile')
 local ids=Ids.new(game.data)
 local function named(kind,value)
  if type(value)=='string'then
   local rows=game.data[kind]or(game.data.constants or{})[kind]or{}
   local row=rows[value];return row and row.name or value
  end
  local native=ids:native(kind,value)
  local row=native and(game.data[kind]or(game.data.constants or{})[kind]or{})[native]
  return row and row.name
 end
 local function mon(value)
  if type(value)=='string'then return value end
  if type(value)~='table'then return end
  local who=value.mon or value
  return who.nickname or named('pokemon',who.species)
 end
 local function prefix(value,variant)
  if type(value)~='table'or value.side~='enemy'then return ''end
  local label=fill.trainer and'sText_FoePkmnPrefix'or'sText_WildPkmnPrefix'
  if variant and variant>1 and fill.trainer then label=label..variant end
  if Text.has(label)then return Text.plain(label)end
  -- Other editions use the original public BattleText labels.
  label=fill.trainer and'BattleText_Foe'or'BattleText_Wild'
  if Text.has(label)then return Text.plain(label)end
  error('native battle name prefix is unavailable',3)
 end
 local battler={ATK='atk',DEF='def',EFF='eff',ACTIVE='active',SCR_ACTIVE='scrActive'}
 local direct={B_BUFF1='buff1',B_BUFF2='buff2',B_BUFF3='buff3',
  B_COPY_VAR_1='copyVar1',B_COPY_VAR_2='copyVar2',B_COPY_VAR_3='copyVar3',
  B_TRAINER1_NAME='trainerName',B_TRAINER1_CLASS='trainerClass',
  B_TRAINER1_LOSE_TEXT='trainerLoseText',B_TRAINER1_WIN_TEXT='trainerWinText',
  B_TRAINER2_LOSE_TEXT='trainer2LoseText',B_TRAINER2_WIN_TEXT='trainer2WinText',
  B_PC_CREATOR_NAME='pcCreatorName'}
 local function placeholder(name)
  local value=fill[name];if value~=nil then return tostring(value)end
  local field=direct[name];if field then value=fill[field]end
  if name=='B_PLAYER_NAME'then value=fill.playerName or(game.save and game.save.player or{}).name end
  local role=name:match('^B_(.+)_NAME_WITH_PREFIX$')
  if role and battler[role]then
   local actor=fill[battler[role]];local display=mon(actor)
   if display then value=prefix(actor)..display end
  end
  role=name:match('^B_(.+)_ABILITY$')
  if role and battler[role]then
   local field=battler[role];local actor=fill[field]
   value=named('abilities',fill[field..'Ability']or type(actor)=='table'and actor.ability)
  end
  local category=({B_CURRENT_MOVE='moves',B_LAST_MOVE='moves',B_LAST_ITEM='items',B_LAST_ABILITY='abilities'})[name]
  if category then
   local field=({B_CURRENT_MOVE='move',B_LAST_MOVE='lastMove',B_LAST_ITEM='lastItem',B_LAST_ABILITY='lastAbility'})[name]
   value=named(category,fill[field])
  end
  local side,slot=name:match('^B_(PLAYER)_MON([12])_NAME$')
  if not side then side,slot=name:match('^B_(OPPONENT)_MON([12])_NAME$')end
  if side then
   local actors=fill[side=='PLAYER'and'playerMons'or'enemyMons']
   value=mon(actors and actors[tonumber(slot)]or tonumber(slot)==1 and fill[side=='PLAYER'and'player'or'enemy'])
  end
  assert(value~=nil,'native battle placeholder '..tostring(name)..' is unavailable')
  return tostring(value)
 end
 local out={}
 for _,node in ipairs(Text.ir(key(id)))do
  if node.t=='text'then out[#out+1]=node.s
  elseif node.t=='ph'then out[#out+1]=placeholder(assert(profile.placeholders[node.code],
    'unknown native battle placeholder: '..tostring(node.code)))
  elseif node.t=='tag'then
   local name=node.tag:match('^{(B_[%w_]+)}$')
   out[#out+1]=name and placeholder(name)or node.tag
  elseif node.t=='nl'then out[#out+1]='\n'
  elseif node.t=='scroll'then out[#out+1]='\v'
  elseif node.t=='para'then out[#out+1]='\f'
  elseif node.t=='ext'and node.cmd==12 then
   -- ESCAPE is a literal character, not a formatting-only command.
   out[#out+1]=assert(node.literal,'native escaped text glyph is unavailable')
  end
 end
 return table.concat(out)
end
M.expand=M.get
return M
