-- THE HATCH'S WORDS ON PLATINUM, HEARTGOLD / SOULSILVER AND BLACK / WHITE.
--
-- CommonScript_HatchEgg says "Oh?" from the common script bank (Pt 213/76,
-- HGSS 40/62); the hatch scene then says "{name} hatched from the Egg!" and
-- asks "Would you like to nickname the newly hatched {name}?" from its own
-- bank (Pt 357, HGSS 187). Black / White keep all three in one bank, 260.
-- Each falls back to the engine's English when the cache lacks the line.

local Strings = require("src.core.Strings")
local Gen45Hatch = {}

Gen45Hatch.LINES = {
  platinum = { oh = { 213, 76 }, hatched = { 357, 0 }, ask = { 357, 1 } },
  hgss = { oh = { 40, 62 }, hatched = { 187, 0 }, ask = { 187, 1 } },
  bw = { oh = { 260, 0 }, hatched = { 260, 1 }, ask = { 260, 2 } },
}

local function family()
  local GameVersion = require("src.core.GameVersion")
  if GameVersion.isGen5 and GameVersion.isGen5() then return "bw" end
  local v = GameVersion.get()
  if v == "heartgold" or v == "soulsilver" then return "hgss" end
  if GameVersion.isGen4() then return "platinum" end
  return nil
end

function Gen45Hatch.applies() return family() ~= nil end

local function line(game, row, name, fallback)
  local Gen4Text = require("src.import.Gen4Text")
  Gen4Text.buffer(game, name)
  local s = row and Gen4Text.resolve(game.data, row[1], row[2], game)
  if type(s) ~= "string" or not s:match("%S") then return fallback end
  s = s:gsub("%s+$", "")
  return s
end

-- The three lines, with `name` (the species) filled in.
function Gen45Hatch.lines(game, name)
  local rows = Gen45Hatch.LINES[family() or "platinum"]
  return line(game, rows.oh, name, Strings("Oh?")),
    line(game, rows.hatched, name, Strings("%s hatched from the Egg!", name)),
    line(game, rows.ask, name, Strings("Would you like to nickname the newly\nhatched %s?", name))
end

return Gen45Hatch
