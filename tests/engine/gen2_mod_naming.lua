-- The public Gen1Recomp ID and caller-owned completion used by Anytime Rename.
package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.modkit")
local Screens = require("src.ui.Screens")
local Font = require("src.render.Font")
local V = require("src.core.GameVersion")
local original = V.get()
V.set("gold")
local data = T.fixtures.fresh()
data.font.charmap[#data.font.charmap + 1] = { seq = "<PK>", code = 0xe1 }
Font.load(data)
local run = T.sdk.loadMods(
  { "mods/rename_probe" },
  {
    data = data,
    fs = T.sdk.memfs({
      ["mods/rename_probe/manifest.json"] = [[{
    "id":"rename_probe", "name":"Rename probe", "version":"1.0.0",
    "api":2, "entry":"main.lua", "affects_link":false
  }]],
      ["mods/rename_probe/main.lua"] = [[
    local mod = ...
    mod.exports.open = function(game, opts)
      return mod.ui.push(game, "Gen2NamingScreen", opts)
    end
    mod.hooks:wrap("ui.naming.grid", function(nextFn, grid, ctx)
      local out = nextFn(grid, ctx)
      if ctx.title == "LOCALIZED?" then
        local copy = {}
        for i, row in ipairs(out) do
          copy[i] = {}
          for j, cell in ipairs(row) do copy[i][j] = cell end
        end
        copy[1][1] = "Ä"
        return copy
      end
      return out
    end)
  ]],
    }),
  }
)
T.eq(#run.errors, 0, "the API-2 screen probe loads")
local game = { data = data, save = { player = {} }, stack = { states = {} } }
function game.stack:push(s)
  self.states[#self.states + 1] = s
  if s.enter then
    s:enter()
  end
end
function game.stack:pop()
  return table.remove(self.states)
end
function game.stack:top()
  return self.states[#self.states]
end
local function press(screen, key)
  game.input = {
    wasPressed = function(_, k)
      return k == key
    end,
  }
  screen:update(1 / 60)
end
local open = run.loader.exports.rename_probe.open
for _, spec in ipairs({
  { "player", 7 },
  { "rival", 7 },
  { "mom", 7 },
  { "box", 8 },
  { "nickname", 10 },
}) do
  Screens.invalidate()
  local parent = { name = "parent" }
  game.stack.states = { parent }
  local calls, result = 0, nil
  local screen
  screen = open(game, {
    type = spec[1],
    initial = "AB",
    onDone = function(name)
      calls, result = calls + 1, name
      T.eq(game.stack:top(), screen, "the caller still owns the naming screen at completion")
      game.stack:pop() -- exactly what the existing Gen1Recomp mod does
    end,
  })
  T.eq(screen.screenId, "Gen2NamingScreen", "the public screen ID resolves")
  T.eq(screen.maxLength, spec[2], spec[1] .. " keeps its name limit")
  T.eq(screen.text, "AB", "the initial name is editable")
  press(screen, "b")
  T.eq(screen.text, "A", "B deletes one initial glyph")
  screen.row, screen.col = 1, 2
  press(screen, "a")
  T.eq(screen.text, "AB", "native keyboard input updates the public text")
  -- Native START confirms; Gen2Recomped may reuse its own keyboard layout.
  press(screen, "start")
  T.eq(calls, 1, "completion calls the caller once")
  T.eq(result, "AB", "completion returns the edited name")
  T.eq(game.stack:top(), parent, "completion preserves the parent state")
end

Screens.invalidate()
local parent = {}
game.stack.states = { parent }
local result
local screen = open(game, {
  type = "nickname",
  prompt = "LOCALIZED?",
  initial = "",
  maxLength = 2,
  monName = "FIXMON",
  onDone = function(name)
    result = name
  end,
})
T.eq(screen.prompt, "LOCALIZED?", "explicit localized prompt survives")
T.eq(screen.monName, "FIXMON", "the nickname header is retained")
press(screen, "a")
T.eq(screen.text, "Ä", "the public grid hook supplies a Unicode glyph")
screen.row, screen.col = 1, 2
press(screen, "a")
T.eq(screen.text, "ÄB", "the name limit counts glyphs rather than bytes")
press(screen, "start")
T.eq(result, "ÄB", "Unicode completion keeps the full glyph")
T.eq(game.stack:top(), screen, "an observing callback does not implicitly close the screen")
press(screen, "b")
T.eq(screen.text, "Ä", "deletion keeps a multi-byte glyph whole")
screen.text = "<PK>ÄZ"
T.eq(screen.text, "<PK>Ä", "direct text assignment respects charmap glyphs and the limit")
T.eq(#screen.glyphs, 2, "the native keyboard receives two actual glyphs")

-- The original, unqualified screen keeps its existing pop-before-callback API.
Screens.invalidate()
game.stack.states = { parent }
local ordinary = Screens.push(game, "NamingScreen", {
  default = "RED",
  onDone = function(name)
    T.eq(game.stack:top(), parent, "ordinary NamingScreen still pops before callback")
    T.eq(name, "RED", "ordinary NamingScreen retains its default-name behavior")
  end,
})
press(ordinary, "start")
T.eq(game.stack:top(), parent, "ordinary screen closes exactly once")

-- A registry override remains authoritative for the compatibility ID.
Screens.invalidate()
local custom = { custom = true }
data.screens = data.screens or {}
data.screens.Gen2NamingScreen = {
  new = function(_, opts)
    T.eq(opts.initial, "OVERRIDE", "screen overrides receive original Gen2 options")
    return custom
  end,
}
T.eq(open(game, { initial = "OVERRIDE" }), custom, "registered screen overrides win")
T.eq(#run.errors, 0, "the native flows produce no mod errors")
run.release()
Screens.invalidate()
V.set(original)
T.finish("public Gen2 mod naming compatibility")
