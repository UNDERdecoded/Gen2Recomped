-- Run the adapter around the actual host summary controller, without a ROM.
local root = arg[1] or "."
local S = dofile(root .. "/src/ui/Gen3SummaryLayout.lua")
local generation = 3
local version = "emerald"
local buttons = {}
local calls = {}
local depth, tones, faces = 0, 0, 0
local function record(kind, ...)
  calls[#calls + 1] = { kind, ... }
end
local F = {
  width = function(s)
    return #tostring(s) * 6
  end,
  draw = function(s, x, y)
    record("text", s, x, y)
  end,
  drawCode = function() end,
  drawBox = function() end,
  hasFace = function()
    return true
  end,
  pushFace = function()
    faces = faces + 1
  end,
  popFace = function()
    faces = faces - 1
  end,
  beginTwoTone = function()
    tones = tones + 1
    return true
  end,
  endTwoTone = function()
    tones = tones - 1
  end,
}
package.loaded["src.render.Font"] = F
package.loaded["src.core.Logger"] = { warn = function() end }
package.loaded["src.pokemon.Stats"] = {}
local strings = { PP = "AP", POWER = "STÄRKE", ACCURACY = "GENAUIGKEIT", CANCEL = "ZURÜCK" }
package.loaded["src.core.Strings"] = function(s)
  return strings[s] or s
end
package.loaded["src.battle.TypeChart"] = {
  displayName = function(s)
    return s
  end,
}
package.loaded["src.core.GameVersion"] = {
  get = function()
    return version
  end,
  generation = function()
    return generation
  end,
}
package.loaded["src.pokemon.Pokemon"] = {
  maxPP = function(def, slot)
    return def.pp + (type(slot) == "table" and (slot.ppUps or 0) * 2 or 0)
  end,
  genderOf = function()
    return "male"
  end,
}
package.loaded["src.pokemon.Sprites"] = {
  path = function()
    return nil
  end,
}
package.loaded["src.pokemon.PicAnim"] = {
  forMon = function()
    return nil
  end,
}
package.loaded["src.pokemon.MonAnim"] = {
  new = function()
    return nil
  end,
}
local image = {
  getDimensions = function()
    return 32, 368
  end,
  getHeight = function()
    return 368
  end,
}
package.loaded["src.render.Assets"] = {
  image = function()
    return image
  end,
}
love = {
  graphics = {
    push = function()
      depth = depth + 1
    end,
    pop = function()
      depth = depth - 1
    end,
    translate = function() end,
    scale = function() end,
    setColor = function() end,
    rectangle = function() end,
    newQuad = function(x, y, w, h)
      return { x = x, y = y, w = w, h = h, release = function() end }
    end,
    draw = function(_, q, x, y)
      record("image", q.x, q.y, x, y)
    end,
  },
}
local Menu = dofile(root .. "/src/ui/Gen3SummaryMenu.lua")
package.loaded["src.ui.Gen3SummaryMenu"] = Menu
Menu.__summaryPresentation = nil
local forwarded = 0
Menu.drawMoves = function()
  forwarded = forwarded + 1
end
Menu.drawFireRed = function()
  forwarded = forwarded + 1
end
S.apply(Menu)
local palette = {}
for i = 0, 127 do
  palette[i] = { 0, 0, 0, 1 }
end
local data = {
  pokemon = { B = { name = "SPECIES", type1 = "GRASS", type2 = "POISON" } },
  moves = {},
  type_chart = { types = { GRASS = { index = 12 }, POISON = { index = 3 } } },
  constants = {
    gen3Summary = {
      pages = { "INFO", "SKILLS", "MOVES", "CONTEST" },
      pageArt = { info = "info", panel = "panel" },
      typeBadges = { image = "types" },
    },
    summaryParts = {
      images = { buttons = "buttons", markings = "marks", selector = "cursor" },
      palette = palette,
    },
    summaryWords = {
      info = "INFO",
      cancel = "ZURÜCK",
      switch = "TAUSCH",
      level = "Lv",
      PageCancel = "{DPAD_RIGHT}SEITE {A_BUTTON}ZURÜCK",
    },
  },
}
data.constants.gen3Summary.parts = data.constants.summaryParts
data.constants.gen3Summary.words = data.constants.summaryWords
for i = 1, 5 do
  data.moves["M" .. i] = {
    name = "CUSTOM MOVE " .. i,
    type = "GRASS",
    pp = 10,
    contestType = (i - 1) % 5,
    description = "effect " .. i,
    power = 35,
    accuracy = 95,
  }
end
local mon = { species = "B", nickname = "PP10/10", level = 15, moves = {} }
for i = 1, 4 do
  mon.moves[i] = { id = "M" .. i, pp = i, ppUps = i % 3 }
end
local pops = 0
local game = {
  data = data,
  save = { player = { name = "OT" }, party = { mon } },
  input = {
    wasPressed = function(_, key)
      return buttons[key]
    end,
  },
  stack = {
    pop = function()
      pops = pops + 1
    end,
  },
}
local function screen(opts)
  opts = opts or {}
  opts.mon = mon
  local s = Menu.new(game, opts)
  s.hasArt = true
  s.drawPagination = function() end
  s.drawDescription = function(_, value)
    record("description", value)
  end
  s.drawHearts = function()
    record("hearts")
  end
  return s
end
local function press(s, key)
  buttons = { [key] = true }
  s:update(1 / 60)
  buttons = {}
end
local function has(kind, value)
  for _, row in ipairs(calls) do
    if row[1] == kind and row[2] == value then
      return true
    end
  end
  return false
end
local menu = screen()
menu.page = 3
local slots = mon.moves
calls = {}
menu:drawMoves(false)
assert(
  has("text", "AP1/12") and not has("description"),
  "Normal move page must use localized PP and keep details closed"
)
local icons = 0
for _, row in ipairs(calls) do
  if row[1] == "image" and row[3] == 12 * 16 then
    icons = icons + 1
  end
end
assert(icons == 4, "Missing battle move type icons")
press(menu, "a")
assert(menu.moveSelect)
press(menu, "down")
calls = {}
menu:drawMoves(false)
assert(has("description", "effect 2"))
local a, b = slots[2], slots[3]
press(menu, "a")
press(menu, "down")
press(menu, "a")
assert(
  slots[2] == b and slots[3] == a and slots == mon.moves and a.pp == 2 and b.pp == 3,
  "Native reorder lost slot PP/identity"
)
press(menu, "b")
assert(not menu.moveSelect)
press(menu, "b")
assert(pops == 1)
local answer
menu = screen({ choose = {
  move = "M5",
  onChoose = function(i)
    answer = i
  end,
} })
for _ = 1, 4 do
  press(menu, "down")
end
assert(menu.moveIndex == 5)
calls = {}
menu:drawMoves(false)
assert(has("description", "effect 5") and has("text", "CUSTOM MOVE 5"))
press(menu, "a")
assert(answer == 5 and pops == 2)
menu = screen({
  choose = {
    move = "M5",
    onChoose = function(i)
      answer = i or "cancel"
    end,
  },
})
press(menu, "b")
assert(answer == "cancel" and pops == 3)
local full = mon.moves
mon.moves = { full[1] }
menu = screen({ choose = {
  move = "M5",
  onChoose = function(i)
    answer = i
  end,
} })
press(menu, "down")
assert(menu.moveIndex == 2)
calls = {}
menu:drawMoves(false)
assert(has("text", "CUSTOM MOVE 5") and has("description", "effect 5"))
press(menu, "a")
assert(answer == 2)
mon.moves = full
menu = screen()
menu.page = 4
calls = {}
menu:drawMoves(true)
local categories = 0
for _, row in ipairs(calls) do
  if row[1] == "image" and row[3] >= 18 * 16 then
    categories = categories + 1
  end
end
assert(categories == 4, "Missing contest categories")
assert(
  S.moveType({ type = "CUSTOM" }, data.type_chart) == nil
    and S.moveType({ type = 17 }, data.type_chart) == 17
)
assert(
  S.ppColor(10, 10) == 12
    and S.ppColor(0, 10) == 11
    and S.ppColor(2, 10) == 10
    and S.ppColor(5, 10) == 9
    and S.ppColor(3, 7) == 12
    and S.ppColor(1, 2) == 10
)
local dexData = {
  pokemon = { B = { dex = 1 }, T = { dex = 252 } },
  constants = { gen3HoennDex = { native = 202, numbers = { T = 1 } } },
}
assert(
  S.dexNumber(dexData, {}, { species = "B" }) == nil
    and S.dexNumber(dexData, {}, { species = "T" }) == 1
)
assert(
  S.dexNumber(dexData, { nationalDex = true }, { species = "B" }) == 1
    and S.dexNumber(dexData, { nationalDex = true }, { species = "T" }) == 252
)
for lang, pp in pairs({ en = "PP", de = "AP", es = "PP", fr = "PP", it = "PP", ["pt-BR"] = "PP" }) do
  strings.PP = pp
  calls = {}
  menu.page = 3
  menu:drawMoves(false)
  assert(has("text", pp .. "1/12"), lang .. " PP label not read from the current catalog")
end
strings.PP = "AP"
calls = {}
menu:drawHeader()
assert(has("text", "PP10/10"), "Nickname was changed into a UI translation")
local draw = F.draw
F.draw = function()
  error("native font failure")
end
assert(not pcall(menu.drawMoves, menu, false))
assert(depth == 0 and tones == 0 and faces == 0, "Failed draw leaked graphics/font state")
F.draw = draw
data.constants.gen3Summary.parts = nil
menu:drawMoves(false)
assert(forwarded == 1)
data.constants.gen3Summary.parts = data.constants.summaryParts
generation = 2
menu:drawMoves(false)
assert(forwarded == 2)
generation = 3
version = "firered"
menu.page = 1
calls = {}
menu:drawFireRed({})
assert(
  has("text", "SEITE ") and has("text", "ZURÜCK"),
  "FireRed header did not use the source control words"
)
local beforeFailure = forwarded
F.draw = function()
  error("hint font failure")
end
assert(not pcall(menu.drawFireRed, menu, {}))
assert(faces == 0 and depth == 0 and tones == 0)
F.draw = draw
forwarded = beforeFailure
assert(forwarded == 3 and faces == 0)
version = "emerald"
data.constants.gen3Summary.parts = nil
menu:drawMoves(false)
assert(forwarded == 4)

print(
  "GEN3_SUMMARY_TEST_OK native navigation, swap identity/PP, short and fifth-row learning, cancel, types/categories, six PP labels, fallback, graphics cleanup"
)
