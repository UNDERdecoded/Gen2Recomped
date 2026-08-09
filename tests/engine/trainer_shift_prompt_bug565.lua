-- SHIFT's "about to use" offer is one box with a CONT, not two boxes.
--
-- _TrainerAboutToUseText (data/text/text_2.asm:911-921) is
-- "<wTrainerName> is" / line "about to use" / cont "<wEnemyMonNick>!": the
-- cont scrolls "X is" off the top so the nick arrives UNDER the words that
-- explain it.  Splitting that into two say() rows put the nick alone on a
-- fresh page, which reads as a bare Pokemon name with no sentence around
-- it (#565).
--
-- The rendered half is checked through BattleState:startMessage, the same
-- parser the battle box types from, so this fails if \v ever stops meaning
-- ContText there.
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

-- SHIFT only offers the switch when the player has more than one party
-- slot and the active mon is alive (core.asm:1366-1443)
local save = SaveData.newGame()
save.player.name = "RED"
save.party = { Pokemon.new(Data, "FIXMON_A", 30), Pokemon.new(Data, "FIXMON_B", 30) }
save.options = save.options or {}
save.options.battleStyle = "shift"

local game = { data = Data, save = save,
               stack = { top = function() return nil end,
                         push = function() end, pop = function() end } }

local battle = BattleState.newTrainer(game, "OPP_FIX_YOUNGSTER", 1)
T.check(#battle.enemyParty >= 2, "the fixture trainer has a reserve to send out")
battle.participants = {}

-- KO the lead so enemyMonFainted queues the send-out for slot 2
battle.enemyParty[1].hp = 0
battle.enemy.mon = battle.enemyParty[1]
battle:enemyMonFainted()

local texts = {}
for _, row in ipairs(battle.queue) do
  if row.text then texts[#texts + 1] = row.text end
end

local offer
for _, text in ipairs(texts) do
  if text:find("about to use", 1, true) then offer = text end
end
T.check(offer ~= nil, "SHIFT queues the about-to-use offer")

local nick = Data.pokemon[battle.enemyParty[2].species].name
T.eq(offer, battle.trainer.name .. " is\nabout to use\v" .. nick .. "!",
     "one box: name, the line break, then a CONT to the nick")

-- the regression itself: the nick must never be a message of its own
for _, text in ipairs(texts) do
  T.neq(text, nick .. "!", "no bare-nickname box follows the offer")
end

-- and what the box actually renders: three lines, the third scrolled in,
-- so the two visible rows when the nick lands are "about to use" / nick
battle:startMessage({ text = offer })
T.eq(#battle.lines, 3, "the offer types as three lines")
T.check(not battle.lines[2].cont, "line 2 follows a plain line break")
-- guarded so a regression reports the missing line instead of dying on it
if battle.lines[3] then
  T.check(battle.lines[3].cont, "line 3 is a ContText scroll, not a new page")
  T.same(battle.lines[2].codes, Font.encode("about to use"),
         "the line above the nick still says 'about to use'")
  T.same(battle.lines[3].codes, Font.encode(nick .. "!"),
         "the scrolled-in line is the nick")
end

T.finish("trainer shift prompt bug565")
