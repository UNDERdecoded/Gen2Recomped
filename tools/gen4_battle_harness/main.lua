-- tools/gen4_battle_harness/main.lua
--
-- A HEADLESS GEN 4 BATTLE, RENDERED TO A PNG.
--
-- WHY THIS EXISTS.  The terrain harness can stand in Twinleaf and diff frames,
-- and that is what made the camera, the back walls, the grass and the sky
-- checkable.  The battle screen had no equivalent, so every battle-side report
-- -- the ball throw, the party icons, the HP bar, the move menu, the stray
-- textbox -- could only be reasoned about.  This project does not ship visuals
-- nobody has looked at, so that gap was the real blocker rather than any one of
-- those items.
--
--   cd <repo>
--   POKEPORT_DATA_DIR=<platinum cache>/data/generated \
--     SPECIES=396 LEVEL=3 PARTY=387 TICKS=30 TAG=starly \
--     love tools/gen4_battle_harness
--
-- The PNG lands in LOVE's save directory for this identity (`bt_gen4`), which
-- `love` prints on the first run.
--
-- WHAT IT DELIBERATELY DOES NOT DO.  It does not stand up a window, an
-- overworld, a save file on disk or the launcher.  It builds the two things
-- `BattleState.newWild` actually requires -- a loaded dataset and a save with
-- one healthy Pokemon -- and draws one frame.
-- THE DS'S OWN SIZE IS THE DEFAULT, and that is not a cosmetic choice.
--
-- This used to default to 512x384. The FIELD is drawn to fill the canvas while
-- the 2D HUD draws in the screen's own 256x192 space, so at twice the size the
-- healthboxes, the message box and the menus all sit in the top-left QUARTER
-- of a full-size field -- a picture no player ever sees, and a useless one for
-- judging where anything sits relative to anything else.  Every HUD-versus-
-- field question asked of this harness at 512x384 was asked of the wrong
-- image.
--
-- W and H still override, for when a bigger canvas is genuinely wanted.
local W = tonumber(os.getenv("W") or "256")
local H = tonumber(os.getenv("H") or "192")
local TAG = os.getenv("TAG") or "battle"

function love.load()
  local ok, err = xpcall(function()
    local GameVersion = require("src.core.GameVersion")
    GameVersion.set(os.getenv("VERSION") or "platinum")

    -- POKEPORT_ASSET_ROOT: the version's cache folder (the one holding
    -- `assets/` and `data/`). The game reaches its images through a mount the
    -- launcher makes; this harness has no launcher, so without this every
    -- extracted picture -- buttons, icons, healthboxes -- comes up placeholder.
    local assetRoot = os.getenv("POKEPORT_ASSET_ROOT")
    if assetRoot then
      local Assets = require("src.render.Assets")
      local realImage = Assets.image
      local held = {}
      Assets.image = function(path, ...)
        if type(path) == "string" and not held[path] then
          local f = io.open(assetRoot .. "/" .. path, "rb")
          if f then
            local bytes = f:read("*a"); f:close()
            local okI, img = pcall(love.graphics.newImage,
                                   love.filesystem.newFileData(bytes, path))
            if okI then img:setFilter("nearest", "nearest"); held[path] = img end
          end
        end
        return held[path] or realImage(path, ...)
      end
      -- ...and the ImageData path the battle pics are baked through
      local realData = Assets.imageData
      local heldData = {}
      Assets.imageData = function(path, ...)
        if type(path) == "string" and not heldData[path] then
          local f = io.open(assetRoot .. "/" .. path, "rb")
          if f then
            local bytes = f:read("*a"); f:close()
            local okD, d = pcall(love.image.newImageData, love.filesystem.newFileData(bytes, path))
            if okD then heldData[path] = d end
          end
        end
        return heldData[path] or realData(path, ...)
      end
    end

    local Data = require("src.core.Data")
    Data:load()
    if not Data.isGen4Cache then
      print("WARNING: POKEPORT_DATA_DIR is not a Gen 4 cache -- "
            .. "this harness is for Sinnoh")
    end

    -- HAND THE GLYPH ATLAS TO THE RENDERER.
    --
    -- The second lifecycle step this harness was missing, after `enter`.
    -- Without it every string reports `no glyph for "A"` and the message area
    -- draws as a plain white rectangle -- which looks exactly like a rendering
    -- bug in the text box and is nothing of the kind.  Measured: ten glyph
    -- warnings without this call, zero with it, and the names and HP appear on
    -- the healthboxes.
    --
    -- Worth knowing before trusting this harness on anything about text: a
    -- white block in the message area means the font was not loaded, not that
    -- the box is wrong.
    local Font = require("src.render.Font")
    Font.load(Data)

    local Pokemon = require("src.pokemon.Pokemon")
    local SaveData = require("src.core.SaveData")
    local BattleState = require("src.battle.BattleState")
    local Game = require("src.core.Game")

    -- THE REAL NEW-GAME SAVE, not a hand-made one.  `newWild` reaches into
    -- `save.inventory`, `save.options` and more, and a hand-built table is how
    -- a harness ends up exercising a save shape the game never produces -- the
    -- first version of this did exactly that and raised on `inventory`.
    Game.data = Data
    Game.save = SaveData.newGame(Game.bootConfig and Game:bootConfig() or {})
    Game.save.party = {
      Pokemon.new(Data, tonumber(os.getenv("PARTY") or "387"),
                        tonumber(os.getenv("PARTYLEVEL") or "12")),
    }

    -- HURT THE LEAD, because a held-item or healing test on a full-health
    -- Pokemon is a test THAT CANNOT FAIL: every heal rule declines at full HP,
    -- so nothing happens either way and the run looks identical with and
    -- without the thing being tested.  Measured after this was added: the
    -- Leftovers check had been reporting 52/52 in both arms.
    if os.getenv("HURT") then
      local m = Game.save.party[1]
      local max = (m.stats and m.stats.hp) or m.maxHp or 20
      -- HURT=<divisor>: the lead ends on max/divisor, 4 by default.  A divisor
      -- is what makes the HP-bar ramp testable -- green, yellow and red are
      -- chosen by how many PIXELS are filled, so one HP level only ever proves
      -- one colour.
      local div = math.max(1, tonumber(os.getenv("HURT")) or 4)
      m.hp = math.max(1, math.floor(max / div))
      print(("[hurt] lead at %d/%d"):format(m.hp, max))
    end
    -- HOLD=<item id>: give the lead a held item, and say what the cache thinks
    -- that item's hold effect IS -- a name or a bare number tells you at once
    -- whether the cache predates the Gen4HoldEffects stage.
    if os.getenv("HOLD") then
      local id = tonumber(os.getenv("HOLD")) or os.getenv("HOLD")
      Game.save.party[1].item = id
      local d = Data.items[id]
      print(("[hold] lead holds %s  holdEffect=%s param=%s"):format(
        tostring(d and d.name), tostring(d and d.holdEffect),
        tostring(d and (d.holdEffectParam or d.effectParam))))
    end
    -- TRAINER=<id>: a trainer battle against Data.trainers[id] instead.
    local battle
    if os.getenv("TRAINER") then
      battle = BattleState.newTrainer(Game, tonumber(os.getenv("TRAINER")), 1)
    else
      battle = BattleState.newWild(Game,
        tonumber(os.getenv("SPECIES") or "396"),
        tonumber(os.getenv("LEVEL") or "3"))
    end
    -- SAFARI=n: a Great Marsh battle with n Safari Balls left.
    if os.getenv("SAFARI") then
      Game.save.safari = { balls = tonumber(os.getenv("SAFARI")) or 30, steps = 0, caught = 0, gen4 = true }
      battle:makeSafari(Game.save.safari)
    end
    -- ENTER IT, which is where a battle loads its pictures.
    --
    -- The first version of this harness constructed a battle and drew it
    -- without ever calling `enter`, and `enter` is where `playerBackPic`,
    -- `showPlayerBack` and the rest of the screen's art are set up.  So every
    -- one of them read as absent, and a question asked of this harness about a
    -- picture would have been answered "missing" when the real game has it.
    -- A harness that skips a lifecycle step reports the step, not the engine.
    if battle.enter then pcall(battle.enter, battle) end
    -- WIN=1: every foe fainted at once and the faint path run, which is where
    -- a trainer battle pays out; prints the wallet and the lines queued.
    -- LOSE=1: the whole party fainted and the player's faint path run, which is
    -- where Platinum takes its money penalty; prints the wallet and the lines.
    if os.getenv("LOSE") then
      local before = Game.save.money or 0
      for _, mon in ipairs(Game.save.party or {}) do mon.hp = 0 end
      local okL, errL = pcall(battle.playerMonFainted, battle)
      if not okL then print("[lose] error: " .. tostring(errL)) end
      print(("[lose] money %d -> %d (-%d)"):format(before, Game.save.money or 0, before - (Game.save.money or 0)))
      for _, item in ipairs(battle.queue or {}) do
        if item.text then print("[lose] " .. tostring(item.text):gsub("\n", " / ")) end
      end
      love.event.quit()
      return
    end
    if os.getenv("WIN") then
      local before = Game.save.money or 0
      for _, mon in ipairs(battle.enemyParty or {}) do mon.hp = 0 end
      local okW, errW = pcall(battle.enemyMonFainted, battle)
      if not okW then print("[win] error: " .. tostring(errW)) end
      print(("[win] money %d -> %d (+%d)"):format(before, Game.save.money or 0, (Game.save.money or 0) - before))
      for _, item in ipairs(battle.queue or {}) do
        if item.text then print("[win] " .. tostring(item.text):gsub("\n", " / ")) end
      end
      love.event.quit()
      return
    end
    if not battle or battle.dead then
      print("no battle: " .. (battle and "dead" or "nil"))
      love.event.quit() return
    end
    -- A battler wraps its Pokemon as `.mon`; the level lives there and not on
    -- the battler, and printing `battler.level` gives a nil that reads like a
    -- broken battle rather than a broken log line.
    local function who(b)
      return ("%s (Lv%s)"):format(tostring(b and b.name),
                                  tostring(b and b.mon and b.mon.level))
    end
    print(("%s vs %s, gen4 layout: %s"):format(
      who(battle.player), who(battle.enemy), tostring(battle:gen4Layout())))

    -- Ticked rather than drawn cold, because the opening of a battle is a queue
    -- of messages and slides: frame zero is not what a player ever sees.
    -- SOMETHING HAS TO PRESS A.
    --
    -- `Game.input` is nil here -- nothing in this harness builds one -- and a
    -- battle opens on a queue of messages that each wait for the player.  With
    -- no input the queue stalls at 9 items, `showPlayerBack` never clears and
    -- the send-out never happens, so the screen never reaches most of what is
    -- worth looking at.
    --
    -- This cost a wrong reading before it was noticed: an earlier version of
    -- this loop pressed A behind `if Game.input then`, which with a nil input
    -- pressed nothing at all, and the stall was reported as if the presses had
    -- been tried and had not helped.  A guard that silently skips the thing the
    -- test is testing is worse than no test.
    --
    -- PRESS is the gap in frames between presses; 0 turns it off for a test
    -- that wants the battle to sit still.
    local press = tonumber(os.getenv("PRESS") or "20")
    local pressed = false
    Game.input = {
      wasPressed = function(_, k) return pressed and (k == "a") end,
      isDown = function() return false end,
      wasReleased = function() return false end,
    }

    -- MSGTRACE: every message the box actually starts typing, in order.
    -- Taken at `startMessage` so it is the text the PLAYER sees rather than
    -- whatever a caller passed -- and printed with the newlines shown, because
    -- a battle line that reads "TURTWIG's / 0!" is two lines and the fault is
    -- in the second one.
    if os.getenv("MSGTRACE") then
      local orig = battle.startMessage
      battle.startMessage = function(selfB, item)
        local t = tostring(item and item.text)
        print("[msg] " .. (t:gsub("\n", " / "):gsub("\v", " <CONT> ")))
        return orig(selfB, item)
      end
    end
    -- MOVES / ABIL: what each side actually brought.  Both exist because the
    -- same class of bug has shipped four times -- an id where the engine wants
    -- a NAME -- and it is invisible in a screenshot: a move with `type=0` and
    -- an ability that prints as `22` both look like nothing at all happening.
    if os.getenv("MOVES") or os.getenv("ABIL") then
      local Abilities = require("src.battle.Abilities")
      for _, side in ipairs({ "player", "enemy" }) do
        local b = battle[side]
        if os.getenv("MOVES") then
          local names = {}
          for _, m in ipairs((b and b.mon and b.mon.moves) or {}) do
            local d = Data.moves[m.id or m]
            names[#names + 1] = ("%s(pow=%s type=%s eff=%s)"):format(
              tostring(d and d.name), tostring(d and d.power),
              tostring(d and d.type), tostring(d and d.effect))
          end
          print(("[moves] %-6s %s: %s"):format(side, tostring(b and b.name),
            table.concat(names, ", ")))
        end
        if os.getenv("ABIL") then
          local got = Abilities.of(b)
          print(("[abil] %-6s %-10s abilities={%s} -> of()=%s (%s)"):format(
            side, tostring(b and b.name),
            table.concat((b.def and b.def.abilities) or {}, ", "),
            tostring(got), type(got)))
        end
      end
    end
    -- MOVEGRID: the WHOLE transition table of the move cursor, every direction
    -- from every cell, against the 2x2 the screen actually draws.  A single
    -- press proves one arrow; the reported fault ("down moves the cursor
    -- right") is only visible as a TABLE.
    if os.getenv("MOVEGRID") then
      local n = tonumber(os.getenv("MOVEGRID")) or 4
      local dirs = { "up", "down", "left", "right" }
      local held
      local stub = { wasPressed = function(_, k) return k == held end,
                     isDown = function() return false end,
                     wasReleased = function() return false end }
      print(("[grid] %d moves, drawn as 2 across:"):format(n))
      print("        from   up    down  left  right")
      for i = 1, n do
        local row = {}
        for _, d in ipairs(dirs) do
          held = d
          local got = battle:moveGridNavigate(i, n, stub)
          row[#row + 1] = ("%-5s"):format(tostring(got))
        end
        print(("        %-6d %s"):format(i, table.concat(row, " ")))
      end
    end
    local ticks = tonumber(os.getenv("TICKS") or "30")
    for i = 1, ticks do
      pressed = press > 0 and (i % press == 0)
      local okU, errU = pcall(battle.update, battle, 1 / 60)
      if not okU then
        print(("update raised on tick %d: %s"):format(i, tostring(errU)))
        break
      end
      -- A PER-TICK TRACE, because two faults this harness was built to find
      -- were only visible as a SEQUENCE and not in any single frame: a Pokemon
      -- revealed sixty ticks before its own send-out, and one frame in which
      -- the ball existed but had not yet hidden the Pokemon it was carrying.
      -- Neither shows up in a screenshot you happen to take.
      if os.getenv("TRACE") then
        local b = battle.gen4Ball
        local ph = b and b:phaseAt(math.min(b.t, b.total - 1))
        print(("t=%d back=%s queue=%d phase=%s | ball=%s"):format(
          i, tostring(battle.showPlayerBack), #(battle.queue or {}),
          tostring(battle.phase),
          b and ("%s (%.0f,%.0f) cell=%s scale=%.2f hidden=%s"):format(
            tostring(ph and ph.kind), b.x or -1, b.y or -1, tostring(b.cell),
            b.monScale or -1, tostring(b.monHidden)) or "none"))
        -- the gates updateQueue waits on, in its own order
        print(("    gates: ui=%s anim4=%s wait=%s sound=%s drain=%s anim=%s current=%s intro=%s"):format(
          tostring(battle.waitingUI), tostring(battle.gen4AnimPlaying), tostring(battle.waitFrames),
          tostring(battle.waitingSound), tostring(battle.draining), tostring(battle.animPlaying),
          tostring(battle.current and (battle.current.text or battle.current.kind or "item")),
          tostring(battle.introSlide)))
      end
    end

    -- WHERE THE HP ENDED, which is the only thing that settles a healing test.
    -- A message saying an item fired is not the same claim as the number
    -- moving, and the two have disagreed here before.
    if os.getenv("MOVES") or os.getenv("HURT") then
      print(("[hp] after %d ticks: player %s/%s  enemy %s/%s"):format(ticks,
        tostring(battle.player.mon.hp), tostring(battle.player.mon.stats.hp),
        tostring(battle.enemy.mon.hp), tostring(battle.enemy.mon.stats.hp)))
    end
    -- PHASE / MOVEINDEX / DRAINPP: open a menu for the picture -- the move list
    -- has no other way to be looked at headless. DRAINPP=n spends each move's
    -- PP down by n*slot so the four PP colours (`GetPPTextColor`) all show.
    -- SINGLE=1: the single-screen presentation (the compact strip), as a
    -- player with the second screen turned off sees it.
    if os.getenv("SINGLE") then
      local okS, SS = pcall(require, "src.ui.SecondScreen")
      if okS and SS then SS.mode = function() return "off" end end
    end
    if os.getenv("PHASE") then
      battle.phase = os.getenv("PHASE")
      battle.moveIndex = tonumber(os.getenv("MOVEINDEX") or "1")
      local drain = tonumber(os.getenv("DRAINPP") or "0")
      if drain > 0 and battle.player and battle.player.curMoves then
        for i, mv in ipairs(battle.player.curMoves) do
          mv.pp = math.max(0, (mv.pp or 0) - drain * i)
        end
      end
    end
    local canvas = love.graphics.newCanvas(W, H)
    love.graphics.setCanvas(canvas)
    love.graphics.clear(0, 0, 0, 1)
    local okD, errD = pcall(battle.draw, battle)
    love.graphics.setCanvas()
    if not okD then print("draw raised: " .. tostring(errD)) end
    canvas:newImageData():encode("png", ("battle_%s.png"):format(TAG))
    print("wrote battle_" .. TAG .. ".png")
  end, debug.traceback)
  if not ok then print("FAILED:\n" .. tostring(err)) end
  love.event.quit()
end

function love.draw() end
