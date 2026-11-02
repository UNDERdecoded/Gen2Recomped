-- PLATINUM FIELD COMMANDS that open an app or only lay one out (pokeplatinum
-- src/scrcmd.c, src/scrcmd_shop.c):
--
--   ShowAccessoryShop          the Floaroma flower shop's Berries-for-
--                              Accessories trade (src/ui/Gen4AccessoryShop.lua),
--                              the script held until it closes
--   OpenRegionMap              a Pokemon Center's wall map: the Town Map in
--                              TOWN_MAP_MODE_WALL_MAP (src/ui/Gen4TownMap.lua
--                              mode "wall"), held until B
--   ShowListMenuSetWidth w     the list menu at a given width (the Villa's
--                              furniture, the Battle Hall) -- the width is
--                              layout, which this port's menu sizes itself
--   SaveTVSegmentHomeAndManor  a Villa purchase recorded for a TV programme
--                              (no TV broadcasts here)
--   SetDressUpPhotoTitle       the gallery's photo title -- superseded by
--                              src/script/Gen4PhotoCommands.lua (installed later)
--   2B2                        FieldSystem_SaveObjects -- the port's objects
--                              live in the save already

local okCommands, Commands = pcall(require, "src.script.Commands")
if not okCommands then Commands = {} end

local M = {}

local function hold(ctx, push)
  local game = ctx.game
  if not (game and game.stack) then return end
  local runner = ctx.runner
  local resumed = false
  local function resume()
    if resumed then return end
    resumed = true
    if runner then runner:resume() end
  end
  if not push(game, resume) then return end
  if runner then runner:yield() end
end

function Commands.g4_accessory_shop(ctx)
  hold(ctx, function(game, resume)
    game.stack:push(require("src.ui.Gen4AccessoryShop").new(game, resume))
    return true
  end)
end
if Commands.meta then Commands.meta.g4_accessory_shop = { foreground = true, blocking = true } end

function Commands.g4_wall_map(ctx)
  hold(ctx, function(game, resume)
    if not (game.data and game.data.gen4_town_map) then return false end
    game.stack:push(require("src.ui.Gen4TownMap").new(game, { mode = "wall", onCancel = resume }))
    return true
  end)
end
if Commands.meta then Commands.meta.g4_wall_map = { foreground = true, blocking = true } end

-- HGSS's TownMap: the Pokegear's map in PGMAP_TYPE_TOWN_MAP (src/ui/HgssFlyMap.lua)
function Commands.g4_hgss_town_map(ctx)
  hold(ctx, function(game, resume)
    local FM = require("src.ui.HgssFlyMap")
    if not FM.available(game) then return false end
    game.stack:push(FM.new(game, { kind = "town", onCancel = resume }))
    return true
  end)
end
if Commands.meta then Commands.meta.g4_hgss_town_map = { foreground = true, blocking = true } end

function M.install(L)
  L.showaccessoryshop = L.showaccessoryshop or function(_, s)
    s.out[#s.out + 1] = { "g4_accessory_shop" }
  end
  L.openregionmap = L.openregionmap or function(_, s)
    s.out[#s.out + 1] = { "g4_wall_map" }
  end
  L.showlistmenusetwidth = L.showlistmenusetwidth or L.showlistmenu
  -- HGSS's SetSpawn <warp>: the blackout spawn row, as Platinum's SetBlackOutWarpId
  L.setspawn = L.setspawn or L.setblackoutwarpid
  L.townmap = L.townmap or function(_, s)
    s.out[#s.out + 1] = { "g4_hgss_town_map" }
  end
  L.savetvsegmenthomeandmanor = L.savetvsegmenthomeandmanor or function(_, s)
    s.out[#s.out + 1] = { "g4_noop", "the Villa's TV segment" }
  end
  L.setdressupphototitle = L.setdressupphototitle or function(_, s)
    s.out[#s.out + 1] = { "g4_noop", "the dress-up photo title" }
  end
  L["2b2"] = L["2b2"] or function(_, s)
    s.out[#s.out + 1] = { "g4_noop", "saving the map's objects" }
  end
end

return M
