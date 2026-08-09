-- Pokemon Yellow has a different TradeMons table from Red and Blue.
-- The import manifest must agree, and Data:seedDefaults repairs Yellow
-- caches made before that manifest carried the Yellow table (#453).

package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local Data = require("src.core.Data")
if not (Data.field and Data.field.trades) then Data:load() end
local GameVersion = require("src.core.GameVersion")
local S = require("tests.harness").suite("parity Yellow trades")
local check, eq = S.check, S.eq

local oldVersion = GameVersion.get()
local oldTrades = {}
for i, trade in ipairs(Data.field.trades) do
  oldTrades[i] = {}
  for key, value in pairs(trade) do oldTrades[i][key] = value end
end

GameVersion.set("yellow")
Data:applyVersionedFieldData()

local expected = {
  { "LICKITUNG", "DUGTRIO", "GURIO" },
  { "CLEFAIRY", "MR_MIME", "MILES" },
  { "BUTTERFREE", "BEEDRILL", "STINGER" },
  { "KANGASKHAN", "MUK", "STICKY" },
  { "MEW", "MEW", "BART" },
  { "TANGELA", "PARASECT", "SPIKE" },
  { "PIDGEOT", "PIDGEOT", "MARTY" },
  { "GOLDUCK", "RHYDON", "BUFFY" },
  { "GROWLITHE", "DEWGONG", "CEZANNE" },
  { "CUBONE", "MACHOKE", "RICKY" },
}

local manifestFile = assert(io.open("tools/rom_manifest_yellow.json", "r"))
local manifest = manifestFile:read("*a")
manifestFile:close()

eq(#Data.field.trades, #expected, "Yellow has ten in-game trade rows")
for i, want in ipairs(expected) do
  local got = Data.field.trades[i]
  check(got.give == want[1] and got.get == want[2] and got.nickname == want[3],
    ("Yellow trade %d is %s for %s (%s)"):format(i, want[1], want[2], want[3]))
  local row = ('"get": "%s",%%s+"give": "%s",%%s+"nickname": "%s"')
    :format(want[2], want[1], want[3])
  check(manifest:find(row) ~= nil,
    ("Yellow manifest carries trade %d"):format(i))
end

local ricky = Data.field.trades[10]
check(ricky.give == "CUBONE" and ricky.get == "MACHOKE",
  "the Underground Path trade is Cubone for Machoke")

Data.field.trades = oldTrades
GameVersion.set(oldVersion)

return S:finish()
