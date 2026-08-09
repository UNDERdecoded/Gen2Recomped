-- Minimal Pokédex: dex-ordered list with seen/owned markers.

local ListMenu = require("src.ui.ListMenu")
local Strings = require("src.core.Strings")

local PokedexMenu = {}

-- SGB: PalPacket_Pokedex, whole screen.
--
-- Gen2's main screen also holds the selected mon's picture, and that art is
-- the same four-shade rip DexEntryMenu shows -- so the picture box gets the
-- mon's own palette as a zone on top of the screen palette, the way the
-- entry page does.  Without it every listing sprite is grey.
--
-- BROWNMON is a Gen1 SuperPalette name and the Gen2 cache has no such entry
-- (extractPalettes writes MON_SPECIES_nnn plus the bar palettes and nothing
-- else), so asking for it by name on Gold returned nil and the whole dex
-- rendered with no colour at all.  Gen2 gets PREDEFPAL_POKEDEX, which is what
-- _CGB_Pokedex_Init loads into BG palette 0.
PokedexMenu.GEN2_PAL = {
  { 255, 255, 255 }, { 255, 165, 82 }, { 214, 82, 49 }, { 0, 0, 0 },
}

function PokedexMenu:sgbPalettes(game)
  local P = require("src.render.PaletteFX")
  local base = self.gen2Dex and { P.whole(PokedexMenu.GEN2_PAL) }
    or P.wholeNamed(game.data, "BROWNMON")
  if not (base and self.gen2Dex) then return base end
  local item = self.items and self.items[self.index]
  if not (item and item.value) then return base end
  local zone = P.zone(P.monPal(game.data, item.value), 1, 1, 7, 7)
  if not zone then return base end
  local out = {}
  for i = 1, #base do out[i] = base[i] end
  out[#out + 1] = zone
  return out
end

-- wCurrentDexMode (Pokedex_OrderMonsByMode's jumptable).  A new game starts
-- in NEW; the option screen is the only thing that changes it, and the
-- choice is saved.
PokedexMenu.MODE_NEW = 0
PokedexMenu.MODE_OLD = 1
PokedexMenu.MODE_ABC = 2

local function nationalOrder(game)
  local constants = game.data.constants or {}
  local byDex = {}
  for _, def in pairs(game.data.pokemon) do
    if def.dex then byDex[def.dex] = def.id end
  end
  local out = {}
  for n = 1, constants.dexSize or 151 do out[n] = byDex[n] end
  return out
end

-- The listing, as one array of species ids indexed by listing position.
--
-- Generation 1 has exactly one order and def.dex is it.  Generation 2 has
-- three (Pokedex_OrderMonsByMode's jumptable) and starts a new game in mode
-- 0, .NewMode, which copies NewPokedexOrder into wPokedexOrder: the JOHTO
-- listing, #001 CHIKORITA.  def.dex on a Gen 2 cache is the national number,
-- which is .OldMode -- the listing you switch to, not the one you are
-- handed -- so following it put BULBASAUR at #001 before the player had any
-- business seeing a Kanto number at all.
--
-- .ABCMode walks AlphabeticalPokedexOrder and keeps only the mons the player
-- has seen, so that listing is short and has no gaps.
local function listing(game, mode)
  local constants = game.data.constants or {}
  if mode == PokedexMenu.MODE_ABC then
    local dex = game.save.pokedex or { seen = {}, owned = {} }
    local out = {}
    for _, def in pairs(game.data.pokemon) do
      if def.dex and (dex.owned[def.id] or dex.seen[def.id]) then
        out[#out + 1] = def.id
      end
    end
    table.sort(out, function(a, b)
      local na, nb = game.data.pokemon[a].name, game.data.pokemon[b].name
      if na == nb then return tostring(a) < tostring(b) end
      return na < nb
    end)
    -- an empty list has nothing to put a cursor on; fall through to NEW
    if #out > 0 then return out end
    mode = PokedexMenu.MODE_NEW
  end
  if mode ~= PokedexMenu.MODE_OLD then
    local regional = constants.regionalOrder
    if type(regional) == "table" and #regional > 0 then return regional end
  end
  return nationalOrder(game)
end

-- Pokedex_CheckUnlockedUnownMode: UNOWN MODE only exists once the Ruins of
-- Alph scientist has upgraded the dex (`setflag ENGINE_UNOWN_DEX`).
local function unownModeUnlocked(game)
  local flags = game.save and game.save.flags
  return (flags and flags.EVENT_GOT_UNOWN_DEX) and true or false
end

-- The SELECT screen (Pokedex_InitOptionScreen).  Picking an order closes the
-- listing and rebuilds it, which is what wCurrentDexMode does on the way back
-- out of the option screen.
local function openOptionScreen(game, dexList, opts)
  local Menu = require("src.ui.Menu")
  local function switchTo(mode)
    game.save.dexMode = mode
    dexList:close()
    require("src.ui.Screens").push(game, "PokedexMenu", opts)
  end
  local entries = {
    { label = Strings("NEW MODE"),
      onSelect = function() switchTo(PokedexMenu.MODE_NEW) end },
    { label = Strings("OLD MODE"),
      onSelect = function() switchTo(PokedexMenu.MODE_OLD) end },
    { label = Strings("A to Z"),
      onSelect = function() switchTo(PokedexMenu.MODE_ABC) end },
  }
  if unownModeUnlocked(game) then
    entries[#entries + 1] = { label = Strings("UNOWN"), onSelect = function()
      require("src.ui.Screens").push(game, "PokedexUnownMode")
    end }
  end
  game.stack:push(Menu.new(game, entries,
    { tx = 5, ty = 4, tw = 10, th = #entries * 2 + 2 }))
end

function PokedexMenu.new(game, opts)
  opts = opts or {}
  local dex = game.save.pokedex or { seen = {}, owned = {} }
  local items = {}
  local seen, owned = 0, 0
  -- number width comes from constants; the fallback keeps a cache imported
  -- before that key existed on the Kanto numbering
  local constants = game.data.constants or {}
  local numFmt = ("%%0%dd"):format(constants.dexDigits or 3)
  -- Gen2's listing carries no dex number: Pokedex_PrintNumberIfOldMode only
  -- prints one in mode 1, and a new game starts in mode 0
  local gen2 = require("src.core.GameVersion").isGen2()
  local mode = gen2 and (game.save.dexMode or PokedexMenu.MODE_NEW)
    or PokedexMenu.MODE_NEW
  local order = listing(game, mode)
  for n = 1, #order do
    local def = game.data.pokemon[order[n]]
    if def then
      -- OLD #DEX MODE numbers with the national number, which is what
      -- def.dex already is
      local prefix = ""
      if not gen2 then
        prefix = (numFmt .. " "):format(n)
      elseif mode == PokedexMenu.MODE_OLD then
        prefix = (numFmt .. " "):format(def.dex or n)
      end
      local label
      if dex.owned[def.id] then
        label = prefix .. def.name
        owned = owned + 1
        seen = seen + 1
      elseif dex.seen[def.id] then
        label = prefix .. def.name
        seen = seen + 1
      else
        label = prefix .. "-----"
      end
      table.insert(items, {
        label = label,
        -- owned entries carry the pokéball marker like the original
        -- list; seen-only entries are just the name
        ball = dex.owned[def.id] or nil,
        value = (dex.owned[def.id] or dex.seen[def.id]) and def.id or nil,
      })
    end
  end
  local list = ListMenu.new(game, "POKéDEX", items, {
    footer = Strings("SEEN %d  OWNED %d", seen, owned),
    gen2Dex = gen2 and { seen = seen, owned = owned } or nil,
    pageJump = true, -- Left/Right page jumps like the original
    onCancel = opts.onCancel, -- B returns to the start menu when opened from it
    -- Pokedex_UpdateMainScreen: SELECT opens the option screen (Gen2 only --
    -- Gen1's dex has no modes)
    onSelectKey = gen2 and function(_, dexList)
      openOptionScreen(game, dexList, opts)
    end or nil,
    onChoose = function(item, dexList)
      if not item.value then return end
      local Screens = require("src.ui.Screens")
      -- GSC has no side menu: Pokedex_MainScreen's A opens the entry screen,
      -- whose PAGE/AREA/CRY/PRNT bar carries the same options
      if gen2 then
        Screens.push(game, "DexEntryMenu", item.value)
        return
      end
      -- the DATA / CRY / AREA / QUIT choice (engine/menus/pokedex.asm
      -- PokedexMenuItemsText); CRY keeps the side menu open like the
      -- original.  B is what returns to the list: HandlePokedexSideMenu
      -- hands back b=2 for B and b=1 for QUIT, and ShowPokedexMenu sends
      -- b=1 to .exitPokedex, so QUIT closes the whole Pokédex (#571)
      local Menu = require("src.ui.Menu")
      local entries = {
        { label = Strings("DATA"), onSelect = function()
            Screens.push(game, "DexEntryMenu", item.value)
          end },
        { label = Strings("CRY"), keepOpen = true, onSelect = function()
            require("src.core.Sound").playCry(game.data, item.value)
          end },
        { label = Strings("AREA"), onSelect = function()
            Screens.push(game, "TownMap", { nestSpecies = item.value })
          end },
      }
      -- Yellow's PRNT item (engine/menus/pokedex.asm PokedexMenuItemsText
      -- _YELLOW branch -> PrintPokedexEntry): the Game Boy Printer job is
      -- stood in for by a PNG of the entry page saved under prints/.
      if require("src.core.GameVersion").isYellow() then
        entries[#entries + 1] = { label = Strings("PRNT"), onSelect = function()
          local DexEntryMenu = require("src.ui.DexEntryMenu")
          local Printer = require("src.core.Printer")
          local TextBox = require("src.render.TextBox")
          local def = game.data.pokemon[item.value]
          local path = require("src.pokemon.Sprites").path(
            game.data, item.value, "front", { kind = "dex" })
          local ok, sprite = false, nil
          if path then ok, sprite = pcall(love.graphics.newImage, path) end
          local saved, err = Printer.save("dex_" .. item.value, 160, 144,
            function()
              DexEntryMenu.render(game, def, ok and sprite or nil, false)
            end)
          game.stack:push(TextBox.new(game, saved
            and Strings("Printed %s's\ndata!\fSaved as\n%s\vin the save\nfolder.",
                        def.name, saved)
            or Strings("Printer error!\n%s", tostring(err))))
        end }
      end
      entries[#entries + 1] = { label = Strings("QUIT"), onSelect = function()
        -- .exitPokedex: drop the dex list too and hand back to whoever
        -- opened it (the start menu, whose saved cursor is still on
        -- POKéDEX -- wBattleAndStartSavedMenuItem)
        dexList:close()
        if opts.onCancel then opts.onCancel() end
      end }
      game.stack:push(Menu.new(game, entries,
        { tx = 12, ty = 8, tw = 8,
          th = #entries * 2 + 2 }))
    end,
  })
  list.sgbPalettes = PokedexMenu.sgbPalettes
  return list
end

return PokedexMenu
