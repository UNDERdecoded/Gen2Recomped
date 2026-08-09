-- Manual check of Yellow's two extra pic rips: PROF.OAK's own back pic in
-- the Pallet catch scene (#557, LoadPlayerBackPic's BATTLE_TYPE_PIKACHU
-- branch, pokeyellow engine/battle/core.asm:6384-6391) and the framed
-- portrait TalkToPikachu raises (#561, each PikaPicAnimScript's own base
-- frame, data/pikachu/pikachu_pic_animation.asm).  Both are gated on files
-- the importer writes, so the asset check comes before any staging.  No
-- POKEPORT_IDENTITY: a sandbox save dir carries no Yellow cache at all.
--   POKEPORT_DRIVER=tests/drivers/oak_pikapic_bug557_bug561_test.lua POKEPORT_TOUCH=0 POKEPORT_VERSION=yellow love .
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local GameVersion = require("src.core.GameVersion")
  local BattleState = require("src.battle.BattleState")
  local Sprites = require("src.pokemon.Sprites")
  local Pokemon = require("src.pokemon.Pokemon")

  local SHOT_DIR = os.getenv("SHOT_DIR") or "/tmp/shots"
  local PROF_BACK = "assets/generated/battle/profoakb.png"
  local OLDMAN_BACK = "assets/generated/battle/oldmanb.png"

  local function check(label, ok)
    U.log(ok and "PASS" or "FAIL", label)
    return ok
  end

  local function idle()
    while true do coroutine.yield() end
  end

  if not check("running the Yellow cache (POKEPORT_VERSION=yellow)",
               GameVersion.isYellow()) then
    U.log("Neither pic exists in Red or Blue. Re-run with")
    U.log("POKEPORT_VERSION=yellow.")
    idle()
  end

  -- ---- the two rips, before anything is staged ----
  -- The importer writes these only when the manifest carries the symbol, and
  -- both call sites fall back silently when the file is absent, so a missing
  -- file looks on screen exactly like the bug being unfixed.
  local oakPicOk = love.filesystem.getInfo(PROF_BACK) ~= nil
  check("Oak's back pic is in the cache (" .. PROF_BACK .. ")", oakPicOk)
  if not oakPicOk then
    U.log("The importer skipped it: tools/rom_manifest_yellow.json has no")
    U.log("ProfOakPicBack entry, so RomExtractor's gate never fires and")
    U.log("Sprites.playerPath falls back to " .. OLDMAN_BACK .. ".")
    U.log("Re-importing will not help until the symbol is in the manifest.")
  end

  local pikapicFound = {}
  for script = 1, 28 do
    local path = "assets/generated/pikachu/pikapic_" .. script .. ".png"
    if love.filesystem.getInfo(path) then
      pikapicFound[#pikapicFound + 1] = script
    end
  end
  local pikapicOk = #pikapicFound > 0
  check("the pikapic base frames are in the cache (assets/generated/pikachu/)",
        pikapicOk)
  if pikapicOk then
    U.log("found base frames for scripts:", table.concat(pikapicFound, " "))
  else
    U.log("The importer skipped all 28: the Pic_e4000..Pic_f0cf4 labels are")
    U.log("absent from tools/rom_manifest_yellow.json, so PikachuFollower")
    U.log("keeps standing the battle front pic in the frame, which is #561")
    U.log("unchanged. Not staging the talk: it cannot look right yet.")
  end
  U.log("tests/engine/yellow_oak_back_pikapic.lua asserts both symbol lists.")

  -- ---- #557: the Pallet catch scene ----
  -- Same two calls data/scripts/story2.lua:255 makes once Oak has said
  -- "That was close!"  Standing in Pallet Town first so the battle draws
  -- over a real map, as it does in play.
  U.teleport(game, "PALLET_TOWN", 10, 8, "up")
  U.wait(10)
  game.save.player.name = "bryan"

  local backPath = Sprites.playerPath(game.data, "back",
    { kind = "battle", demo = true, oakDemo = true })
  U.log("the demo resolves its back pic to:", tostring(backPath))
  check("it is Oak's pic, not the old man's", backPath == PROF_BACK)

  local battle = BattleState.newWild(game, "PIKACHU", 5)
  battle:makeOldManDemo("PROF.OAK")
  check("the thrower is named PROF.OAK", battle.demoName == "PROF.OAK")
  check("the battle asks for the BATTLE_TYPE_PIKACHU back pic",
        battle.oakDemo == true)

  -- record what the scripted throw actually prints, so the name half can be
  -- judged without reading glyph codes off the canvas
  local said = {}
  local realSay = battle.say
  battle.say = function(self, text)
    said[#said + 1] = tostring(text)
    return realSay(self, text)
  end

  game.stack:push(battle)
  U.wait(10)

  -- clear the "Wild PIKACHU appeared!" box; the scripted cursor script only
  -- starts once the intro chrome is gone
  for _ = 1, 90 do
    if battle.phase == "menu" then break end
    U.tap(game, "a")
    U.wait(4)
  end
  if not check("the demo battle reached its scripted menu",
               battle.phase == "menu") then
    U.log("phase is", tostring(battle.phase), "- the intro never cleared.")
    idle()
  end
  U.wait(20)
  if U.shot(game, SHOT_DIR .. "/bug557_back_pic.png") then
    U.log("captured", SHOT_DIR .. "/bug557_back_pic.png")
  end

  -- The other half of the issue title, "referred to as Pikachu".
  -- DisplayBattleMenu's simulated branch puts BATTLE_MENU_TEMPLATE on screen
  -- and nothing else (data/text_boxes.asm:31 -- FIGHT/PKMN/ITEM/RUN from
  -- column 8), so no name is printed at all: there is no player mon in this
  -- battle to name.  The classic layout ports that branch; WideBattle's menu
  -- has no demo case and prints "What will <battle.player.name> do?" over the
  -- hidden placeholder battler, which is a level 5 PIKACHU.
  local options = game.save.options or {}
  U.log("battle layout option:", tostring(options.battleLayout or "classic"))
  local wide = battle:isWideBattleLayout()
  check("the layout on screen leaves the scripted menu unnamed", not wide)
  if wide then
    U.log("The wide layout is on, so the menu reads \"What will PIKACHU do?\"")
    U.log("beside Oak's throw. Switch OPTIONS to the classic battle layout")
    U.log("and re-run to see the box the original draws.")
  end

  -- the rest runs itself: 130 frames of cursor, the forced ITEM list, then
  -- the throw.  Never tap through it -- the timing is the port of
  -- DisplayBattleMenu's simulated keystrokes.
  local function thrownLine()
    for _, text in ipairs(said) do
      if text:find("POK", 1, true) and text:find("PROF.OAK", 1, true) then
        return text
      end
    end
    return nil
  end
  for _ = 1, 600 do
    if thrownLine() then break end
    U.wait(1)
  end
  local line = thrownLine()
  check("the throw is announced under PROF.OAK's name", line ~= nil)
  if line then U.log("the box reads:", (line:gsub("\n", " / "))) end
  U.wait(45)
  if U.shot(game, SHOT_DIR .. "/bug557_throw.png") then
    U.log("captured", SHOT_DIR .. "/bug557_throw.png")
  end

  if oakPicOk then
    U.log("Both #557 shots are taken. The back pic in the lower left is the")
    U.log("man throwing the ball: Oak in his lab coat, and the throw line")
    U.log("names PROF.OAK. The near miss is a back pic that reads as a")
    U.log("person and looks plausible while still being oldmanb.png --")
    U.log("compare against the catch tutorial north of Viridian, which")
    U.log("SHOULD be the old man and proves the demo path works at all.")
  else
    U.log("The shots are evidence of the FAIL, not of a fix: the back pic in")
    U.log("the lower left is the bald OLD MAN from the Route 5 tutorial,")
    U.log("exactly as #557 reported him. The throw line above it does name")
    U.log("PROF.OAK, so the thrower half is right and only the pic is stuck.")
  end

  -- ---- #561: the framed portrait ----
  if not pikapicOk then
    U.log("Skipping the Pikachu portrait: see the FAIL above.")
    idle()
  end

  for _ = 1, 300 do
    if game.stack:top() ~= battle then break end
    U.wait(1)
  end
  U.wait(20)

  -- ShouldPikachuSpawn (pokeyellow engine/pikachu/pikachu_follow.asm): the
  -- lab gift happened and a healthy Pikachu leads the party.  Pallet's
  -- objects sit at (10,4), (3,8) and (11,14), so (10,8) and the road cells
  -- around it are clear.
  game.save.party = { Pokemon.new(game.data, "PIKACHU", 12) }
  game.save.flags = game.save.flags or {}
  game.save.flags.EVENT_GOT_STARTER = true
  U.teleport(game, "PALLET_TOWN", 10, 8, "down")
  U.wait(12)

  local ow = game.overworld
  local function follower()
    for _, n in ipairs(ow.npcs or {}) do
      if n.pikachuFollower then return n end
    end
    return nil
  end
  local npc = follower()
  if not check("the follower spawned", npc ~= nil) then idle() end

  -- one step then a turn back, so the follower is on the cell just vacated
  local DIRS = { { "down", 0, 1 }, { "up", 0, -1 },
                 { "left", -1, 0 }, { "right", 1, 0 } }
  local OPPOSITE = { up = "down", down = "up", left = "right", right = "left" }
  local stepDir
  for _, d in ipairs(DIRS) do
    local cx, cy = ow.player.cellX + d[2], ow.player.cellY + d[3]
    if ow.map:inBounds(cx, cy) and ow.map:isWalkableCell(cx, cy)
       and not ow:npcAtCell(cx, cy) then
      stepDir = d[1]
      break
    end
  end
  if not check("a walkable neighbour to step into exists", stepDir ~= nil) then
    idle()
  end
  U.hold(game, stepDir, 24)
  U.wait(6)
  U.tap(game, OPPOSITE[stepDir])
  U.wait(6)

  local function facingFollower()
    local fx, fy = ow.player:facingCell()
    return ow:npcAtCell(fx, fy) == npc
  end
  if not facingFollower() then
    for _, d in ipairs(DIRS) do
      if npc.cellX == ow.player.cellX + d[2]
         and npc.cellY == ow.player.cellY + d[3] then
        U.tap(game, d[1])
        U.wait(6)
        break
      end
    end
  end
  check("player is facing the follower", facingFollower())

  U.tap(game, "a")
  U.wait(8)
  local emote = ow.emote
  if not check("the A press raised a portrait", emote ~= nil and emote.pikaPic) then
    U.log("Nothing answered the press, which is #407 territory, not #561.")
    idle()
  end
  U.log("the frame is drawing:", tostring(emote.pikaPic))
  check("it is this script's own base frame, not the battle front pic",
        emote.pikaPic:find("pikachu/pikapic_", 1, true) ~= nil)
  if U.shot(game, SHOT_DIR .. "/bug561_portrait.png") then
    U.log("captured", SHOT_DIR .. "/bug561_portrait.png")
  end

  U.log("The portrait box is up over the map now. Inside the 5x5 frame is a")
  U.log("posed Pikachu drawn for that emotion, not the battle front pic")
  U.log("standing to attention -- that stand-in is the screenshot on #561.")
  U.log("Face it and press A again for another emotion; the pose should")
  U.log("change with it. A frame that never changes between emotions is the")
  U.log("near miss: the path resolved but every script picked one base.")

  idle()
end
