-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- A GATE'S ELECTRONIC BOARD: script op 0x17E <frames> (every gate's board
-- sign, `2E 17E 0024 30 2F 02`). READ FROM CODE (ov48 0x021F4650, task
-- 0x021F4C20):
--   SE 0x547; the camera's pitch / yaw / distance / target are kept, then it
--   moves over <frames> (36 at every site) to look at the board (pitch
--   0x0EE5, distance 134, yaw 0 -- a quarter turn for a board whose facing
--   is 1 or 3); it waits for B or Left / Right / Down (not A, not Up); then
--   it moves back over the same frames.
-- The board itself scrolls a run of lines the gate overlay composes on the
-- way in (0x021F3D78; records from /a/1/7/4, see src/import/Gen5GateBoards.lua):
--   the outbreak line (0x021F4058, only when one is on)  the date (0x021F3E6C)
--   the weather of up to four zones (0x021F3EE8: "{place}: {weather}" in a
--   row, bank 38 #192 into #193..#196)  then four lines picked by weekday
--   (0x021F4104 / 4188 / 420C / 4290: three of the nine local lines and one
--   of the seven advertisements).
-- Here the camera looks at the board's cell with the player's own camera
-- mode, and the lines scroll across an LED band while it does.
-- NOT PORTED (inferred or missing): the post-game Hall of Fame variant and
-- the event variant (/a/1/6/6), daily / event weather overrides (the zone header's weather is used),
-- the month's word (English names stand in) and the board model's own
-- marquee texture and scroll speed.

local okCommands, Commands = pcall(require, "src.script.Commands")
if not okCommands then Commands = {} end

local M = {}
M.SOUND, M.BANK, M.PLACE_NONE = 0x547, 38, 427
M.VERSION = { white = 20, black = 21 }
-- weekday (0 Sunday) -> the line index (record +0x24 is line 0)
M.LOCAL = {
  { [0] = 6, 3, 0, 4, 1, 5, 2 },   -- 0x021F4104
  { [0] = 7, 4, 1, 5, 2, 6, 3 },   -- 0x021F4188
  { [0] = 8, 5, 2, 6, 3, 7, 4 },   -- 0x021F420C
}
M.AD = { [0] = 15, 9, 10, 11, 12, 13, 14 }   -- 0x021F4290 (+0x48.. is line 9)
M.MONTHS = { "January", "February", "March", "April", "May", "June", "July",
             "August", "September", "October", "November", "December" }

local function Game() return package.loaded["src.core.Game"] end
local function line(data, index, vars)
  return require("src.inventory.Gen5ItemUse").line(data, ("TEXT_G5S_%04d_%05d"):format(M.BANK, index), vars, "")
end

function M.boards(data) return data and data.constants and data.constants.gen5GateBoards end

-- 0x021F392C: the record for this zone and version
function M.record(data, zone)
  local b = M.boards(data)
  local v = M.VERSION[require("src.core.GameVersion").get() or ""] or 21
  for _, r in ipairs(b and b.records or {}) do
    if r.zone == zone and (r.version == 0 or r.version == v) then return r end
  end
end

local function placeName(data, zone)
  local def = data and data.maps and data.maps[("Z%03d"):format(zone)]
  return def and def.label or ""
end

-- the board's lines, in the order they scroll
function M.compose(data, rec, t)
  t = t or os.date("*t")
  local okS, St = pcall(require, "src.script.Gen5Stadium")
  local c = okS and St.clock and St.clock()
  local wday = ((c and c.wday or t.wday or 1) - 1) % 7
  local out = {}
  -- the outbreak line (ov48 0x021F4058, READ): today's outbreak zone
  -- (0x021A9810, src/world/Gen5Swarms.lua) -- none, or zone 345 in winter
  -- (season 3), and no line; else the record's +0x20 line with the zone's
  -- place name in word 0
  do
    local G = Game()
    local today = G and G.save and rec.outbreak and require("src.world.Gen5Swarms").today(G.save)
    local winter = require("src.world.Gen5FieldRules").season(G and G.save) == 3
    if today and not (today[1] == 345 and winter) then
      out[#out + 1] = line(data, rec.outbreak, { placeName(data, today[1]) })
    end
  end
  -- the date: "{VAR1} {CMD 0201 1}, 20{CMD 0201 2}"
  local key = ("TEXT_G5S_%04d_%05d"):format(M.BANK, rec.date)
  local raw = data and data.text and data.text[key] or "{VAR1} {CMD 0201 1}, 20{CMD 0201 2}"
  raw = raw:gsub("{CMD 0201 1}", tostring(t.day)):gsub("{CMD 0201 2}", ("%02d"):format((t.year or 2000) % 100))
  out[#out + 1] = (raw:gsub("{VAR1}", M.MONTHS[t.month] or ""):gsub("{CMD[^}]*}", ""))
  -- the weather of the record's zones
  local b = M.boards(data)
  local parts = {}
  for k = 0, 3 do
    local z = rec.places[k]
    if z and z ~= M.PLACE_NONE then
      local w = b.weather and b.weather[z] or 0
      local word = line(data, b.weatherWord and b.weatherWord[w] or 181, nil)
      parts[#parts + 1] = line(data, 192, { placeName(data, z), word })
    end
  end
  if #parts > 0 then out[#out + 1] = line(data, 192 + #parts, parts) end
  for _, pick in ipairs(M.LOCAL) do out[#out + 1] = line(data, rec.lines[pick[wday]] or 0, nil) end
  out[#out + 1] = line(data, rec.lines[M.AD[wday]] or 0, nil)
  local kept = {}
  for _, s in ipairs(out) do
    s = s:gsub("\n", " ")
    if s ~= "" then kept[#kept + 1] = s end
  end
  return kept
end

-- ------------------------------------------------------------ the view --

local View = {}
View.__index = View
View.isOpaque = false
local W, H = 256, 192
function View:uiSize() return W, H end
function View.new(game, text, onDone)
  return setmetatable({ game = game, text = text, onDone = onDone, frame = 0, x = W }, View)
end
function View:update()
  self.frame = self.frame + 1
  local Font = require("src.render.Font")
  self.width = self.width or (Font.width(self.text) or (#self.text * 6))
  self.x = self.x - 1
  if self.x < -self.width then self.x = W end
  local input = self.game.input
  if self.frame > 2 and input and (input:wasPressed("b") or input:wasPressed("left")
      or input:wasPressed("right") or input:wasPressed("down")) then
    self.game.stack:pop()
    if self.onDone then self.onDone() end
  end
end
function View:draw()
  local g = love.graphics
  local Font = require("src.render.Font")
  g.setColor(0.05, 0.04, 0.02, 0.92)
  g.rectangle("fill", 0, 8, W, 20)
  g.setColor(0.35, 0.25, 0.05, 1)
  g.rectangle("line", 0.5, 8.5, W - 1, 19)
  if Font.beginTint then Font.beginTint() end
  g.setColor(1, 0.72, 0.18, 1)
  Font.draw(self.text, math.floor(self.x), 13)
  if Font.endTint then Font.endTint() end
  g.setColor(1, 1, 1, 1)
end
M.View = View

function Commands.g5_gate_board(ctx, frames)
  local ow, game = ctx.overworld, ctx.game
  if not (ow and game and ow.map and ow.map.def) then return end
  local def = ow.map.def
  pcall(function() require("src.core.Sound").play(game.data, M.SOUND) end)
  local rec = M.record(game.data, tonumber(def.header) or -1)
  if not rec then
    require("src.core.Logger").warn("gen5 gate board: no board for %s (re-import the ROM)", tostring(ow.map.id))
    return
  end
  local lines = M.compose(game.data, rec)
  require("src.core.Logger").info("gen5 gate board %s: %s", tostring(ow.map.id), table.concat(lines, " | "))
  -- the record's position is the field's (world units, 16 a cell), which
  -- the free camera takes as it takes 0x143's
  local cx, cz = math.floor(rec.x / 16), math.floor(rec.z / 16)
  -- ...three cells out from the wall it hangs on, so the port's own camera
  -- (which centres on its target) keeps the room in view: facing 1 hangs on
  -- a north wall (Nacrene Gate's at (8.5, 2.5)), 3 on a west wall (Castelia
  -- Gate's at (1, 8.5)) -- inferred from the records, not read
  if rec.facing == 3 then cx = cx + 3 else cz = cz + 3 end
  if Commands.g4_add_free_camera then Commands.g4_add_free_camera(ctx, cx, cz) end
  local runner = ctx.runner
  game.stack:push(View.new(game, table.concat(lines, "      "), function()
    if Commands.g4_restore_camera then Commands.g4_restore_camera(ctx) end
    if runner then runner:resume() end
  end))
  if runner then runner:yield() end
end
Commands.meta = Commands.meta or {}
Commands.meta.g5_gate_board = { foreground = true, blocking = true }

function M.install(L)
  L.bwgateboard = L.bwgateboard or function(ins, s) s.out[#s.out + 1] = { "g5_gate_board", ins.args[1] } end
  -- every site is `17E 0024`: a cache linked before the name keeps bw_17E
  -- without its operand
  L.bw_17E = L.bw_17E or function(_, s) s.out[#s.out + 1] = { "g5_gate_board", 0x24 } end
end

return M
