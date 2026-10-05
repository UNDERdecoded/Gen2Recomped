-- Platinum's named archive forms use the ROM's zero-based MON_DATA_FORM order.
local Forms = {}
local order = {}
for _, row in ipairs(require('src.import.Gen4Otherpoke').FORMS) do
  if row.species > 0 then
    order[row.species] = order[row.species] or {}
    table.insert(order[row.species], row.form)
  end
end
local tracked = {[201]=true,[386]=true,[412]=true,[413]=true,[422]=true,
                 [423]=true,[479]=true,[487]=true,[492]=true}
function Forms.species(species)
  return tonumber(species) or tonumber(tostring(species):match('^SPECIES_(%d+)$'))
end
function Forms.key(def, mon)
  if not (def and def.forms and def.forms.base and mon) then return nil end
  local species = Forms.species(mon.species) or def.forms.base.species
  local value = mon.form
  if value == nil then value = mon.gen4Form end
  if value == nil then value = 0 end
  local key
  if type(value)=='string' and def.forms[value] then key=value
  else
    local index=tonumber(value)
    if index and index>=0 and index%1==0 then
      key=(order[species] or {})[index+1]
    end
  end
  -- Bad imported form values safely use the base picture.
  if key and def.forms[key] then return key,true end
  return 'base',false
end
-- Pokemon_GetFormNarcIndex: only these forms have distinct personal records.
local personal = {
  [386]={496,497,498}, [413]={499,500}, [487]={501},
  [492]={502}, [479]={503,504,505,506,507},
}
function Forms.personalIndex(species, value)
  local id=Forms.species(species)
  local index=tonumber(value)
  if not index and type(value)=='string' then
    for i,key in ipairs(order[id] or {}) do
      if key==value then index=i-1; break end
    end
  end
  return index and (personal[id] or {})[index] or id
end
-- Pokemon_GetForm: the zero-based MON_DATA_FORM, whichever way it is stored.
function Forms.index(mon)
  local value = mon and (mon.form == nil and mon.gen4Form or mon.form)
  if value == nil then return 0 end
  if tonumber(value) then return math.floor(tonumber(value)) end
  local id = Forms.species(mon.species)
  for i, key in ipairs(order[id] or {}) do
    if key == value then return i - 1 end
  end
  return 0
end
function Forms.definition(data, mon)
  local registry=data and data.pokemon or {}
  local id=mon and Forms.species(mon.species)
  local base=mon and (registry[mon.species] or registry[id])
  if not base or (data.constants or {}).gen~=4 then return base end
  local index=Forms.personalIndex(id,mon.form or mon.gen4Form or 0)
  local alternate=registry[index]
  if index==id or not alternate then return base end
  -- Keep identity and presentation on the base species, while the ROM's
  -- personal/learnset row supplies form-dependent battle properties.
  local view={}
  for key,value in pairs(base) do view[key]=value end
  for _,key in ipairs({'baseStats','types','typeIds','abilities','abilityIds',
      'evYield','evYields','heldItems','tmLearnset','tmhm','learnset','level1Moves'}) do
    if alternate[key]~=nil then view[key]=alternate[key] end
  end
  return view
end
function Forms.record(game, species, mon)
  if not (game and game.data and (game.data.constants or {}).gen==4 and mon) then return end
  local id=Forms.species(species)
  if not tracked[id] or require('src.pokemon.Party').isEgg(mon) then return end
  local def=(game.data.pokemon or {})[species] or (game.data.pokemon or {})[id]
  local key,valid=Forms.key(def,mon)
  if not key or not valid then return end
  local dex=game.save and game.save.pokedex
  if not dex then return end
  dex.gen4FormsSeen=dex.gen4FormsSeen or {}
  local list=dex.gen4FormsSeen[id] or {}
  dex.gen4FormsSeen[id]=list
  for _,seen in ipairs(list) do if seen==key then return end end
  list[#list+1]=key
end
-- SET A FORM AND RECALCULATE, as `Pokemon_CalcLevelAndStats` does after every
-- form change on the cartridge. The stats come from the form's own personal
-- row (`definition`), and so does the ability -- `abilitySlot` indexes the
-- form's ability list. HP follows `Pokemon_CalcStats`: it moves by the change
-- in max HP, a fainted mon stays fainted, and a one-HP species stays at one.
function Forms.setForm(data, mon, form)
  if type(mon) ~= 'table' then return false end
  mon.form = form
  mon.gen4Form = nil
  local okS, Stats = pcall(require, 'src.pokemon.Stats')
  local def = Forms.definition(data, mon)
  if not (okS and def and def.baseStats) then return true end
  local oldMax = mon.stats and mon.stats.hp or 0
  local okC, stats = pcall(Stats.calc, def, mon.level or 1, mon.ivs, nil, mon.evs, mon.nature)
  if not (okC and type(stats) == 'table') then return true end
  mon.stats = stats
  local hp = tonumber(mon.hp) or 0
  if hp ~= 0 or oldMax == 0 then
    if stats.hp == 1 then hp = 1
    elseif hp == 0 then hp = stats.hp
    else hp = hp + (stats.hp - oldMax) end
  end
  mon.hp = math.max(0, math.min(hp, stats.hp))
  return true
end

-- GIRATINA FOLLOWS ITS HELD ITEM: Origin while holding the Griseous Orb,
-- Altered otherwise (`BoxPokemon_SetGiratinaForm`). The cartridge re-applies
-- this whenever a held item can have changed -- giving or taking one in the
-- party menu, the PC, after a battle -- and the port applied it nowhere, so an
-- Orb did nothing at all. Returns the form set, or nil for any other species.
local GIRATINA, GRISEOUS_ORB = 487, 112
local function itemNumber(id)
  if type(id) == 'number' then return id end
  return tonumber(tostring(id or ''):match('(%d+)$'))
end
function Forms.giratinaByHeldItem(data, mon)
  if not (mon and Forms.species(mon.species) == GIRATINA) then return nil end
  if require('src.pokemon.Party').isEgg(mon) then return nil end
  local form = itemNumber(mon.item) == GRISEOUS_ORB and 1 or 0
  if (tonumber(mon.form) or 0) ~= form then Forms.setForm(data, mon, form) end
  return form
end

function Forms.seen(dex, species)
  return ((dex and dex.gen4FormsSeen) or {})[Forms.species(species)] or {}
end
return Forms
