-- Parity test for Route 5 Day Care (issue #118).
-- Self-contained: `luajit tests/parity_daycare.lua`; also dofile'd by
-- tests/run_tests.lua's parity_* aggregator.
--
-- Covers scripts/Daycare.asm retrieve flow ported in
-- data/scripts/story2.lua M.DAYCARE:
--   * name substitution in grown / got-back text
--   * fee = ¥100 + ¥100 per level gained
--   * declining retrieve must not collapse the fee to ¥100 on re-talk
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end
local Data = require("src.core.Data")
if not (Data.maps and Data.maps.PALLET_TOWN) then Data:load() end
local S = require("tests.harness").suite("parity daycare")
local check, eq = S.check, S.eq

local realTextBox = package.loaded["src.render.TextBox"]
local shownTexts = {}
local choiceAnswer = true
package.loaded["src.render.TextBox"] = {
  new = function(game, text, onDone, opts)
    table.insert(shownTexts, text)
    if opts and opts.choice then
      opts.choice(choiceAnswer)
    elseif onDone then
      onDone()
    end
    return { text = text }
  end,
}

local SaveData = require("src.core.SaveData")
local Pokemon = require("src.pokemon.Pokemon")
local Growth = require("src.pokemon.Growth")
local story2 = require("data.scripts.story2")

check(story2.DAYCARE ~= nil, "DAYCARE registered")
check(story2.DAYCARE.talk.TEXT_DAYCARE_GENTLEMAN ~= nil,
      "DAYCARE gentleman talk handler registered")

local talkGentleman = story2.DAYCARE.talk.TEXT_DAYCARE_GENTLEMAN

local function newGame()
  local save = SaveData.newGame()
  save.money = 10000
  local game = { data = Data, save = save, stack = { push = function() end } }
  return game
end

local function talk(game)
  shownTexts = {}
  local doneCalled = false
  talkGentleman(game, {}, nil, function() doneCalled = true end)
  return doneCalled
end

local function boardAtLevel(game, species, level, nickname)
  local mon = Pokemon.new(Data, species, level)
  if nickname then mon.nickname = nickname end
  game.save.daycare = { mon = mon, steps = 0 }
  return mon
end

-- Exp needed to gain `gained` levels from `level` (exclusive of current).
local function stepsForLevels(species, level, gained)
  local def = Data.pokemon[species]
  local target = Growth.expForLevel(def.growthRate, level + gained)
  local current = Growth.expForLevel(def.growthRate, level)
  return target - current
end

-- === 1) grown text names the mon; fee matches levels grown ===
do
  local game = newGame()
  local mon = boardAtLevel(game, "RATTATA", 5, "SCRAPPY")
  local gained = 3
  game.save.daycare.steps = stepsForLevels("RATTATA", 5, gained)
  choiceAnswer = false -- decline retrieve
  check(talk(game), "grown+decline talk completes")
  local grown
  for _, s in ipairs(shownTexts) do
    if s:find("grown a lot", 1, true) then grown = s break end
  end
  check(grown ~= nil, "shows MonHasGrownText")
  check(grown:find("SCRAPPY", 1, true), "grown text substitutes wNameBuffer")
  check(grown:find(tostring(gained), 1, true), "grown text shows levels grown")
  check(not grown:find("{RAM:", 1, true), "grown text has no leftover RAM tokens")
  local owe
  for _, s in ipairs(shownTexts) do
    if s:find("owe me", 1, true) then owe = s break end
  end
  check(owe ~= nil, "shows OweMoneyText")
  eq(owe:match("¥(%d+)"), tostring(100 + gained * 100),
     "fee is ¥100 + ¥100 per level gained")
  eq(game.save.daycare.mon.level, 5,
     "decline leaves deposit level untouched (BoxLevel baseline)")
  eq(game.save.daycare.steps, 0, "pending steps folded into exp on talk")
end

-- === 2) re-talk after decline keeps the correct fee (issue #118) ===
do
  local game = newGame()
  boardAtLevel(game, "RATTATA", 5, "SCRAPPY")
  local gained = 3
  game.save.daycare.steps = stepsForLevels("RATTATA", 5, gained)
  choiceAnswer = false
  talk(game)
  choiceAnswer = false
  check(talk(game), "second decline talk completes")
  local owe
  for _, s in ipairs(shownTexts) do
    if s:find("owe me", 1, true) then owe = s break end
  end
  check(owe ~= nil, "re-talk still shows OweMoneyText")
  eq(owe:match("¥(%d+)"), tostring(100 + gained * 100),
     "re-talk after decline keeps fee (not ¥100)")
  eq(game.save.daycare.mon.level, 5, "re-talk still leaves deposit level")
end

-- === 3) paid retrieve raises level, names the mon, clears daycare ===
do
  local game = newGame()
  boardAtLevel(game, "RATTATA", 5, "SCRAPPY")
  local gained = 2
  game.save.daycare.steps = stepsForLevels("RATTATA", 5, gained)
  local fee = 100 + gained * 100
  local moneyBefore = game.save.money
  choiceAnswer = true
  check(talk(game), "retrieve talk completes")
  eq(game.save.daycare, nil, "daycare cleared after paid retrieve")
  eq(#game.save.party, 1, "mon returned to party")
  eq(game.save.party[1].nickname, "SCRAPPY", "retrieved nickname preserved")
  eq(game.save.party[1].level, 5 + gained, "level applied only on retrieve")
  eq(game.save.money, moneyBefore - fee, "money deducted by correct fee")
  local got
  for _, s in ipairs(shownTexts) do
    if s:find("got", 1, true) and s:find("back", 1, true) then got = s break end
  end
  check(got ~= nil, "shows GotMonBackText")
  check(got:find("SCRAPPY", 1, true), "got-back text substitutes wDayCareMonName")
  check(not got:find("{RAM:", 1, true), "got-back text has no leftover RAM tokens")
end

-- === 4) no levels gained: NeedsMoreTime still names the mon; fee ¥100 ===
do
  local game = newGame()
  boardAtLevel(game, "RATTATA", 10, "PIP")
  game.save.daycare.steps = 0
  choiceAnswer = false
  check(talk(game), "no-growth talk completes")
  local needs
  for _, s in ipairs(shownTexts) do
    if s:find("Back already", 1, true) then needs = s break end
  end
  check(needs ~= nil, "shows MonNeedsMoreTimeText")
  check(needs and needs:find("PIP", 1, true), "needs-more-time names the mon")
  local owe
  for _, s in ipairs(shownTexts) do
    if s:find("owe me", 1, true) then owe = s break end
  end
  eq(owe and owe:match("¥(%d+)"), "100", "no growth still costs base ¥100")
end

-- === 5) depositLevel survives a corrupted mon.level from older buggy talks ===
do
  local game = newGame()
  local mon = boardAtLevel(game, "RATTATA", 5, "SCRAPPY")
  local gained = 4
  game.save.daycare.steps = stepsForLevels("RATTATA", 5, gained)
  game.save.daycare.depositLevel = 5
  mon.level = 5 + gained -- simulate pre-#118 raise-on-talk corruption
  choiceAnswer = false
  check(talk(game), "depositLevel baseline talk completes")
  local owe
  for _, s in ipairs(shownTexts) do
    if s:find("owe me", 1, true) then owe = s break end
  end
  eq(owe and owe:match("¥(%d+)"), tostring(100 + gained * 100),
     "depositLevel keeps fee correct even if mon.level was raised early")
  eq(game.save.daycare.mon.level, 5, "decline restores mon.level to depositLevel")
end

-- === 6) skipped level-up moves granted on retrieve (#184 / WriteMonMoves) ===
do
  local game = newGame()
  local mon = boardAtLevel(game, "MAGIKARP", 13, "FISHY")
  game.save.daycare.depositLevel = 13
  local hasTackle = false
  for _, mv in ipairs(mon.moves) do
    if mv.id == "TACKLE" then hasTackle = true break end
  end
  check(not hasTackle, "Magikarp Lv13 does not already know Tackle")
  game.save.daycare.steps = stepsForLevels("MAGIKARP", 13, 6) -- → 19
  choiceAnswer = true
  check(talk(game), "Magikarp retrieve talk completes")
  local back = game.save.party[1]
  eq(back.level, 19, "Magikarp raised 13→19 on retrieve")
  local moveIds = {}
  for _, mv in ipairs(back.moves) do moveIds[#moveIds + 1] = mv.id end
  local joined = table.concat(moveIds, ",")
  check(joined:find("TACKLE", 1, true),
        "Magikarp learns Tackle at 15 via daycare skip (#184): " .. joined)
  check(joined:find("SPLASH", 1, true), "Splash retained alongside Tackle")
end

-- === 7) decline does not teach skipped moves ===
do
  local game = newGame()
  local mon = boardAtLevel(game, "MAGIKARP", 13)
  game.save.daycare.depositLevel = 13
  game.save.daycare.steps = stepsForLevels("MAGIKARP", 13, 6)
  choiceAnswer = false
  talk(game)
  local hasTackle = false
  for _, mv in ipairs(game.save.daycare.mon.moves) do
    if mv.id == "TACKLE" then hasTackle = true break end
  end
  check(not hasTackle, "decline leaves moves unchanged (no Tackle yet)")
end

package.loaded["src.render.TextBox"] = realTextBox
S.finish()
