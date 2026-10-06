-- tools/gen4_art_extract/main.lua
--
-- Writes the art modules the importer builds after a cache was made -- the
-- Super Contest's (src/import/Gen4ContestArt.lua) and the Poffins'
-- (src/import/Gen4PoffinArt.lua) -- into an EXISTING Platinum cache: the
-- pictures to <asset root>/assets/generated/gen4/<dir>/<key>.png and each
-- index to <cache dir>/<module>.lua, so a cache gains them without a
-- re-import. Name modules to do only some: contest, poffin.
--
--   love tools/gen4_art_extract <platinum .nds> <asset root> <cache dir> [contest] [poffin] [ending] [options] [mining] [menu] [party]

local MODULES = {
  contest = { module = "src.import.Gen4ContestArt", dir = "contest", cache = "gen4_contest_art" },
  poffin = { module = "src.import.Gen4PoffinArt", dir = "poffin", cache = "gen4_poffin_art" },
  ending = { module = "src.import.Gen4EndingArt", dir = "ending", cache = "gen4_ending_art", dataCache = "gen4_ending" },
  options = { module = "src.import.Gen4OptionsArt", dir = "options", cache = "gen4_options_art" },
  mining = { module = "src.import.Gen4MiningArt", dir = "mining", cache = "gen4_mining_art" },
  menu = { module = "src.import.Gen4MenuArt", dir = "menu_art", cache = "gen4_menu_art" },
  party = { module = "src.import.Gen4PartyArt", dir = "party", cache = "gen4_party_art", dataCache = "gen4_party_ink" },
  naming = { module = "src.import.Gen4Naming", dir = "naming", cache = "gen4_naming_art", dataCache = "gen4_naming_ink" },
  bag = { module = "src.import.Gen4BagArt", dir = "bag_art", cache = "gen4_bag_art" },
  trainer_card = { module = "src.import.Gen4TrainerCardArt", dir = "trainer_card_art", cache = "gen4_trainer_card_art" },
  summary = { module = "src.import.Gen4SummaryArt", dir = "summary_art", cache = "gen4_summary_art", dataCache = "gen4_summary_ink" },
  box = { module = "src.import.Gen4BoxArt", dir = "box", cache = "gen4_box_art", dataCache = "gen4_box_ink" },
  mainmenu = { module = "src.import.Gen4MainMenuArt", dir = "main_menu", cache = "gen4_main_menu_art", dataCache = "gen4_main_menu_ink" },
  shop = { module = "src.import.Gen4ShopArt", dir = "shop_art", cache = "gen4_shop_art" },
  battle = { module = "src.import.Gen4BattleArt", dir = "battle_art", cache = "gen4_battle_art", dataCache = "gen4_battle_anims" },
  poketch = { module = "src.import.Gen4PoketchArt", dir = "poketch_art", cache = "gen4_poketch_art", dataCache = "gen4_poketch_ink" },
  evolution = { module = "src.import.Gen4EvolutionArt", dir = "evolution_art", cache = "gen4_evolution_art", dataCache = "gen4_evolution_ink" },
}

function love.load(args)
  local ok, err = xpcall(function()
    local romPath, assetRoot, cacheDir = args[1], args[2], args[3]
    assert(romPath and assetRoot and cacheDir, "usage: love tools/gen4_art_extract <rom> <asset root> <cache dir> [contest] [poffin] [ending] [options] [mining] [menu] [party]")
    assetRoot, cacheDir = assetRoot:gsub("[/\\]$", ""), cacheDir:gsub("[/\\]$", "")
    local wanted = {}
    for i = 4, #args do wanted[args[i]] = true end
    if next(wanted) == nil then for name in pairs(MODULES) do wanted[name] = true end end
    local rom = assert(require("src.import.NdsRom").open(romPath))
    for name, m in pairs(MODULES) do
      if wanted[name] then
        local images = assert(require(m.module).images(rom))
        require("src.import.CacheFs").mkdirReal(assetRoot .. "/assets/generated/gen4/" .. m.dir)
        local index, n = {}, 0
        for key, pic in pairs(images) do
          local rel = "assets/generated/gen4/" .. m.dir .. "/" .. key .. ".png"
          local data = love.image.newImageData(pic.width, pic.height, "rgba8", pic.rgba)
          local f = assert(io.open(assetRoot .. "/" .. rel, "wb"))
          f:write(data:encode("png"):getString())
          f:close()
          index[key] = { path = rel, width = pic.width, height = pic.height, originX = pic.originX, originY = pic.originY }
          n = n + 1
        end
        local f = assert(io.open(cacheDir .. "/" .. m.cache .. ".lua", "wb"))
        f:write(require("src.import.LuaWriter").encode(index))
        f:close()
        print(("%s: wrote %d pictures and %s/%s.lua"):format(name, n, cacheDir, m.cache))
        -- a module with data beside its pictures (the credits' staff roll)
        local mod = require(m.module)
        if mod.data and m.dataCache then
          local d = mod.data(rom)
          local df = assert(io.open(cacheDir .. "/" .. m.dataCache .. ".lua", "wb"))
          df:write(require("src.import.LuaWriter").encode(d))
          df:close()
          print(("%s: wrote %s/%s.lua"):format(name, cacheDir, m.dataCache))
        end
      end
    end
  end, debug.traceback)
  if not ok then print(err) end
  love.event.quit()
end
