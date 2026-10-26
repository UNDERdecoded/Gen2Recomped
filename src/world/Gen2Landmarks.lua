-- Original adapter/selection logic by Roxas2712. See the PR contribution permission in docs/native-gen2-landmarks.md.
-- Constant identities/order only, not cartridge coordinates, names or art.
-- Orders: pret/pokegold and pret/pokecrystal constants/landmark_constants.asm.
local Version=require('src.core.GameVersion')
local M={}
local gold={}
for name in ([[
 SPECIAL NEW_BARK_TOWN ROUTE_29 CHERRYGROVE_CITY ROUTE_30 ROUTE_31
 VIOLET_CITY SPROUT_TOWER ROUTE_32 RUINS_OF_ALPH UNION_CAVE ROUTE_33
 AZALEA_TOWN SLOWPOKE_WELL ILEX_FOREST ROUTE_34 GOLDENROD_CITY RADIO_TOWER
 ROUTE_35 NATIONAL_PARK ROUTE_36 ROUTE_37 ECRUTEAK_CITY TIN_TOWER BURNED_TOWER
 ROUTE_38 ROUTE_39 OLIVINE_CITY LIGHTHOUSE ROUTE_40 WHIRL_ISLANDS ROUTE_41
 CIANWOOD_CITY ROUTE_42 MT_MORTAR MAHOGANY_TOWN ROUTE_43 LAKE_OF_RAGE
 ROUTE_44 ICE_PATH BLACKTHORN_CITY DRAGONS_DEN ROUTE_45 DARK_CAVE ROUTE_46
 SILVER_CAVE PALLET_TOWN ROUTE_1 VIRIDIAN_CITY ROUTE_2 PEWTER_CITY ROUTE_3
 MT_MOON ROUTE_4 CERULEAN_CITY ROUTE_24 ROUTE_25 ROUTE_5 UNDERGROUND_PATH
 ROUTE_6 VERMILION_CITY DIGLETTS_CAVE ROUTE_7 ROUTE_8 ROUTE_9 ROCK_TUNNEL
 ROUTE_10 POWER_PLANT LAVENDER_TOWN LAV_RADIO_TOWER CELADON_CITY SAFFRON_CITY
 ROUTE_11 ROUTE_12 ROUTE_13 ROUTE_14 ROUTE_15 ROUTE_16 ROUTE_17 ROUTE_18
 FUCHSIA_CITY ROUTE_19 ROUTE_20 SEAFOAM_ISLANDS CINNABAR_ISLAND ROUTE_21
 ROUTE_22 VICTORY_ROAD ROUTE_23 INDIGO_PLATEAU ROUTE_26 ROUTE_27 TOHJO_FALLS
 ROUTE_28 FAST_SHIP
]]):gmatch('%S+')do gold[#gold+1]='LANDMARK_'..name end
local function validOrder(source)
 if type(source)~='table' or #source==0 or #source>256 then return nil end
 local result,seen={},{}
 for i=1,#source do
  local id=source[i]
  if type(id)~='string' or id=='' or seen[id]then return nil end
  seen[id]=true;result[i]=id
 end
 for key in pairs(source)do
  if type(key)~='number' or key%1~=0 or key<1 or key>#source then return nil end
 end
 return result
end
function M.order(version,metadata)
 local declared=metadata and (metadata.landmarkOrder or metadata.constants and metadata.constants.landmarkOrder)
 if declared~=nil then
  local order=validOrder(declared)
  if not order then return {},'invalid landmark identity order' end
  return order
 end
 if version~='gold' and version~='silver' and version~='crystal'then return{}end
 local result={};for i,id in ipairs(gold)do result[i]=id end
 if version=='crystal'then table.insert(result,30,'LANDMARK_BATTLE_TOWER')end
 return result
end
function M.town(data)return data and data.field and data.field.townMap end
function M.dataOrder(data)
 local town=M.town(data)
 if town and town.landmarkOrder~=nil then return validOrder(town.landmarkOrder) or{}end
 return M.order(Version.get(),data and data.constants and {landmarkOrder=data.constants.landmarkOrder})
end
function M.index(data,id)
 local town=M.town(data);local rows=town and town.landmarks
 local found
 for key,row in pairs(rows or{})do
  if type(row)=='table' and (row.landmarkId or row.id)==id and tonumber(row.index or key)then
   local n=tonumber(row.index or key)
   if found and found~=n then return nil end
   found=n
  end
 end
 if found then return found,true end
 for i,name in ipairs(M.dataOrder(data))do if name==id then return i-1,false end end
end
function M.kantoStart(data)
 local index,native=M.index(data,'LANDMARK_PALLET_TOWN')
 local town=M.town(data)
 if index and (native or town and town.landmarkOrder~=nil or
     data and data.constants and data.constants.landmarkOrder~=nil)then return index end
 local pallet=data and data.maps and data.maps.PALLET_TOWN
 return tonumber(pallet and pallet.landmark) or index or (Version.get()=='crystal' and 0x2f or 0x2e)
end
return M
