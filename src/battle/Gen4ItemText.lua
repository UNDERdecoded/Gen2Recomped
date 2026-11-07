-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- THE HELD-ITEM LINES ON A CARTRIDGE WITHOUT BLACK AND WHITE'S TEXT BANKS.
--
-- src/battle/Gen5HoldItems.lua asks src/battle/Gen5BattleText.lua for its
-- lines by BW btl_set / btl_std index. Platinum and HGSS now run the same
-- item rules (battle parity pass), but a Gen 4 cache has no TEXT_G5S_* bank,
-- so every T.set answered the bare nickname as the whole line. `wrap`
-- returns a view of Gen5BattleText whose set / std / pair fall back to the
-- English below (Platinum's wording, in this engine's own "Enemy X" form the
-- rest of a Gen 4 battle already prints) when the bank line is missing.

local Strings = require("src.core.Strings")

local M = {}

local function who(b)
  if not b then return "?" end
  local n = b.name or (b.mon and b.mon.nickname) or "?"
  return b.isPlayer and n or ("Enemy " .. n)
end

local STAT_NAME = { [0] = "ATTACK", "DEFENSE", "SP. ATK", "SP. DEF", "SPEED", "accuracy", "evasiveness" }

-- set lines: key -> function(name, vars) -> text
local SET = {
  [908] = function(n, v) return Strings("%s restored\nhealth using its\n%s!", n, v[2] or "item") end,
  [911] = function(n, v) return Strings("%s restored\n%s's PP\nusing its %s!", n, v[3] or "a move", v[2] or "item") end,
  [914] = function(n, v) return Strings("%s restored\na little HP using\nits %s!", n, v[2] or "item") end,
  [917] = function(n, v) return Strings("%s's %s\ncured its poison!", n, v[2] or "item") end,
  [920] = function(n, v) return Strings("%s's %s\ncured its paralysis!", n, v[2] or "item") end,
  [923] = function(n, v) return Strings("%s's %s\nwoke it up!", n, v[2] or "item") end,
  [926] = function(n, v) return Strings("%s's %s\ndefrosted it!", n, v[2] or "item") end,
  [929] = function(n, v) return Strings("%s's %s\nhealed its burn!", n, v[2] or "item") end,
  [932] = function(n, v) return Strings("%s's %s\nsnapped it out\nof confusion!", n, v[2] or "item") end,
  [935] = function(n, v) return Strings("%s's %s\ncured its\ninfatuation!", n, v[2] or "item") end,
  [1001] = function(n, v) return Strings("%s used its\n%s to get\npumped!", n, v[2] or "item") end,
  [1004] = function(n, v) return Strings("%s fled\nusing its %s!", n, v[2] or "item") end,
  [1007] = function(n, v) return Strings("%s hung on\nusing its %s!", n, v[2] or "item") end,
  [1010] = function(n, v) return Strings("%s's status\nreturned to normal\nusing its %s!", n, v[2] or "item") end,
  [1013] = function(n) return Strings("%s lost\nsome of its HP!", n) end,
  [1022] = function(n, v) return Strings("%s became fully\ncharged due to its\n%s!", n, v[2] or "item") end,
  [1025] = function(n, v) return Strings("%s's %s\nlet it move first!", n, v[2] or "item") end,
  [1028] = function(n, v) return Strings("%s boosted the\naccuracy of its next\nmove using %s!", n, v[2] or "item") end,
  [1038] = function(n, v) return Strings("%s is hurt by\nits %s!", n, v[2] or "item") end,
  [219] = function(n, v) return Strings("The %s\nweakened the damage\nto %s!", v[2] or "item", n) end,
  [240] = function(n, v) return Strings("%s was badly\npoisoned by its\n%s!", n, v[2] or "item") end,
  [258] = function(n, v) return Strings("%s was burned\nby its %s!", n, v[2] or "item") end,
  [330] = function(n, v) return Strings("%s fell in love\nfrom the %s!", n, v[2] or "item") end,
  confused = function(n) return Strings("%s became\nconfused!", n) end,
}
-- the item stat lines: 938 (+1) / 959 (+2), + 3 * stat order
for order = 0, 6 do
  SET[938 + 3 * order] = function(n, v)
    return Strings("The %s raised\n%s's %s!", v[2] or "item", n, STAT_NAME[order])
  end
  SET[959 + 3 * order] = function(n, v)
    return Strings("The %s sharply\nraised %s's\n%s!", v[2] or "item", n, STAT_NAME[order])
  end
end

local PAIR = {
  -- Jaboca / Rowap: "X was hurt by the foe's Y's BERRY!"
  [1031] = function(a, b, v) return Strings("%s was hurt by\n%s's %s!", a, b, v[3] or "item") end,
}

function M.line(key, battler, vars)
  local f = SET[key]
  if not f then return nil end
  return f(who(battler), vars or {})
end

function M.wrap(T)
  local W = setmetatable({}, { __index = T })
  -- (T.set answers the bare name when its bank is missing, so the Gen 4
  -- English is asked FIRST on a Gen 4 cartridge rather than as a fallback)
  local function gen4() return require("src.core.GameVersion").isGen4() == true end
  function W.set(battle, key, battler, vars, fallback)
    if gen4() then
      local s = M.line(key, battler, vars)
      if s then return s end
    end
    return T.set(battle, key, battler, vars, fallback)
  end
  function W.pair(battle, key, a, b, vars, fallback)
    if gen4() then
      local f = PAIR[key]
      if f then return f(who(a), who(b), vars or {}) end
    end
    return T.pair(battle, key, a, b, vars, fallback)
  end
  return W
end

return M
