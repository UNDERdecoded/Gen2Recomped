local M = {}
function M.fixture(root, backend, version)
  local codeRoot = debug.getinfo(1, "S").source:sub(2):match("^(.*)/script_shops%.lua$")
  local f = dofile(codeRoot .. "/script_gifts.lua").fixture(root, backend, version, "script_shops")
  local data = f.game.data
  f.ow.game, f.ow.text = f.game, data.text
  f.ow.map.def.label = "SHOP_HOME"
  data.text_pointers = { SHOP_HOME = { SHOP = { mart = { "POTION" } } } }
  if data.items and data.items.POTION then
    data.items.POTION.price = 100
  end
  if backend == "gen1" and f.gen == 3 then
    require("src.core.game3.scripting.space").ensureBundle = function()
      local IR = require("src.core.game3.scripting.text_ir")
      return {
        text = {
          Text_MayIHelpYou = IR.fromAscii("WELCOME"),
          gText_HowMayIServeYou = IR.fromAscii("WELCOME"),
        },
      }
    end
  end
  if backend == "gen1" and f.gen == 2 then
    f.ow.openMart = require("src.world.gen2.World").openMart
  end
  function f:tick(key)
    self.game.input.wasPressed = function(_, button)
      return button == key
    end
    self.loader.hooks:call(backend == "gen1" and "core.update" or "input.step", function()
      if backend == "gen2" then
        self.ow.runner:update()
      end
    end, self.game, 1 / 60)
    self.game.stack:update(1 / 60)
    self.game.input.wasPressed = function()
      return false
    end
  end
  function f:close()
    if backend == "gen1" and f.gen == 3 then
      require("src.ui.game3.shop_menu").close()
    else
      for _ = 1, 2000 do
        if self.exports.result().done > 0 then
          return
        end
        self:tick("b")
      end
      error("native shop did not close")
    end
  end
  function f:drain()
    for _ = 1, 100 do
      if self.exports.result().done > 0 then
        return
      end
      self:tick()
    end
    error("shop script did not finish")
  end
  return f
end
function M.run(root, backend, version)
  local f = M.fixture(root, backend, version)
  local ok, why = f.exports.queue({ { "open_mart", "SHOP" }, { "set_flag", "mod:after" } })
  assert(ok, why)
  assert(
    f.exports.result().done == 0 and not f.exports.get("mod:after"),
    require("src.link.Json").encode(f.exports.result()) .. " " .. table.concat(f.loader.errors, "; ")
  )
  f:close()
  f:drain()
  assert(f.exports.result().success and f.exports.get("mod:after"))
  local report = { complete = true, quantity = f.quantity() }
  f = M.fixture(root, backend, version)
  local value, reason = f.exports.queue({ { "set_flag", "mod:prefix" }, { "open_mart", "UNKNOWN" } })
  assert(value == nil and type(reason) == "string" and not f.exports.get("mod:prefix"))
  report.preflight = true
  print("API3_CONTRACT " .. require("src.link.Json").encode(report))
  return report
end
return M
