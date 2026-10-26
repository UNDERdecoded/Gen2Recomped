package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.modkit")
local Strings = require("src.core.Strings")
local Version = require("src.core.GameVersion")
local Text = require("src.import.Gen4Text")
Strings.load({})
-- Loading modules before the catalog must not freeze their source strings.
local Hatch = require("src.pokemon.Gen45Hatch")
local Transfer = require("src.ui.Gen5PokeTransferScreen")
local Shop = require("src.ui.Gen4ShopMenu")
local Team = require("src.ui.HgssPokeathlonTeamInfo")
local Shops = require("src.script.HgssPokeathlonShops")
local Font = require("src.render.Font")
local oldDraw, oldImage = Font.draw, love.graphics.newImage
love.graphics.newImage = function(...)
  local img = oldImage(...)
  img.setFilter = img.setFilter or function() end
  return img
end
local phrases = {
  ["Oh?"] = "OH",
  ["%s hatched from the Egg!"] = "%s:EGG",
  ["Would you like to nickname the newly\nhatched %s?"] = "%s:NAME",
  ["Would you like\n%s?"] = "%s:BUY",
  ["All right, here you go.\nCome back anytime!"] = "DONE",
  ["Here you are!\nThank you!"] = "THANKS",
  ["You don't have enough points!"] = "POOR",
  ["Athlete Pts."] = "POINTS",
  ["%sP"] = "%s:PTS",
  ["An Egg cannot be transferred."] = "NO_EGG",
  ["A Pokémon holding an item cannot\nbe transferred."] = "NO_ITEM",
  ["This Pokémon knows a hidden move.\nIt cannot be transferred."] = "NO_HM",
  ["Medals won by\n%s"] = "%s:MEDALS",
}
local originalVersion = Version.get()
for _, tag in ipairs({ "FIRST", "RELOADED" }) do
  Version.set("heartgold")
  local entry = { "return function(mod)" }
  for source, translated in pairs(phrases) do
    entry[#entry + 1] = ("mod.content.strings:override(%q, %q)"):format(source, tag .. ":" .. translated)
  end
  entry[#entry + 1] = "end"
  local run = T.sdk.loadMod("mods/native_translation", {
    data = T.fixtures.fresh(),
    fs = T.sdk.memfs({
      ["mods/native_translation/manifest.json"] = [[{"id":"native_translation","name":"Native translation",
        "version":"1.0.0","api":2,"entry":"main.lua","games":["all"],"generations":[1,2,3,4,5]}]],
      ["mods/native_translation/main.lua"] = table.concat(entry, "\n"),
    }),
  })
  T.eq(#run.errors, 0, "public strings mod loads")
  T.check(run.loader.exports.native_translation ~= nil, "translation entry actually executes")
  Strings.load(run.data)
  local game = { data = run.data, save = { inventory = {}, options = {}, hgssAthletePoints = 2000 } }
  game.stack = setmetatable({}, { __index = require("src.core.StateStack") })
  game.stack:init()
  for _, version in ipairs({ "platinum", "heartgold", "black" }) do
    Version.set(version)
    local oh, hatched, ask = Hatch.lines(game, "PIKA%CHU")
    T.eq(oh, tag .. ":OH", "native hatch opening translates")
    T.eq(hatched, tag .. ":PIKA%CHU:EGG", "species is formatted after translating the hatch template")
    T.eq(ask, tag .. ":PIKA%CHU:NAME", "nickname template translates before formatting")
    local family = version == "heartgold" and "hgss" or version == "black" and "bw" or "platinum"
    local rows = Hatch.LINES[family]
    for name, row in pairs(rows) do
      game.data.text[Text.label(row[1], row[2])] = "ROM:" .. name .. "\f"
    end
    oh, hatched, ask = Hatch.lines(game, "OTHER")
    T.eq(oh, "ROM:oh", "native bank opening keeps precedence")
    T.eq(hatched, "ROM:hatched", "native bank hatch keeps precedence")
    T.eq(ask, "ROM:ask", "native bank nickname prompt keeps precedence")
    for _, row in pairs(rows) do
      game.data.text[Text.label(row[1], row[2])] = nil
    end
  end
  Version.set("heartgold")
  game.data.items[505] = { id = 505, name = "DATA CARD", price = 500, fieldPocket = 0 }
  local shop = Shop.new(game, { 505 }, nil, nil, { athlon = { kind = "cards", prices = { [505] = 500 } } })
  shop:choose()
  T.eq(shop.mode, "confirm", "real athlete shop opens its purchase confirmation")
  T.eq(shop.message, tag .. ":DATA CARD:BUY", "purchase template translates before item substitution")
  shop:choose()
  T.eq(shop.message, tag .. ":DONE", "real card transaction translates its completion")
  T.check(Shops.hasCard(game.save, 0), "translated transaction still awards the card")
  T.eq(game.save.hgssAthletePoints, 1500, "translated transaction keeps the native price")
  T.eq(shop:line(18, "unused"), tag .. ":POINTS", "points caption translates")
  T.eq(shop:line(19, "unused"), tag .. ":1500:PTS", "balance formats after translation")
  local poor = Shop.new(game, { 506 }, nil, nil, { athlon = { kind = "cards", prices = { [506] = 3000 } } })
  game.data.items[506] = { id = 506, name = "NEXT CARD", price = 3000, fieldPocket = 0 }
  poor:choose()
  T.eq(poor.message, tag .. ":POOR", "native insufficient-points result translates")
  game.data.text[Text.label(435, 48)] = "ROM:points\f"
  poor:choose()
  T.eq(poor.message, "ROM:points", "athlete native message keeps precedence")
  game.data.text[Text.label(435, 48)] = nil
  Version.set("black")
  for _, case in ipairs({
    { { species = 1, isEgg = true }, "NO_EGG" },
    { { species = 1, item = 1 }, "NO_ITEM" },
    { { species = 1, moves = { { id = 15 } } }, "NO_HM" },
  }) do
    local screen = setmetatable({ game = game, picks = {}, srcData = {} }, Transfer)
    screen:toggle({ raw = case[1] })
    local box = game.stack:pop()
    T.check(box and box.pages, "native transfer refusal creates a text box")
    local wanted = tag .. ":" .. case[2]
    T.eq(
      box and table.concat(box.pages[1], "\n"),
      wanted,
      "refusal translates at use time after catalog reload"
    )
    T.eq(#screen.picks, 0, "refused Pokemon remains unselected")
  end
  Version.set("heartgold")
  Font.load(game.data)
  local drawn = {}
  Font.draw = function(text)
    drawn[#drawn + 1] = text
  end
  Team.draw(game, { mon = { species = "FIXMON_A", level = 5, moves = {} } })
  local species = game.data.pokemon.FIXMON_A.name
  local function contains(value)
    for _, text in ipairs(drawn) do
      if text == value then
        return true
      end
    end
    return false
  end
  T.check(contains(tag .. ":" .. species .. ":MEDALS"), "actual team panel translates its species template")
  drawn = {}
  game.data.text[Text.label(278, 9)] = "ROM:medals"
  Team.draw(game, { mon = { species = "FIXMON_A", level = 5, moves = {} } })
  T.check(contains("ROM:medals"), "native medal caption keeps precedence")
  game.data.text[Text.label(278, 9)] = nil
  Font.draw = oldDraw
  T.eq(#run.errors, 0, "native consumers record no mod errors")
  run.release()
  Strings.load({})
end
Version.set("platinum")
local a, b, c = Hatch.lines({ data = { text = {} } }, "EEVEE")
T.eq(a, "Oh?", "no catalog retains English")
T.eq(b, "EEVEE hatched from the Egg!", "no catalog retains hatch formatting")
T.eq(c, "Would you like to nickname the newly\nhatched EEVEE?", "no catalog retains nickname prompt")
Font.draw, love.graphics.newImage = oldDraw, oldImage
Version.set(originalVersion)
T.finish("native fallback strings through a public translation mod")
