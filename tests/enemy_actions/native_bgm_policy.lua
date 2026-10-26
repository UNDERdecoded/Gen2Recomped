-- Actual world adapters read live map, weather and story state in both engines.
local M = {}
function M.run(root, backend, version)
  local f = dofile(root .. "/tests/enemy_actions/assist.lua").fixture(root, backend, version)
  local cases = {}
  local function add(name, number, options)
    options = options or {}
    options.name, options.group, options.number = name, options.group or 0, number
    options.music = options.music == nil and 413 or options.music
    cases[#cases + 1] = options
  end
  if version == "emerald" then
    for _, weather in ipairs({ 0, 8 }) do
      for _, flag in ipairs({ false, true }) do
        add(
          "ROUTE111",
          26,
          { weather = weather, activeWeather = weather == 8 and 0 or 8, flags = { [2186] = flag } }
        )
      end
    end
    for _, sky in ipairs({ 0, 1, 2 }) do
      for _, flag in ipairs({ false, true }) do
        for _, city in ipairs({ 3, 4 }) do
          add("SOOTOPOLIS_CITY", 7, { flags = { [2186] = flag }, vars = { [16586] = sky, [16478] = city } })
        end
      end
    end
    local legendary = {
      { "LILYCOVE_CITY", 5 },
      { "MOSSDEEP_CITY", 6 },
      { "EVER_GRANDE_CITY", 8 },
      { "ROUTE124", 39 },
      { "ROUTE125", 40 },
      { "ROUTE126", 41 },
      { "ROUTE127", 42 },
      { "ROUTE128", 43 },
      { "ROUTE129", 44 },
      { "ROUTE130", 45 },
      { "ROUTE131", 46 },
    }
    for _, map in ipairs(legendary) do
      for _, flag in ipairs({ false, true }) do
        for _, city in ipairs({ 3, 4 }) do
          add(map[1], map[2], { flags = { [2186] = flag }, vars = { [16478] = city } })
        end
      end
    end
    for floor = 1, 2 do
      for _, state in ipairs({ 0, 1, 2, 3 }) do
        add(
          "MOSSDEEP_CITY_SPACE_CENTER_" .. floor .. "F",
          floor + 8,
          { group = 14, vars = { [16477] = state } }
        )
      end
      for _, state in ipairs({ 0, 1 }) do
        add(
          "ROUTE119_WEATHER_INSTITUTE_" .. floor .. "F",
          floor - 1,
          { group = 32, vars = { [16563] = state } }
        )
      end
    end
    for _, x in ipairs({ 0, 23, 24, 50 }) do
      for _, music in ipairs({ 32767, "32767", 413 }) do
        add("ROUTE118", 33, { x = x, music = music })
      end
    end
    for _, music in ipairs({ 413, "413", 0, "unregistered-header" }) do
      add("OWNED_UNRELATED", 120, { music = music, weather = 8, flags = { [2186] = true } })
    end
  else
    for _, music in ipairs({ 0, 413, 65535 }) do
      add("ROUTE111", 26, { music = music, weather = 8, flags = { [2186] = true } })
      add("SOOTOPOLIS_CITY", 7, { music = music, vars = { [16586] = 1 } })
    end
  end
  local rows = {}
  for index, input in ipairs(cases) do
    local h =
      dofile(root .. "/tests/native_bgm/fixture.lua").install(root, backend, version, f, { policy = true })
    h.location(input)
    local runner =
      h.start({ { "playbgm", h.ids[2], 0 }, { "savebgm", h.ids[3] }, { "fadedefaultbgm" }, { "end" } })
    local frames = {}
    for tick = 0, 4 do
      h.tick(tick)
      if tick == 2 then
        -- Re-read live values: a previous result must not become a cached header.
        h.location({
          name = input.name,
          group = input.group,
          number = input.number,
          x = 24,
          music = input.music,
          weather = 0,
          flags = {},
          vars = { [16586] = 2, [16477] = 3, [16563] = 1 },
        })
        runner = h.start({ { "fadedefaultbgm" }, { "end" } })
      end
      local state = h.state()
      state.tick, state.running = tick, runner:isRunning()
      frames[#frames + 1] = state
      h.update()
    end
    rows[#rows + 1] = { case = index, input = input, frames = frames, plays = h.trace() }
    h.close()
  end
  f.close()
  return rows
end
return M
