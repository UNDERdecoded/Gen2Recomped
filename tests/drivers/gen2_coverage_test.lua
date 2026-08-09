-- Gen2 script coverage: every opcode in the extracted scripts is either
-- lowered or knowingly dropped, every script compiles, and the newly wired
-- opcodes (fruittree, coins, earthquake, tree_shake, the map-refresh family)
-- behave.
local U = require("tests.drivers.util")

-- Rows the port drops on purpose.  Text-box lifecycle is owned by show_text,
-- the movement language is decoded in Gen2Commands, and the rest are raw-RAM
-- or string-buffer ops with no rendering target in the port.
local DROPPED = {
  closetext = true, waitbutton = true, opentext = true, promptbutton = true,
  itemnotify = true, closewindow = true, closepokepic = true,
  -- string buffers: getitemname/getmonname are lowered (they feed the
  -- "{RAM:...}" splices); the rest still carry the placeholder as raw bytes
  gettrainername = true, getstring = true,
  getnum = true, getcurlandmarkname = true,
  getmoney = true, describedecoration = true,
  -- raw RAM / asm
  readmem = true, writemem = true, loadvar = true, memcall = true,
  callasm = true, writecmdqueue = true, unknown = true,
  -- menus and set pieces with no port equivalent yet
  _2dmenu = true, pokepic = true,
  trade = true, halloffame = true, credits = true,
  catchtutorial = true, checkpokemail = true, givepokemail = true,
  randomwildmon = true, loadtemptrainer = true,
}

return function(game)
  local pass, fail = 0, 0
  local function ok(cond, what)
    if cond then pass = pass + 1 else
      fail = fail + 1
      U.log("FAIL " .. what)
    end
  end

  U.newGame(game)
  U.wait(2)

  local VM = require("src.script.Gen2ScriptVM")
  require("src.script.Gen2Commands")
  local Commands = require("src.script.Commands")
  local store = game.data.map_scripts

  -- 1. every script compiles ------------------------------------------------
  local total, compiled = 0, 0
  for label in pairs(store.scripts or {}) do
    total = total + 1
    local good, rows = pcall(VM.compile, game.data, label)
    if good and rows then compiled = compiled + 1 end
  end
  ok(total > 3000, ("script pool has %d scripts"):format(total))
  ok(compiled == total, ("all %d scripts compile (%d did)"):format(total, compiled))

  -- 2. opcode coverage ------------------------------------------------------
  local unhandled, kinds = {}, 0
  for _, rows in pairs(store.scripts or {}) do
    for _, ir in ipairs(rows) do
      local op = ir[1]
      if not VM.lowered(op) and not DROPPED[op] and not unhandled[op] then
        unhandled[op] = true
        kinds = kinds + 1
      end
    end
  end
  if kinds > 0 then
    local names = {}
    for op in pairs(unhandled) do names[#names + 1] = op end
    table.sort(names)
    U.log("unhandled opcodes: " .. table.concat(names, ","))
  end
  ok(kinds == 0, ("no unhandled script opcodes (%d kinds)"):format(kinds))

  -- 2b. every event on every map resolves --------------------------------
  local maps = game.data.maps
  local mapById = {}
  for _, def in pairs(maps) do
    if type(def) == "table" and def.id then mapById[def.id] = def end
  end

  local missingMap, missingScript, badWarp, badConn, orphanCond = 0, 0, 0, 0, 0
  local warps, signs, objects = 0, 0, 0
  local dangling, badWarps = {}, {}
  for mapId, entry in pairs(store.maps or {}) do
    local def = mapById[mapId]
    if not def then missingMap = missingMap + 1 end

    local function resolves(label)
      if type(label) == "table" then label = label.script end
      if label and not store.scripts[label] then
        missingScript = missingScript + 1
        if #dangling < 8 then dangling[#dangling + 1] = mapId .. ":" .. tostring(label) end
      end
    end
    for _, label in ipairs(entry.scenes or {}) do resolves(label) end
    for _, cb in ipairs(entry.callbacks or {}) do resolves(cb.script) end
    for _, label in pairs(entry.objects or {}) do resolves(label) end
    for _, label in pairs(entry.objectAfter or {}) do resolves(label) end
    for _, label in pairs(entry.coords or {}) do resolves(label) end
    for i, label in pairs(entry.signs or {}) do
      resolves(label)
      signs = signs + 1
      local _ = i
    end
    -- a BGEVENT_IFSET condition without a sign body would gate nothing
    for i in pairs(entry.signConds or {}) do
      if not (entry.signs and entry.signs[i]) then
        orphanCond = orphanCond + 1
      end
    end

    if def then
      for _, w in ipairs(def.warps or {}) do
        warps = warps + 1
        -- destWarp 255 / destMap LAST_WARP is "back out the way you came",
        -- which the elevators and the S.S. Aqua use
        local dest = w.destMap and mapById[w.destMap]
        if w.destMap == "LAST_WARP" then
          dest = nil
        elseif not dest then
          badWarp = badWarp + 1
          if #badWarps < 8 then
            badWarps[#badWarps + 1] = mapId .. "->" .. tostring(w.destMap)
          end
        elseif w.destWarp ~= 255
               and not (dest.warps and dest.warps[w.destWarp]) then
          badWarp = badWarp + 1
          if #badWarps < 8 then
            badWarps[#badWarps + 1] = ("%s->%s#%s"):format(mapId,
              tostring(w.destMap), tostring(w.destWarp))
          end
        end
      end
      for _, o in ipairs(def.objects or {}) do
        objects = objects + 1
        local _ = o
      end
      for _, c in pairs(def.connections or {}) do
        if not mapById[c.map] then badConn = badConn + 1 end
      end
    end
  end
  if #dangling > 0 then U.log("dangling: " .. table.concat(dangling, " ")) end
  if #badWarps > 0 then U.log("bad warps: " .. table.concat(badWarps, " ")) end
  ok(missingMap == 0, ("every scripted map has a map def (%d missing)"):format(missingMap))
  ok(missingScript == 0, ("every event label resolves (%d dangling)"):format(missingScript))
  ok(orphanCond == 0, ("no orphan BGEVENT conditions (%d)"):format(orphanCond))
  ok(badWarp == 0, ("all %d warps land on a real map + index (%d bad)"):format(warps, badWarp))
  ok(badConn == 0, ("all map connections resolve (%d bad)"):format(badConn))
  ok(warps > 1000, ("warp census looks complete (%d)"):format(warps))
  ok(signs > 400, ("sign census looks complete (%d)"):format(signs))
  ok(objects > 1200, ("object census looks complete (%d)"):format(objects))

  -- 2c. BGEVENT_IFSET signs decode to real scripts, not to the flag word ---
  local house = store.maps and store.maps.PLAYERS_HOUSE2_F
  ok(house ~= nil, "PLAYERS_HOUSE2_F has map scripts")
  if house then
    local anyUnknown = false
    for _, label in pairs(house.signs or {}) do
      for _, ir in ipairs(store.scripts[label] or {}) do
        if ir[1] == "unknown" then anyUnknown = true end
      end
    end
    ok(not anyUnknown, "the player's-house IFSET signs decode cleanly")
    ok(house.signConds ~= nil, "the IFSET sign carries its event condition")
  end

  -- 2d. every SPRITE_VAR slot is either defaulted or assigned by a script -
  local assigned = {}
  for _, rows in pairs(store.scripts or {}) do
    for _, ir in ipairs(rows) do
      if ir[1] == "variablesprite" then assigned[ir[2]] = true end
    end
  end
  local missingVar, varSlots = 0, {}
  for _, def in pairs(mapById) do
    for _, o in ipairs(def.objects or {}) do
      local slot = type(o.sprite) == "string" and o.sprite:match("^SPRITE_VAR_(%d+)$")
      slot = slot and tonumber(slot)
      -- slots 0-3 are the bedroom decoration sprites (console and the three
      -- dolls); GSC fills those from wDecorations, not from
      -- InitializeEventsScript, and their objects stay hidden until bought
      if slot and slot >= 4 and not (store.varSprites and store.varSprites[slot])
         and not assigned[slot] then
        missingVar = missingVar + 1
        varSlots[slot] = true
      end
    end
  end
  if missingVar > 0 then
    local list = {}
    for slot in pairs(varSlots) do list[#list + 1] = tostring(slot) end
    table.sort(list)
    U.log("unbacked SPRITE_VAR slots: " .. table.concat(list, ","))
  end
  ok(missingVar == 0, ("every SPRITE_VAR slot is defaulted or assigned (%d missing)"):format(missingVar))

  -- 3. Sudowoodo: the wiggle before the SQUIRTBOTTLE ------------------------
  local sudowoodo = VM.compile(game.data, "S4B_61AA")
  ok(sudowoodo ~= nil, "SudowoodoScript compiles")
  local sawItem, sawMove = false, false
  for _, r in ipairs(sudowoodo or {}) do
    if r[1] == "check_item" and r[2] == "ITEM_175" then sawItem = true end
    if r[1] == "g2_move" and r[3] == "M4B_631C" then sawMove = true end
  end
  ok(sawItem, "Sudowoodo checks the SQUIRTBOTTLE (ITEM_175)")
  ok(sawMove, "Sudowoodo applies the shake movement")
  local shake = store.movements and store.movements.M4B_631C
  ok(shake and shake[1] and shake[1][1] == "tree_shake", "M4B_631C is tree_shake")

  local NPC = require("src.world.NPC")
  ok(type(NPC.shake) == "function", "NPC:shake exists")

  -- ...and end to end: run the script on ROUTE36 with no SQUIRTBOTTLE and
  -- watch object 4 start rattling.
  U.teleport(game, "ROUTE36", 10, 10, "down")
  U.wait(4)
  local route = game.overworld or game.stack:top()
  game.save.inventory = game.save.inventory or {}
  game.save.inventory.ITEM_175 = nil
  route:queueScript(sudowoodo)
  local shook = false
  for _ = 1, 120 do
    U.wait(1)
    for _, npc in ipairs(route.npcs or {}) do
      if npc.shakeFrames then shook = true end
    end
    if shook then break end
  end
  if not shook then
    local ids = {}
    for _, npc in ipairs(route.npcs or {}) do
      ids[#ids + 1] = tostring(npc.def and npc.def.index)
    end
    U.log("ROUTE36 map=" .. tostring(route.map and route.map.id)
          .. " npc indices: " .. table.concat(ids, ","))
  end
  ok(shook, "talking to Sudowoodo without the SQUIRTBOTTLE wiggles it")
  U.wait(60)
  while game.stack:top() ~= route do game.stack:pop() end

  -- 4. fruit trees ----------------------------------------------------------
  local trees = game.data.field.gen2FruitTrees
  ok(type(trees) == "table" and #trees == 30,
     ("30 fruit trees (%d)"):format(trees and #trees or 0))
  local allItems = true
  for _, id in ipairs(trees or {}) do
    if not game.data.items[id] then allItems = false end
  end
  ok(allItems, "every fruit tree item resolves")
  ok(trees and trees[1] == "ITEM_173", "tree 1 is a BERRY")

  -- 4b. headbutt tree encounters -------------------------------------------
  local treeMons = game.data.field.gen2TreeMons
  ok(type(treeMons) == "table" and treeMons.maps.IlexForest == 1,
     "Ilex Forest uses the forest treemon set")
  ok(treeMons and treeMons.maps.Route29 == 2, "Route 29 uses the canyon set")
  local badSet, badSpecies = 0, 0
  for _, set in pairs(treeMons and treeMons.maps or {}) do
    if not (treeMons.sets and treeMons.sets[set]) then badSet = badSet + 1 end
  end
  for _, tbl in pairs(treeMons and treeMons.sets or {}) do
    for _, half in pairs(tbl) do
      for _, row in ipairs(half) do
        if not game.data.pokemon[row.species] then badSpecies = badSpecies + 1 end
      end
    end
  end
  ok(badSet == 0, ("every treemon map points at a real set (%d bad)"):format(badSet))
  ok(badSpecies == 0, ("every treemon species resolves (%d bad)"):format(badSpecies))
  ok(treeMons and #treeMons.rock == 2 and treeMons.rock[1].species == "SPECIES_098",
     "rock smash yields KRABBY 90% / SHUCKLE 10%")

  local ow = game.overworld or game.stack:top()
  local ctx = { game = game, save = game.save, overworld = ow,
                runner = { resume = function() end, yield = function() end } }
  game.save.inventory = game.save.inventory or {}
  local Bag = require("src.inventory.Bag")
  ok(type(Bag.add) == "function", "Bag.add exists")
  Commands.g2_fruittree(ctx, 5)
  ok(game.save.g2FruitTrees and game.save.g2FruitTrees[5] == true,
     "picking tree 5 sets its flag")
  ok(game.save.inventory["ITEM_074"] == 1,
     "tree 5 hands over PSNCUREBERRY")
  while game.stack:top() ~= ow do game.stack:pop() end
  Commands.g2_fruittree(ctx, 5)
  ok(game.save.inventory["ITEM_074"] == 1,
     "a picked tree gives nothing a second time")
  while game.stack:top() ~= ow do game.stack:pop() end

  -- 5. coins ----------------------------------------------------------------
  Commands.g2_give_coins(ctx, 50)
  ok(game.save.coins == 50, "givecoins 50")
  Commands.g2_check_coins(ctx, 40)
  ok(ctx.lastCheck == true, "checkcoins 40 passes at 50")
  Commands.g2_check_coins(ctx, 9999)
  ok(ctx.lastCheck == false, "checkcoins 9999 fails at 50")
  Commands.g2_give_coins(ctx, -100)
  ok(game.save.coins == 0, "takecoins clamps at 0")
  Commands.g2_give_coins(ctx, 99999)
  ok(game.save.coins == 9999, "coins clamp at 9999")

  -- 6. earthquake + refreshmap ---------------------------------------------
  Commands.g2_earthquake(ctx, 20)
  ok(ow.quakeFrames == 20, "earthquake arms the screen shake")
  ow.quakeFrames = nil
  ow.bgShakeY = 0
  local refreshed = pcall(Commands.g2_refreshmap, ctx)
  ok(refreshed, "refreshmap redraws without erroring")

  -- 7. the remaining overworld HM hooks ------------------------------------
  local Map = require("src.world.Map")
  ok(Map.gen2IsCutTree(0x12), "cut tree collision")
  ok(type(ow.tryFieldMoveOW) == "function", "tryFieldMoveOW exists")
  ok(type(ow.gen2FieldMoveAt) == "function", "gen2FieldMoveAt exists")
  ok(type(ow.gen2SweetScent) == "function", "gen2SweetScent exists")
  for _, key in ipairs({ "_AskHeadbuttText", "_AskWhirlpoolText",
                         "_AskWaterfallText", "_HeadbuttNothingText" }) do
    ok(type(game.data.text[key]) == "string", key .. " present")
  end

  U.log(("RESULT %s (%d pass, %d fail)"):format(fail == 0 and "PASS" or "FAIL",
                                                pass, fail))
  love.event.quit()
end
