-- Keep Platinum origin fields when Pokemon are received or hatch.
local Origin={}

-- PLATINUM'S MET LOCATION IS THE MAP'S LABEL. The cartridge stamps a caught,
-- given or hatched Pokemon with MapHeader_GetMapLabelTextID of the map it
-- happens on (egg_hatch.c, field_battle_data_transfer.c's mapLabelTextID):
-- an index into the place-name bank 433, the number an NDS save carries and
-- the Hall of Fame and the summary print by name. The callers hand in
-- BattleState.metHere, which is a Gen 3 region-map section and nil on every
-- Gen 4 map -- so every Platinum Pokemon was met "nowhere": the Hall of Fame
-- printed "Met at ." and the summary left the line out. The label comes
-- from the area popup's row for the map's header (Gen4AreaPopup), which is
-- the header's own labelText. HeartGold / SoulSilver name their places out
-- of another bank, so they keep what they had.
Origin.PLACE_BANK=433
local function platinumFamily(data)
  return data and data.gen4_area_popup~=nil
    and not (data.gen4_version and data.gen4_version.family=='hgss')
end
function Origin.hereLabel(game)
  local data,save=game and game.data,game and game.save
  if not platinumFamily(data) then return nil end
  -- the map the player is ON: save.player.map is only written by a save
  -- (OverworldState:captureSave), so it still names wherever the last one was
  local ow=game.overworld
  local here=(ow and ow.map and ow.map.id) or (save and save.player and save.player.map)
  local def=here and (data.maps or {})[here]
  local row=def and (data.gen4_area_popup.headers or {})[tonumber(def.header) or -1]
  return row and tonumber(row.text) or nil
end
-- A numeric met location's name (bank 433), or nil
function Origin.placeName(data,location)
  if type(location)~='number' or not platinumFamily(data) then return nil end
  local name=(data.text or {})[('TEXT_B%04d_%05d'):format(Origin.PLACE_BANK,location)]
  if type(name)~='string' then return nil end
  return (name:gsub('[\n\r\f\v]',' '))
end

function Origin.stamp(game,mon,kind,location,today)
  if not (game and game.data and (game.data.constants or {}).gen==4 and mon) then return end
  today=today or os.date('*t')
  local date={year=today.year,month=today.month,day=today.day}
  if kind~='egg' and location==nil then location=Origin.hereLabel(game) end
  if kind=='egg' then
    mon.eggDate=mon.eggDate or date
    mon.eggLocation=mon.eggLocation or location
  elseif kind=='hatch' then
    mon.metDate=date
    mon.metLocation=location
    mon.hatched=true
  else
    mon.metDate=mon.metDate or date
    mon.metLocation=mon.metLocation or location
  end
end
return Origin
