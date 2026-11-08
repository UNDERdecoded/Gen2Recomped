-- tools/trailer/capture.lua -- TRAILER FOOTAGE, recorded from the real game.
--
-- A POKEPORT_DRIVER script: it plays scripted shots (walks through towns, day
-- and night, battles, the voxel diorama, first and third person, Platinum on
-- the cartridge camera, single screen) and streams every other rendered frame
-- into ffmpeg, so each shot comes out as one 30 fps MP4:
--
--   <OUT>/<version>_<shot>.mp4
--
-- One run records the shots for ONE game (POKEPORT_VERSION). Every Gen 2 and
-- Gen 3 shot is recorded with DramaticShapes' voxel diorama ON, except the
-- "voxel_reveal" shot that starts flat and switches the voxels on mid-walk.
-- tools/trailer/capture_all.ps1 runs every game.
--
-- THE DS GAMES (Platinum, HeartGold, SoulSilver, Black, White) are natively
-- 3D: their towns are strolls on the cartridge camera (CAM TILT rung 1), and
-- first / third person (rungs 10 / 9) steer the free camera's kept look
-- (Gen4View.look) along a planned path, so the view turns as the player
-- walks. The second trailer (TRAILER_ONLINE.md) records them with
--
--   powershell -ExecutionPolicy Bypass -File tools/trailer/capture_all.ps1 `
--     -Identity trailer2_cap -ImportRom `
--     -SnapshotDir G:\Gen2Recomped\scratch_claude\playthrough `
--     -Versions heartgold,soulsilver,black,white,platinum
--
-- SNAPSHOT_DIR: a folder of playthrough snapshots (<game>_<n>.lua, from
-- tools/gen4_playthrough); the newest one for the game's family is the save
-- the shots play on, so no story scene starts in a town mid-shot. SNAPSHOT
-- names one file instead.
--
-- CAMERA CRAFT: strolls keep to open ground (no tree line between the lens
-- and the player), voxel cameras settle before the first frame, and first /
-- third person steer the free camera's look along a planned path, easing
-- through each corner, so the view turns the way the player walks.
--
-- SMOOTH FOOTAGE ON A SLOW RUN: the logic steps a fixed 1/60 per frame, the
-- wall clock (love.timer.getTime, which water and shaders animate from) is
-- replaced by a frame clock, and encoding happens off the main thread in
-- ffmpeg. The window may crawl while recording; the video does not.
--
-- Env: OUT (required), FFMPEG (path, default "ffmpeg"), CRF (default 14),
-- FORMAT (mp4 | png), VOXEL (level, default 4), WIDTH/HEIGHT (default
-- 1920x1080), ONLY (comma list of shot names), FPS_STEP (default 2 = 30 fps),
-- WRITERS (PNG threads when FORMAT=png, default 4).

return function(game)
  local U = dofile("tests/drivers/util.lua")
  local OUT = assert(os.getenv("OUT"), "set OUT to the footage folder")
  local VOX = tonumber(os.getenv("VOXEL") or "4") or 4
  local STEP = tonumber(os.getenv("FPS_STEP") or "2") or 2
  local ONLY = {}
  for name in (os.getenv("ONLY") or ""):gmatch("[^,]+") do ONLY[name] = true end
  local GameVersion = require("src.core.GameVersion")
  local version = GameVersion.get()
  local Pokemon = require("src.pokemon.Pokemon")
  local BattleState = require("src.battle.BattleState")

  -- a 1080p window, so the frames are trailer-sized
  local W, H = tonumber(os.getenv("WIDTH") or "1920"), tonumber(os.getenv("HEIGHT") or "1080")
  pcall(love.window.setMode, W, H, { resizable = true, vsync = 0 })
  U.wait(10)

  -- THE CLOCK: Gen 2's day and night come from the wall clock, so a shot pins
  -- the hour by answering os.date("%H") itself
  local realDate = os.date
  local pinnedHour = nil
  os.date = function(fmt, t)
    if pinnedHour and fmt == "%H" then return ("%02d"):format(pinnedHour) end
    if pinnedHour and fmt == "*t" then
      local r = realDate("*t", t); r.hour = pinnedHour; return r
    end
    return realDate(fmt, t)
  end

  -- THE FRAME CLOCK AND THE WRITER (tools/trailer/recorder.lua): one 1/60
  -- tick per logic step, whatever the wall says; captureScreenshot hands each
  -- frame to a worker thread that streams it, raw RGBA, into an ffmpeg
  -- process per shot -- an MP4 comes out and no PNGs touch the disk.
  -- FORMAT=png keeps the old image-sequence output instead.
  local FORMAT = os.getenv("FORMAT") or "mp4"
  local Rec = dofile("tools/trailer/recorder.lua")({
    out = OUT, ffmpeg = os.getenv("FFMPEG") or "ffmpeg", crf = os.getenv("CRF") or "14",
    step = STEP, format = FORMAT, writers = tonumber(os.getenv("WRITERS") or "4") or 4,
  })
  local function capture(dir, n) Rec.capture(dir, n) end

  local DS = { platinum = true, heartgold = true, soulsilver = true, black = true, white = true }
  local isDS = DS[version] or false
  -- no wild battle cuts a stroll short
  require("src.world.OverworldController").rollEncounter = function() return nil end

  -- the fit zoom, not whatever survey zoom the player's options hold
  local Zoom = require("src.render.Zoom")

  -- the save: a fresh one with the player's own options kept -- or a
  -- playthrough snapshot (SNAPSHOT / SNAPSHOT_DIR, see the header)
  local function snapshotSave()
    local file = os.getenv("SNAPSHOT")
    local dir = os.getenv("SNAPSHOT_DIR")
    local family = ({ heartgold = "heartgold", soulsilver = "heartgold", black = "black",
                      white = "black", platinum = "platinum" })[version]
    if (not file or file == "") and dir and dir ~= "" and family then
      for n = 200, 1, -1 do
        local p = ("%s/%s_%d.lua"):format(dir:gsub("\\", "/"), family, n)
        local f = io.open(p, "rb")
        if f then f:close(); file = p; break end
      end
    end
    if not file or file == "" then return nil end
    local okL, snap = pcall(dofile, file)
    if not (okL and type(snap) == "table") then U.log("snapshot unreadable: " .. file); return nil end
    local okD, save = pcall(require("src.core.SaveData").decode, snap.save)
    if not (okD and type(save) == "table") then U.log("snapshot did not decode: " .. file); return nil end
    U.log("save from snapshot " .. file)
    return save
  end
  local kept = game.save and game.save.options
  local snapped = snapshotSave()
  if snapped then
    game.save = snapped
    game.save.version = version
  else
    U.freshSave(game)
  end
  if kept then game.save.options = kept end
  game.save.options.zoom = 0
  Zoom.offset = 0
  if not snapped then
    game.save.player.name = (version == "platinum") and "LUCAS" or "GOLD"
  end

  local function speciesByName(name)
    for id, def in pairs(game.data.pokemon or {}) do
      if type(def) == "table" and type(def.name) == "string" and def.name:upper() == name then return id end
    end
    return nil
  end
  local function mon(name, level)
    local id = speciesByName(name)
    return id and Pokemon.new(game.data, id, level) or nil
  end
  if not snapped then
    local party = {}
    for _, pick in ipairs({ { "TYPHLOSION", 40 }, { "CHARIZARD", 42 }, { "INFERNAPE", 40 }, { "PIKACHU", 30 } }) do
      local m = mon(pick[1], pick[2])
      if m then party[#party + 1] = m end
      if #party >= 2 then break end
    end
    game.save.party = party
  end

  -- where a shot goes: <OUT>/<version>_<shot>.mp4, or a folder of PNGs
  -- (the recorder makes the folder)
  -- (the Emerald 3DS shots keep the names the edit asks for)
  local NAMES = { e3ds_reveal = "emerald3ds_reveal", e3ds_town = "emerald3ds_town",
                  e3ds_battle = "emerald3ds_battle" }
  local function newShotDir(shot)
    return OUT .. "/" .. (NAMES[shot] or (version .. "_" .. shot))
  end

  -- one frame of footage every STEP frames
  local function record(shot, frames)
    local dir = newShotDir(shot)
    local n = 0
    for f = 1, frames do
      if f % STEP == 0 then
        n = n + 1
        capture(dir, n)
      end
      coroutine.yield()
    end
    U.log(("recorded %s: %d frames -> %s"):format(shot, n, dir))
  end

  -- OPEN GROUND: the diorama camera looks north from the south, so whatever
  -- stands in the rows just below the player (a tree line, a roof) stands
  -- between it and the lens. A cell is open when that strip is walkable.
  local function openScore(cx, cy)
    local map = game.overworld and game.overworld.map
    if not map then return 9 end
    local n = 0
    for dy = 1, 3 do
      for dx = -1, 1 do
        local x, y = cx + dx, cy + dy
        if map:inBounds(x, y) and map:isWalkableCell(x, y) then n = n + 1 end
      end
    end
    return n
  end
  local strict = 7          -- openScore a walked cell needs; 0 = anywhere
  -- the nearest cell the player can stand on, from the map's middle outwards
  local function standable(mapId, x, y)
    U.teleport(game, mapId, x, y, "down")
    local ow = game.overworld
    local map = ow and ow.map
    if not (map and map.isWalkableCell) then return x, y end
    if map:isWalkableCell(x, y) then return x, y end
    for r = 1, 24 do
      for dy = -r, r do
        for dx = -r, r do
          if math.abs(dx) == r or math.abs(dy) == r then
            local cx, cy = x + dx, y + dy
            if map:inBounds(cx, cy) and map:isWalkableCell(cx, cy) then return cx, cy end
          end
        end
      end
    end
    return x, y
  end
  local function goTo(mapId, x, y, facing)
    if not game.data.maps[mapId] then U.log("no map " .. tostring(mapId)); return false end
    local m = game.data.maps[mapId]
    x = x or math.floor((m.width or 20) / 2)
    y = y or math.floor((m.height or 18) / 2)
    local sx, sy = standable(mapId, x, y)
    -- then the nearest cell with open ground in front of the camera
    local map = game.overworld and game.overworld.map
    if map then
      local best, bestD
      for dy = -14, 14 do
        for dx = -14, 14 do
          local cx, cy = sx + dx, sy + dy
          if map:inBounds(cx, cy) and map:isWalkableCell(cx, cy) and openScore(cx, cy) >= 9 then
            local d = math.abs(dx) + math.abs(dy)
            if not bestD or d < bestD then best, bestD = { cx, cy }, d end
          end
        end
      end
      if best then sx, sy = best[1], best[2] end
    end
    U.teleport(game, mapId, sx, sy, facing or "down")
    U.wait(60)
    return true
  end
  -- ------------------------------------------------- walking that knows the map
  --
  -- A breadth-first search over the cells the player can stand on (and that
  -- nobody stands on), so a stroll goes AROUND houses and trees instead of
  -- into them. The tour picks a far cell, then a second leg in another
  -- direction, and walks it one tile at a time, re-planning when something
  -- (a wandering NPC) blocks the way.
  local Pipelines = require("src.render.Pipelines")
  local function voxel(level) pcall(Pipelines.setLevel, "voxel", level) end
  local function tiltshift(level) pcall(Pipelines.setLevel, "tiltshift", level) end
  local DIRS = { up = { 0, -1 }, down = { 0, 1 }, left = { -1, 0 }, right = { 1, 0 } }
  local Collision = require("src.world.Collision")
  -- the map's warp cells (doors, mats, stairs): a stroll never steps on one
  local warpCells, warpMap = {}, nil
  local function warpAt(cx, cy)
    local map = game.overworld and game.overworld.map
    if not map then return false end
    if warpMap ~= map then
      warpMap, warpCells = map, {}
      local def = map.def or {}
      for _, w in ipairs(def.warps or {}) do
        local wx, wy = tonumber(w.x), tonumber(w.y or w.z)
        if wx and wy then warpCells[wx .. "," .. wy] = true end
      end
    end
    return warpCells[cx .. "," .. cy] == true
  end
  local function free(cx, cy)
    local ow = game.overworld
    local map = ow and ow.map
    if not (map and map:inBounds(cx, cy) and map:isWalkableCell(cx, cy)) then return false end
    if warpAt(cx, cy) then return false end
    local okO, occ = pcall(Collision.occupied, ow.entities or ow.npcs or {}, cx, cy, ow.player)
    return not (okO and occ)
  end
  -- strict: 0 anywhere, a number = that much open ground in front, "wide" =
  -- all four neighbours walkable too (a free camera's eye clears the walls),
  -- { clear = r } = every cell within r walkable (a DS free camera's room)
  local function cellOK(cx, cy)
    if strict == 0 then return true end
    if type(strict) == "table" then
      local map = game.overworld.map
      local r = strict.clear or 1
      for dy = -r, r do
        for dx = -r, r do
          local x, y = cx + dx, cy + dy
          if not (map:inBounds(x, y) and map:isWalkableCell(x, y)) or warpAt(x, y) then return false end
        end
      end
      return true
    end
    if strict == "wide" then
      local map = game.overworld.map
      for _, v in pairs(DIRS) do
        if not (map:inBounds(cx + v[1], cy + v[2]) and map:isWalkableCell(cx + v[1], cy + v[2])) then return false end
      end
      return true
    end
    return openScore(cx, cy) >= strict
  end
  local function bfs(sx, sy)
    local dist, prev, queue, head = { [sx .. "," .. sy] = 0 }, {}, { { sx, sy } }, 1
    while head <= #queue do
      local c = queue[head]; head = head + 1
      local d = dist[c[1] .. "," .. c[2]]
      if d < 60 then
        for name, v in pairs(DIRS) do
          local nx, ny = c[1] + v[1], c[2] + v[2]
          local k = nx .. "," .. ny
          if dist[k] == nil and free(nx, ny) and cellOK(nx, ny) then
            dist[k], prev[k] = d + 1, { c[1], c[2], name }
            queue[#queue + 1] = { nx, ny }
          end
        end
      end
    end
    return dist, prev
  end
  local function pathTo(prev, sx, sy, tx, ty)
    local steps, k = {}, tx .. "," .. ty
    while prev[k] do
      local p = prev[k]
      table.insert(steps, 1, p[3])
      k = p[1] .. "," .. p[2]
    end
    return steps
  end
  -- a far cell around `want` steps away, away from `avoid` if given
  local function pickTarget(dist, sx, sy, want, avoid)
    local best, bestScore
    for k, d in pairs(dist) do
      if d >= want - 4 and d <= want + 4 then
        local x, y = k:match("(-?%d+),(-?%d+)")
        x, y = tonumber(x), tonumber(y)
        local score = math.abs(x - sx) + math.abs(y - sy)
        if avoid then score = score + 0.5 * (math.abs(x - avoid[1]) + math.abs(y - avoid[2])) end
        if not bestScore or score > bestScore then best, bestScore = { x, y }, score end
      end
    end
    return best
  end
  local rec = { dir = nil, f = 0, n = 0 }
  local function tick()
    rec.f = rec.f + 1
    if rec.dir and rec.f % STEP == 0 then
      rec.n = rec.n + 1
      capture(rec.dir, rec.n)
    end
    coroutine.yield()
  end
  local function hold(btn, frames)
    for _ = 1, frames do
      table.insert(game.input.pressQueue, btn)
      game.input.state[btn] = true
      tick()
    end
    game.input.state[btn] = false
  end
  -- walk to (tx, ty) along the planned path, one tile at a time
  local function walkTo(tx, ty, budget)
    local p = game.overworld.player
    local tries = 0
    while budget > 0 and (p.cellX ~= tx or p.cellY ~= ty) and tries < 6 do
      local _, prev = bfs(p.cellX, p.cellY)
      local steps = pathTo(prev, p.cellX, p.cellY, tx, ty)
      if #steps == 0 then return budget end
      tries = tries + 1
      for _, d in ipairs(steps) do
        local wx, wy = p.cellX + DIRS[d][1], p.cellY + DIRS[d][2]
        local t = 0
        while (p.cellX ~= wx or p.cellY ~= wy) and t < 48 and budget > 0 do
          table.insert(game.input.pressQueue, d)
          game.input.state[d] = true
          tick(); t = t + 1; budget = budget - 1
        end
        game.input.state[d] = false
        if p.cellX ~= wx or p.cellY ~= wy then break end   -- blocked: plan again
        if budget <= 0 then return 0 end
      end
    end
    return budget
  end
  -- a tour of about `frames` frames: a far cell, then a second leg elsewhere
  local function strollRecord(shot, frames)
    rec.dir, rec.f, rec.n = newShotDir(shot), 0, 0
    frames = frames or 420
    local p = game.overworld.player
    local start = { p.cellX, p.cellY }
    local budget = frames
    strict = 7
    local n = 0
    for _ in pairs(bfs(p.cellX, p.cellY)) do n = n + 1 end
    if n < 40 then strict = 5 end
    n = 0
    for _ in pairs(bfs(p.cellX, p.cellY)) do n = n + 1 end
    if n < 40 then strict = 0 end
    for leg = 1, 3 do
      if budget <= 0 then break end
      local dist = bfs(p.cellX, p.cellY)
      local target = pickTarget(dist, p.cellX, p.cellY, leg == 1 and 14 or 10, start)
      if not target then break end
      budget = walkTo(target[1], target[2], budget)
    end
    while budget > 0 do tick(); budget = budget - 1 end
    U.log(("recorded %s: %d frames -> %s"):format(shot, rec.n, rec.dir))
    rec.dir = nil
  end
  -- first / third person: the free camera takes its yaw from the player's
  -- facing at the moment the mode engages, and "up" then means forward. So
  -- face the longest clear straight line FIRST, switch the mode on, and hold
  -- forward.
  local function longestLine()
    local p = game.overworld.player
    local bestDir, bestLen = "up", 0
    for name, v in pairs(DIRS) do
      local len = 0
      while len < 30 and free(p.cellX + v[1] * (len + 1), p.cellY + v[2] * (len + 1)) do len = len + 1 end
      if len > bestLen then bestDir, bestLen = name, len end
    end
    return bestDir, bestLen
  end
  local function forwardRecord(shot, frames, level)
    local V = rawget(_G, "__DRAMATIC_SHAPE_V")
    local okF, FP = pcall(function() return V and V.require("FirstPerson") end)
    local okM, FM = pcall(function() return V and V.require("FreeMove") end)
    if not (okF and FP and okM and FM) then U.log("no free camera for " .. shot); return end
    local p = game.overworld.player
    -- a route with corners in it: a far open cell, then a second leg, kept
    -- to cells with room on every side so the eye never brushes a wall
    strict = "wide"
    local reach = 0
    for _ in pairs(bfs(p.cellX, p.cellY)) do reach = reach + 1 end
    if reach < 30 then strict = 5 end
    local dist, prev = bfs(p.cellX, p.cellY)
    local t1 = pickTarget(dist, p.cellX, p.cellY, 12)
    local cells = {}
    if t1 then
      local cx, cy = p.cellX, p.cellY
      for _, d in ipairs(pathTo(prev, cx, cy, t1[1], t1[2])) do
        cx, cy = cx + DIRS[d][1], cy + DIRS[d][2]
        cells[#cells + 1] = { cx, cy }
      end
      local dist2, prev2 = bfs(cx, cy)
      local t2 = pickTarget(dist2, cx, cy, 10, { p.cellX, p.cellY })
      if t2 then
        for _, d in ipairs(pathTo(prev2, cx, cy, t2[1], t2[2])) do
          cx, cy = cx + DIRS[d][1], cy + DIRS[d][2]
          cells[#cells + 1] = { cx, cy }
        end
      end
    end
    strict = 7
    -- only the corners: a straight run is one waypoint
    local wps = {}
    for i, c in ipairs(cells) do
      local nx = cells[i + 1]
      local pv = cells[i - 1] or { p.cellX, p.cellY }
      if not nx or (nx[1] - c[1]) ~= (c[1] - pv[1]) or (nx[2] - c[2]) ~= (c[2] - pv[2]) then
        wps[#wps + 1] = { c[1] * 16 + 8, c[2] * 16 + 8 }
      end
    end
    -- face the first leg before the mode engages, so it starts looking ahead
    if wps[1] then
      local dx, dy = wps[1][1] - (p.px + 8), wps[1][2] - (p.py + 8)
      p.facing = math.abs(dx) > math.abs(dy) and (dx > 0 and "right" or "left") or (dy > 0 and "down" or "up")
    end
    voxel(level)
    U.wait(90)
    -- a pre-roll: the camera starts behind the player, which can be inside
    -- whatever they were standing in front of; record once they are walking
    local pre = (level == 7) and 75 or 30
    rec.dir, rec.f, rec.n = nil, 0, 0
    local function wrap(a) return (a + math.pi) % (2 * math.pi) - math.pi end
    local wi, stuck, lastX, lastZ = 1, 0, nil, nil
    while rec.f < frames + pre do
      if not rec.dir and rec.f >= pre then rec.dir, rec.n = newShotDir(shot), 0 end
      local pos = FM._pos()
      local x = pos and pos.x or (p.px + 8)
      local z = pos and pos.z or (p.py + 8)
      local w = wps[wi]
      if w and math.abs(w[1] - x) + math.abs(w[2] - z) < 5 then wi = wi + 1; w = wps[wi] end
      local walking = false
      if w then
        -- ease the look toward the next corner: fast enough to round it,
        -- slow enough to read as a person turning their head
        local want = math.atan2(w[1] - x, w[2] - z)
        local diff = wrap(want - FP.yaw)
        local turn = diff * 0.1
        local maxTurn = 2.4 / 60
        if turn > maxTurn then turn = maxTurn elseif turn < -maxTurn then turn = -maxTurn end
        FP.yaw = wrap(FP.yaw + turn)
        walking = math.abs(diff) < 0.45    -- a corner turns first, then goes
        -- a body that has not moved in a second is stuck: skip the corner
        if lastX and math.abs(x - lastX) + math.abs(z - lastZ) < 0.05 and walking then stuck = stuck + 1 else stuck = 0 end
        if stuck > 60 then wi = wi + 1; stuck = 0 end
      end
      lastX, lastZ = x, z
      game.input.state.up = walking
      if walking then table.insert(game.input.pressQueue, "up") end
      tick()
    end
    game.input.state.up = false
    U.log(("recorded %s: %d frames (%d corners) -> %s"):format(shot, rec.n, #wps, rec.dir))
    rec.dir = nil
  end
  local WALK = 420

  -- THE DS CAMERA: the CAM TILT ladder (Gen4Camera.TILTS) -- 1 the
  -- cartridge's own, 9 third person, 10 first person. OverworldState:enter
  -- syncs it from the save, so the option is written as well as set.
  local Gen4Camera = isDS and require("src.render.Gen4Camera") or nil
  local function rung(i)
    if not Gen4Camera then return end
    game.save.options.gen4CameraTilt = i
    pcall(Gen4Camera.setTilt, i)
  end

  -- DS FIRST / THIRD PERSON. Unorbited, the free camera keeps one heading
  -- whichever way the player walks; orbited (Gen4View.look.orbiting) it
  -- looks along look.yaw and "up" walks that way (forward = sin yaw, -cos
  -- yaw on the map). So plan a route with corners, ease look.yaw toward the
  -- next corner each frame and hold "up" -- the view turns the way a person
  -- turns their head, and the walk follows it.
  local function dsFreeRecord(shot, frames, mode, opts)
    opts = opts or {}
    local GV = require("src.render.Gen4View")
    local look = GV.look
    local p = game.overworld.player
    local function plan(r)
      strict = { clear = r }
      local dist, prev = bfs(p.cellX, p.cellY)
      local t1 = pickTarget(dist, p.cellX, p.cellY, opts.leg1 or 14)
      local cells = {}
      if t1 then
        local cx, cy = p.cellX, p.cellY
        for _, d in ipairs(pathTo(prev, cx, cy, t1[1], t1[2])) do
          cx, cy = cx + DIRS[d][1], cy + DIRS[d][2]
          cells[#cells + 1] = { cx, cy }
        end
        local _, prev2 = bfs(cx, cy)
        local dist2 = bfs(cx, cy)
        local t2 = pickTarget(dist2, cx, cy, opts.leg2 or 12, { p.cellX, p.cellY })
        if t2 then
          for _, d in ipairs(pathTo(prev2, cx, cy, t2[1], t2[2])) do
            cx, cy = cx + DIRS[d][1], cy + DIRS[d][2]
            cells[#cells + 1] = { cx, cy }
          end
        end
      end
      return cells
    end
    -- the most room the map can give the eye: three cells clear, then two, one
    local cells = {}
    for r = opts.clear or (mode == "third" and 4 or 3), 1, -1 do
      cells = plan(r)
      if #cells >= 16 then break end
    end
    strict = 7
    -- the corners only: a straight run is one waypoint
    local wps = {}
    for i, c in ipairs(cells) do
      local nx = cells[i + 1]
      local pv = cells[i - 1] or { p.cellX, p.cellY }
      if not nx or (nx[1] - c[1]) ~= (c[1] - pv[1]) or (nx[2] - c[2]) ~= (c[2] - pv[2]) then
        wps[#wps + 1] = { c[1] * 16 + 8, c[2] * 16 + 8 }
      end
    end
    -- whoever stands within three cells of the route would wander between
    -- the lens and the player (or into the eye), so they sit this shot out
    -- (hidden from the first frame, put back after); everyone further off
    -- stays
    local hiddenNpcs = {}
    if opts.keepNpcs ~= true then
      local follower = nil
      pcall(function() follower = require("src.world.HgssFollowMon").current(game.overworld) end)
      for _, npc in ipairs(game.overworld.npcs or {}) do
        if npc ~= follower and not npc.hidden and npc.cellX and npc.cellY then
          local near = math.abs(npc.cellX - p.cellX) <= 3 and math.abs(npc.cellY - p.cellY) <= 3
          for _, c in ipairs(cells) do
            if near then break end
            near = math.abs(npc.cellX - c[1]) <= 3 and math.abs(npc.cellY - c[2]) <= 3
          end
          if near then npc.hidden = true; hiddenNpcs[#hiddenNpcs + 1] = npc end
        end
      end
    end
    local function wrap(a) return (a + math.pi) % (2 * math.pi) - math.pi end
    local function bearing(w, x, z) return math.atan2(w[1] - x, -(w[2] - z)) end
    -- third person a little higher than its rest, so it looks over whoever
    -- walks between the lens and the player
    look.orbiting = true
    look.zoom = opts.zoom or (mode == "third" and 0.65 or nil)
    look.rise = opts.rise or (mode == "third" and 12 or 0)
    look.yaw = wps[1] and bearing(wps[1], p.px + 8, p.py + 8) or 0
    rung(mode == "first" and 10 or 9)
    U.wait(opts.preroll or 90)
    -- a lead-in: the first steps off the start cell (often against a wall)
    -- are walked before the first frame
    local lead = opts.lead or 45
    rec.dir, rec.f, rec.n = nil, 0, 0
    local wi, stuck, lastX, lastZ = 1, 0, nil, nil
    while rec.f < frames + lead do
      if not rec.dir and rec.f >= lead then rec.dir, rec.n = newShotDir(shot), 0 end
      local x, z = p.px + 8, p.py + 8
      local w = wps[wi]
      if w and math.abs(w[1] - x) + math.abs(w[2] - z) < 6 then wi = wi + 1; w = wps[wi] end
      local walking = false
      if w then
        local diff = wrap(bearing(w, x, z) - (look.yaw or 0))
        local turn = diff * 0.08
        local maxTurn = (opts.turn or 2.0) / 60
        if turn > maxTurn then turn = maxTurn elseif turn < -maxTurn then turn = -maxTurn end
        look.yaw = wrap((look.yaw or 0) + turn)
        walking = math.abs(diff) < 0.5     -- a corner turns first, then goes
        if lastX and math.abs(x - lastX) + math.abs(z - lastZ) < 0.05 and walking then stuck = stuck + 1 else stuck = 0 end
        if stuck > 45 then wi = wi + 1; stuck = 0 end
      end
      lastX, lastZ = x, z
      game.input.state.up = walking
      if walking then table.insert(game.input.pressQueue, "up") end
      tick()
    end
    game.input.state.up = false
    U.log(("recorded %s: %d frames (%d corners, map %s) -> %s"):format(shot, rec.n, #wps,
      tostring(game.overworld.map and game.overworld.map.id), rec.dir))
    rec.dir = nil
    look.orbiting, look.yaw, look.rise, look.zoom = nil, nil, nil, nil
    for _, npc in ipairs(hiddenNpcs) do npc.hidden = false end
    rung(1)
  end

  -- `skip`: frames played before the first one is kept (the wipe)
  local function battleShot(shot, species, level, opts, extraFrames, skip)
    local id = speciesByName(species) or species
    local ok, battle = pcall(BattleState.newWild, game, id, level, opts)
    if not ok or not battle then U.log("battle failed: " .. tostring(battle)); return end
    battle.onFinish = function() end
    game.overworld:pushBattle(battle)
    -- the wipe and the send-out, then a turn: A every 40 frames
    local dir = newShotDir(shot)
    local n = 0
    for f = 1, extraFrames or 900 do
      if f > 200 and f % 40 == 0 then table.insert(game.input.pressQueue, "a") end
      if f > (skip or 0) and f % STEP == 0 then
        n = n + 1
        capture(dir, n)
      end
      coroutine.yield()
      if f % 40 == 1 then game.input.state.a = false end
    end
    U.log(("recorded %s: %d frames -> %s"):format(shot, n, dir))
    while game.stack:top() and game.stack:top() ~= game.overworld do game.stack:pop() end
    U.wait(20)
  end


  -- ------------------------------------------------------------- the shots
  local SHOTS = {}
  local function shot(name, fn) SHOTS[#SHOTS + 1] = { name = name, fn = fn } end

  -- flat for the first half, then the voxels switch on mid-walk (`on` /
  -- `off` switch another pipeline instead: the Emerald 3DS reveal)
  local function revealRecord(shotName, frames, on, off)
    local voxel = voxel
    if on then voxel = function(level) if level == 0 then off() else on() end end end
    voxel(0)
    rec.dir, rec.f, rec.n = newShotDir(shotName), 0, 0
    local p = game.overworld.player
    local dist = bfs(p.cellX, p.cellY)
    local target = pickTarget(dist, p.cellX, p.cellY, 18)
    local half = math.floor(frames / 2)
    local function step(n) while n > 0 do tick(); n = n - 1 end end
    if target then
      -- walk the first half flat, then switch and keep walking
      local left = walkTo(target[1], target[2], half)
      step(left)
      voxel(VOX)
      local dist2 = bfs(p.cellX, p.cellY)
      local t2 = pickTarget(dist2, p.cellX, p.cellY, 10)
      left = t2 and walkTo(t2[1], t2[2], frames - half) or (frames - half)
      step(left)
    else
      step(half); voxel(VOX); step(frames - half)
    end
    U.log(("recorded %s: %d frames -> %s"):format(shotName, rec.n, rec.dir))
    rec.dir = nil
  end
  -- every ordinary shot: voxels on at the chosen level, then the stroll
  -- (a DS town waits out the place-name banner before the first frame)
  local function town(name, mapId, x, y, hour, level)
    shot(name, function()
      pinnedHour = hour or 12
      rung(1)
      goTo(mapId, x, y)
      if not isDS then voxel(level or VOX); U.wait(150) else U.wait(150) end
      strollRecord(name, WALK)
    end)
  end
  local function fight(name, mapId, species, level, opts, frames, hour)
    shot(name, function()
      pinnedHour = hour or 12
      goTo(mapId)
      if not isDS then voxel(VOX); U.wait(150) end
      battleShot(name, species, level, opts, frames)
    end)
  end
  -- DS first / third person: the free camera, steered (dsFreeRecord)
  local function dsPerson(name, mapId, mode, hour, x, y, opts)
    shot(name, function()
      pinnedHour = hour or 12
      rung(1)
      -- HGSS's walking Pokemon follows between the lens and the player in
      -- third person: recalled into its ball for the shot (HgssFollowMon)
      local wasRecalled = game.save.hgssFollowMon and game.save.hgssFollowMon.recalled
      goTo(mapId, x, y)
      -- (after the warp: a map change clears the recall)
      if mode == "third" then
        game.save.hgssFollowMon = game.save.hgssFollowMon or {}
        game.save.hgssFollowMon.recalled = true
      end
      U.wait(120)
      dsFreeRecord(name, (opts and opts.frames) or 360, mode, opts)
      if mode == "third" and game.save.hgssFollowMon then game.save.hgssFollowMon.recalled = wasRecalled end
    end)
  end
  if isDS then
    -- natively 3D; single screen, the bottom screen off
    game.save.options.secondScreenMode = "off"
    pcall(function() game:applyOptions() end)
    rung(1)
  end
  local function person(name, mapId, level, hour)
    shot(name, function()
      pinnedHour = hour or 12
      goTo(mapId, mapId == "NEW_BARK_TOWN" and 9 or nil, mapId == "NEW_BARK_TOWN" and 8 or nil)
      forwardRecord(name, 420, level)
    end)
  end

  if version == "crystal" or version == "gold" or version == "silver" then
    shot("voxel_reveal", function() pinnedHour = 12; goTo("NEW_BARK_TOWN", 9, 8); revealRecord("voxel_reveal", 480) end)
    town("newbark_day", "NEW_BARK_TOWN", 9, 8, 12)
    town("newbark_night", "NEW_BARK_TOWN", 9, 8, 21)
    town("cherrygrove_tiltshift", "CHERRYGROVE_CITY", nil, nil, 12, 3)
    town("violet", "VIOLET_CITY", nil, nil, 10)
    town("ecruteak_dusk", "ECRUTEAK_CITY", nil, nil, 18)
    town("goldenrod", "GOLDENROD_CITY", nil, nil, 14)
    town("overview", "VIOLET_CITY", nil, nil, 12, 1)
    fight("battle_shiny", "ROUTE_29", "GYARADOS", 30, { shiny = true }, 1000, 12)
    fight("battle_dusk", "ROUTE_29", "PIDGEOTTO", 18, nil, 1200, 17)
    person("first_person", "NEW_BARK_TOWN", 6, 12)
    person("third_person", "CHERRYGROVE_CITY", 7, 16)
  elseif version == "firered" then
    shot("voxel_reveal", function() pinnedHour = 12; goTo("MAP_G03_N00"); revealRecord("voxel_reveal", 480) end)
    town("pallet", "MAP_G03_N00")
    town("cerulean", "MAP_G03_N03")
    fight("battle", "MAP_G03_N00", "PIDGEY", 12, nil, 1000)
    person("third_person", "MAP_G03_N03", 7)
  elseif version == "emerald" and os.getenv("E3DS") == "1" then
    -- ZALLAX'S EMERALD 3DS VOXELS (mods/EMERALD_3DS_VOXEL, pipeline
    -- e3ds_voxel, rung 3 = its default 40 degrees; E3DS_RUNG overrides):
    --   E3DS=1 ... capture_all.ps1 -Identity trailer2_cap -Versions emerald
    -- writes emerald3ds_reveal / _town / _battle
    local E3 = tonumber(os.getenv("E3DS_RUNG") or "3") or 3
    local function e3(level) pcall(Pipelines.setLevel, "e3ds_voxel", level) end
    shot("e3ds_reveal", function()
      pinnedHour = 12
      goTo("MAP_G00_N09")                                   -- Littleroot Town
      e3(0); U.wait(120)
      revealRecord("e3ds_reveal", 480, function() e3(E3) end, function() e3(0) end)
      e3(0)
    end)
    shot("e3ds_town", function()
      pinnedHour = 12
      goTo("MAP_G00_N01")                                   -- Slateport City
      e3(E3); U.wait(150)
      strollRecord("e3ds_town", WALK)
      e3(0)
    end)
    shot("e3ds_battle", function()
      pinnedHour = 12
      goTo("MAP_G00_N16")                                   -- Route 101's grass
      e3(E3); U.wait(150)
      battleShot("e3ds_battle", "ZIGZAGOON", 8, nil, 640, 160)
      e3(0)
    end)
  elseif version == "emerald" then
    town("littleroot", "MAP_G00_N09")
    town("slateport", "MAP_G00_N01")
    town("lilycove", "MAP_G00_N05")
    fight("battle", "MAP_G00_N09", "ZIGZAGOON", 10, nil, 1000)
    person("first_person", "MAP_G00_N05", 6)
  elseif version == "platinum" then
    -- the camera rung: 1 is the cartridge's own; 9 third person, 10 first
    dsPerson("third_person", "C01", "third")
    dsPerson("first_person", "C05", "first")
    town("twinleaf", "T01")
    town("jubilife", "C01")
    town("snowpoint", "C09")
    town("eterna", "C04")
    town("hearthome", "C05")
    fight("battle", "R201", "STARLY", 8, nil, 1100)
  elseif version == "heartgold" then
    -- Johto on the DS engine (map ids: gen4_map_headers internalName)
    town("newbark", "T20")                        -- New Bark Town
    town("goldenrod", "T25", nil, nil, 14)        -- Goldenrod City
    dsPerson("first_person", "T25", "first")
  elseif version == "soulsilver" then
    town("ecruteak", "T27", nil, nil, 16)         -- Ecruteak City
    dsPerson("third_person", "T27", "third", 16) -- Ecruteak City
  elseif version == "black" then
    -- Unova (zone ids: tools/gen4_playthrough/black.lua)
    town("nuvema", "Z389")                        -- Nuvema Town
    town("castelia", "Z037")                      -- Castelia, the piers
    dsPerson("first_person", "Z062", "first")    -- Nimbasa City
  elseif version == "white" then
    town("nimbasa", "Z062")                       -- Nimbasa City
  end

  -- PROBE="map[:x:y],...": scouting instead of the shot list -- a short
  -- stroll at each place, <version>_probe_<n>.mp4, to look for a spot
  if (os.getenv("PROBE") or "") ~= "" then
    SHOTS, ONLY = {}, {}
    local i = 0
    for spec in os.getenv("PROBE"):gmatch("[^,]+") do
      i = i + 1
      local id, x, y = spec:match("^([^:]+):?(%d*):?(%d*)$")
      town("probe_" .. i, id, tonumber(x), tonumber(y))
    end
    WALK = tonumber(os.getenv("PROBE_FRAMES") or "180") or 180
  end

  for _, s in ipairs(SHOTS) do
    if next(ONLY) == nil or ONLY[s.name] then
      local ok, err = pcall(s.fn)
      if not ok then U.log("shot " .. s.name .. " failed: " .. tostring(err)) end
      voxel(0)
    end
  end
  os.date = realDate
  -- let the last screenshots land, then drain the writer
  U.wait(4)
  Rec.finish()
  U.log("done")
  love.event.quit()
end
