-- tools/trailer/minigames.lua -- TRAILER FOOTAGE of the minigames, recorded
-- from the real game (a POKEPORT_DRIVER script, like capture.lua).
--
-- Each shot pushes the minigame's own screen over the overworld, plays it
-- (a small bot presses what a player would) and streams it into
-- <OUT>/minigame_<name>.mp4 through tools/trailer/recorder.lua:
--
--   pokeathlon  HeartGold / SoulSilver   Goal Roll (HgssPokeathlonGoalRoll)
--   musical     Black / White            the Musical's stage (Gen5MusicalStage)
--   contest     Platinum                 a Super Contest's Dance (Gen4ContestScreen)
--   slots       Platinum                 the Game Corner slots (PtSlotMachineApp)
--
-- A run records the shots its game has:
--
--   powershell -ExecutionPolicy Bypass -File tools/trailer/capture_all.ps1 `
--     -Identity trailer2_cap -ImportRom -Driver tools/trailer/minigames.lua `
--     -SnapshotDir G:\Gen2Recomped\scratch_claude\playthrough -Versions heartgold,black,platinum
--
-- Env: OUT (required), FFMPEG, CRF, ONLY (comma list of the names above),
-- SNAPSHOT_DIR / SNAPSHOT (a playthrough save for the party; capture.lua).

return function(game)
  local U = dofile("tests/drivers/util.lua")
  local OUT = assert(os.getenv("OUT"), "set OUT to the footage folder")
  local Rec = dofile("tools/trailer/recorder.lua")({
    out = OUT, ffmpeg = os.getenv("FFMPEG") or "ffmpeg", crf = os.getenv("CRF") or "14" })
  local ONLY = {}
  for name in (os.getenv("ONLY") or ""):gmatch("[^,]+") do ONLY[name] = true end
  local version = require("src.core.GameVersion").get()
  pcall(love.window.setMode, 1920, 1080, { resizable = true, vsync = 0 })
  U.wait(10)

  -- the party: a playthrough snapshot's, when one is given
  local family = ({ heartgold = "heartgold", soulsilver = "heartgold", black = "black",
                    white = "black", platinum = "platinum" })[version]
  local file = os.getenv("SNAPSHOT")
  local dir = os.getenv("SNAPSHOT_DIR")
  if (not file or file == "") and dir and dir ~= "" and family then
    for n = 200, 1, -1 do
      local p = ("%s/%s_%d.lua"):format(dir:gsub("\\", "/"), family, n)
      local f = io.open(p, "rb")
      if f then f:close(); file = p; break end
    end
  end
  local kept = game.save and game.save.options
  local okL, snap = pcall(dofile, file or "")
  local okD, save = false, nil
  if okL and type(snap) == "table" then okD, save = pcall(require("src.core.SaveData").decode, snap.save) end
  if okD and type(save) == "table" then
    game.save = save
    game.save.version = version
    U.log("save from snapshot " .. file)
  else
    U.freshSave(game)
  end
  if kept then game.save.options = kept end
  game.save.options.secondScreenMode = "off"
  pcall(function() game:applyOptions() end)
  require("src.world.OverworldController").rollEncounter = function() return nil end

  local Pokemon = require("src.pokemon.Pokemon")
  local function speciesByName(name)
    for id, def in pairs(game.data.pokemon or {}) do
      if type(def) == "table" and type(def.name) == "string" and def.name:upper() == name then return id end
    end
  end
  local function party(n, names)
    local out = {}
    for _, m in ipairs(game.save.party or {}) do
      if not m.isEgg and #out < n then out[#out + 1] = m end
    end
    for _, name in ipairs(names) do
      if #out >= n then break end
      local id = speciesByName(name)
      if id then out[#out + 1] = Pokemon.new(game.data, id, 30) end
    end
    return out
  end
  if #(game.save.party or {}) == 0 then game.save.party = party(3, { "PIKACHU", "MARILL", "EEVEE" }) end

  -- a backdrop the screen is pushed over
  local home = ({ heartgold = "T25", soulsilver = "T25", black = "Z062", white = "Z062", platinum = "C05" })[version]
  if home then U.teleport(game, home, 10, 10, "down"); U.wait(30) end

  local function press(btn) table.insert(game.input.pressQueue, btn) end
  local function release() for k in pairs(game.input.state) do game.input.state[k] = false end end
  -- n frames; `each(f)` before each; recording into <name> when given
  local function run(n, name, each)
    if name then Rec.start(name) end
    for f = 1, n do
      if each then each(f) end
      Rec.frame()
      coroutine.yield()
      release()
    end
    if name then Rec.stop() end
  end
  local function unwind()
    Rec.stop()
    while game.stack:top() and game.stack:top() ~= game.overworld do game.stack:pop() end
    U.wait(10)
  end

  local SHOTS = {}
  local function shot(name, fn) SHOTS[#SHOTS + 1] = { name = name, fn = fn } end

  if version == "heartgold" or version == "soulsilver" then
    -- GOAL ROLL: four teams of three on one field, two balls; the player's
    -- team is steered by the bot the event's test kit used (drag a Pokemon
    -- behind the ball, or flick it through)
    shot("pokeathlon", function()
      local E = require("src.ui.HgssPokeathlonGoalRoll")
      if not E.available(game) then U.log("goal roll art missing"); return end
      local rivals = {
        { { species = 19 }, { species = 16 }, { species = 21 } },
        { { species = 52 }, { species = 133 }, { species = 39 } },
        { { species = 74 }, { species = 95 }, { species = 143 } },
      }
      local gr = E.new(game, { team = party(3, { "PIKACHU", "MARILL", "EEVEE" }), rivals = rivals, onDone = function() end })
      game.stack:push(gr)
      local plan, t = nil, 0
      local function bot()
        t = t + 1
        if gr.countdown > 0 or gr.over then return end
        local me = gr.teams[1]
        local phase = t % 24
        if phase == 0 then
          local best, bm, bb
          for _, ball in ipairs(gr.balls) do
            if ball.kind ~= 0 and ball.state ~= 1 then
              for k, mp in ipairs(me.members) do
                local dd = (mp.x - ball.x) ^ 2 + (mp.y - ball.y) ^ 2
                if mp.state ~= 2 and mp.knock == 0 and (not best or dd < best) then best, bm, bb = dd, k, ball end
              end
            end
          end
          if bm then
            local mp = me.members[bm]
            local gx, gy = 236, 172
            local ax, ay = bb.x - gx, bb.y - gy
            local n = math.sqrt(ax * ax + ay * ay)
            if n < 1 then n = 1 end
            local bx, by = bb.x + ax / n * 14, bb.y + ay / n * 14
            local dx, dy = mp.x - bx, mp.y - by
            plan = { flick = (dx * dx + dy * dy) < 18 * 18 and mp.state == 0, tx = bx, ty = by, ball = bb, gx = gx, gy = gy }
            gr.touch = { x = mp.x, y = mp.y, down = true }
          end
        elseif plan and gr.touch then
          if plan.flick then
            if phase == 2 then gr.touch.x, gr.touch.y = plan.ball.x + (plan.gx - plan.ball.x) * 0.3, plan.ball.y + (plan.gy - plan.ball.y) * 0.3 end
            if phase == 6 then gr.touch.down = false end
          else
            if phase < 20 then gr.touch.x, gr.touch.y = plan.tx, plan.ty else gr.touch.down = false end
          end
        end
      end
      -- through the 3-2-1, then the play
      while gr.countdown > 100 do bot(); coroutine.yield() end
      run(360, "minigame_pokeathlon", bot)
      unwind()
    end)
  end

  if version == "black" or version == "white" then
    -- THE MUSICAL: the show's program and lineup as 0x167 makes them, the
    -- player's Pokemon in a few props, scored, on stage
    shot("musical", function()
      local M = require("src.script.Gen5Musical")
      local St = require("src.ui.Gen5MusicalStage")
      local mon = party(1, { "PIKACHU" })[1]
      local prog = M.program(game.data, 0, 0)
      if not (prog and mon) then U.log("no musical program"); return end
      local performers = M.performers(game.data, prog, mon, {})
      -- the player wears what the first NPC wears (props they own anyway)
      local npc = performers[2]
      if npc then
        local outfit = {}
        for slot, item in pairs(npc.props or {}) do outfit[slot] = { id = item.id } end
        performers[1].props = outfit
      end
      local ordered = { performers[2], performers[1], performers[3], performers[4] }
      M.score(game.data, prog, ordered)
      local st = St.new(game, { prog = prog, performers = ordered, onDone = function() end })
      game.stack:push(st)
      run(90)
      run(420, "minigame_musical", function(f) if f % 70 == 35 then press("a") end end)
      unwind()
    end)
  end

  if version == "platinum" then
    -- A SUPER CONTEST'S DANCE: the Dance practice (competition 5), the player's lead Pokemon against three of the rank's entrants;
    -- the bot dances on the beat
    shot("contest", function()
      local C = require("src.pokemon.Gen4Contest")
      local mon = party(1, { "PIKACHU" })[1]
      local c = C.new({ data = game.data, rank = 0, type = 0, competition = C.PRACTICE_DANCE, partySlot = 0, mon = mon,
        playerName = game.save.player and game.save.player.name, playerGender = 0, postgame = false,
        seed = 1234 })
      game.gen4Contest = c
      local Screen = require("src.ui.Gen4ContestScreen")
      local screen = Screen.new(game, c, function() end)
      game.stack:push(screen)
      -- through the introductions to the stage (the round is the screen's
      -- own `dance`, Gen4ContestDance)
      for f = 1, 3000 do
        if game.stack:top() ~= screen then U.log("contest screen closed early"); break end
        if screen.dance and screen.dance.mode ~= "intro" then break end
        if f % 20 == 0 then press("a") end
        coroutine.yield()
        release()
      end
      local keys = { "up", "down", "left", "right" }
      run(420, "minigame_contest", function(f) if f % 30 == 0 then press(keys[(f / 30) % 4 + 1]) end end)
      unwind()
    end)

    -- THE SLOTS: bet (X), spin (down), stop the reels left to right (Y, B, A)
    shot("slots", function()
      local S = require("src.ui.PtSlotMachineApp")
      if not S.available(game) then U.log("slot art missing"); return end
      local app = S.new(game, { machine = 0, setting = 6, coins = 900 }, function() end)
      local appUpdate = app.update
      app.update = function(self, ...)
        local r = appUpdate(self, ...)
        self.inset = false
        return r
      end
      game.stack:push(app)
      run(150)
      -- (Y also reads as SELECT, which flips the one-screen inset: keep the
      -- cabinet full-size)
      local cycle = { [1] = "x", [12] = "down", [70] = "y", [92] = "b", [114] = "a" }
      run(450, "minigame_slots", function(f)
        app.inset = false
        local k = cycle[(f - 1) % 160 + 1]
        if k then press(k) end
      end)
      unwind()
    end)
  end

  for _, s in ipairs(SHOTS) do
    if next(ONLY) == nil or ONLY[s.name] then
      local ok, err = pcall(s.fn)
      if not ok then U.log("shot " .. s.name .. " failed: " .. tostring(err)); unwind() end
    end
  end
  U.wait(4)
  Rec.finish()
  U.log("done")
  love.event.quit()
end
