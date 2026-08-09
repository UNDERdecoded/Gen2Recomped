-- Driver: Route 4 ledges (issue #223).
--
-- #223 reports "can't jump down the lower-right cliff outside Mt. Moon".  The
-- reporter (build v0.1.25, RED++/OG-RED brown palette) is standing on the open
-- EAST plateau of ROUTE_4 (the tile-57 ground with the "01/10" texture, cells
-- ~72-80, rows 3-6) near its SE corner.  The owner clarified the complaint is
-- about pressing DOWN (a south-facing ledge), not the vertical side ledges the
-- first triage looked at.
--
-- Finding after an exhaustive DOWN-hop sweep of every ROUTE_4 south-ledge cell
-- (see tests/drivers/route4_downsweep_bug223.lua): every functional south
-- ledge hops.  The "cliff" the reporter pressed DOWN on at the SE corner is a
-- solid mountain-wall FACE -- OVERWORLD tile 58, a 5-cell-tall vertical cliff
-- (ROUTE_4 cell 80, rows 5-9) -- which is NOT a ledge tile.  Gen1 only hops the
-- three straight ledge families in data/tilesets/ledge_tiles.asm (54/55 face
-- DOWN, 39 faces LEFT, 13/29 face RIGHT); a tall cliff face and the diagonal
-- corner tiles are not hoppable in any direction (engine/overworld/ledges.asm
-- HandleLedges keys the hop on wPlayerFacingDirection + wTilePlayerStandingOn +
-- wTileInFrontOfPlayer + hJoyHeld, all four of which must match a LedgeTiles
-- row).  The ledge code and data are byte-identical between v0.1.25 and HEAD,
-- so this is the same behavior the reporter saw: correct, matching Gen1.
--
-- Cases (all assert the CORRECT Gen1 behavior, so this passes on a good build
-- and would fail on any future ledge regression):
--   A  a plain south ledge hops with DOWN                    (system works)
--   B  the cx45 right-facing side ledge hops with RIGHT      (correct input)
--   C  the cx50 left-facing side ledge hops with LEFT
--   D  DOWN along the plaza terraces descends by hopping south ledges
--   E  DOWN into a solid cliff face (tile 58) correctly bonks
--   F  the reporter's EAST plateau south ledges hop with DOWN (rows 4 and 6)
--   G  the reporter's SE-corner cliff FACE (tile 58, cell 80) does NOT hop --
--      this is the "cliff outside Mt Moon" the report was about, working as
--      Gen1 does (a mountain wall is not a ledge)
--
-- Run:
--   POKEPORT_DRIVER=tests/drivers/route4_ledge_bug223_test.lua \
--   POKEPORT_IDENTITY=bug223 POKEPORT_TOUCH=0 love .
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local shotDir = os.getenv("POKEPORT_SHOTDIR") or "."
  local function shot(name) U.shot(game, shotDir .. "/" .. name) end

  -- a party + starter flag so the overworld is fully usable
  game.save.flags = game.save.flags or {}
  game.save.flags.EVENT_GOT_STARTER = true
  local Pokemon = require("src.pokemon.Pokemon")
  if #game.save.party == 0 then
    table.insert(game.save.party, Pokemon.new(game.data, "CHARMANDER", 5))
  end
  -- survey zoom-out + the reporter's RED++ palette so the shots frame the whole
  -- cliff like the report
  game.save.options = game.save.options or {}
  game.save.options.zoom = -2
  game.save.options.colors = "redpp"
  require("src.render.PaletteFX").setMode("redpp")

  local fails = 0
  local function expect(cond, ...)
    if not cond then fails = fails + 1 end
    U.log(cond and "PASS" or "FAIL", ...)
  end

  -- hold a direction for n frames, returning end cell + whether a hop arc was
  -- ever active (p.hopFrames>0 is set only by checkLedgeHop's jump arc)
  local function holdDir(x, y, facing, dir, frames)
    U.teleport(game, "ROUTE_4", x, y, facing)
    require("src.render.Zoom").applyOptions(game.save.options)
    U.wait(6)
    local p = game.overworld.player
    local hopSeen = false
    for _ = 1, frames do
      table.insert(game.input.pressQueue, dir)
      game.input.state[dir] = true
      coroutine.yield()
      if (p.hopFrames or 0) > 0 then hopSeen = true end
    end
    game.input.state[dir] = false
    U.wait(4)
    return p.cellX, p.cellY, hopSeen
  end

  -- A) control: a south-facing ledge must hop with DOWN.  Standing at (40,8),
  -- the cell in front (40,9) is a tile-55 south ledge; hop lands on (40,10).
  do
    U.teleport(game, "ROUTE_4", 40, 8, "down")
    require("src.render.Zoom").applyOptions(game.save.options)
    U.wait(6); shot("route4_south_ledge_before.png")
    local x, y, hop = holdDir(40, 8, "down", "down", 60)
    shot("route4_south_ledge_after.png")
    expect(hop, "A: DOWN hops the south ledge (hop arc seen)")
    expect(x == 40 and y >= 10, "A: landed south of the ledge, got:", x, y)
  end

  -- B) a RIGHT-facing side ledge (tile 29) at cx45.  DOWN never crosses it;
  -- RIGHT does.  From (44,6) a RIGHT hop clears cx45 and lands on (46,6).
  do
    U.teleport(game, "ROUTE_4", 44, 6, "right")
    require("src.render.Zoom").applyOptions(game.save.options)
    U.wait(6); shot("route4_side_ledge_right_before.png")
    local x, y, hop = holdDir(44, 6, "right", "right", 40)
    shot("route4_side_ledge_right_after.png")
    expect(hop, "B: RIGHT hops the cx45 side ledge (hop arc seen)")
    expect(x == 46 and y == 6, "B: landed east of the side ledge, got:", x, y)
  end

  -- C) the mirror side ledge: cx50 (tile 39) faces LEFT; from (51,5) a LEFT hop
  -- clears cx50 and lands on (49,5).
  do
    local x, y, hop = holdDir(51, 5, "left", "left", 40)
    expect(hop, "C: LEFT hops the cx50 side ledge (hop arc seen)")
    expect(x == 49 and y == 5, "C: landed west of the side ledge, got:", x, y)
  end

  -- D) DOWN down the plaza terraces DOES descend by hopping south ledges: from
  -- the plaza top (44,5), holding DOWN walks to a south edge and hops the
  -- terraces; held long enough the player ends well south of the start.
  do
    U.teleport(game, "ROUTE_4", 44, 5, "down")
    require("src.render.Zoom").applyOptions(game.save.options)
    U.wait(6); shot("route4_terrace_down_before.png")
    local x, y, hop = holdDir(44, 5, "down", "down", 150)
    shot("route4_terrace_down_after.png")
    expect(hop, "D: DOWN down the plaza terraces hops a south ledge")
    expect(y >= 12, "D: descended the terraces, got:", x, y)
  end

  -- E) a solid cliff face is NOT a ledge: from (80,4) the cell below (80,5) is a
  -- tile-58 cliff wall.  DOWN bonks in place with no hop -- matching Gen1, DOWN
  -- only hops south-facing ledge tiles (54/55), not cliff faces.
  do
    local x, y, hop = holdDir(80, 4, "down", "down", 30)
    expect(not hop, "E: DOWN into a solid cliff face does not hop")
    expect(x == 80 and y == 4, "E: bonked in place at the cliff face, got:", x, y)
  end

  -- F) the reporter's EAST plateau (the "cliff outside Mt Moon"): the tile-57
  -- ground at (70,4) and (75,4) sits above the row-5 south ledge (tiles 54/55).
  -- DOWN hops each two cells south -- this is exactly the "jump down to the
  -- bottom half of the cliff" the report expected, and it works.
  do
    U.teleport(game, "ROUTE_4", 70, 4, "down")
    require("src.render.Zoom").applyOptions(game.save.options)
    U.wait(8); shot("route4_east_plateau_before.png")
    local x1, y1, h1 = holdDir(70, 4, "down", "down", 44)
    shot("route4_east_plateau_after.png")
    expect(h1 and x1 == 70 and y1 == 6, "F: (70,4) DOWN hops to (70,6), got:", x1, y1)
    local x2, y2, h2 = holdDir(75, 4, "down", "down", 44)
    expect(h2 and x2 == 75 and y2 == 6, "F: (75,4) DOWN hops to (75,6), got:", x2, y2)
  end

  -- G) the reporter's SE-corner "cliff": (80,4) is tile-57 ground whose south
  -- neighbour is the tile-58 mountain-wall face (cell 80, rows 5-9).  DOWN must
  -- NOT hop -- a tall cliff face is not a ledge, matching Gen1.  This is the
  -- cliff the report was about; refusing the hop here is correct.
  do
    U.teleport(game, "ROUTE_4", 78, 3, "down")
    require("src.render.Zoom").applyOptions(game.save.options)
    U.wait(8); shot("route4_se_corner_cliff.png")
    local x, y, hop = holdDir(80, 4, "down", "down", 30)
    expect(not hop and x == 80 and y == 4,
      "G: SE-corner cliff face does not hop (Gen1-correct), got:", x, y, hop)
  end

  if fails > 0 then error(fails .. " check(s) failed") end
  U.log("all checks passed -- #223: every functional ROUTE_4 south ledge hops "
    .. "with DOWN; the reporter's SE 'cliff' is a solid mountain-wall face "
    .. "(tile 58), correctly not hoppable, matching Gen1")
end
