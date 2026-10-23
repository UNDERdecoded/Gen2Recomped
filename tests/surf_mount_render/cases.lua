local M = {}
function M.all()
  local out = {}
  for _, facing in ipairs({ "down", "up", "left", "right" }) do
    for _, tick in ipairs({ 0, 15, 16, 31, 32, 47, 48, 49, 95, 96 }) do
      out[#out + 1] = { facing = facing, tick = tick, name = facing .. ":" .. tick }
    end
  end
  for _, mode in ipairs({
    "inactive",
    "underwater",
    "hidden",
    "multipartFishing",
    "spin",
    "hop",
    "boarding",
    "dismounting",
  }) do
    out[#out + 1] = { facing = "right", tick = 16, mode = mode, name = mode }
  end
  return out
end
function M.apply(f, backend, case)
  local p = f.player
  p.spinning = nil
  p.spinTimer = nil
  p.hopFrames = nil
  p.hopTotal = nil
  p.fishing = nil
  p.fishTiles = nil
  p.hidden = false
  p.surfing = true
  if f.world then
    f.world.map.def.mapType = "TOWN"
  end
  f.setPhase(case.facing, case.tick)
  local mode = case.mode
  if mode == "inactive" then
    p.surfing = false
  elseif mode == "underwater" then
    p.surfing = false
    if f.world then
      f.world.map.def.mapType = "UNDERWATER"
    else
      p.underwater = true
    end
  elseif mode == "hidden" then
    p.hidden = true
  elseif mode == "multipartFishing" then
    p.fishing = true
    p.fishTiles = { right = {} }
  elseif mode == "spin" then
    p.spinning = true
    p.spinTimer = 1
  elseif mode == "hop" then
    p.hopFrames = 8
    p.hopTotal = 16
  elseif mode == "boarding" then
    if backend == "gen1" then
      p.surfHopping = true
    else
      p.surfing = false
    end
  elseif mode == "dismounting" then
    if backend == "gen1" then
      p.dismounting = true
    else
      p.surfing = false
    end
  end
end
return M
