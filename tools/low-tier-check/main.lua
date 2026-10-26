-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
local root = assert(os.getenv("LOW_TIER_QA_ROOT"))
package.path = root .. "/?.lua;" .. root .. "/?/init.lua;" .. package.path
local P = require("src.core.Performance")
local Profile = require("src.core.FrameProfile")
local Json = require("src.link.Json")
local Assets = require("src.render.Assets")
local Bag = require("src.ui.Gen3BagMenu")
local Box = require("src.ui.Gen3BoxMenu")
local Text = require("src.render.TextBox")
local phase, frame, total, allocations = 1, 0, 0, 0
local function art(w, h)
  local data = love.image.newImageData(w, h)
  data:mapPixel(function(x, y)
    return ((x * 13 + y * 3) % 256) / 255, ((x * 7 + y * 17) % 256) / 255, ((x * 19 + y * 11) % 256) / 255, 1
  end)
  local image = love.graphics.newImage(data)
  image:setFilter("nearest", "nearest")
  data:release()
  return image
end
local sheet, icon, arrow = art(128, 64), art(16, 64), art(30, 12)
Assets.image = function(path)
  if path == "arrow" then
    return arrow
  end
  return sheet
end
local bag = setmetatable(
  {
    pocket = 1,
    game = {
      save = { player = {} },
      data = {
        items = {},
        constants = {
          gen3Bag = { male = "owned", frames = 8, frameWidth = 16, frameHeight = 16 },
          gen3ItemIcons = { image = "owned", size = 16, cols = 8, count = 32 },
        },
      },
    },
  },
  Bag
)
local box = setmetatable({
  t = 0,
  iconFor = function()
    return icon, 16
  end,
}, Box)
local text = setmetatable(
  {
    boxTx = 0,
    boxTy = 0,
    boxTw = 20,
    boxTh = 6,
    drawFrame = false,
    shown = { {} },
    line1Y = 184,
    line2Y = 200,
    textX = 12,
    waiting = true,
    promptArrowAtPen = true,
    promptArrow = { path = "arrow", width = 10, height = 12, frames = 3 },
    promptArrowImage = arrow,
    blink = 0,
  },
  Text
)
local target = love.graphics.newCanvas(320, 240, { dpiscale = 1 })
local originalQuad = love.graphics.newQuad
love.graphics.newQuad = function(...)
  allocations = allocations + 1
  return originalQuad(...)
end
local function draw()
  love.graphics.setCanvas(target)
  love.graphics.clear(0, 0, 0, 1)
  love.graphics.setColor(1, 1, 1, 1)
  for i = 0, 63 do
    bag.pocket = i % 8 + 1
    local img, q = bag:bagFrame()
    love.graphics.draw(img, q, (i % 16) * 20, math.floor(i / 16) * 20)
    img, q = bag:itemIcon(nil, i % 32)
    love.graphics.draw(img, q, (i % 16) * 20, 90 + math.floor(i / 16) * 20)
    box.t = i * 0.1
    box:drawIcon({}, (i % 16) * 20 + 8, 166)
    local crop = box:frlgQuad(sheet, (i % 8) * 16, 16, 16, 16)
    love.graphics.draw(sheet, crop, (i % 16) * 20, 210)
  end
  text.blink = frame % 36
  text:draw()
  love.graphics.setCanvas()
end
local checks, results = 0, {}
local function check(ok, msg)
  assert(ok, msg)
  checks = checks + 1
end
local function qualify()
  for _, tick in ipairs({ 0, 9, 18, 27 }) do
    frame = tick
    P.lowTierBudget = false
    draw()
    local before = target:newImageData():getString()
    P.lowTierBudget = true
    draw()
    check(target:newImageData():getString() == before, "native UI pixels changed after quad reuse")
  end
  local owner = require("src.render.UiQuad")
  local a, b = {}, {}
  local qa = owner.get(a, "test", sheet, 0, 0, 16, 16, 128, 64)
  local qb = owner.get(b, "test", sheet, 16, 16, 16, 16, 128, 64)
  check(qa ~= qb, "native quad owner storage overlaps")
end
function love.errorhandler(message)
  print(debug.traceback(tostring(message), 2))
  return function()
    return 1
  end
end
function love.run()
  qualify()
  frame, allocations = 0, 0
  return function()
    love.event.pump()
    for e in love.event.poll() do
      if e == "quit" then
        return 1
      end
    end
    P.lowTierBudget = phase == 2
    if frame == 120 then
      Profile.setEnabled(true)
      allocations = 0
    end
    local close = Profile.section("native UI quads (owned art)")
    local began = love.timer.getTime()
    draw()
    if frame >= 120 then
      total = total + love.timer.getTime() - began
    end
    close()
    local fence = target:newImageData(1, 1, 0, 0, 1, 1)
    fence:release()
    if frame >= 120 then
      Profile.frame()
    end
    frame = frame + 1
    if frame == 240 then
      results[phase] = {
        mode = phase == 1 and "legacy" or "cached",
        frames = 120,
        warmupFrames = 120,
        meanMs = total / 120 * 1000,
        quadAllocations = allocations,
      }
      if phase == 2 then
        check(
          results[1].quadAllocations > 0 and results[2].quadAllocations == 0,
          "native quad allocations were not eliminated after warmup"
        )
        print(
          "LOW_TIER_RESULT "
            .. Json.encode({
              phases = results,
              checks = checks,
              renderer = love.graphics.getRendererInfo(),
              scope = "Actual bag, box and textbox draw producers with owned artwork; CPU draw submission, no ROM or full-game FPS",
            })
        )
        return 0
      end
      Profile.setEnabled(false)
      phase, frame, total, allocations = 2, 0, 0, 0
    end
  end
end
