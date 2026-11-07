-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md).

-- BLACK / WHITE'S DAILY FLAGS.
--
-- READ (Pokemon Black): the daily update ov10 0x02169004 calls arm9
-- 0x020143F0, which clears event flags 0xAA0 .. 0xB5F (0x02014368 with
-- 0xAA0, 0xAA0 + 0xBF) and raises the "day passed" byte (+0x3E8). Every
-- daily-gated BW event lives in that range: Cynthia's (0xAC7), Cheren's
-- (0xAC4) and the other once-a-day rematches (Baker Chris 0xAC3, the Bikers
-- 0xAC0, Draco 0xABB), the Nimbasa venues (0xAB9) and the rest.
--
-- Before this only the stadium's 0xAB9 was ever cleared (Gen5Stadium.dailyTick),
-- so each daily rematch could be fought once per save.

local M = {}

M.FIRST, M.LAST = 0xAA0, 0xB5F

function M.clear(save)
  save.flags = save.flags or {}
  for f = M.FIRST, M.LAST do
    local k = ("FLAG_G4_%04X"):format(f)
    if save.flags[k] == true then save.flags[k] = false end    -- Flags.clear's spelling
  end
end

-- once per frame from the overworld; acts on a civil-day change
function M.poll(save)
  if not save then return end
  local today = require("src.script.Gen4Daily").civilDay()
  local last = tonumber(save.g5DailyDay)
  if last == today then return end
  save.g5DailyDay = today
  if last == nil or today < last then return end
  M.clear(save)
  -- ...and the day's mass outbreak (arm9 0x0200D440; src/world/Gen5Swarms.lua)
  require("src.world.Gen5Swarms").newDay(save)
end

return M
