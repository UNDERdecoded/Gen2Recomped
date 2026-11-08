-- tools/trailer/recorder.lua -- stream rendered frames into ffmpeg, one MP4 per
-- segment, off the main thread. capture.lua and the other trailer drivers
-- (minigames.lua, e3ds.lua, launcher/) all write through this.
--
--   local Rec = dofile("tools/trailer/recorder.lua")({ out = OUT, ffmpeg = FFMPEG })
--   Rec.start("editor_open")    -- later frames go to <out>/editor_open.mp4
--   Rec.frame()                 -- call once per logic step; keeps every STEPth
--   Rec.stop()                  -- segment over; the next start opens a new file
--   Rec.capture(path, n)        -- one frame to <path>.mp4 now (no STEP gating)
--   Rec.finish()                -- drain and close ffmpeg (end of the run)
--
-- Also pins love.timer.getTime to a 1/60-per-update frame clock, so animation
-- in the footage is even however slowly the window renders (opts.clock =
-- false leaves the clock alone).
--
-- opts: out (folder), ffmpeg, crf (14), step (2 = 30 fps), format ("mp4" or
-- "png": numbered PNGs in a <path>/ folder), writers (PNG threads, 4),
-- guard (default true: a Lua error prints and exits the process instead of
-- leaving LOVE's error window open).
return function(opts)
  opts = opts or {}
  local OUT = assert(opts.out, "recorder: out folder")
  local FFMPEG = opts.ffmpeg or "ffmpeg"
  local CRF = tostring(opts.crf or 14)
  local STEP = opts.step or 2
  local FORMAT = opts.format or "mp4"

  if opts.guard ~= false then
    love.errorhandler = function(msg)
      print("ERROR " .. tostring(msg))
      print(debug.traceback())
      io.stdout:flush()
      os.exit(1)
    end
  end

  local realGetTime = love.timer.getTime
  local realUpdate = love.update
  if opts.clock ~= false then
    local clock = realGetTime()
    love.update = function(dt) clock = clock + 1 / 60; return realUpdate(dt) end
    love.timer.getTime = function() return clock end
  end

  local WRITER = [[
    local ch, format, ffmpeg, crf, fps = ...
    require("love.image")
    local pipe, current
    local function close()
      if pipe then pipe:close(); pipe = nil end
      current = nil
    end
    while true do
      local job = ch:demand()
      if job == "stop" then close(); return end
      if format == "png" then
        local fd = job.img:encode("png")
        local f = io.open(("%s/%05d.png"):format(job.path, job.n or 0), "wb")
        if f then f:write(fd:getString()); f:close() end
      else
        if job.path ~= current then
          close()
          local w, h = job.img:getDimensions()
          local cmd = ('"%s" -y -loglevel error -f rawvideo -pix_fmt rgba -s %dx%d -r %d -i - '
            .. '-c:v libx264 -preset slow -crf %s -pix_fmt yuv420p -movflags +faststart "%s.mp4"')
            :format(ffmpeg, w, h, fps, crf, job.path)
          if package.config:sub(1, 1) == "\\" then cmd = '"' .. cmd .. '"' end
          pipe = io.popen(cmd, "wb")
          current = job.path
        end
        if pipe then pipe:write(job.img:getString()) end
      end
      job.img:release()
    end
  ]]
  local queue = love.thread.getChannel("recorder_frames")
  local threads = {}
  for i = 1, (FORMAT == "png") and (opts.writers or 4) or 1 do
    threads[i] = love.thread.newThread(WRITER)
    threads[i]:start(queue, FORMAT, FFMPEG, CRF, math.floor(60 / STEP))
  end

  local R = { frames = 0, step = STEP, format = FORMAT, realGetTime = realGetTime }
  local made = {}
  local function mkdir(dir)
    if made[dir] then return end
    made[dir] = true
    if love._os == "Windows" then os.execute('mkdir "' .. dir:gsub("/", "\\") .. '" 2>nul')
    else os.execute('mkdir -p "' .. dir .. '"') end
  end

  -- one frame into <path>.mp4 (or <path>/<n>.png), whatever the STEP
  function R.capture(path, n)
    if FORMAT == "png" then mkdir(path) end
    -- back-pressure: 1080p frames are 8 MB each in the queue
    while queue:getCount() > 24 do realGetTime(); love.timer.sleep(0.004) end
    love.graphics.captureScreenshot(function(img) queue:push({ path = path, n = n, img = img }) end)
  end

  local path, f = nil, 0
  function R.start(name)
    path, f, R.frames = OUT .. "/" .. name, 0, 0
  end
  function R.stop()
    if path then print(("[recorder] %s: %d frames"):format(path, R.frames)) end
    path = nil
  end
  function R.recording() return path ~= nil end
  function R.frame()
    if not path then return end
    f = f + 1
    if f % STEP ~= 0 then return end
    R.frames = R.frames + 1
    R.capture(path, R.frames)
  end
  function R.finish()
    R.stop()
    for _ in ipairs(threads) do queue:push("stop") end
    for _, t in ipairs(threads) do t:wait() end
    love.timer.getTime, love.update = realGetTime, realUpdate
  end
  return R
end
