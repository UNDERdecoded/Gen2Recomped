-- Parity test: Lance room walk-in stays on the floor, and defeat dialogue
-- includes the rival-became-champion after-battle text.
--
-- Sources: scripts/LancesRoom.asm (WalkToLance / LancesRoomLanceEndBattleScript),
-- text/LancesRoom.asm (_LancesRoomLanceAfterBattleText).
-- Self-contained: run via `luajit tests/parity_lance.lua`; also dofile'd
-- by tests/run_tests.lua's aggregator.
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end
local Data = require("src.core.Data")
if not (Data.maps and Data.maps.LANCES_ROOM) then Data:load() end
local Font = require("src.render.Font")
if not pcall(Font.encode, "A") then Font.load(Data) end
local S = require("tests.harness").suite("parity lance")
local check, eq = S.check, S.eq

local mapScripts = require("data.scripts.init")
local hooks = mapScripts.get("LANCES_ROOM")
check(hooks and hooks.walkInRoute, "LANCES_ROOM exposes walkInRoute")

local D = { up = { 0, -1 }, down = { 0, 1 }, left = { -1, 0 }, right = { 1, 0 } }

-- === (1) walk-in RLE lands on the door-lock trigger (6,11) ===
do
  local x, y = 24, 16
  local steps = 0
  for _, seg in ipairs(hooks.walkInRoute) do
    local d = D[seg[1]]
    check(d ~= nil, "walk segment direction " .. tostring(seg[1]))
    for _ = 1, seg[2] do
      x, y = x + d[1], y + d[2]
      steps = steps + 1
    end
  end
  eq(x, 6, "walk-in ends at x=6")
  eq(y, 11, "walk-in ends at y=11 (door-lock / arena entry)")
  check(steps > 0, "walk-in has steps")
end

-- === (2) every cell of the route is walkable with the entrance open ===
do
  local Map = require("src.world.Map")
  local def = Data.maps.LANCES_ROOM
  local tileset = Data.tilesets[def.tileset]
  -- mutate a copy of the block list so we don't poison the registry
  local blocks = {}
  for i, b in ipairs(def.blocks) do blocks[i] = b end
  local copy = {}
  for k, v in pairs(def) do copy[k] = v end
  copy.blocks = blocks
  -- LanceShowOrHideEntranceBlocks with the door unlocked
  blocks[6 * def.width + 2 + 1] = 0x31
  blocks[6 * def.width + 3 + 1] = 0x32
  local map = Map.new(copy, tileset)
  local x, y = 24, 16
  check(map:isWalkableCell(x, y), "start (24,16) walkable")
  for _, seg in ipairs(hooks.walkInRoute) do
    local d = D[seg[1]]
    for _ = 1, seg[2] do
      x, y = x + d[1], y + d[2]
      check(map:isWalkableCell(x, y),
            ("walk-in cell (%d,%d) is floor, not void/wall"):format(x, y))
    end
  end
end

-- === (3) after-battle text names the rival as the real champion ===
do
  local after = Data.text._LancesRoomLanceAfterBattleText
  check(after ~= nil, "_LancesRoomLanceAfterBattleText extracted")
  check(after:find("ELITE", 1, true) or after:find("{RIVAL}", 1, true),
        "after text mentions rival / Elite Four")
  check(after:find("champion", 1, true) or after:find("CHAMPION", 1, true),
        "after text has the champion reveal")
  check(after:find("before you", 1, true) or after:find("before you!", 1, true)
        or after:find("FOUR before", 1, true),
        "after text says rival beat the Elite Four first")
  local header = Data:trainerHeader("LancesRoom", 1)
  check(header and header.after == "_LancesRoomLanceAfterBattleText",
        "trainer header wires the after-battle label")
  check(header and header.won == "_LancesRoomLanceEndBattleText",
        "trainer header wires the won label")
end

-- === (4) onStep win callback pushes the after text (not only won text) ===
do
  local pushed = {}
  local game = {
    data = Data,
    save = {
      flags = {},
      defeatedTrainers = {},
      player = { name = "RED", rival = "BLUE" },
    },
    stack = {
      push = function(_, state)
        pushed[#pushed + 1] = state
      end,
    },
  }
  local lance = {
    def = { name = "LANCESROOM_LANCE", index = 1,
            trainerClass = "OPP_LANCE", trainerParty = 1, text = 1 },
    id = "LANCES_ROOM:1",
    facePlayer = function() end,
  }
  local engaged = false
  local ow = {
    npcs = { lance },
    player = { cellX = 6, cellY = 2 },
    trainerDefeated = function(_, npc)
      return game.save.defeatedTrainers[npc.id] == true
    end,
    engageTrainer = function(_, npc, onDone)
      engaged = npc == lance
      -- simulate engageTrainer's win path: flag the trainer, then onDone
      game.save.defeatedTrainers[npc.id] = true
      game.save.flags.EVENT_BEAT_LANCES_ROOM_TRAINER_0 = true
      if onDone then onDone() end
    end,
  }
  local handled = hooks.onStep(game, ow, 6, 2)
  check(handled == true, "Lance coord trigger engages")
  check(engaged, "engageTrainer called for Lance")
  check(#pushed == 1 and pushed[1].pages ~= nil, "after-battle TextBox pushed")
  -- TextBox.substitute already expanded {RIVAL}/{PLAYER}; page glyphs
  -- are opaque, so re-check the source label via the header + that a
  -- box was queued on win only.
  check(#pushed[1].pages > 0, "after-battle TextBox has pages")
  -- loss path must not show after text
  pushed = {}
  game.save.defeatedTrainers = {}
  ow.engageTrainer = function(_, npc, onDone)
    -- lose: do not mark defeated
    if onDone then onDone() end
  end
  hooks.onStep(game, ow, 6, 2)
  eq(#pushed, 0, "loss does not push after-battle text")
end

print("parity_lance: ok")
