package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.modkit")
local Data = require("src.core.Data")
local Names = require("src.core.Gen2TilesetNames")
local Version = require("src.core.GameVersion")
local original = Version.get()
for native, public in pairs({
  TilesetPlayersHouse="TILESET_PLAYERS_HOUSE", TilesetPlayersRoom="TILESET_PLAYERS_ROOM",
  TilesetPokecenter="TILESET_POKECENTER", TilesetPokeComCenter="TILESET_POKECOM_CENTER",
  TilesetMart="TILESET_MART", TilesetJohtoModern="TILESET_JOHTO_MODERN",
  TilesetHoOhWordRoom="TILESET_HO_OH_WORD_ROOM", TilesetRuinsOfAlph="TILESET_RUINS_OF_ALPH",
}) do T.eq(Names.constant(native),public,"named ROM family spelling") end
for _, id in ipairs({"HOUSE","OVERWORLD","Tileset0","Tileset03","TILESET_MART","TilesetBad/path"}) do
  T.eq(Names.constant(id),nil,"no inferred family for "..id)
end
T.eq(Names.constant(false),nil,"malformed name unavailable")
for _,version in ipairs(Version.ORDER) do
  Version.set(version)
  local native={id="TilesetPlayersHouse",image="real.png",collision={0,0x18},blocks={{1}}}
  local other={id="authored"}
  local data={tilesets={TilesetPlayersHouse=native,TilesetMart=other,TILESET_MART={id="explicit"}},
    maps={ROOM={id="PLAYERS_HOUSE1_F",tileset="TilesetPlayersHouse",environment=3},
          CUSTOM={tileset="CUSTOM"},CONFLICT={tileset="TilesetMart"},PUBLIC={tileset="TILESET_MART"}}}
  local result=Data.publishGen2TilesetNames(data)
  if Version.isGen2() then
    T.eq(result,true,version.." publishes native names")
    T.eq(data.tilesets.TILESET_PLAYERS_HOUSE,native,"public name owns the same actual tileset")
    T.eq(data.tilesets.TilesetPlayersHouse,native,"native registry remains available")
    T.eq(native.id,"TilesetPlayersHouse","native animation/asset identity retained")
    T.eq(native.image,"real.png","actual asset path retained")
    T.eq(data.maps.ROOM.tileset,"TILESET_PLAYERS_HOUSE","map resolves the public constant")
    T.eq(data.maps.ROOM.sourceTileset,"TilesetPlayersHouse","source family remains observable")
    T.eq(data.maps.ROOM.id,"PLAYERS_HOUSE1_F","no map ID migration")
    T.eq(data.maps.ROOM.environment,3,"no environment or save migration")
    T.eq(data.maps.CONFLICT.tileset,"TilesetMart","conflicting authored constant is not guessed")
    T.eq(data.maps.PUBLIC.tileset,"TILESET_MART","authored public target remains authoritative")
    T.eq(data.maps.CUSTOM.tileset,"CUSTOM","unknown authored family unchanged")
    local replacement={id="TilesetPlayersHouse",image="replacement.png"}
    data.tilesets.TilesetPlayersHouse=replacement
    T.eq(Data.publishGen2TilesetNames(data),true,"post-merge refresh")
    T.eq(data.tilesets.TILESET_PLAYERS_HOUSE,replacement,"native replacement reaches generated alias")
    local authored={id="replacement constant"};data.tilesets.TILESET_PLAYERS_HOUSE=authored
    Data.publishGen2TilesetNames(data)
    T.eq(data.tilesets.TILESET_PLAYERS_HOUSE,authored,"explicit later constant override survives")
    T.eq(data.maps.ROOM.tileset,"TILESET_PLAYERS_HOUSE","map keeps the explicit override")
  else
    T.eq(result,false,version.." unrelated generation unchanged")
    T.eq(data.tilesets.TILESET_PLAYERS_HOUSE,nil,"no unrelated aliases")
    T.eq(data.maps.ROOM.tileset,"TilesetPlayersHouse","no unrelated data changes")
  end
end
Version.set("crystal")
local a,b={},{}
local ambiguous={tilesets={TilesetPokeComCenter=a,TilesetPokecomCenter=b},maps={A={tileset="TilesetPokeComCenter"},B={tileset="TilesetPokecomCenter"}}}
Data.publishGen2TilesetNames(ambiguous)
T.eq(ambiguous.tilesets.TILESET_POKECOM_CENTER,nil,"ambiguous distinct families have no alias")
T.eq(ambiguous.maps.A.tileset,"TilesetPokeComCenter","ambiguous first family preserved")
T.eq(ambiguous.maps.B.tileset,"TilesetPokecomCenter","ambiguous second family preserved")
T.eq(Data.publishGen2TilesetNames({}),false,"missing registries are not invented")
Version.set(original)
T.finish("native Gen2 tileset constant names")
