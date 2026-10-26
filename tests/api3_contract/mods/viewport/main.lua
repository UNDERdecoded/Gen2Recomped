local mod = ...
assert(mod:supports("hooks", "render.viewport"))
assert(mod:supports("hooks", "render.window"))
assert(mod:supports("hooks", "input.pointer"))
local request, canvasRef, windowAction = nil, nil, nil
local trace = { viewport = {}, window = {}, pointer = {} }
mod.hooks:wrap("render.viewport", function(next, ctx)
  trace.viewport[#trace.viewport + 1] = {
    width = ctx.width,
    height = ctx.height,
    pixelWidth = ctx.pixelWidth,
    pixelHeight = ctx.pixelHeight,
    dpiX = ctx.dpiX,
    dpiY = ctx.dpiY,
    generation = ctx.generation,
  }
  if request then
    return request
  end
  return next(ctx)
end)
mod.hooks:wrap("render.window", function(next, game, ctx)
  assert(ctx.canvas == canvasRef)
  trace.window[#trace.window + 1] = {
    x = ctx.x,
    y = ctx.y,
    width = ctx.width,
    height = ctx.height,
    windowWidth = ctx.windowWidth,
    windowHeight = ctx.windowHeight,
    dpiX = ctx.dpiX,
    dpiY = ctx.dpiY,
    generation = ctx.generation,
  }
  if windowAction then
    return windowAction(next, game, ctx)
  end
  return next(game, ctx)
end)
mod.hooks:wrap("input.pointer", function(next, game, ctx)
  trace.pointer[#trace.pointer + 1] = {
    phase = ctx.phase,
    source = ctx.source,
    id = ctx.id,
    x = ctx.x,
    y = ctx.y,
    gameX = ctx.gameX,
    gameY = ctx.gameY,
    insideGame = ctx.insideGame,
    dx = ctx.dx,
    dy = ctx.dy,
    pressure = ctx.pressure,
    button = ctx.button,
  }
  return next(game, ctx)
end)
mod.exports.request = function(value)
  request = value
end
mod.exports.canvas = function(value)
  canvasRef = value
end
mod.exports.window = function(fn)
  windowAction = fn
end
mod.exports.trace = function()
  return trace
end
