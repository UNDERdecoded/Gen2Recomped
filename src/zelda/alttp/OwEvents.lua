-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- THE MEDALLIONS, THE TABLETS AND THE SEALED ENTRANCES (round 26, team A).
-- The SNES routines the GBA keeps (zelda3 names), its tables (OFF):
--
--   LinkItem_Ether / Bombos / Quake   a sword (link_sword_type + 1 & ~1),
--                         magic cost index 1; Link's spell pose (LinkOam yt
--                         0x15, rt = state_for_spin_attack) steps through
--                         kEther / kBombos / kQuakeAnimDelays and AnimStates
--                         (GBA 0x167FE4..0x16803B); the last steps loop
--                         until the spell ends (Ether step 10 -> 12 -> 10,
--                         Bombos 19 -> 20 -> 19, Quake's hop at 10).
--   the spells            every sprite on the screen takes kAncilla_Damage
--                         [0x18] (Ether 14), [0x19] (Bombos 13), [0x1C]
--                         (Quake 15); at the end Ancilla_CheckForEntranceTrigger
--                         (kEntranceTrigger_BaseY / X / SizeY / X, GBA
--                         0x1719D8..) opens Misery Mire (Ether, area 0x70,
--                         trigger 2) or Turtle Rock (Quake, area 0x47,
--                         trigger 3) unless save_ow_event_info & 0x20.
--   Overworld_AnimateEntrance_Mire / _TurtleRock / _Skull  the map16 tiles
--                         drawn (Overworld_DrawMap16_Persist) at the
--                         cartridge's counters; the event bit 0x20 keeps them
--                         (drawn again whenever the area loads).
--   FireRodShot_BecomeSkullWoodsFire  a fire rod shot ending on attribute
--                         0x43 in area 0x40 opens Skull Woods' back door.
--   Sprite_F2_MedallionTablet  (area lists): Link below it facing up; R
--                         reads (message 0x10D, "can't read"), the Book of
--                         Mudora with A reads 0x10E (Ether) / 0x10F (Bombos);
--                         with the Master Sword (type >= 2) the cutscene
--                         (EtherTablet_StartCutscene: 0xC0 frames, Bombos
--                         0xE0) ends in the medallion's receipt (0x10 / 0x0F).
--
-- OURS: the spells' own pictures (the lightning, the fire columns, the
-- quake bolts) are a white flash of 8 frames every 16; the spell lasts 96
-- frames after Link's pose; the tablet's crumbling picture and dust are
-- not drawn; the Mire's rain / screen shake and Turtle Rock's palette fade
-- are not drawn; no sounds.

local bit = require("bit")
local band, bor = bit.band, bit.bor

local EV = {}

EV.OFF = {
  etherStates = 0x167FE4, etherDelays = 0x167FF0, bombosStates = 0x167FFC, bombosDelays = 0x168010,
  quakeStates = 0x168024, quakeDelays = 0x168030,
  trigY = 0x1719D8, trigX = 0x1719E0, trigSY = 0x1719E8, trigSX = 0x1719F0,   -- the sizes are u16 on the GBA
}
EV.SLOT = { [9] = "bombos", [10] = "ether", [11] = "quake" }
EV.DAMAGE = { ether = 0x18, bombos = 0x19, quake = 0x1C }    -- kAncilla_Damage index
EV.SPELL_FRAMES = 96                                         -- OURS
-- the entrances' final tiles (area-relative map16 byte positions, ids)
local function seq(list, first)
  local out, j = {}, first
  for _, p in ipairs(list) do out[#out + 1] = { p, j }; j = j + 1 end
  return out
end
EV.MIRE = { area = 0x70, trigger = 2,
            stages = { { at = 72, tiles = seq({ 0x622, 0x624, 0x626, 0x628, 0x6A2, 0x6A4, 0x6A6, 0x6A8, 0x722, 0x724, 0x726, 0x728 }, 0xE48) },
                       { at = 72, tiles = seq({ 0x5A2, 0x5A4, 0x5A6, 0x5A8, 0x622, 0x624, 0x626, 0x628, 0x6A2, 0x6A4, 0x6A6, 0x6A8, 0x722, 0x724, 0x726, 0x728 }, 0xE54) },
                       { at = 80, tiles = seq({ 0x522, 0x524, 0x526, 0x528, 0x5A2, 0x5A4, 0x5A6, 0x5A8, 0x622, 0x624, 0x626, 0x628, 0x6A2, 0x6A4, 0x6A6, 0x6A8, 0x722, 0x724, 0x726, 0x728 }, 0xE64) } } }
EV.TR = { area = 0x47, trigger = 3,
          stages = { { at = 8, tiles = seq({ 0x99E, 0x9A0, 0x9A2, 0x9A4, 0xA1E, 0xA20, 0xA22, 0xA24, 0xA9E, 0xAA0, 0xAA2, 0xAA4, 0xB1E, 0xB20, 0xB22, 0xB24 }, 0xE78) } } }
EV.SKULL = { area = 0x40,
             stages = { { at = 4, tiles = { { 0x409 * 2, 0xE06 }, { 0x40A * 2, 0xE06 } } },
                        { at = 12, tiles = { { 0x3C8 * 2, 0xE07 }, { 0x3C9 * 2, 0xE08 }, { 0x3CA * 2, 0xE09 }, { 0x3CB * 2, 0xE0A } } },
                        { at = 12, tiles = { { 0x388 * 2, 0xE07 }, { 0x389 * 2, 0xE08 }, { 0x38A * 2, 0xE09 }, { 0x38B * 2, 0xE0A } } },
                        { at = 12, tiles = { { 0x2C8 * 2, 0xE11 }, { 0x2CB * 2, 0xE12 }, { 0x308 * 2, 0xE0D }, { 0x309 * 2, 0xE0E },
                                             { 0x30A * 2, 0xE0F }, { 0x30B * 2, 0xE10 }, { 0x349 * 2, 0xE0B }, { 0x34A * 2, 0xE0C } } },
                        { at = 12, tiles = { { 0x2C8 * 2, 0xE13 }, { 0x2CB * 2, 0xE14 }, { 0x308 * 2, 0xE15 }, { 0x309 * 2, 0xE16 },
                                             { 0x30A * 2, 0xE17 }, { 0x30B * 2, 0xE18 }, { 0x349 * 2, 0xE19 }, { 0x34A * 2, 0xE1A } } } } }
EV.TABLET = 0xF2
EV.MSG_CANT, EV.MSG_ETHER, EV.MSG_BOMBOS = 0x10D, 0x10E, 0x10F

function EV.extract(rom, R, check)
  local O = EV.OFF
  local u8 = function(o, n) return rom:bytesU8(o, n) end
  local t = { etherStates = u8(O.etherStates, 12), etherDelays = u8(O.etherDelays, 12),
              bombosStates = u8(O.bombosStates, 20), bombosDelays = u8(O.bombosDelays, 20),
              quakeStates = u8(O.quakeStates, 12), quakeDelays = u8(O.quakeDelays, 12),
              trigY = rom:bytesU16(O.trigY, 4), trigX = rom:bytesU16(O.trigX, 4),
              trigSY = rom:bytesU16(O.trigSY, 4), trigSX = rom:bytesU16(O.trigSX, 4), map16 = {} }
  for m = 0xE06, 0xE1A do t.map16[m] = rom:bytesU16(R.map16 + m * 8, 4) end
  for m = 0xE48, 0xE87 do t.map16[m] = rom:bytesU16(R.map16 + m * 8, 4) end
  check(t.etherDelays[9] == 7 and t.bombosDelays[20] == 13 and t.quakeDelays[12] == 19 and t.quakeStates[9] == 18,
        "kEther / kBombos / kQuakeAnim tables")
  check(t.trigY[3] == 0xCFC and t.trigX[3] == 0x130 and t.trigSY[2] == 32, "kEntranceTrigger tables")
  return t
end

local function T(game) return game.data.t and game.data.t.events end

local function mergeMap16(game)
  local tb, idx = T(game), game.data.roomIdx
  if not (tb and idx and idx.map16) or game.eventsMap16 then return end
  game.eventsMap16 = true
  for k, v in pairs(tb.map16) do if not idx.map16[k] then idx.map16[k] = v end end
end

-- Overworld_DrawMap16_Persist at an area-relative byte position
local function draw16(game, area, pos, id)
  local x = area.x + (pos % 128) / 2 * 16
  local y = area.y + math.floor(pos / 128) * 16
  game:owSetMap16(x, y, id)
end

local function events(game)
  game.progress.owEvents = game.progress.owEvents or {}
  return game.progress.owEvents
end
local function done(game, area) return band(events(game)[tostring(area)] or 0, 0x20) ~= 0 end

-- Ancilla_CheckForEntranceTrigger
function EV.trigger(game, what)
  local tb = T(game)
  local lk = game.link
  return math.abs(lk.y + 12 - tb.trigY[what + 1]) < tb.trigSY[what + 1]
     and math.abs(lk.x + 8 - tb.trigX[what + 1]) < tb.trigSX[what + 1]
end

-- start an entrance's sequence (trigger_special_entrance)
function EV.open(game, spec)
  mergeMap16(game)
  game.owEntrance = { spec = spec, stage = 1, ctr = 0 }
  local e = events(game)
  e[tostring(spec.area)] = bor(e[tostring(spec.area)] or 0, 0x20)
  game.entrancesOpened = (game.entrancesOpened or 0) + 1
end

local function entranceFrame(game)
  local s = game.owEntrance
  local st = s.spec.stages[s.stage]
  s.ctr = s.ctr + 1
  if s.ctr < st.at then return end
  s.ctr = 0
  for _, t in ipairs(st.tiles) do draw16(game, game.area, t[1], t[2]) end
  s.stage = s.stage + 1
  if s.stage > #s.spec.stages then game.owEntrance = nil end
end

-- the opened entrances stay (save_ow_event_info & 0x20)
local function applyOpened(game)
  if game.link.world ~= "dw" or not game.area then return end
  local key = game.area.parent
  if game.eventsApplied == key then return end
  game.eventsApplied = key
  for _, spec in ipairs({ EV.MIRE, EV.TR, EV.SKULL }) do
    if spec.area == key and done(game, key) then
      mergeMap16(game)
      local last = {}
      for _, st in ipairs(spec.stages) do for _, t in ipairs(st.tiles) do last[t[1]] = t[2] end end
      for pos, id in pairs(last) do draw16(game, game.area, pos, id) end
    end
  end
end

-- ------------------------------------------------------------ the spells
local function startSpell(game, kind)
  local tb = T(game)
  local delays = tb[kind .. "Delays"]
  game.spell = { kind = kind, step = 0, delay = delays[1], state = tb[kind .. "States"][1], t = 0, z = 0, vz = 40 }
  game.spellsCast = (game.spellsCast or 0) + 1
end

local function spellDamage(game, kind)
  local acts = game.interior and game.actors or game.owActors
  if not acts then return 0 end
  local Items = require("src.zelda.alttp.Items")
  local Actors = require("src.zelda.alttp.Actors")
  local cls = Items.tabs(game).ancDamage[EV.DAMAGE[kind] + 1]
  local cx, cy = game:ancCamera()
  local n = 0
  for _, s in ipairs(acts.list) do
    if not s.dead and not s.npc and (Actors.fights(s.type) or (EV.bossTypes and EV.bossTypes[s.type])) and s.x - cx > -16 and s.x - cx < 256 and s.y - cy > -16 and s.y - cy < 176
       and not (kind == "quake" and (s.z or 0) > 0) then
      local hx, hy, hw, hh = Actors.hitbox(game.data.roomIdx.combat, s)
      if not (EV.bossHook and EV.bossHook(game, acts, s, cls, kind)) then
      acts:swordHit(hx, hy - (s.z or 0), hw, hh, { cls = cls, bomb = true, only = s,
                                                  dmg = function(t) return Items.damage(game, cls, t) end })
      end
      n = n + 1
    end
  end
  return n
end

local function spellFrame(game)
  local tb = T(game)
  local s = game.spell
  local kind = s.kind
  local delays, states = tb[kind .. "Delays"], tb[kind .. "States"]
  local last = (kind == "ether" and 10) or (kind == "bombos" and 19) or 10
  if s.cast then
    s.t = s.t + 1
    if s.t == 1 then game.spellHits = (game.spellHits or 0) + spellDamage(game, kind) end
    if s.t >= EV.SPELL_FRAMES then
      game.spell = nil
      game.link.z = 0
      if not game.interior then
        if kind == "ether" and game.area.parent == EV.MIRE.area and not done(game, EV.MIRE.area) and EV.trigger(game, EV.MIRE.trigger) then
          EV.open(game, EV.MIRE)
        elseif kind == "quake" and game.area.parent == EV.TR.area and not done(game, EV.TR.area) and EV.trigger(game, EV.TR.trigger) then
          EV.open(game, EV.TR)
        end
      end
    end
    return
  end
  if kind == "quake" and s.step == 10 then
    -- the hop (Player_ChangeZ(2), z in 1/16 px)
    s.fz = (s.fz or 0) + s.vz
    local mz = s.fz >= 0 and math.floor(s.fz / 16) or -math.floor(-s.fz / 16)
    s.fz = s.fz - mz * 16
    s.z = s.z + mz
    s.vz = s.vz - 2
    game.link.z = math.max(0, s.z)
    if s.z > 0 then s.state = s.vz < 0 and 21 or 20 return end
    game.link.z = 0
  else
    s.delay = s.delay - 1
    if s.delay >= 0 then return end
  end
  s.step = s.step + 1
  if kind == "ether" and s.step == 12 then s.step = 10 end
  if kind == "bombos" and s.step == 20 then s.step = 19 end
  if s.step >= #delays then s.step = #delays - 1 end
  s.delay = delays[s.step + 1]
  s.state = states[s.step + 1]
  if s.step == last and kind ~= "quake" then s.cast = true end
  if kind == "quake" and s.step == 11 then s.cast = true end
end

-- ------------------------------------------------------------ the tablets
local function tablets(game)
  local t = game.data.t and game.data.t.npc
  if not (t and game.area) or game.link.world ~= "lw" then return {} end
  if game.tabletKey == game.area.parent then return game.tabletList end
  game.tabletKey = game.area.parent
  local list = {}
  local prog = game:storyProgress()
  local phase = (prog == 2 and 2) or (prog == 3 and 3) or 1
  local l = t.ow[phase] and t.ow[phase][game.area.parent + 1]
  local bx = (game.area.parent % 8) * 512
  local by = math.floor((game.area.parent % 64) / 8) * 512
  for _, e in ipairs(l or {}) do
    if e[3] == EV.TABLET then list[#list + 1] = { x = bx + e[2] * 16, y = by + e[1] * 16 } end
  end
  game.tabletList = list
  return list
end

local function tabletFrame(game, inp)
  local lk = game.link
  for _, tb in ipairs(tablets(game)) do
    if lk.facing == 0 and math.abs(lk.x - tb.x) < 16 and lk.y >= tb.y + 8 and lk.y <= tb.y + 24 then
      local ether = game.area.parent == 3
      local item = game:yItem()
      local readBook = item == "book" and inp.y
      if not (readBook or inp.a) then return false end
      local medal = ether and 0x10 or 0x0F
      local inv = require("src.zelda.alttp.Menu").inventory(game)
      local has = (inv[ether and 0x29 or 0x28] or 0) ~= 0
      if readBook then
        local sword = inv[0x3D] or (game.progress.sword and 1 or 0)
        if sword >= 2 and not has then
          game.tabletCut = { t = ether and 0xC0 or 0xE0, medal = medal }
        end
        game:showMessage(ether and EV.MSG_ETHER or EV.MSG_BOMBOS)
      else
        game:showMessage(EV.MSG_CANT)
      end
      game.tabletReads = (game.tabletReads or 0) + 1
      inp.a, inp.y = false, false
      return true
    end
  end
  return false
end

-- ------------------------------------------------------------ install
function EV.install(G)
  local Items = require("src.zelda.alttp.Items")
  for s, n in pairs(EV.SLOT) do Items.SLOT[s] = n end

  local itemFrame0 = G.itemFrame
  function G:itemFrame(inp)
    if not T(self) then return itemFrame0(self, inp) end
    if self.spell then spellFrame(self); self.link.moving, self.link.steps = false, 0; return true end
    if inp.y and not self.bowUse and not self.toolUse then
      local item = self:yItem()
      if item == "ether" or item == "bombos" or item == "quake" then
        local inv = require("src.zelda.alttp.Menu").inventory(self)
        local sword = inv[0x3D] or (self.progress.sword and 1 or 0)
        if (self.link.doorway or 0) ~= 0 or band(sword + 1, bit.bnot(1)) == 0 then return false end
        if require("src.zelda.alttp.Tools").magic(self, 1) then
          startSpell(self, item)
          return true
        end
        return false
      end
    end
    return itemFrame0(self, inp)
  end

  local owFrame = G.escapeOwFrame
  function G:escapeOwFrame(inp)
    if T(self) then
      applyOpened(self)
      if self.owEntrance then entranceFrame(self); self.link.moving = false; return true end
      local c = self.tabletCut
      if c then
        c.t = c.t - 1
        self.link.moving, self.link.steps = false, 0
        if c.t <= 0 then self.tabletCut = nil; self:getItem(c.medal); self.medallionsGot = (self.medallionsGot or 0) + 1 end
        return true
      end
      if (inp.a or inp.y) and not self.textBox and tabletFrame(self, inp) then return true end
    end
    return owFrame(self, inp)
  end

  local pose0 = G.linkPose
  function G:linkPose()
    if self.spell then return 0x15, self.spell.state end
    if self.tabletCut then return 0x24, 0 end
    return pose0(self)
  end

  -- the spells' flash (OURS) at the end of the field
  local xf0 = G.drawCrossfade
  function G:drawCrossfade()
    if xf0 then xf0(self) end
    local s = self.spell
    if s and s.cast and band(s.t, 15) < 8 then
      local lg = love.graphics
      lg.push("all")
      lg.setColor(1, 1, 1, 0.35)
      lg.rectangle("fill", -4096, -4096, 8192, 8192)
      lg.pop()
    end
  end

  local enter0 = G.enterRoom
  function G:enterRoom(e)
    self.spell, self.owEntrance, self.tabletCut = nil, nil, nil
    self.eventsApplied = nil
    return enter0(self, e)
  end
  local leave0 = G.leaveRoom
  function G:leaveRoom()
    self.eventsApplied = nil
    return leave0(self)
  end

  -- Skull Woods: a fire shot ending on 0x43 in area 0x40
    local updAnc0 = G.updateAncillae
  function G:updateAncillae()
    local before = {}
    for _, a in ipairs(self.anc or {}) do if a.kind == "fire" and a.step == 0 then before[a] = true end end
    updAnc0(self)
    if self.interior or not T(self) or self.link.world ~= "dw" or not self.area or self.area.parent ~= EV.SKULL.area then return end
    if done(self, EV.SKULL.area) then return end
    for _, a in ipairs(self.anc or {}) do
      if before[a] and a.step == 1 then
        local IT = Items.tabs(self)
        for _, j in ipairs({ a.dir + 8, a.dir + 12 }) do
          if self.ow:attrAt("dw", a.x + IT.collX[j + 1], a.y + IT.collY[j + 1]) == 0x43 then
            EV.open(self, EV.SKULL)
            return
          end
        end
      end
    end
  end
end

return EV
