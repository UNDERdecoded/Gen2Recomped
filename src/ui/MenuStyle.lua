-- MENU STYLE: one DS game's menus drawn with another imported game's art.
--
-- Every Gen 4/5 game opens its OWN start menu, bag, summary, Pokedex, trainer
-- card and PC by default -- which screen is decided in Screens.resolveId from
-- the art the game's own cache wrote. This module is the one sanctioned way
-- to change that: OPTIONS -> MENU STYLE, stored per game in the shared options
-- file as `options.menuStyle[<version>] = <donor version>`. Unset (OWN) is the
-- default, and anything that does not check out -- a donor that is not a DS
-- game, is not imported (any more), or is the game itself -- reads as OWN.
--
-- HOW A BORROWED SCREEN SEES THE DONOR'S ART without the donor's files being
-- on the read path (that was the bug: a previous game's data/generated left
-- mounted made Platinum draw Black's menus -- CacheFs.unmountVersion):
--   * the donor's menu-art modules are read straight from its version folder
--     (`black/data/generated/gen5_menu_art.lua`), and every
--     "assets/generated/..." path inside them is re-pointed at that folder
--     (`black/assets/generated/...`), so nothing of the donor is mounted;
--   * Screens.resolveId routes each slot to the donor family's screen
--     (MenuStyle.route), and Screens hands that screen a game whose `data`
--     overlays the donor modules on the game's own (MenuStyle.gameFor) -- the
--     game's real data table is never touched, so nothing else (scripts,
--     battles, the field panel) sees another game's modules.
-- A slot whose donor art is missing keeps the game's own screen for that slot
-- (a mix never breaks a screen; it falls back to OWN for it).
--
-- Pure Lua apart from love.filesystem.read; tests/menu_style_test.lua drives
-- it headless with a stub filesystem.

local MenuStyle = {}

MenuStyle.SLOTS = { "start", "bag", "summary", "dex", "card", "box" }

-- the screen each family opens for each slot (Screens.resolveId's own routes)
MenuStyle.SCREENS = {
  platinum = { start = "Gen4StartMenu", bag = "Gen4BagMenu", summary = "Gen4SummaryMenu",
               dex = "Gen4Pokedex", card = "Gen4TrainerCard", box = "Gen4BoxMenu" },
  hgss = { start = "HgssStartMenu", bag = "HgssBagMenu", summary = "HgssSummaryMenu",
           dex = "HgssPokedex", card = "HgssTrainerCard", box = "HgssBoxMenu" },
  bw = { start = "Gen5StartMenu", bag = "Gen5BagMenu", summary = "Gen5SummaryMenu",
         dex = "Gen5Pokedex", card = "Gen5TrainerCard", box = "Gen5BoxMenu" },
}

-- the cache modules each family's screen reads its art from; the FIRST one is
-- required (no file -> the slot stays the game's own), the rest ride along
-- when present. `lend` modules are the donor family's shared tables its
-- screens also read (Platinum's screen pictures and menu vocabulary); across
-- families they replace the borrowing game's for the borrowed screen. And
-- across families every borrowed screen reads the donor's `text` too: each
-- family's screens name their words by its own bank numbers (HGSS's start
-- menu is bank 196, its summary 302), and the same number in another game's
-- banks is some other line -- measured: Platinum's text in HGSS's start menu
-- printed trainer chatter over the buttons. Loaded on first use only.
MenuStyle.MODULES = {
  platinum = {
    start = { "gen4_start_menu_art", "gen4_start_menu_ink", "gen4_menu_art" },
    bag = { "gen4_bag_art", "gen4_summary_art", "gen4_shop_art" },
    summary = { "gen4_summary_art", "gen4_summary_ink" },
    dex = { "gen4_dex" },
    card = { "gen4_trainer_card_art" },
    box = { "gen4_box_art", "gen4_box_ink" },
    lend = { "gen4_graphics", "gen4_menus" },
  },
  hgss = {
    start = { "gen4_hgss_menu_art", "gen4_hgss_pokegear_art" },
    bag = { "gen4_hgss_bag_art" },
    summary = { "gen4_hgss_summary_art" },
    dex = { "gen4_hgss_dex_art", "gen4_version" },
    card = { "gen4_trainer_card_art" },
    box = { "gen4_hgss_box_art" },
  },
  bw = {
    start = { "gen5_menu_art" },
    bag = { "gen5_bag_art" },
    summary = { "gen5_summary_art", "gen5_bag_art" },
    dex = { "gen5_dex_art", "gen5_town_map" },
    card = { "gen4_trainer_card_art" },
    box = { "gen5_box_art", "gen5_bag_art" },
  },
}

-- SLOTS THAT ONLY WORK INSIDE THEIR OWN FAMILY. BW's Pokedex lists the Unova
-- dex, which a Sinnoh/Johto save has nothing in (measured: one "000 ?????"
-- row). Borrowed across families it falls back to the game's own screen.
MenuStyle.SAME_FAMILY_ONLY = { bw = { dex = true } }

-- the trainer card's art is one module for all three families; only a card
-- composed for the donor's family is the donor's card
local CARD_FLAG = { hgss = "hgss", bw = "bw" }

local SLOT_OF, FAMILY_OF = {}, {}
for family, screens in pairs(MenuStyle.SCREENS) do
  for slot, id in pairs(screens) do SLOT_OF[id], FAMILY_OF[id] = slot, family end
end

local REAL = setmetatable({}, { __mode = "k" })   -- proxy -> real game

local function GV() return require("src.core.GameVersion") end

-- "platinum" | "hgss" | "bw" for a DS Pokemon version, else nil
function MenuStyle.familyOf(version)
  local ok, info = pcall(function() return GV().info(version) end)
  if not (ok and type(info) == "table") then return nil end
  if (info.generation or 0) < 4 or info.engine ~= nil then return nil end
  local f = info.family or info.id
  if f == "hgss" or f == "bw" then return f end
  if info.generation == 4 then return "platinum" end
  return nil
end

function MenuStyle.real(game)
  return (game and REAL[game]) or game
end

-- the file reader; tests swap it for a table
MenuStyle.readFile = function(path)
  if not (love and love.filesystem and love.filesystem.read) then return nil end
  local ok, body = pcall(love.filesystem.read, path)
  return ok and type(body) == "string" and body or nil
end

local function prefixOf(version)
  local ok, p = pcall(function() return GV().cachePrefix(version) end)
  return ok and type(p) == "string" and p or nil
end

-- every "assets/generated/..." string re-pointed into the donor's folder
local function repoint(value, prefix, seen)
  if type(value) == "string" then
    if value:sub(1, 17) == "assets/generated/" then return prefix .. value end
    return value
  end
  if type(value) ~= "table" then return value end
  if seen[value] then return seen[value] end
  local out = {}
  seen[value] = out
  for k, v in pairs(value) do out[k] = repoint(v, prefix, seen) end
  return out
end

local function loadDonorModule(version, name)
  local prefix = prefixOf(version)
  if not prefix or prefix == "" then return nil end
  local body = MenuStyle.readFile(prefix .. "data/generated/" .. name .. ".lua")
  if not body then return nil end
  local chunk = (loadstring or load)(body, "@" .. prefix .. name)
  if not chunk then return nil end
  -- a generated module is a bare `return { ... }`: no globals needed
  if setfenv then setfenv(chunk, {}) end   -- (text.lua: numeric for only)
  local ok, mod = pcall(chunk)
  if not ok or type(mod) ~= "table" then return nil end
  return repoint(mod, prefix, {})
end

-- does `version` carry its family's art for `slot`? (cheap: one file probe)
local probeCache = {}
local function hasSlot(version, slot)
  local family = MenuStyle.familyOf(version)
  local mods = family and MenuStyle.MODULES[family][slot]
  if not mods then return false end
  local key = version .. ":" .. slot
  if probeCache[key] == nil then
    local prefix = prefixOf(version)
    local body = prefix and prefix ~= "" and MenuStyle.readFile(prefix .. "data/generated/" .. mods[1] .. ".lua")
    probeCache[key] = body ~= nil
  end
  return probeCache[key]
end

-- The donor versions this game may borrow from: every OTHER imported DS game
-- that carries at least its start menu art. Empty for Gen 1-3 (their menus are
-- a different engine; nothing to borrow) and for a DS game alone on the shelf.
function MenuStyle.choices(version)
  version = version or GV().get()
  local out = {}
  if not MenuStyle.familyOf(version) then return out end
  local ids = {}
  for id in pairs(GV().VERSIONS or {}) do ids[#ids + 1] = id end
  table.sort(ids, function(a, b)
    local ia, ib = GV().info(a), GV().info(b)
    if (ia.generation or 0) ~= (ib.generation or 0) then return (ia.generation or 0) < (ib.generation or 0) end
    return a < b
  end)
  for _, id in ipairs(ids) do
    if id ~= version and MenuStyle.familyOf(id) and hasSlot(id, "start") then out[#out + 1] = id end
  end
  return out
end

-- The donor this game's menus borrow from right now, or nil (= OWN).
function MenuStyle.donor(game)
  game = MenuStyle.real(game)
  local version = GV().get()
  local opts = game and game.save and game.save.options
  local map = opts and opts.menuStyle
  local d = type(map) == "table" and map[version] or nil
  if type(d) ~= "string" or d == "" or d == "own" or d == version then return nil end
  if not (MenuStyle.familyOf(version) and MenuStyle.familyOf(d)) then return nil end
  if not hasSlot(d, "start") then return nil end
  return d
end

local active = { key = nil, state = nil }

function MenuStyle.invalidate()
  active.key, active.state = nil, nil
  probeCache = {}
end

local function build(donor)
  local family = MenuStyle.familyOf(donor)
  local spec = MenuStyle.MODULES[family]
  local loaded = {}
  local function get(name)
    if loaded[name] == nil then loaded[name] = loadDonorModule(donor, name) or false end
    return loaded[name] or nil
  end
  local state = { donor = donor, family = family, slots = {} }
  -- the donor's whole text table (a few MB), read the first time a borrowed
  -- screen asks for `text`, then kept with the state
  function state.text()
    if state._text == nil then
      state._text = loadDonorModule(donor, "text") or false
    end
    return state._text or nil
  end
  local own = MenuStyle.familyOf(GV().get())
  local only = MenuStyle.SAME_FAMILY_ONLY[family] or {}
  for _, slot in ipairs(MenuStyle.SLOTS) do
    local mods = spec[slot]
    if only[slot] and own ~= family then mods = nil end
    local first = mods and get(mods[1])
    local okScreen = first and pcall(require, "src.ui." .. MenuStyle.SCREENS[family][slot])
    if first and slot == "card" and CARD_FLAG[family] and not first[CARD_FLAG[family]] then first = nil end
    if first and okScreen then
      local overlay = {}
      for _, name in ipairs(mods) do overlay[name] = get(name) end
      if own ~= family then
        for _, name in ipairs(spec.lend or {}) do overlay[name] = get(name) end
      end
      state.slots[slot] = { overlay = overlay, lendText = own ~= family }
    end
  end
  return state
end

-- the borrowing in force, or nil
function MenuStyle.state(game)
  local donor = MenuStyle.donor(game)
  if not donor then return nil end
  local key = tostring(GV().get()) .. ">" .. donor
  if active.key ~= key then
    active.key, active.state = key, build(donor)
    pcall(function()
      local n = 0
      for _ in pairs(active.state.slots) do n = n + 1 end
      require("src.core.Logger").info("menu style: %s borrows %s's menus (%d of %d screens)",
        tostring(GV().get()), donor, n, #MenuStyle.SLOTS)
    end)
  end
  return active.state
end

-- Screens.resolveId's last word: the screen id this game really opens.
function MenuStyle.route(game, id)
  local slot = SLOT_OF[id]
  if not slot then return id end
  local state = MenuStyle.state(game)
  if not (state and state.slots[slot]) then return id end
  return MenuStyle.SCREENS[state.family][slot]
end

-- the `game` a screen is built with: the real one, or for a borrowed slot a
-- stand-in whose `data` lays the donor's modules over the game's own
function MenuStyle.gameFor(game, id)
  local real = MenuStyle.real(game)
  local slot, family = SLOT_OF[id], FAMILY_OF[id]
  if not (slot and real) then return game end
  local state = MenuStyle.state(real)
  local borrowed = state and state.family == family and state.slots[slot]
  if not borrowed then return real end
  local data = real.data
  local overlay = borrowed.overlay
  local pdata = setmetatable({}, {
    __index = function(_, k)
      local v = overlay[k]
      if v ~= nil then return v end
      if k == "text" and borrowed.lendText then
        v = state.text()
        if v ~= nil then return v end
      end
      return data and data[k]
    end,
    __newindex = function(_, k, v) if data then data[k] = v end end,
  })
  local proxy = setmetatable({ data = pdata }, { __index = real, __newindex = real })
  REAL[proxy] = real
  return proxy
end

-- does `id` name one of the screens this module may route? (Screens' factory)
function MenuStyle.isMenuScreen(id)
  return SLOT_OF[id] ~= nil
end

-- OPTIONS -> MENU STYLE. Nil (no row) where there is nothing to choose: a
-- Gen 1-3 game, or a DS game with no other DS game imported.
function MenuStyle.optionRow(game, Strings)
  Strings = Strings or function(s) return s end
  local version = GV().get()
  if not MenuStyle.familyOf(version) then return nil end
  if not MenuStyle.choices(version)[1] then return nil end
  local function label(v)
    if not v then return Strings("OWN") end
    local info = GV().info(v) or {}
    local name = tostring(info.displayName or v):gsub("^Pok%S* ", "")
    return Strings(name:upper())
  end
  return { id = "menuStyle", label = Strings("MENU STYLE"),
    value = function(g) return label(MenuStyle.donor(g)) end,
    step = function(g, dir)
      local list = MenuStyle.choices(version)
      local cur = MenuStyle.donor(g)
      local at = 0
      for i, v in ipairs(list) do if v == cur then at = i end end
      local n = #list + 1                       -- slot 0 = OWN
      local by = (tonumber(dir) or 1) < 0 and -1 or 1
      local next_ = (at + by) % n
      local o = g.save.options
      local map = {}
      if type(o.menuStyle) == "table" then for k, v in pairs(o.menuStyle) do map[k] = v end end
      map[version] = list[next_]                 -- nil at 0 = OWN
      -- always a table: an options write folds keys in, so a nil here
      -- would leave the old choice on disk
      o.menuStyle = map
      MenuStyle.invalidate()
      return true
    end }
end

return MenuStyle
