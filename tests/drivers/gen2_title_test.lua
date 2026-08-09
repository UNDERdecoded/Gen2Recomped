-- Driver: the Gen2 attract movie + title screen.
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local field = game.data.field or {}
  U.log("title layout:", tostring(field.title and field.title.layout))
  U.log("intro layout:", tostring(field.intro and field.intro.layout))

  local function top()
    local s = game.stack.states[#game.stack.states]
    return s and (s.__name or tostring(getmetatable(s))) or "nil"
  end

  local shots = {
    { 80, "gen2_s1_copyright.png" },
    { 240, "gen2_s2_gamefreak.png" },
    { 450, "gen2_s3_ocean.png" },
    { 700, "gen2_s4_meadow.png" },
    { 900, "gen2_s5_meadow2.png" },
    { 1060, "gen2_s6_title.png" },
  }
  local frame = 0
  for _, shot in ipairs(shots) do
    U.wait(shot[1] - frame)
    love.graphics.captureScreenshot(shot[2])
    U.wait(2)
    frame = shot[1] + 2
    U.log(shot[2], top())
  end
  U.log("DONE")
  love.event.quit()
end
