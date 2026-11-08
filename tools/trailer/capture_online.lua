-- tools/trailer/capture_online.lua -- ONLINE TRAILER FOOTAGE, recorded from
-- the real game (a POKEPORT_DRIVER script, like capture.lua).
--
-- This process is the recording client: the player's own view. The friends
-- around it are tools/trailer/online_peer processes on 127.0.0.1, started by
-- tools/trailer/capture_online.py, which also cuts the final clips. Nothing
-- leaves loopback: worlds are direct codes on 127.0.0.1, no router mapping,
-- no STUN, no LAN beacon, no relay.
--
-- One run records ONE shot (SHOT env) as a raw take:
--   <RUN>/raw.mp4          every other frame of the whole interaction, 30 fps
--   <RUN>/events.txt       "<raw frame> <event>" markers the cutter keys off
--
-- Shots: world | room | trade | battle | gts | multi
--
-- Env: SHOT, RUN (flag/scratch folder), FFMPEG, CRF (default 12),
--      WIDTH/HEIGHT (1920x1080), PEERS (how many peers to wait for).
--
-- Talks to the peers through files in RUN (see online_peer/main.lua).

return function(game)
  function love.errorhandler(msg)
    print("DRIVER ERROR: " .. tostring(msg))
    print(debug.traceback())
    os.exit(1)
  end
  love.errhand = love.errorhandler
  local U = dofile("tests/drivers/util.lua")
  local SHOT = assert(os.getenv("SHOT"), "SHOT")
  local RUN = assert(os.getenv("RUN"), "RUN"):gsub("\\", "/") .. "/"
  local PEERS = tonumber(os.getenv("PEERS") or "3") or 3
  local FFMPEG = os.getenv("FFMPEG") or "ffmpeg"
  local CRF = os.getenv("CRF") or "12"
  local W, H = tonumber(os.getenv("WIDTH") or "1920"), tonumber(os.getenv("HEIGHT") or "1080")
  local version = require("src.core.GameVersion").get()
  local Pokemon = require("src.pokemon.Pokemon")
  local function log(...) U.log(SHOT, ...) end

  pcall(love.window.setMode, W, H, { resizable = false, vsync = 0 })
  U.wait(10)

  -- ------------------------------------------------------------ clocks
  -- REAL-TIME PACING: the peers run on the wall clock, so this one must
  -- too (a driver run is otherwise unpaced). THE FRAME CLOCK: one 1/60 per
  -- logic step, so the footage animates evenly if a frame runs long.
  local realGetTime = love.timer.getTime
  local clock = realGetTime()
  local realUpdate = love.update
  love.update = function(dt) clock = clock + 1 / 60; return realUpdate(dt) end
  love.timer.getTime = function() return clock end
  local paceStart, paceFrames, behind = realGetTime(), 0, 0
  local lastFpsAt
  -- THE HOUR: Platinum's light follows the clock; the shots are at noon
  local realDate = os.date
  os.date = function(fmt, t)
    if fmt == "%H" then return "12" end
    if fmt == "*t" or fmt == "!*t" then local r = realDate(fmt, t); r.hour = 12; return r end
    return realDate(fmt, t)
  end

  -- ------------------------------------------------------------ the writer
  local WRITER = [[
    local ch, ffmpeg, crf, fps = ...
    require("love.image")
    local pipe, current
    local function close()
      if pipe then pipe:close(); pipe = nil end
      current = nil
    end
    while true do
      local job = ch:demand()
      if job == "stop" then close(); return end
      if job.path ~= current then
        close()
        local w, h = job.img:getDimensions()
        local cmd = ('"%s" -y -loglevel error -f rawvideo -pix_fmt rgba -s %dx%d -r %d -i - '
          .. '-c:v libx264 -preset veryfast -crf %s -pix_fmt yuv420p "%s"')
          :format(ffmpeg, w, h, fps, crf, job.path)
        if package.config:sub(1, 1) == "\\" then cmd = '"' .. cmd .. '"' end
        pipe = io.popen(cmd, "wb")
        current = job.path
      end
      if pipe then pipe:write(job.img:getString()) end
      job.img:release()
    end
  ]]
  local queue = love.thread.getChannel("trailer_online_frames")
  local writer = love.thread.newThread(WRITER)
  writer:start(queue, FFMPEG, CRF, 30)
  local recording, rawFrames, f = false, 0, 0
  local events = assert(io.open(RUN .. "events.txt", "w"))
  local function event(name)
    events:write(("%d %s\n"):format(rawFrames, name)); events:flush()
    log("event", name, rawFrames)
  end

  -- one logic frame: capture (every 2nd), yield, then hold to real time
  local function frame()
    f = f + 1
    if recording and f % 2 == 0 then
      rawFrames = rawFrames + 1
      while queue:getCount() > 24 do
        local e = writer:getError()
        if e then error("frame writer: " .. tostring(e)) end
        love.timer.sleep(0.004)
      end
      love.graphics.captureScreenshot(function(img) queue:push({ path = RUN .. "raw.mp4", img = img }) end)
    end
    coroutine.yield()
    paceFrames = paceFrames + 1
    -- the peers follow this clock (online_peer paces to RUN/clock)
    local ch = io.open(RUN .. "clock", "w")
    if ch then ch:write(tostring(paceFrames)) ch:close() end
    local due = paceStart + paceFrames / 60
    local now = realGetTime()
    if due > now then love.timer.sleep(due - now)
    elseif now - due > 0.05 then behind = behind + 1 end
    if paceFrames % 300 == 0 then
      local fps = 300 / math.max(0.001, now - (lastFpsAt or now - 5))
      lastFpsAt = now
      log("fps", ("%.1f"):format(fps), recording and "rec" or "")
    end
  end
  local function wait(n) for _ = 1, n do frame() end end
  local function waitUntil(fn, n, what)
    for _ = 1, n or 1800 do
      if fn() then return true end
      frame()
    end
    error("timed out waiting for " .. tostring(what))
  end
  local function tap(btn)
    table.insert(game.input.pressQueue, btn)
    frame()
    game.input.state[btn] = false
  end
  local function holdStep(dir)
    local p = game.overworld.player
    local x0, y0 = p.cellX, p.cellY
    for _ = 1, 40 do
      table.insert(game.input.pressQueue, dir)
      game.input.state[dir] = true
      frame()
      if p.cellX ~= x0 or p.cellY ~= y0 then break end
    end
    game.input.state[dir] = false
    for _ = 1, 40 do if not p.moving then break end frame() end
  end
  local function face(dir)
    local p = game.overworld.player
    if p.facing == dir then return end
    table.insert(game.input.pressQueue, dir)
    game.input.state[dir] = true
    frame(); frame()
    game.input.state[dir] = false
    wait(8)
  end

  -- ------------------------------------------------------------ flags
  local function mark(name, text)
    local tmp = RUN .. name .. ".tmp"
    local fh = assert(io.open(tmp, "w")) fh:write(text or "1") fh:close()
    os.remove(RUN .. name)
    os.rename(tmp, RUN .. name)
  end
  local function readFlag(name)
    local fh = io.open(RUN .. name, "r")
    if not fh then return nil end
    local s = fh:read("*a") fh:close()
    return s
  end
  local NAMES = { "ALICE", "BOB", "CAROL" }
  local function peersFlagged(suffix, n)
    local k = 0
    for i = 1, #NAMES do if readFlag(NAMES[i] .. suffix) then k = k + 1 end end
    return k >= (n or PEERS)
  end

  -- ------------------------------------------------------------ state names
  local function nameOf(st)
    if not st then return "nil" end
    local mt = getmetatable(st)
    for name, mod in pairs(package.loaded) do
      if type(name) == "string" and name:match("^src%.") and (mt == mod or st == mod) then
        return (name:gsub("^src%.", ""))
      end
    end
    return tostring(st.kind or st.stage or "?")
  end
  local lastTop
  local function watchTop()
    local t = game.stack:top()
    local label = nameOf(t) .. ":" .. tostring(t and (t.stage or t.kind or t.phase) or "")
    if label ~= lastTop then lastTop = label event("top " .. label) end
  end

  -- ------------------------------------------------------------ the save
  game.writeSave = function() end
  game.writeOptions = function() end
  local kept = game.save and game.save.options
  U.freshSave(game)
  if kept then game.save.options = kept end
  game.save.options.zoom = 0
  pcall(function() require("src.render.Zoom").offset = 0 end)
  game.save.player.name = (version == "black" or version == "white") and "HILBERT" or "LUCAS"
  game.save.player.id = 12345
  game.save.player.gender = "boy"
  game.save.options.online = { portMap = false, stun = false, lanBeacon = false, allowRelay = false,
                               bind = "127.0.0.1", lanIp = "127.0.0.1", port = 47900,
                               timeouts = { lan = 4 }, worldCap = 8 }
  game.save.options.secondScreenMode = "off"
  -- battles as wide as the 16:9 frame (Platinum's DS compositor on a wider
  -- surface), filling the height
  game.save.options.battleLayout = "wide"
  game.save.options.battleFit = "fill"
  pcall(function() game:applyOptions() end)
  if version == "platinum" then
    pcall(function()
      local Gen4Camera = require("src.render.Gen4Camera")
      game.save.options.gen4CameraTilt = 1
      Gen4Camera.setTilt(1)
    end)
  end
  local function speciesByName(name)
    for id, def in pairs(game.data.pokemon or {}) do
      if type(def) == "table" and type(def.name) == "string" and def.name:upper() == name then return id end
    end
    return nil
  end
  local bw = version == "black" or version == "white"
  local partyNames = bw and { "SERPERIOR", "SAMUROTT", "EMBOAR" } or { "INFERNAPE", "EMPOLEON", "TORTERRA" }
  game.save.party = {}
  for _, n in ipairs(partyNames) do
    local id = speciesByName(n)
    if id then game.save.party[#game.save.party + 1] = Pokemon.new(game.data, id, 50) end
  end
  -- seen: the starters and the friends' Pokemon (the GTS lists seen ones)
  game.save.pokedex = game.save.pokedex or {}
  game.save.pokedex.seen = game.save.pokedex.seen or {}
  for _, n in ipairs({ "TURTWIG", "CHIMCHAR", "PIPLUP", "LUCARIO", "GARCHOMP", "PACHIRISU",
                       "SNIVY", "TEPIG", "OSHAWOTT", "ZOROARK", "HAXORUS", "VOLCARONA" }) do
    local id = speciesByName(n)
    if id then game.save.pokedex.seen[id] = true end
  end

  -- ------------------------------------------------------------ places
  local function walkable(map, x, y)
    return map:inBounds(x, y) and map:isWalkableCell(x, y)
  end
  -- the cell near (cx, cy) with the most walkable ground in the box around
  -- it (x -bx..bx, y -by0..by1)
  local function openSpot(map, cx, cy, bx, by0, by1, radius)
    local best, bestN
    for dy = -radius, radius do
      for dx = -radius, radius do
        local x, y = cx + dx, cy + dy
        if walkable(map, x, y) then
          local n = 0
          for yy = y - by0, y + by1 do
            for xx = x - bx, x + bx do
              if walkable(map, xx, yy) then n = n + 1 end
            end
          end
          n = n - (math.abs(dx) + math.abs(dy)) * 0.05
          if not bestN or n > bestN then best, bestN = { x, y }, n end
        end
      end
    end
    return best[1], best[2], bestN
  end
  local function goTo(mapId, x, y, facing)
    U.teleport(game, mapId, x, y, facing or "down")
    wait(30)
  end
  local function place(mapId, x, y, bx, by0, by1, radius)
    local m = game.data.maps[mapId]
    assert(m, "no map " .. tostring(mapId))
    x = x or math.floor((m.width or 32) / 2)
    y = y or math.floor((m.height or 32) / 2)
    goTo(mapId, x, y)
    local sx, sy, n = openSpot(game.overworld.map, x, y, bx, by0, by1, radius or 12)
    log("spot", mapId, sx, sy, n)
    goTo(mapId, sx, sy, "down")
    return sx, sy
  end

  -- ------------------------------------------------------------ the world
  local OnlineWorld = require("src.online.world.OnlineWorld")
  local function hostWorld(name)
    local WorldStore = require("src.online.world.WorldStore")
    OnlineWorld.hostWorld(game, { name = name, cap = 8,
      connector = { port = 47900, portMap = false, stun = false, lanBeacon = false, lanIp = "127.0.0.1",
                    bind = "127.0.0.1", portRetries = 3, allowRelay = false, hub = false },
      store = WorldStore.new() })
    local code
    waitUntil(function() code = OnlineWorld.inviteCode() return code ~= nil end, 600, "world code")
    log("world code", code)
    mark("code", code)
  end
  local function waitPeers(n)
    waitUntil(function()
      local s = OnlineWorld.current()
      return s and s.host and s.host:count() >= n + 1 and peersFlagged("_in", n)
    end, 60 * 120, "peers")
    log("peers in", n)
  end
  local function ghostCount()
    local P = require("src.online.world.Presence")
    local n = 0
    for _ in pairs(P.ghosts) do n = n + 1 end
    return n
  end
  local function say(text)
    local c = OnlineWorld.client()
    if c then c:say(text) end
  end

  -- a battle bot for the recorder: damaging moves, A through text
  local function findBattle()
    local states = game.stack.states or {}
    for i = #states, 1, -1 do
      local st = states[i]
      if type(st) == "table" and st.phase and st.activeBattlers then return st end
    end
    return nil
  end
  local rng = love.math.newRandomGenerator(7)
  local function battleStep(b)
    if b.phase == "menu" then
      b.menuIndex = 1
      tap("a")
    elseif b.phase == "moveSelect" then
      local who = b.menuBattler and b:menuBattler()
      if who and who.curMoves then
        local ok = {}
        for i, mv in ipairs(who.curMoves) do
          local d = game.data.moves[mv.id]
          if (mv.pp or 0) > 0 and d and (d.power or 0) > 0 then ok[#ok + 1] = i end
        end
        if #ok > 0 then b.moveIndex = ok[rng:random(#ok)] end
      end
      wait(20)
      tap("a")
    elseif b.phase == "targetSelect" then
      tap("a")
    elseif b.phase ~= "waitRemote" then
      tap("a")
    else
      frame()
    end
  end

  -- ------------------------------------------------------------ shots
  local SHOTS = {}

  -- friends walking around you in Jubilife, chatting
  local function wander(mapId, x, y, worldName, lines, frames, o)
    o = o or {}
    local sx, sy = place(mapId, x, y, o.bx or 6, o.by0 or 4, o.by1 or 2, o.radius or 14)
    mark("offsets", table.concat(o.offsets or { "ALICE -3 0 right", "BOB 3 0 left", "CAROL 0 -3 down" }, "\n"))
    mark("lanes", table.concat(o.lanes or { "ALICE -6 -2 -1 2", "BOB 2 6 -1 2", "CAROL -1 1 -4 -2" }, "\n"))
    hostWorld(worldName)
    mark("spot", ("%s %d %d"):format(mapId, sx, sy))
    waitPeers(PEERS)
    waitUntil(function() return ghostCount() >= PEERS end, 600, "ghosts")
    wait(90)
    recording = true
    event("rec")
    mark("go")
    event("go")
    local t0 = f
    local li = 1
    while f - t0 < frames do
      watchTop()
      local t = f - t0
      if lines[li] and t >= lines[li][1] then
        local l = lines[li]
        if l[2] == "say" then say(l[3])
        elseif l[2] == "emote" then local c = OnlineWorld.client() if c then c:emote(l[3]) end
        elseif l[2] == "step" then holdStep(l[3])
        elseif l[2] == "face" then face(l[3]) end
        li = li + 1
      else
        frame()
      end
    end
    event("end")
    mark("stop")
  end

  SHOTS.world = function()
    local map = bw and "Z089" or "C01"
    wander(map, nil, nil, "FRIENDS", {
      { 90, "say", "Welcome!" }, { 200, "face", "left" }, { 330, "face", "right" },
      { 420, "emote", "heart" }, { 480, "face", "down" },
    }, 60 * 12)
  end
  -- the Pokemon Center's link floor (ROOM_MAP / ROOM_XY pick another room)
  SHOTS.room = function()
    local map = os.getenv("ROOM_MAP") or "C01PC0102"
    local rx, ry = (os.getenv("ROOM_XY") or "8,7"):match("(%d+),(%d+)")
    wander(map, tonumber(rx), tonumber(ry), "LINK ROOM", {
      { 120, "face", "left" }, { 300, "say", "Hi!" }, { 360, "face", "right" },
      { 480, "face", "down" },
    }, 60 * 12, { bx = 4, by0 = 3, by1 = 2, radius = 5,
                  offsets = { "ALICE -4 0 right", "BOB 4 0 left", "CAROL 0 -3 down" },
                  lanes = { "ALICE -5 -3 -2 1", "BOB 3 5 -2 1", "CAROL -2 2 -4 -3" } })
  end

  -- walk up to BOB, press A: TRADE or BATTLE; the link screens by bot
  local function linkShot(mode, maxFrames)
    local sx, sy = place(bw and "Z089" or "C01", nil, nil, 3, 2, 2, 14)
    mark("offsets", "BOB 2 0 left")
    hostWorld("FRIENDS")
    mark("spot", ("%s %d %d"):format(game.overworld.map.id, sx, sy))
    waitPeers(1)
    waitUntil(function() return ghostCount() >= 1 end, 600, "ghost")
    wait(60)
    recording = true
    event("rec")
    face("right")
    wait(30)
    holdStep("right")   -- BOB is two to the right: one step, then A
    face("right")
    wait(20)
    event("press_a")
    tap("a")
    wait(30)
    watchTop()
    local t = game.stack:top()
    if t and t.kind == "ask" then
      if mode == "battle" then wait(20) tap("down") end
      wait(25)
      tap("a")
    else
      log("no ask window: " .. nameOf(t))
    end
    local t0 = f
    local battleSeen, done = false, false
    while f - t0 < maxFrames and not done do
      watchTop()
      local b = findBattle()
      local top = game.stack:top()
      if b and not battleSeen then battleSeen = true event("battle") end
      if b and top == b then
        battleStep(b)
        if b.result then event("battle_result " .. tostring(b.result)) end
      elseif b and b.linkPickReplacement and b.linkRoundOpen and top ~= b then
        for i = 1, #game.save.party do
          local m = game.save.party[i]
          if m.hp > 0 then b.linkPickReplacement(m) break end
        end
        wait(20)
      elseif top and top.stage == "battleOptions" then
        -- the host's BATTLE RULES: up wraps to START (default single rules)
        wait(30)
        tap("up")
        wait(30)
        tap("a")
      elseif top ~= game.overworld then
        wait(16)
        tap("a")
      else
        if (battleSeen or mode == "trade") and f - t0 > 600 then done = true end
        frame()
      end
    end
    event("end")
    mark("stop")
  end
  SHOTS.trade = function() linkShot("trade", 60 * 150) end
  SHOTS.battle = function() linkShot("battle", 60 * 240) end

  -- the GTS: deposit, then seek a friend's Pokemon
  SHOTS.gts = function()
    local sx, sy = place(bw and "Z089" or "C01", nil, nil, 3, 2, 2, 14)
    mark("offsets", "ALICE -2 0 right\nBOB 2 0 left\nCAROL 0 -2 down")
    hostWorld("FRIENDS")
    mark("spot", ("%s %d %d"):format(game.overworld.map.id, sx, sy))
    waitPeers(PEERS)
    waitUntil(function() return peersFlagged("_in_gts", PEERS) end, 60 * 60, "deposits")
    OnlineWorld.syncGtsProvider()
    local GtsClient = require("src.online.gts.GtsClient")
    local scr = GtsClient.open(game, {})
    waitUntil(function() return scr.client and scr.client.state == "ready" and scr:top() and scr:top().kind == "list" end,
      600, "gts menu")
    wait(20)
    recording = true
    event("rec")
    local function pickLabel(label, pause)
      local v = scr:top()
      for _ = 1, 40 do
        v = scr:top()
        if v and v.kind == "list" then break end
        frame()
      end
      local want
      for i, r in ipairs(v.rows or {}) do
        if tostring(r.label):upper():find(label, 1, true) then want = i break end
      end
      if not want then log("no row " .. label) want = 1 end
      while v.index ~= want do
        wait(pause or 12)
        tap(v.index < want and "down" or "up")
      end
      wait(pause or 18)
      tap("a")
      wait(10)
    end
    wait(30)
    event("deposit")
    pickLabel("DEPOSIT")
    pickLabel("TORTERRA")
    pickLabel("GARCHOMP", 8)
    local v = scr:top()
    if v and v.title == "WHAT DO YOU WANT?" and v.header == "Choose the gender." then pickLabel("EITHER") end
    pickLabel("ANY LEVEL")
    pickLabel("YES")
    waitUntil(function() local x = scr:top() return x and x.kind == "message" end, 600, "deposited")
    wait(70)
    tap("a")
    wait(30)
    event("seek")
    pickLabel("SEEK")
    pickLabel("LUCARIO", 8)
    v = scr:top()
    if v and v.header == "Choose the gender." then pickLabel("EITHER") end
    pickLabel("ANY LEVEL")
    waitUntil(function() local x = scr:top() return x and x.title == "RESULTS" end, 600, "results")
    event("results")
    wait(80)
    tap("a")
    event("listing")
    wait(90)
    event("end")
    mark("stop")
    wait(30)
  end

  -- 4-player multi: this game leads the lobby, three peers join
  SHOTS.multi = function()
    place(bw and "Z089" or "C01", nil, nil, 2, 2, 2, 8)
    local MultiBattle = require("src.online.MultiBattle")
    local Json = require("src.link.Json")
    MultiBattle.defaults = {
      autoTeam = true, autoStart = true,
      connector = { port = 47920, bind = "127.0.0.1", portMap = false, lanIp = "127.0.0.1",
                    lanBeacon = false, stun = false },
      joinOptions = { timeouts = { lan = 3 } },
    }
    local battles, lobby, result = {}, nil, nil
    MultiBattle.defaults.onBattle = function(b) battles[#battles + 1] = b end
    MultiBattle.onLobby = function(l) lobby = l end
    MultiBattle.open(game, nil, { role = "host", need = 4 }, function(r, why) result = r log("lobby done", r, why) end)
    waitUntil(function() return lobby and lobby.code end, 600, "multi code")
    mark("multi_invite.json", Json.encode({ code = lobby.code }))
    recording = true
    event("rec")
    local t0 = f
    while result == nil and f - t0 < 60 * 300 do
      watchTop()
      local b = battles[#battles]
      local top = game.stack:top()
      if b and not b.seenEvent then b.seenEvent = true event("battle") end
      if b and b.linkRoundOpen and b.linkPickReplacement and top ~= b then
        local taken = {}
        for _, x in b:activeBattlers() do if x and x.mon and x.mon.hp > 0 then taken[x.mon] = true end end
        for i = #game.save.party, 1, -1 do
          local m = game.save.party[i]
          if m.hp > 0 and not taken[m] then b.linkPickReplacement(m) break end
        end
        wait(30)
      elseif b and top == b then
        battleStep(b)
      elseif top ~= lobby or (lobby and lobby.stage ~= "gather") then
        wait(10)
        tap("a")
      else
        frame()
      end
    end
    event("end " .. tostring(result))
    mark("stop")
  end

  local fn = assert(SHOTS[SHOT], "unknown shot " .. tostring(SHOT))
  local ok, err = xpcall(fn, debug.traceback)
  if not ok then log("FAILED: " .. tostring(err)) mark("stop") event("failed") end
  recording = false
  log("raw frames", rawFrames, "late frames", behind)
  pcall(OnlineWorld.leave)
  wait(4)
  queue:push("stop")
  writer:wait()
  events:close()
  love.timer.getTime, love.update = realGetTime, realUpdate
  mark(ok and "recorder_ok" or "recorder_failed", tostring(err or ""))
  os.exit(ok and 0 or 1)
end
