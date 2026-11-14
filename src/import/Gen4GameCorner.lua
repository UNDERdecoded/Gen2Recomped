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

-- Rows 1..3 (Wide Lens, Zoom Lens, Metronome at 1000 coins), for a table
-- whose FIRST prize was replaced: Renegade Platinum swaps the Silk Scarf for
-- item 275 and keeps the next three, so the table starts one row earlier.
Gen4GameCorner.SIGNATURE_ROW1 = string.char(0x09, 1, 0xE8, 3, 0x14, 1, 0xE8, 3, 0x15, 1, 0xE8, 3)

function Gen4GameCorner.parse(arm9)
  if type(arm9) ~= "string" then return nil, "no arm9" end
  local at = arm9:find(Gen4GameCorner.SIGNATURE, 1, true)
  if not at then
    local row1 = arm9:find(Gen4GameCorner.SIGNATURE_ROW1, 5, true)
    -- the row before must still read as a prize: an item id and 1000 coins
    if row1 and arm9:byte(row1 - 2) == 0xE8 and arm9:byte(row1 - 1) == 3 then
      -- ...and so must all nineteen: an item id and a price in tens of coins
      local ok = true
      for i = 0, Gen4GameCorner.PRIZES - 1 do
        local o = row1 - 4 + i * 4
        local item = (arm9:byte(o) or 0) + (arm9:byte(o + 1) or 0) * 256
        local price = (arm9:byte(o + 2) or 0) + (arm9:byte(o + 3) or 0) * 256
        if item == 0 or item > 600 or price == 0 or price % 10 ~= 0
           or price > Gen4GameCorner.MAX_COINS then ok = false break end
      end
      if ok then at = row1 - 4 end
    end
  end
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
