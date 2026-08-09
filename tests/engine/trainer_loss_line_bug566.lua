-- A beaten trainer's own line is spoken, so it carries their name tag.
--
-- TrainerEndBattleText (home/trainers.asm:381-386) prints _TrainerNameText
-- -- wNameBuffer then ": " (data/text/text_1.asm:16-19) -- and only then
-- the saved EndBattleText pointer, so the loss line opens
-- "BUG CATCHER: ...".  The port printed the pointer alone, leaving an
-- unattributed sentence on the battle screen (#566).  SaveTrainerName reads
-- TrainerNamePointers, whose RIVAL1/2/3 entries aim at wTrainerName, so the
-- rival tags with his name and never with the class id.
--
-- The tag belongs to the box, not to every page: a `para` inside the loss
-- text is a second page and prints untagged.
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local Data = T.fixtures.fresh()
local Font = require("src.render.Font")
Font.load(Data)
local TypeChart = require("src.battle.TypeChart")
TypeChart.load(Data)
local Pokemon = require("src.pokemon.Pokemon")
local SaveData = require("src.core.SaveData")
local BattleState = require("src.battle.BattleState")

local function freshGame()
  local save = SaveData.newGame()
  save.player.name = "RED"
  save.player.rival = "GARY"
  save.party = { Pokemon.new(Data, "FIXMON_A", 30) }
  return { data = Data, save = save,
           stack = { top = function() return nil end,
                     push = function() end, pop = function() end } }
end

-- KO the whole enemy party and take the win branch of enemyMonFainted
local function beat(game, oppClass, endText)
  local battle = BattleState.newTrainer(game, oppClass, 1)
  battle.participants = {}
  battle.playVictoryMusic = function() end
  battle.endBattleText = endText
  for _, mon in ipairs(battle.enemyParty) do mon.hp = 0 end
  battle.enemyIndex = #battle.enemyParty
  battle.enemy.mon = battle.enemyParty[battle.enemyIndex]
  battle:enemyMonFainted()
  local texts = {}
  for _, row in ipairs(battle.queue) do
    if row.text then texts[#texts + 1] = row.text end
  end
  return battle, texts
end

-- index of the first queued message containing `needle`
local function findText(texts, needle)
  for i, text in ipairs(texts) do
    if text:find(needle, 1, true) then return i end
  end
end

do
  local game = freshGame()
  local battle, texts = beat(game, "OPP_FIX_YOUNGSTER",
                             "Well fixed!\fBut I will win next time.")
  T.eq(battle.result, "win", "the last enemy mon fainting ends the battle")

  local loss = findText(texts, "Well fixed!")
  T.check(loss ~= nil, "the trainer's loss line is queued")
  T.eq(texts[loss], battle.trainer.name .. ": Well fixed!",
       "the loss line opens with the trainer class and a colon")
  T.eq(texts[loss + 1], "But I will win next time.",
       "the `para` page is a page of the same box, so it is not tagged again")

  -- TrainerBattleVictory (core.asm:915-949) order: TrainerDefeatedText,
  -- the pic scroll, PrintEndBattleText, then MoneyForWinningText
  local defeated = findText(texts, "defeated")
  local money = findText(texts, "for winning")
  T.check(defeated and defeated < loss, "the tag follows 'RED defeated ...'")
  T.check(money and money > loss + 1, "the prize line still comes last")
end

-- RIVAL1/2/3 tag with the rival's name, not the class id: newTrainer
-- overlays wRivalName the way GetTrainerName_ does.
do
  local game = freshGame()
  Data.trainers.OPP_RIVAL1 = {
    id = "OPP_RIVAL1", index = 2, name = "RIVAL1", baseMoney = 15,
    parties = { { { level = 5, species = "FIXMON_C" } } },
  }
  local battle, texts = beat(game, "OPP_RIVAL1", "You're still learning!")
  T.eq(battle.trainer.name, "GARY", "the rival battles under his own name")
  local loss = findText(texts, "still learning")
  T.check(loss ~= nil, "the rival's loss line is queued")
  T.eq(texts[loss], "GARY: You're still learning!",
       "the rival tag is his name, never the RIVAL1 class id")
end

-- A scripted battle that prints its own follow-up leaves endBattleText nil;
-- nothing may invent a tagged empty box for it.
do
  local game = freshGame()
  local _, texts = beat(game, "OPP_FIX_YOUNGSTER", nil)
  for _, text in ipairs(texts) do
    T.check(not text:match("^FIX YOUNGSTER: %s*$"),
            "no empty tagged box when the trainer has no loss line")
  end
end

T.finish("trainer loss line bug566")
