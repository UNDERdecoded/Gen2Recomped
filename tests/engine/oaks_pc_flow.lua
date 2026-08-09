-- Prof. Oak's PC session (#576): engine/menus/oaks_pc.asm OpenOaksPC --
-- the access text, "Want to get your #DEX rated?" with a YES/NO, the dex
-- rating (completion line + tier text), the rating jingle only once the
-- rating text has printed (DisplayDexRating -> PlayPokedexRatingSfx), and
-- the "Closed link to PROF.OAK's PC." tail before control returns.  The
-- old flow played the jingle the moment the entry was picked and skipped
-- both the intro and the closing link.
-- ROM-free: uses the fixture dataset so CI (no data/generated/) stays green.
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local Data = T.fixtures.load()

-- the ROM-extracted strings the fixture text table does not carry; labels
-- and wording match pokered text/pokedex_ratings.asm + oaks_pc.asm
Data.text._AccessedOaksPCText =
  "Accessed PROF.\nOAK's PC.\fAccessed #DEX\nRating System."
Data.text._GetDexRatedText = "Want to get your\n#DEX rated?"
Data.text._ClosedOaksPCText = "Closed link to\nPROF.OAK's PC."
Data.text._DexCompletionText =
  "#DEX comp-\nletion is:\f{NUM:hDexRatingNumMonsSeen} #MON seen\n" ..
  "{NUM:hDexRatingNumMonsOwned} #MON owned\fPROF.OAK's\nRating:"
Data.text._DexRatingText_Own50To59 =
  "You finally got at\nleast 50 species!"

local SaveData = require("src.core.SaveData")
local OW = require("src.world.OverworldController")

local function setUpvalue(fn, name, val)
  local i = 1
  while true do
    local n = debug.getupvalue(fn, i)
    if not n then return false end
    if n == name then debug.setupvalue(fn, i, val); return true end
    i = i + 1
  end
end

local pushed = {}
local plays = {}
local stackStub = {
  push = function(_, item)
    pushed[#pushed + 1] = item
  end,
}
local textBoxStub = {
  new = function(_, text, onDone, opts)
    return { kind = "text", text = text, onDone = onDone, opts = opts }
  end,
}
local menuStub = {
  new = function(_, items, opts)
    return { kind = "menu", items = items, opts = opts or {} }
  end,
}
-- Sound / Menu are required lazily at the call sites; stub via package.loaded
local realSound = package.loaded["src.core.Sound"]
package.loaded["src.core.Sound"] = {
  play = function(_, name)
    plays[#plays + 1] = name
  end,
  playCry = function() end,
}
local realMenu = package.loaded["src.ui.Menu"]
package.loaded["src.ui.Menu"] = menuStub

local fakeGame = {
  data = Data,
  save = SaveData.newGame(),
  stack = stackStub,
}
for _, name in ipairs({ "openOaksPC", "dexRating" }) do
  T.check(setUpvalue(OW[name], "TextBox", textBoxStub),
    ("TextBox upvalue on %s"):format(name))
  T.check(setUpvalue(OW[name], "Game", fakeGame),
    ("Game upvalue on %s"):format(name))
end
T.check(setUpvalue(OW.openPC, "Game", fakeGame), "Game upvalue on openPC")

local fakeSelf = setmetatable({}, { __index = OW })

local function lastPush()
  return pushed[#pushed]
end
local function reset()
  fakeGame.save = SaveData.newGame()
  fakeGame.save.flags.EVENT_GOT_POKEDEX = true
  local seen, owned = {}, {}
  for i = 1, 55 do seen[i] = true; owned[i] = true end
  fakeGame.save.pokedex = { seen = seen, owned = owned }
  pushed = {}
  plays = {}
end
local function runChain()
  -- A through every box that is up; the choice box answers YES
  local guard = 0
  while lastPush() and lastPush().kind == "text" and guard < 10 do
    guard = guard + 1
    local box = lastPush()
    if box.opts and box.opts.choice then
      box.opts.choice(true)
    elseif box.onDone then
      box.onDone()
    else
      break
    end
  end
end

-- === full session from the launcher menu: intro, YES, rating, jingle, close
reset()
local done = false
fakeSelf:openPC(function() done = true end)
local menu = lastPush()
T.eq(menu.kind, "menu", "openPC pushes the PC menu")
local oak
for _, item in ipairs(menu.items) do
  if item.label == "PROF.OAK's PC" then oak = item end
end
T.check(oak ~= nil, "PROF.OAK's PC is offered once the Pokédex is had")
plays = {} -- drop the menu's Turn_On_PC; the session's jingle is what counts
oak.onSelect()
T.eq(pushed[2].kind, "text", "selection opens the access text")
T.check(tostring(pushed[2].text):find("Accessed", 1, true) ~= nil,
  "first session box is the access text")
runChain()
T.check(done, "session completes")
T.check(pushed[3].opts ~= nil and pushed[3].opts.choice ~= nil,
  "the rated question carries the YES/NO choice")
T.check(tostring(pushed[3].text):find("rated", 1, true) ~= nil,
  "second session box asks for the rating")
local ratingBox = pushed[4]
T.check(ratingBox.opts and ratingBox.opts.auto ~= nil
  and ratingBox.opts.auto.wait ~= nil,
  "rating box sounds the jingle then waits for a button")
T.check(tostring(ratingBox.text):find("55", 1, true) ~= nil,
  "completion line carries the seen/owned counts")
T.check(tostring(ratingBox.text):find("least 50 species", 1, true) ~= nil,
  "rating box carries the Own50To59 tier text")
T.eq(#plays, 0, "no jingle while the evaluation is printing")
ratingBox.opts.auto.sound()
T.eq(#plays, 1, "jingle fires once the rating text is printed")
T.eq(plays[1], "Pokedex_Rating", "jingle is the Pokedex_Rating fanfare")
T.check(tostring(pushed[5].text):find("Closed link", 1, true) ~= nil,
  "the closing link prints at the end of the session")

-- === declining the rating skips the evaluation but still closes the link
reset()
done = false
fakeSelf:openOaksPC(function() done = true end)
T.eq(pushed[1].kind, "text", "openOaksPC opens with the access text")
pushed[1].onDone()
T.check(pushed[2].opts and pushed[2].opts.choice ~= nil,
  "rated question is a YES/NO")
pushed[2].opts.choice(false)
T.check(tostring(lastPush().text):find("Closed link", 1, true) ~= nil,
  "NO skips the rating and closes the PC")
T.eq(#plays, 0, "declining plays no jingle")

package.loaded["src.ui.Menu"] = realMenu
if realSound ~= nil then package.loaded["src.core.Sound"] = realSound end

T.finish("oaks_pc_flow")
