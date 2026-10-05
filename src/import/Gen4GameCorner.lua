-- THE VEILSTONE GAME CORNER, the data half (pokeplatinum
-- src/scrcmd_game_corner_prize.c, src/coins.c).
--
-- `sGameCornerPrizeData` is nineteen { u16 item, u16 price } rows compiled
-- into ARM9, read by `getgamecornerprizedata <index> <itemVar> <priceVar>`;
-- the prize counter's script walks 0..18 (its var 0x4001 is set to 19).
-- Found by content: Silk Scarf (251) and Wide Lens (265), 1000 coins each.
--
-- Written to the cache module `gen4_game_corner` as { prizes = { {item, price} } }.

local Gen4GameCorner = {}

Gen4GameCorner.PRIZES = 19
Gen4GameCorner.SIGNATURE = string.char(0xFB, 0, 0xE8, 3, 0x09, 1, 0xE8, 3)
Gen4GameCorner.MAX_COINS = 50000   -- include/coins.h

function Gen4GameCorner.parse(arm9)
  if type(arm9) ~= "string" then return nil, "no arm9" end
  local at = arm9:find(Gen4GameCorner.SIGNATURE, 1, true)
  if not at then return nil, "sGameCornerPrizeData not found in arm9" end
  local prizes = {}
  for i = 0, Gen4GameCorner.PRIZES - 1 do
    local o = at + i * 4
    prizes[i + 1] = {
      item = arm9:byte(o) + arm9:byte(o + 1) * 256,
      price = arm9:byte(o + 2) + arm9:byte(o + 3) * 256,
    }
  end
  return { prizes = prizes }
end

function Gen4GameCorner.extract(rom)
  return Gen4GameCorner.parse(rom and rom:arm9())
end

-- ------------------------------------------------------------------ coins --

function Gen4GameCorner.coins(save)
  return math.max(0, math.floor(tonumber(save and save.coins) or 0))
end

-- Coins_CanAdd: the sum may not pass MAX_COINS.
function Gen4GameCorner.canAdd(save, n)
  return Gen4GameCorner.coins(save) + n <= Gen4GameCorner.MAX_COINS
end

-- Coins_Add: refused only when already full, then clamped.
function Gen4GameCorner.add(save, n)
  local have = Gen4GameCorner.coins(save)
  if have >= Gen4GameCorner.MAX_COINS then return false end
  save.coins = math.min(Gen4GameCorner.MAX_COINS, have + n)
  return true
end

-- Coins_Subtract: all or nothing.
function Gen4GameCorner.subtract(save, n)
  local have = Gen4GameCorner.coins(save)
  if have < n then return false end
  save.coins = have - n
  return true
end

return Gen4GameCorner
