package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.modkit")
local Contract = require("tests.api3_contract.render_output")
local Runtime = require("src.mods.Runtime")
local Version = require("src.core.GameVersion")
local saved = { Version.get(), Runtime.events, Runtime.hooks, Runtime.errors, Runtime.currentMod, love }
local Output = require("src.render.Output")
for _, v in ipairs({ "red", "blue", "yellow", "gold", "silver", "crystal", "firered", "emerald" }) do
  local ok, why = pcall(Contract.run, "tests/api3_contract", "gen2", v)
  T.check(ok, v .. " output boundary contract: " .. tostring(why))
end
for _, mode in ipairs({ "dirty", "throw", "leak", "overpop" }) do
  local f = Contract.fixture("tests/api3_contract", "gen2", "red")
  local G = love.graphics
  local previous, foreign, shader = {}, {}, {}
  G.setCanvas(previous)
  G.setShader(shader)
  G.setColor(0.2, 0.3, 0.4, 0.5)
  G.setBlendMode("add")
  local originalPush, originalPop = G.push, G.pop
  f.exports.state(true, true)
  f.exports.callback(function()
    G.setShader({})
    G.setCanvas(foreign)
    G.setColor(1, 0, 0, 1)
    G.setBlendMode("replace")
    if mode == "throw" then
      error("injected output failure")
    end
    if mode == "leak" then
      G.push("all")
      G.push("all")
    end
    if mode == "overpop" then
      G.pop()
    end
    return true
  end)
  local ctx = {
    canvas = {},
    width = 320,
    height = 288,
    gameX = 0,
    gameY = 0,
    gameWidth = 320,
    gameHeight = 288,
    scale = 2,
    dpiX = 1,
    dpiY = 1,
    generation = 1,
  }
  T.eq(Output.enabled(), true, "enabled output owner")
  T.eq(Output.draw(ctx), mode == "dirty" or mode == "leak", "error/overpop falls back")
  T.eq(G.getCanvas(), previous, "canvas restored after " .. mode)
  T.eq(G.getShader(), shader, "shader restored after " .. mode)
  T.eq(G.getBlendMode(), "add", "blend restored after " .. mode)
  T.eq(select(1, G.getColor()), 0.2, "color restored after " .. mode)
  T.eq(G.push, originalPush, "push wrapper removed after " .. mode)
  T.eq(G.pop, originalPop, "pop wrapper removed after " .. mode)
  f.exports.gate(function()
    G.setCanvas(foreign)
    G.setShader({})
    return 1
  end)
  T.eq(Output.enabled(), false, "only exact true enables capture")
  T.eq(G.getCanvas(), previous, "predicate canvas restored")
  T.eq(G.getShader(), shader, "predicate shader restored")
  local mod = f.loader.apis.render_output
  mod.hooks:wrap("render.output_enabled", function(next)
    return next()
  end, -10)
  mod.hooks:wrap("render.output", function(next, frame)
    return next(frame)
  end, -10)
  f.loader:_rollback("render_output")
  T.eq(Output.enabled(), false, "unloaded owner no longer captures output")
end
Version.set(saved[1])
Runtime.events, Runtime.hooks, Runtime.errors, Runtime.currentMod = saved[2], saved[3], saved[4], saved[5]
love = saved[6]
T.finish()
