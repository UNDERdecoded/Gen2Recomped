-- src/import/Gen4PtTvSchedule.lua
--
-- PLATINUM'S TV TIMETABLE: `/arc/tv.narc`, the two members
-- TVBroadcast_GetScheduledProgramID / TVBroadcast_GetProgramType read
-- (pokeplatinum src/overlay006/ov6_022465FC.c).
--
--   member 0  the week grid: one byte per (quarter hour, weekday). The row for
--             a time is ((19 + hour) % 24) * 4 + minute / 15, seven bytes a
--             row, indexed by (weekday + 6) % 7. Each byte is a program id,
--             1..9 (GF_ASSERT(0 < id < TV_BROADCAST_MAX_PROGRAM)).
--   member 1  one 12-byte record per program id - 1: the program TYPE, then
--             up to eleven segment ids (0 ends the list).
--
-- Kept as raw bytes: the arithmetic lives in src/script/PtTvBroadcast.lua,
-- beside the rest of the TV, so the layout is spelled out in one place each.

local M = {}

M.PATH = "/arc/tv.narc"

local function bytes(s)
  local t = {}
  for i = 1, #(s or "") do t[i] = s:byte(i) end
  return t
end

function M.build(x)
  local arc = x:archiveAt(M.PATH)
  if not arc then return nil, "no " .. M.PATH end
  local grid, programs = arc:get(0), arc:get(1)
  if not (grid and programs) then return nil, M.PATH .. " lacks member 0 or 1" end
  return { schedule = bytes(grid), programs = bytes(programs) }
end

return M
