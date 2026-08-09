-- Parity test: the wild enemy's cry waits for the silhouette slide.
--
-- SlidePlayerAndEnemySilhouettesOnScreen (engine/battle/core.asm:9-100)
-- ends with `jpfar PrintBeginningBattleText`, and that routine calls
-- PlayCry immediately before PrintText WildMonAppearedText
-- (engine/battle/common_text.asm:10-19).  So the cry belongs at the moment
-- the silhouettes land and the "Wild X appeared!" box opens -- not on the
-- slide's first frame, which is where it landed once the cry was queued
-- ahead of the intro text (#303).
--
-- The hold lives in BattleState:update rather than in updateQueue, because
-- only the frame loop has a clock to count introSlide down with; this test
-- drives the real update() for that reason, not the queue pump.
--
-- Self-contained; run via `luajit tests/parity_battle_intro_cry.lua`.
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end
local S = require("tests.harness").suite("parity battle intro cry")
local check, eq = S.check, S.eq

local Data = require("src.core.Data")
if not Data.maps then Data:load() end
local Font = require("src.render.Font")
Font.load(Data)

local BattleState = require("src.battle.BattleState")
local Pokemon = require("src.pokemon.Pokemon")
local SaveData = require("src.core.SaveData")
local Sound = require("src.core.Sound")

-- Record cries instead of sounding them.  BattleState reaches the module
-- through require() at the call site, so replacing the field here is what
-- the battle will actually call.
local cries = {}
Sound.playCry = function(_, species) cries[#cries + 1] = species end

-- stub stack + input, like the other headless battle probes: no UI rows
-- come out of the intro, so top() never has to return the battle
local function makeGame(party)
  local save = SaveData.newGame()
  save.party = party
  local stack = { states = {} }
  function stack:push(state) self.states[#self.states + 1] = state end
  function stack:pop() return table.remove(self.states) end
  function stack:top() return self.states[#self.states] end
  return { data = Data, save = save, stack = stack,
           input = { wasPressed = function() return false end } }
end

local game = makeGame({ Pokemon.new(Data, "BULBASAUR", 50) })
local battle = BattleState.newWild(game, "RATTATA", 2)
battle.onFinish = function() end
battle:enter()

local slide = battle.introSlide or 0
check(slide > 0, "the intro arms a silhouette slide")
eq(#cries, 0, "no cry has sounded when the battle opens")
local queued = #battle.queue
check(queued > 0, "the intro queued its cry and text")

-- mid-slide: the queue must not have started
for _ = 1, math.floor(slide / 2) do battle:update(1 / 60) end
check((battle.introSlide or 0) > 0, "the slide is still running")
eq(#battle.queue, queued, "the queue is held for the whole slide")
eq(#cries, 0, "the cry does not sound during the slide (#303)")
eq(battle.phase, "messages", "the battle stays in the messages phase")

-- the slide lands: the cry is the first thing out of the queue, so it
-- sounds with the "Wild X appeared!" box rather than after it
for _ = 1, slide do battle:update(1 / 60) end
eq(battle.introSlide or 0, 0, "the slide finishes")
eq(cries[1], "RATTATA", "the wild cry sounds as the slide lands")
check(#battle.queue < queued, "the queue drains once the slide is done")

S.finish()
