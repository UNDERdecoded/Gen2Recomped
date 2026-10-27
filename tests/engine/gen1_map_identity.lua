package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.modkit")
local Identity = require("src.compat.gen1.MapIdentity")
local Names = require("src.compat.gen1.MapNames")
local Version = require("src.core.GameVersion")
local Catalog = require("src.import.gba.map_catalog")
local prior = Version.get()
for _, edition in ipairs({ "firered", "leafgreen", "emerald", "ruby", "sapphire" }) do
  Version.set(edition)
  local maps, nativeKeys = {}, {}
  for _, row in ipairs(Names[edition]) do
    local key = ("NATIVE_%d_%d"):format(row[1], row[2])
    maps[key] = { id = key, group = row[1], number = row[2], untouched = {} }
    nativeKeys[row[3]] = key
  end
  local binding = Identity.bind(maps, edition)
  for _, row in ipairs(Names[edition]) do
    local key, def = binding:nativeId(row[3])
    T.eq(key, nativeKeys[row[3]], "original name reaches actual native record")
    T.eq(def, maps[key], "definition is borrowed with its exact identity")
    T.eq(binding:legacyId(key), row[3], "native name returns original name")
    if Version.get() == edition then
      T.eq(Catalog.resolve(row[4]), row[3], "original mod import resolves pret alias")
    else
      T.eq(Catalog.isKnown(row[3]), false, "unavailable host edition has no active catalog")
    end
    T.eq(def.id, key, "native id was never rewritten")
  end
  local first = Names[edition][1]
  local key = nativeKeys[first[3]]
  local def = maps[key]
  maps[key] = nil
  T.eq(binding:nativeId(first[3]), nil, "removed native record retires its binding")
  maps[key] = { id = key, group = first[1], number = first[2] }
  T.eq(binding:nativeId(first[3]), nil, "replacement cannot inherit prior binding")
  maps[key] = def
  local duplicate = { id = "OTHER", group = def.group, number = def.number }
  maps.OTHER = duplicate
  local ambiguous = Identity.bind(maps, edition)
  T.eq(ambiguous:nativeId(first[3]), nil, "ambiguous slot cannot choose a different room")
  maps.OTHER = def
  local aliases = Identity.bind(maps, edition)
  T.eq(aliases:nativeId(first[3]), key, "same-object aliases prefer actual def.id")
  T.eq(aliases:legacyId("OTHER"), first[3], "same-object alias has same legacy identity")
  def.group = 255
  T.eq(aliases:nativeId(first[3]), nil, "changed slot retires prior binding")
  T.eq(binding:nativeId("invented"), nil, "unknown mod map is not guessed")
  T.eq(binding:legacyId("invented"), nil, "unknown native map is not guessed")
end
Version.set("gold")
T.eq(Catalog.isKnown("FR_PALLET_TOWN"), false, "other generations do not acquire Gen3 maps")
T.eq(Identity.lookup("firered", -1, 0), nil, "negative group is rejected")
T.eq(Identity.lookup("firered", 3.5, 0), nil, "fractional group is rejected")
T.eq(Identity.lookup("firered", 3, 256), nil, "out of range map number is rejected")
Version.set(prior)
T.finish("Gen1 native map identity compatibility")
