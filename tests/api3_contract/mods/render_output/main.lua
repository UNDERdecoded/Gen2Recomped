local mod = ...
assert(mod:supports("hooks", "render.output"))
assert(mod:supports("hooks", "render.output_enabled"))
local enabled, handled, callback, gate = false, false, nil, nil
local trace = {}
mod.hooks:wrap("render.output_enabled", function(next)
  if gate then
    return gate()
  end
  if enabled then
    return true
  end
  return next()
end)
mod.hooks:wrap("render.output", function(next, ctx)
  assert(ctx.canvas and ctx.width == 320 and ctx.height == 288 and ctx.generation == mod.generation)
  trace[#trace + 1] = {
    width = ctx.width,
    height = ctx.height,
    gameWidth = ctx.gameWidth,
    gameHeight = ctx.gameHeight,
    gameX = ctx.gameX,
    gameY = ctx.gameY,
    scale = ctx.scale,
    dpiX = ctx.dpiX,
    dpiY = ctx.dpiY,
    generation = ctx.generation,
  }
  if callback then
    return callback(ctx)
  end
  if handled then
    return true
  end
  return next(ctx)
end)
mod.exports.state = function(on, owns)
  enabled, handled = on, owns
end
mod.exports.callback = function(fn)
  callback = fn
end
mod.exports.gate = function(fn)
  gate = fn
end
mod.exports.trace = function()
  return trace
end
