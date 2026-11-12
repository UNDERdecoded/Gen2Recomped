-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- THE CASTLE ESCAPE (round 6): the game-object side of rooms -- Link's
-- sword, damage, keys and chests, locked doors and shutters, in-room stairs
-- between the two levels, the uncle, Zelda and the priest. Installed into
-- Game (G) as methods; the room actors are Actors.lua.
--
-- From the cartridge: the in-room stair attributes and level swaps
-- (Interior.markInroomStairs, SNES Module07_08/10: up 0x38 frames, down
-- 0x3C), the sword's swing steps and hit boxes, chest contents, key drops,
-- door kinds, room tags, the messages. OURS (alttp.md "Round 6"): Link climbs
-- in-room stairs at 0.5 px a frame (the SNES speed table entry for stairs is
-- not read), blink time (58 frames; round 10: Link's knockback is the
-- cartridge's, 19 frames at speed 24),
-- opening a key door by walking into it with a key, A to open a chest or
-- talk (round 10: the shelf moves as Sprite_EE_MovableMantle, Actors:mantle),
-- the drawing of every actor, the sword and opened doors (plain shapes, not
-- cartridge art).

local Actors = require("src.zelda.alttp.Actors")
local Link = require("src.zelda.alttp.Link")
local bit = require("bit")

local E = {}

local FRONT = { [Link.UP] = { 8, 4 }, [Link.DOWN] = { 8, 26 }, [Link.LEFT] = { -3, 16 }, [Link.RIGHT] = { 19, 16 } }
E.FRONT = FRONT

function E.install(G)
  -- a dungeon item (SNES receipt ids): 0x24 small key, 0x32 big key, others
  -- are kept by id (map 0x33, compass 0x25, lamp 0x12, boomerang 0x0C)
  function G:getItem(id)
    local p = self.progress
    if id == 0x24 then
      p.keys = (p.keys or 0) + 1
    elseif id == 0x32 then
      p.bigKey = p.bigKey or {}
      p.bigKey.castle = true
    else
      p.items = p.items or {}
      p.items[#p.items + 1] = id
    end
    self.itemLog = self.itemLog or {}
    self.itemLog[#self.itemLog + 1] = { id = id, room = self.interior and self.interior.room }
    self:syncKeys()
  end

  function G:syncKeys()
    -- the key counter shows in dungeons only (entrance palace byte +0x20)
    local ent = self.interior and self.interior.entrance
    if ent and (ent.palace or 0xFF) ~= 0xFF then self.stats.keys = self.progress.keys or 0
    else self.stats.keys = 0xFF end
  end

  function G:hurtLink(dmg, fx, fy)
    if (self.blink or 0) > 0 then return end
    self.stats.health = math.max(0, self.stats.health - dmg)
    self.blink = 58
    local lk = self.link
    -- round 10: Sprite_AttemptDamageToLinkPlusRecoil (0x86F3DB): Link is
    -- incapacitated 19 frames, knocked away at Sprite_ApplyRecoilToLink(24)
    -- (1/16 px a frame, the projection from the sprite towards Link)
    local vx, vy = Actors.project(fx - 8, fy - 8, lk.x, lk.y, 24)
    self.recoil = { vx = vx, vy = vy, t = 19, sx = 0, sy = 0, vz = 12 }   -- r20: link_actual_vel_z = 24 >> 1
    -- r20: Link_HandleRecoilAndTimer resets the sword when he lands (button_b_frames,
    -- the spin charge): a hit ends a held sword
    self.swing, self.swordHeld = nil, 0
    if self.link.speedSetting == 12 then self.link.speedSetting = 0 end
    -- r20: LinkState_SpinAttack ends the spin when Link is hit
    if self.swing and self.swing.spin then self.swing, self.swordHeld = nil, 0 end
    self.hits = (self.hits or 0) + 1
    if self.stats.health <= 0 then
      -- round 7: game over (G:updateGameOver)
      self.gameOver = { t = 0 }
      self.deaths = (self.deaths or 0) + 1
    end
  end

  -- GAME OVER (round 7). SNES Module12_GameOver: Link's death spin, the
  -- screen fades, then the player continues at the last entrance with 3
  -- hearts (SNES: health 0x18 when the maximum is larger). OURS: the
  -- spin and the cartridge's game-over / continue menu art are not drawn
  -- (a 96-frame fade to black stands for them) and Continue is automatic.
  G.GAMEOVER_FRAMES = 96
  function G:updateGameOver()
    local go = self.gameOver
    go.t = go.t + 1
    if go.t < G.GAMEOVER_FRAMES then return end
    self.gameOver = nil
    self.stats.health = math.min(self.stats.healthMax, 0x18)
    self.blink, self.recoil, self.swing = 0, nil, nil
    if self.interior then
      self.actors.room = nil
      -- round 12, SNES Death_Func (messaging.c 0x09F5..): indoors, death_var4
      -- (the restored health) survives unless Link is in a palace without
      -- Zelda following; then module 5 / Dungeon_LoadEntrance puts him at
      -- which_starting_point (the prison once Zelda follows, the throne
      -- room once the shelf moved); in a palace without her, the entrance
      local ent = self.interior.entrance
      local palace = ent and ent.palace or 0xFF
      local sps = self.data.roomIdx.startPoints
      if sps and (self.progress.zelda == 1 or palace == 0xFF) then
        self:enterStart(self.progress.startPoint or 0, self.interior.entranceId)
      else
        self:enterRoom(self.interior.entranceId or 0)
      end
    end
    self.continues = (self.continues or 0) + 1
  end
  function G:drawGameOver()
    local a = math.min(1, self.gameOver.t / (G.GAMEOVER_FRAMES * 0.6))
    love.graphics.setColor(0, 0, 0, a)
    love.graphics.rectangle("fill", 0, 0, 240, 160)
    love.graphics.setColor(1, 1, 1, 1)
  end

  -- DARK ROOMS (round 7): header byte 0 bit 0 is the SNES
  -- dung_want_lights_out. OURS (the GBA's window/blend setup for the dark
  -- and its lamp cone are not decoded): the BG layers are covered by black
  -- at 75 % (94 % outside a soft 40 px light round Link when he carries the
  -- lamp, receipt item 0x12); sprites are drawn over it, as the SNES keeps
  -- them out of the colour math.
  function G:hasLamp()
    for _, id in ipairs(self.progress.items or {}) do if id == 0x12 then return true end end
    return false
  end
  function G:drawDarkness(cx, cy)
    local inside = self.interior
    if not (inside and inside.hdr and bit.band(inside.hdr[1] or 0, 1) == 1) then return end
    local lg = love.graphics
    if not self.darkMask then
      local W, H = 480, 320
      local img = love.image.newImageData(W, H)
      local lamp = 40
      img:mapPixel(function(x, y)
        local d = math.sqrt((x - W / 2) ^ 2 + (y - H / 2) ^ 2)
        local a = d < lamp and 0 or math.min(0.94, (d - lamp) / 16 * 0.94)
        return 0, 0, 0, a
      end)
      self.darkMask = lg.newImage(img)
    end
    if self:hasLamp() then
      lg.setColor(1, 1, 1, 1)
      lg.draw(self.darkMask, self.link.x + 8 - cx - 240, self.link.y + 14 - cy - 160)
    else
      lg.setColor(0, 0, 0, 0.75)
      lg.rectangle("fill", 0, 0, 240, 160)
    end
    lg.setColor(1, 1, 1, 1)
  end

  -- RAIN (round 7; SNES Overworld_LoadOverlays + OverworldOverlay_HandleRain):
  -- while the escape is on (sram progress < 2), Light World screens other
  -- than the forest (0x00) and Death Mountain (0x03/0x05/0x07) load overlay
  -- screen 0x9F -- the cartridge's own rain picture, map 0x9F of the GBA's
  -- overworld table -- on the subscreen, half-added over the field (CGWSEL
  -- 0x82, CGADSUB 0x72: this is the night colour), full-added on frames 3,
  -- 36 and 88 of the 256-frame counter (lightning), scrolled at half the
  -- camera speed and jumped by 256 px every 4 frames (kDrawBadWeather X/Y).
  -- OURS: the GBA's own blend registers for it are not read; LOVE's 50 %
  -- alpha is the SNES half-add, the flash an additive draw.
  local RAIN_X, RAIN_Y = { [0] = 1, 0, 1, 0 }, { [0] = 0, 17, 0, 17 }
  function G:raining()
    if self.progress.escaped or self.link.world ~= "lw" then return false end
    local sc = self.area and self.area.parent or 0
    return not (sc == 0x00 or sc == 0x03 or sc == 0x05 or sc == 0x07)
  end
  function G:drawRain()
    if not self:raining() then return end
    local fc = self.frame % 256
    if fc % 4 == 0 then
      self.rainCtr = ((self.rainCtr or 0) + 1) % 4
      self.rainX = ((self.rainX or 0) + RAIN_X[self.rainCtr] * 256) % 512
      self.rainY = ((self.rainY or 0) + RAIN_Y[self.rainCtr] * 256) % 512
    end
    local scr = self.view:screen(0x9F)
    local ox = (math.floor(self.cam.x / 2) + (self.rainX or 0)) % 512
    local oy = (math.floor(self.cam.y / 2) + (self.rainY or 0)) % 512
    local flash = fc == 3 or fc == 36 or fc == 88
    local lg = love.graphics
    if flash then lg.setBlendMode("add") end
    lg.setColor(1, 1, 1, flash and 1 or 0.5)
    -- round 14: as many 512 px tiles as the (zoomed) view needs
    for dy = 0, math.ceil((self.viewH or 160) / 512) do for dx = 0, math.ceil((self.viewW or 240) / 512) do
      lg.draw(scr.bg2, dx * 512 - ox, dy * 512 - oy)
      lg.draw(scr.bg1, dx * 512 - ox, dy * 512 - oy)
    end end
    lg.setBlendMode("alpha")
    lg.setColor(1, 1, 1, 1)
  end

  -- round 16: the trapdoors down again (a push-block tag after a second push)
  function G:closeShutters()
    local inside = self.interior
    for _, l in ipairs(inside.locks) do
      if l.kind == "shutter" and l.open then
        inside:closeLock(l)
        inside.mem.doors[l.index] = nil
      end
    end
    self.roomImages = nil
  end

  function G:openShutters()
    local inside = self.interior
    for _, l in ipairs(inside.locks) do
      l.entry = nil
      if l.kind == "shutter" and not l.open then
        inside:openLock(l)
        inside.mem.doors[l.index] = true
      end
    end
    self.roomImages = nil
  end

  -- one frame in a room before Link moves; returns true when the frame is
  -- used up (climbing, recoil, swinging)
  function G:escapeRoomFrame(inp)
    local inside = self.interior
    local lk = self.link
    if self.actors.room ~= inside.room or self.actors.inside ~= inside then
      self.actors:enterRoom(inside)
      self:syncKeys()
    end
    if (self.blink or 0) > 0 then self.blink = self.blink - 1 end
    -- round 10: trapdoors Link came in through go down once he is past
    -- them (SNES Dungeon_InterRoomTrans_State15 at the transition's end,
    -- when the cartridge's walk-in has carried him through the door)
    for _, l in ipairs(inside.locks) do
      if l.entry and l.open and not self.roomScroll then
        local past = true
        for _, cell in ipairs(l.cells) do
          local cx, cy = (cell % 64) * 8, math.floor(cell / 64) * 8
          if (l.entry == "up" and lk.y + 24 > cy) or (l.entry == "down" and lk.y + 8 < cy + 8)
             or (l.entry == "left" and lk.x + 16 > cx) or (l.entry == "right" and lk.x < cx + 8) then
            past = false break
          end
        end
        if past then l.entry = nil; inside:closeLock(l); self.roomImages = nil end
      end
    end
    -- bug round: the item rising out of a chest holds Link
    if self:updateReceipt() then return true end
    self.rNow = inp.a   -- r22: R this frame (Shop.lua: ShopItem_CheckForAPress)
    self.actors:update()
    -- round 18: arrows, bombs, the lamp's flame, torches (Items.lua)
    if self.updateAncillae then self:updateAncillae() end
    -- in-room stairs climb
    if self.climb then
      local c = self.climb
      c.t = c.t + 1
      if c.t % 2 == 0 then lk.y = lk.y + c.dy end
      lk.steps = math.floor(c.t / 4) % 8 + 1
      if c.t >= c.frames then
        if c.endSwap then inside.lower = not inside.lower end
        if c.endLower ~= nil then inside.lower = c.endLower end
        self.climb = nil
        lk.steps = 0
        self.climbs = (self.climbs or 0) + 1
      end
      return true
    end
    if self.recoil then
      local r = self.recoil
      r.t = r.t - 1
      -- r22: hurt while lifting / carrying throws it (Carry.lua)
      if self.carryRecoilFrame then self:carryRecoilFrame() end
      -- round 11: knockback does not carry Link across in-room stairs
      -- (0x1D-0x1F / 0x3D-0x3F; OURS: the cartridge's recoil runs its tile
      -- detection, which starts the stairs; a knockback ending on the other
      -- level's side of them left Link off the room's floor)
      local function stairAt(x, y)
        local a = inside:attrAt(x, y) or 0
        return (a >= 0x1D and a <= 0x1F) or (a >= 0x3D and a <= 0x3F)
      end
      -- round 13: a probe already on the stairs does not stop the move (Link
      -- standing on their edge was stuck: every knockback refused, and a
      -- guard beside him hit him again every 58 frames)
      local function free(x, y)
        for _, p in ipairs({ { 1, 8 }, { 14, 8 }, { 1, 23 }, { 14, 23 } }) do
          if inside:blocked(x + p[1], y + p[2]) then return false end
          if stairAt(x + p[1], y + p[2]) and not stairAt(lk.x + p[1], lk.y + p[2]) then return false end
        end
        return true
      end
      -- round 10: 1/16 px velocities (8.8 fixed point, Link_MovePosition)
      r.sx, r.sy = (r.sx or 0) + r.vx, (r.sy or 0) + r.vy
      local mx = (r.sx >= 0) and math.floor(r.sx / 16) or -math.floor(-r.sx / 16)
      local my = (r.sy >= 0) and math.floor(r.sy / 16) or -math.floor(-r.sy / 16)
      r.sx, r.sy = r.sx - mx * 16, r.sy - my * 16
      if mx ~= 0 and free(lk.x + mx, lk.y) then lk.x = lk.x + mx end
      if my ~= 0 and free(lk.x, lk.y + my) then lk.y = lk.y + my end
      -- r20: the hop (Sprite_ApplyRecoilToLink: z speed = speed >> 1;
      -- Player_ChangeZ: - 2 a frame; Link_HandleRecoilAndTimer keeps the
      -- timer at 1 until Link lands)
      if r.vz then
        r.fz = (r.fz or 0) + r.vz
        local mz = (r.fz >= 0) and math.floor(r.fz / 16) or -math.floor(-r.fz / 16)
        r.fz = r.fz - mz * 16
        lk.z = math.max(0, (lk.z or 0) + mz)
        if not (r.vz < 0 and (lk.z or 0) == 0) then r.vz = r.vz - 2 end
        if r.t <= 0 and not ((lk.z or 0) <= 0 and r.vz < 0) then r.t = 1 end
      end
      if r.t <= 0 then self.recoil = nil; lk.z = 0 end
      return true
    end
    -- bug round: lifting / carrying / throwing (Carry.lua)
    if self:carryFrame(inp) then return true end
    -- round 18: the item button (A on the GBA; Items.lua)
    if not self.swing and self.itemFrame and self:itemFrame(inp) then return true end
    -- the sword: B, once Link has it (kSpinAttackDelays steps 0-8)
    local cb = self.data.roomIdx.combat
    local function held(input, b) return input and input.isDown and input.isDown(b) end
    if self.swing then
      local s = self.swing
      -- r19: B still held after the swing: the sword stays out (LinkItem_
      -- Sword -> HandleSwordControls -> Player_Sword_SpinAttackJerks_HoldDown):
      -- button_b_frames 9, its hit box (kPlayer_SetupActionHitBox row 9)
      -- pokes what it touches, and Link walks facing the same way. The
      -- Stalfos do not jump away from a held sword (Stalfos_Skellington,
      -- button_b_frames 9..0x8F). Letting go ends it.
      -- r20 (cartridge): while set_when_damaging_enemies (game.swde) is 0
      -- the charge counts up to 64 and Link walks at link_speed_setting 12
      -- (kSpeedMod[12] = 20, 1.25 px a frame); a hit sets it to 16: the
      -- jerk frames 10-12 run (kSpinAttackDelays) and at 1 the sword is put
      -- away (Link_ResetSwordAndItemUsage; B must be pressed again). Letting
      -- go with the charge at 48 or more starts the spin attack
      -- (Link_ActivateSpinAttack -> LinkState_SpinAttack): 12 steps,
      -- kLinkSpinGraphicsByDir / kLinkSpinDelays, button_b_frames 144 (the
      -- box x - 14, y - 10, 44 x 45; the damage class | 4)
      if s.spin then
        s.delay = s.delay - 1
        if s.delay < 0 then
          s.step = s.step + 1
          if s.step >= 12 then
            self.swing, self.swordHeld = nil, 0
            return true
          end
          s.gfx = cb.spinGfx[s.step + s.offs + 1] or 0
          s.delay = cb.spinDelays[s.step + 1] or 1
        end
        s.box = { lk.x - 14, lk.y - 10, 44, 45 }
        self.actors:swordHit(lk.x - 14, lk.y - 10, 44, 45, { vel = 0x50, lower = inside.lower or false,
                                                            sword = true, spin = true, bFrames = 144 })
        return true
      end
      if s.held then
        if not held(self.input, "b") then
          lk.speedSetting = 0
          if (s.charge or 0) >= 48 then
            -- Link_AnimateVictorySpin: delay 3, the first picture, then one
            -- frame of LinkState_SpinAttack at once
            s.held, s.spin, s.step, s.delay = nil, true, 0, 3
            s.offs = math.floor(lk.facing / 2) * 12
            s.gfx = cb.spinGfx[s.offs + 1] or 0
            self.swordHeld = 144
            self.spins = (self.spins or 0) + 1
            s.delay = s.delay - 1
            s.box = { lk.x - 14, lk.y - 10, 44, 45 }
            self.actors:swordHit(lk.x - 14, lk.y - 10, 44, 45, { vel = 0x50, lower = inside.lower or false,
                                                                sword = true, spin = true, bFrames = 144 })
            return true
          end
          self.swing, self.swordHeld = nil, 0
          return true
        end
        local swde = self.swde or 0
        if s.step == 9 and swde == 0 then
          lk.speedSetting = 12
          if (s.charge or 0) < 64 then s.charge = (s.charge or 0) + 1 end
          self.swordHeld = 9
        elseif swde == 1 then
          lk.speedSetting = 0
          self.swing, self.swordHeld = nil, 0
          self.swordPutAway = (self.swordPutAway or 0) + 1
          return true
        else
          if s.step == 9 then s.step, s.delay = 10, cb.swordDelays[11] or 0 end
          s.delay = s.delay - 1
          if s.delay < 0 then
            local f = s.step + 1
            if f == 13 then f = 10 end
            s.step, s.delay = f, cb.swordDelays[f + 1] or 0
          end
        end
        local yt, rt = 2, 0
        if s.step > 9 then yt, rt = 3, s.step - 10 end
        local x, y, w, h = Actors.swordBox(cb, lk, s.step, self.data.t.playerOamOffs, yt, rt)
        s.box = x and { x, y, w, h } or nil
        if x then
          local n = self.actors:swordHit(x, y, w, h, { vel = 0x40, lower = inside.lower or false, sword = true,
                                                       held = true, bFrames = s.step })
          if (n or 0) > 0 then self.swordPokes = (self.swordPokes or 0) + 1 end
        end
        -- (falls through: key doors and in-room stairs work with it held)
      else
      s.delay = s.delay - 1
      if s.delay < 0 then
        s.step = s.step + 1
        if s.step >= 9 then
          if held(self.input, "b") then
            s.held, s.step, s.delay, s.charge, s.facing = true, 9, 0, 0, lk.facing
            self.swordHeld = 9
            self.swordHolds = (self.swordHolds or 0) + 1
            return true
          end
          self.swing = nil return true
        end
        s.delay = cb.swordDelays[s.step + 1] or 0
      end
      local x, y, w, h = Actors.swordBox(cb, lk, s.step, self.data.t.playerOamOffs)
      s.box = x and { x, y, w, h } or nil
      -- round 10: the knockback is 0x50 while button_b_frames < 9 (r20: the
      -- swing's steps 0-8 are all under 9), else 0x40
      s.n = (s.n or 0) + 1
      -- round 13: only sprites on Link's level (Sprite_CheckDamageFromLink
      -- returns when sprite_floor != link_is_on_lower_level)
      if x then self.actors:swordHit(x, y, w, h, { vel = 0x50, lower = inside.lower or false,
                                                   sword = true, bFrames = s.step }) end
      return true
      end
    end
    local heldSword = self.swing ~= nil and self.swing.held
    if inp.b and self.progress.sword and cb and not heldSword then
      self.swing = { step = 0, delay = cb.swordDelays[1] or 1 }
      self.swings = (self.swings or 0) + 1
      return true
    end
    -- A: chests, locks, people, the mantle, the switch; else a pot
    if inp.a and not heldSword and not self:escapeAct() then
      if self:tryLift() then return true end
      -- r19: nothing to lift: the Pegasus Boots dash (Link_PerformDash, Dash.lua)
      if require("src.zelda.alttp.Dash").start(self) then return true end
    end
    -- round 16: push blocks, the rupee floor (RoomObjects.lua)
    require("src.zelda.alttp.RoomObjects").frame(self, inp)
    -- key doors: walking into one with a key opens it
    local f = FRONT[lk.facing]
    if inp.up or inp.down or inp.left or inp.right then
      local fx, fy = lk.x + f[1], lk.y + f[2]
      local cell = math.floor(fy / 8) * 64 + math.floor(fx / 8)
      for _, l in ipairs(inside.locks) do
        -- round 18: a big-key door (type 0x1E) wants the palace's big key
        local bigOk = l.kind == "bigkey" and self.hasBigKey and self:hasBigKey()
        if l.kind == "bigkey" and not l.open and not bigOk then
          for _, c in ipairs(l.cells) do
            if c == cell and not self.bigKeyMsg then self.bigKeyMsg = true; self:showMessage(122) end
          end
        end
        if ((l.kind == "key" and (self.progress.keys or 0) > 0) or bigOk) and not l.open then
          for _, c in ipairs(l.cells) do
            if c == cell then
              if l.kind == "key" then self.progress.keys = self.progress.keys - 1 end
              inside:openLock(l)
              inside.mem.doors[l.index] = true
              self.roomImages = nil
              self.doorsOpened = (self.doorsOpened or 0) + 1
              self:syncKeys()
              break
            end
          end
        end
      end
    end
    -- in-room stairs: Link walking onto them
    local dir = (inp.up and "up") or (inp.down and "down") or nil
    local st = dir and inside:inroomStair(lk.x, lk.y, dir)
    if st then
      local up = dir == "up"
      local c = { t = 0, frames = up and 0x38 or 0x3C, dy = up and -1 or 1 }
      if st.kind ~= 0x0D then
        if not st.south then
          -- north stairs: going up puts Link on the upper level at once, going
          -- down puts him on the lower level at the end
          if up then inside.lower = false else c.endLower = true end
        else
          if not up then inside.lower = not inside.lower else c.endSwap = true end
        end
      end
      self.climb = c
      return true
    end
    return false
  end

  function G:escapeAct()
    local inside = self.interior
    local lk = self.link
    local f = FRONT[lk.facing]
    local px, py = lk.x + f[1], lk.y + f[2]
    local chest, i = inside:chestAt(px, py)
    if chest and not chest.opened then
      if chest.lock then
        if self:hasBigKey() then
          inside:openChest(chest)
          inside.mem.chests[i] = true
          self.roomImages = nil
        end
      elseif lk.facing == Link.UP and (chest.w ~= 4 or self:hasBigKey()) then
        -- round 18: a big chest wants the palace's big key; opening it
        -- starts the falling-Stalfos overlords (OpenBigChest: byte_7E0B9E)
        inside:openChest(chest)
        if chest.w == 4 then inside.mem.bigChestOpened = true end
        inside.mem.chests[i] = true
        self.roomImages = nil
        if chest.item then
          self:getItem(chest.item)
          self:startReceipt(chest.item, chest)
        end
      end
      return true
    end
    local a = self.actors:facing(px, py)
    if not a then return false end
    if a.type == Actors.UNCLE and inside.room == 0x55 and not self.progress.sword then
      self:showMessage(Actors.MSG_UNCLE)
      self.onTextDone = function(g) g.progress.sword = true; g.progress.startPoint = 3 end   -- r12: SNES which_starting_point = 3
    elseif a.type == Actors.UNCLE and inside.room == 0x12 then
      if self.progress.zelda == 1 then
        self:showMessage(Actors.MSG_PRIEST)
        self.onTextDone = function(g) g.progress.zelda = 2; g.progress.escaped = true; g.progress.startPoint = 1 end   -- r12: the sanctuary
      end
    elseif a.type == Actors.ZELDA then
      local cellOpen = true
      for _, c in ipairs(inside.chests) do if c.lock and not c.opened then cellOpen = false end end
      if cellOpen then
        self:showMessage(Actors.MSG_ZELDA)
        self.onTextDone = function(g) g.progress.zelda = 1; a.dead = true; g.progress.startPoint = 2 end   -- r12: TransitionToTagalong, the prison
      end
    elseif require("src.zelda.alttp.Npc").TYPES[a.type] then
      -- round 16: people (Npc.lua)
      require("src.zelda.alttp.Npc").talk(self, a)
    elseif a.type == Actors.PULL then
      if not a.pulled then
        a.pulled = true
        self:openShutters()
      end
    end
  end

  -- OVERWORLD (round 6): the sword cuts bushes (SNES
  -- Overworld_ToolAndTileInteraction at swing step 5: map16 0x36 -> 0xDC7,
  -- the replacement words from the cartridge's map16 table), and a pit
  -- under Link sends him to the entrance the cartridge's hole table names
  -- for the area (0x0808B55C).
  local O = require("src.zelda.alttp.Overworld")
  local CUT = { [0x36] = 0xDC7, [0x72A] = 0xDC8, [0x20F] = 0xDCA, [0x239] = 0xDCA, [0x101] = 0xDC6 }
  G.CUT_TILES = CUT
  G.SWORD_CUT = { [0x36] = 0xDC7, [0x72A] = 0xDC8, [0x37E] = 0xDC5 }
  function G:owTileChange(x, y, fromTo)
    local m16 = self.data.roomIdx and self.data.roomIdx.map16
    if not m16 then return false end
    local world = self.link.world
    local tx, ty = math.floor(x / 16) * 16, math.floor(y / 16) * 16
    local screen = O.screenAt(world, tx, ty)
    if not screen then return false end
    local n = self.data:mapNumber("bg2", screen)
    local lx, ly = (tx % 512) / 8, (ty % 512) / 8
    local cells = { O.cellIndex(lx, ly), O.cellIndex(lx + 1, ly), O.cellIndex(lx, ly + 1), O.cellIndex(lx + 1, ly + 1) }
    for from, to in pairs(fromTo) do
      local w = m16[from]
      if w and m16[to] then
        local same = true
        for k = 1, 4 do if self.data:mapWord(n, cells[k]) ~= w[k] then same = false break end end
        if same then
          -- a secret under the tile (SNES Overworld_RevealSecret: kTileBelow)
          local area = self.ow:area(screen)
          local pos = math.floor((ty - area.y) / 16) * 128 + math.floor((tx - area.x) / 16) * 2
          local secrets = self.data.roomIdx.owSecrets and self.data.roomIdx.owSecrets[area.parent + 1]
          -- round 9: the secret's value for the drop (Overworld_RevealSecret:
          -- below 0x80 it is what the tile hides, 0x80+ a hole/stairs = 0xFF)
          self.lastSecret, self.lastCutFrom = 0, from
          for _, sc in ipairs(secrets or {}) do
            local below = ({ [0x80] = 0xDCC, [0x82] = 0x212, [0x86] = 0xDB4 })[sc.type]
            if sc.pos == pos and below and m16[below] then to = below; self.secretsFound = (self.secretsFound or 0) + 1 end
            if sc.pos == pos then self.lastSecret = sc.type < 0x80 and sc.type or 0xFF end
          end
          self.data.mapPatch = self.data.mapPatch or {}
          local p = self.data.mapPatch[n] or {}
          self.data.mapPatch[n] = p
          for k = 1, 4 do p[cells[k]] = m16[to][k] end
          self.ow.attrCache[screen] = nil
          if self.view then self.view.screens[screen] = nil end
          self.bushesCut = (self.bushesCut or 0) + 1
          return true
        end
      end
    end
    return false
  end

  -- set the 16x16 tile at world (x, y) to a map16 tile (the cartridge's
  -- map16 -> map8 table), as Overworld_DrawMap16_Persist does
  function G:owSetMap16(x, y, id)
    local m16 = self.data.roomIdx and self.data.roomIdx.map16
    if not (m16 and m16[id]) then return false end
    local tx, ty = math.floor(x / 16) * 16, math.floor(y / 16) * 16
    local screen = O.screenAt(self.link.world, tx, ty)
    if not screen then return false end
    local n = self.data:mapNumber("bg2", screen)
    local lx, ly = (tx % 512) / 8, (ty % 512) / 8
    local cells = { O.cellIndex(lx, ly), O.cellIndex(lx + 1, ly), O.cellIndex(lx, ly + 1), O.cellIndex(lx + 1, ly + 1) }
    self.data.mapPatch = self.data.mapPatch or {}
    local p = self.data.mapPatch[n] or {}
    self.data.mapPatch[n] = p
    for k = 1, 4 do p[cells[k]] = m16[id][k] end
    self.ow.attrCache[screen] = nil
    if self.view then self.view.screens[screen] = nil end
    return true
  end

  -- THE BIG DOOR OPENING (round 7; SNES Module09_0C_OpenBigDoor): Link
  -- waits while the door's 32x32 block (its tile and the one above, two
  -- wide) is redrawn; it ends on kDoorAnimTiles[16..19] (map16 0xDBA-0xDBD,
  -- the open gate), then the door is entered like any other. OURS: only the
  -- last frame is drawn (the GBA's own frame list is not located) and the
  -- wait is the SNES step count (1 frame a step, 8 per update).
  function G:updateGate()
    local gt = self.gate
    gt.t = gt.t + 1
    self.cam = self:cameraFor(self.area)
    if gt.t < gt.frames then return end
    for k = 0, 3 do
      self:owSetMap16(gt.x + (k % 2) * 16, gt.y - 16 + math.floor(k / 2) * 16, 0xDBA + k)
    end
    -- the open block's four tiles may now be entered as doors (the
    -- entrance table names one of them)
    local Interior = require("src.zelda.alttp.Interior")
    for k = 0, 3 do
      local key = Interior.owDoorKey(self.data, self.ow, self.link.world, gt.x + (k % 2) * 16,
                                     gt.y - 16 + math.floor(k / 2) * 16 - 7)
      if key then self.progress.gates[key] = true end
    end
    self.gatesOpened = (self.gatesOpened or 0) + 1
    self.gate = nil
  end

  function G:escapeOwFrame(inp)
    local lk = self.link
    if (self.blink or 0) > 0 then self.blink = self.blink - 1 end
    local cb = self.data.roomIdx and self.data.roomIdx.combat
    -- round 18: arrows, bombs, the lamp's flame (Items.lua); they run
    -- whatever Link is doing (Ancilla_Main)
    if self.updateAncillae then self:updateAncillae() end
    -- round 10: knocked back by an overworld enemy (as in rooms)
    if self.recoil then
      local r = self.recoil
      r.t = r.t - 1
      -- r22: hurt while lifting / carrying throws it (Carry.lua)
      if self.carryRecoilFrame then self:carryRecoilFrame() end
      local O = require("src.zelda.alttp.Overworld")
      local function free(x, y)
        for _, p in ipairs({ { 1, 8 }, { 14, 8 }, { 1, 23 }, { 14, 23 } }) do
          local at = self.ow:attrAt(lk.world, x + p[1], y + p[2])
          if O.isSolid(at) or O.LEDGE[at] then return false end
        end
        return true
      end
      r.sx, r.sy = (r.sx or 0) + r.vx, (r.sy or 0) + r.vy
      local mx = (r.sx >= 0) and math.floor(r.sx / 16) or -math.floor(-r.sx / 16)
      local my = (r.sy >= 0) and math.floor(r.sy / 16) or -math.floor(-r.sy / 16)
      r.sx, r.sy = r.sx - mx * 16, r.sy - my * 16
      if mx ~= 0 and free(lk.x + mx, lk.y) then lk.x = lk.x + mx end
      if my ~= 0 and free(lk.x, lk.y + my) then lk.y = lk.y + my end
      -- r20: the hop (Sprite_ApplyRecoilToLink: z speed = speed >> 1;
      -- Player_ChangeZ: - 2 a frame; Link_HandleRecoilAndTimer keeps the
      -- timer at 1 until Link lands)
      if r.vz then
        r.fz = (r.fz or 0) + r.vz
        local mz = (r.fz >= 0) and math.floor(r.fz / 16) or -math.floor(-r.fz / 16)
        r.fz = r.fz - mz * 16
        lk.z = math.max(0, (lk.z or 0) + mz)
        if not (r.vz < 0 and (lk.z or 0) == 0) then r.vz = r.vz - 2 end
        if r.t <= 0 and not ((lk.z or 0) <= 0 and r.vz < 0) then r.t = 1 end
      end
      if r.t <= 0 then self.recoil = nil; lk.z = 0 end
      return true
    end
    -- bug round: lifting / carrying / throwing (Carry.lua)
    if self:carryFrame(inp) then return true end
    if not self.swing and self.itemFrame and self:itemFrame(inp) then return true end
    if self.swing then
      -- r21: the held sword and the spin attack outdoors (OwSword.lua)
      local OwSword = require("src.zelda.alttp.OwSword")
      local ow = OwSword.frame(self)
      if ow ~= nil then return ow end
      local s = self.swing
      s.delay = s.delay - 1
      if s.delay < 0 then
        s.step = s.step + 1
        if s.step >= 9 then
          if OwSword.startHold(self) then return true end
          self.swing = nil return true
        end
        s.delay = cb.swordDelays[s.step + 1] or 0
        if s.step == 5 then
          -- r21: the point is the cartridge's (TileDetect_MainHandler(1))
          local f = OwSword.tileOffset(self, 1) or FRONT[lk.facing]
          -- round 9: the sword cuts bushes and thick grass only (SNES
          -- Overworld_ToolAndTileInteraction: 0x36, 0x72A, 0x37E), then the
          -- cartridge's drop routine runs for the cut tile (Drops.lua)
          local cx, cy = lk.x + f[1], lk.y + f[2]
          if self:owTileChange(cx, cy, G.SWORD_CUT) then
            local Drops = require("src.zelda.alttp.Drops")
            local kind = Drops.CUT_KIND[self.lastCutFrom] or 2
            local tx, ty = math.floor(cx / 16) * 16, math.floor(cy / 16) * 16
            self:terrainDrop(kind, self.lastSecret, tx, ty)
            -- Sprite_SpawnImmediatelySmashedTerrain: the bush breaks at once
            self:spawnDebris(kind, tx, ty)
          end
        end
      end
      local x, y, w, h = Actors.swordBox(cb, lk, s.step, self.data.t.playerOamOffs)
      s.box = x and { x, y, w, h } or nil
      -- round 10: the sword hits the overworld's actors too
      s.n = (s.n or 0) + 1
      if x and self.owActors then self.owActors:swordHit(x, y, w, h, { vel = (s.n < 9) and 0x50 or 0x40 }) end
      return true
    end
    if inp.b and self.progress.sword and cb then
      self.swing = { step = 0, delay = cb.swordDelays[1] or 1 }
      return true
    end
    -- A lifts the bush in front of Link (SNES Overworld_LiftableTiles: the
    -- same replacement and secret check; OURS: the bush is not carried or
    -- thrown, it is gone)
    -- (bug round: lifted, carried and thrown, Carry.lua)
    if inp.a and self:tryLift() then return true end
    -- pits (attribute 0x20) under Link's feet
    local a = self.ow:attrAt(lk.world, lk.x + 8, lk.y + 16)
    if a == 0x20 then
      local area = self.ow:area(self:screen()).parent
      for _, hole in ipairs(self.data.roomIdx.holes or {}) do
        if hole.area == area and hole.keys[1] == 0xFFF0 then
          self.fellFrom = { world = lk.world, x = lk.x, y = lk.y }
          self:enterRoom(hole.ent)
          return true
        end
      end
    end
    return false
  end

  -- BUG ROUND: THE ITEM OUT OF A CHEST (zelda3 AncillaAdd_ItemReceipt with
  -- item_receipt_method 1, Ancilla22_ItemReceipt): Link stands still while
  -- the item rises from the chest (y velocity -1 a frame down to -8, in
  -- 1/16 px, once the 0x38-frame timer is below 24 frames from its start --
  -- i.e. after 0x38 - 24 = 32 frames of the timer), then the cartridge's
  -- message for the item (kReceiveItemMsgs, t.items.receiptMsgs) opens; the
  -- item goes when the text closes. The SNES draws Link with his normal
  -- pose for a chest (link_pose_for_item is only set for method 0).
  -- OURS: the item is drawn with its item-menu icon (the receipt sprite
  -- sheet, kReceiveItemGfx, is not ported); the chest-relative offsets
  -- kReceiveItem_Tab2/3 are not read (the item starts 4 px into the chest).
  G.RECEIPT_FRAMES = 0x38
  function G:startReceipt(item, chest)
    self.receipt = { item = item, x = chest.x * 8 + (chest.w == 4 and 8 or 0), y = chest.y * 8 + 4,
                     sub = 0, vel = 0, t = G.RECEIPT_FRAMES }
    self.receipts = (self.receipts or 0) + 1
  end
  function G:receiptMessage(item)
    local it = self.data.t and self.data.t.items
    local v = it and it.receiptMsgs[item + 1]
    if not v or v == 0xFFFF then return nil end
    return require("src.zelda.alttp.Text").bmgIndex(v)
  end
  -- one frame; true while the receipt holds Link
  function G:updateReceipt()
    local r = self.receipt
    if not r then return false end
    if r.waiting then return true end
    r.t = r.t - 1
    if r.t >= 24 then
      if r.vel > -8 then r.vel = r.vel - 1 end
    end
    r.sub = r.sub + r.vel
    while r.sub <= -16 do r.sub = r.sub + 16; r.y = r.y - 1 end
    if r.t <= 0 then
      local msg = self:receiptMessage(r.item)
      if msg and self:showMessage(msg) then
        r.waiting = true
        local prev = self.onTextDone
        self.onTextDone = function(g)
          g.receipt = nil
          if prev then prev(g) end
        end
      else
        self.receipt = nil
      end
    end
    return true
  end
  function G:drawReceipt(cx, cy)
    local r = self.receipt
    if not (r and self.view and self.data.menus and self.data.ui) then return end
    local Menu = require("src.zelda.alttp.Menu")
    local R = require("src.zelda.alttp.RomMap")
    local slot = Menu.RECEIPT_SLOT[r.item]
    if not slot then return end
    local tab = R.menu.gridTab[slot[1]]
    local t = self.data.menus
    local a = tab + slot[2] * 8
    local words = { t:u16(a), t:u16(a + 2), t:u16(a + 4), t:u16(a + 6) }
    local Hud = require("src.zelda.alttp.Hud")
    self.hudPal = self.hudPal or Hud.palette(self.data, 0)
    -- the menu box's black behind the icon is left out (OURS)
    if not self.receiptPal then
      self.receiptPal = {}
      for k, v in pairs(self.hudPal) do if v ~= 0 then self.receiptPal[k] = v end end
    end
    local im = self.view:hudImage(words, 2, 2, self.receiptPal, t:get("itemLang"))
    love.graphics.draw(im, r.x - cx, r.y - cy)
  end

  -- round 17: an item's menu icon at (x, y) on the screen (the falling
  -- pendant; OURS as the receipt above); the pendants use the menu's
  -- pendant words (RomMap.menu.pendants)
  function G:drawItemIcon(item, x, y)
    if not (self.view and self.data.menus and self.data.ui) then return end
    local R = require("src.zelda.alttp.RomMap")
    local t = self.data.menus
    local words
    local pk = ({ [0x37] = 4, [0x38] = 3, [0x39] = 2 })[item]
    if pk then
      local e = R.menu.pendants[pk]
      local a = e[1] + 8
      words = { t:u16(a), t:u16(a + 2), t:u16(a + 4), t:u16(a + 6) }
    else
      local slot = require("src.zelda.alttp.Menu").RECEIPT_SLOT[item]
      if not slot then return end
      local a = R.menu.gridTab[slot[1]] + slot[2] * 8
      words = { t:u16(a), t:u16(a + 2), t:u16(a + 4), t:u16(a + 6) }
    end
    local Hud = require("src.zelda.alttp.Hud")
    self.hudPal = self.hudPal or Hud.palette(self.data, 0)
    if not self.receiptPal then
      self.receiptPal = {}
      for k, v in pairs(self.hudPal) do if v ~= 0 then self.receiptPal[k] = v end end
    end
    local im = self.view:hudImage(words, 2, 2, self.receiptPal, t:get("itemLang"))
    love.graphics.draw(im, x, y)
  end

  -- drawing (OURS: plain shapes, see the header)
  local COLORS = { soldier = { 0.2, 0.5, 0.9 }, green = { 0.2, 0.7, 0.3 }, critter = { 0.55, 0.45, 0.35 },
                   uncle = { 0.75, 0.4, 0.3 }, zelda = { 0.95, 0.75, 0.85 }, key = { 0.95, 0.85, 0.2 },
                   mantle = { 0.5, 0.3, 0.15 }, switch = { 0.7, 0.7, 0.7 } }
  local function colorOf(a)
    if a.type == 0x41 or a.type == 0x6A then return COLORS.soldier end
    if Actors.SOLDIER[a.type] then return COLORS.green end
    if Actors.CRITTER[a.type] then return COLORS.critter end
    if a.type == Actors.UNCLE then return COLORS.uncle end
    if a.type == Actors.ZELDA then return COLORS.zelda end
    if a.type == Actors.KEY then return COLORS.key end
    if a.type == Actors.MANTLE then return COLORS.mantle end
    return COLORS.switch
  end
  -- round 7: the cartridge's sprite graphics (Sprites.lua) when the cache
  -- has them; the plain shapes below stay as the fallback for an old cache
  function G:spriteGfx()
    local Sprites = require("src.zelda.alttp.Sprites")
    if not Sprites.available(self.data) then return nil end
    self.sprites = self.sprites or Sprites.new(self.data)
    local inside = self.interior
    self.sprites:setRoom(inside.hdr, inside.palSet, self.data.roomIdx.palSets)
    return self.sprites
  end

  function G:drawActors(cx, cy)
    local lg = love.graphics
    local spr = self:spriteGfx()
    if spr then
      lg.setColor(1, 1, 1, 1)
      local lower = self.interior.lower or false
      -- round 14: one GBA OBJ priority per pass (Layers.lua): a sprite's
      -- priority is kSpritePrios[its floor]
      local Layers = require("src.zelda.alttp.Layers")
      for _, a in ipairs(self.actors.list) do
        if not a.dead and not (a.inv and a.inv > 0 and a.inv % 4 < 2)
           and self:inPrioPass(Layers.spritePrio(self.data, a.lower)) then
          -- round 9: the sprite's shadow under it (SpriteDraw_Shadow)
          if spr:hasShadow(a.type) then spr:drawShadow(a.x - cx, a.y - cy, a.type) end
          if a.type == 0x3B then require("src.zelda.alttp.DashItem").draw(self, a, a.x - cx, a.y - cy)   -- r21
          elseif a.type == 0xBB and a.shopItem then require("src.zelda.alttp.Shop").draw(spr, a, a.x - cx, a.y - cy, self.frame, self)   -- r22
          else spr:drawActor(a, a.x - cx, a.y - cy, self.frame, self.interior.room) end
        end
      end
      -- r21: the death puffs (Effects.lua), at the sprites' priority
      require("src.zelda.alttp.Effects").drawPuffs(self, spr, cx, cy,
        function(p) return self:inPrioPass(Layers.spritePrio(self.data, p.lower)) end)
      local fo = self.actors.follower
      -- round 14: the follower is drawn on Link's priority (kTagalongLayerBits)
      if fo and self:inPrioPass(self:linkObjPrio()) then
        -- round 10: the follower's facing is Link's (0/2/4/6); the actor
        -- direction is 0-3 (up, down, left, right) -- facing left/right crashed
        spr:drawZelda({ type = 0x76, dir = math.floor((fo.facing or 2) / 2), moving = fo.moving }, fo.x - cx, fo.y + 8 - cy, self.frame)
      end
      self:drawOpenedLocks(cx, cy)
      return
    end
    for _, a in ipairs(self.actors.list) do
      if not a.dead then
        local c = colorOf(a)
        local blink = a.inv and a.inv > 0 and a.inv % 4 < 2
        lg.setColor(c[1], c[2], c[3], blink and 0.4 or 1)
        local w = a.type == Actors.MANTLE and 32 or 16
        if a.type == Actors.KEY then
          lg.rectangle("fill", a.x + 5 - cx, a.y + 2 - cy, 6, 12)
        elseif Actors.CRITTER[a.type] then
          lg.rectangle("fill", a.x + 2 - cx, a.y + 6 - cy, 12, 8)
        else
          lg.rectangle("fill", a.x - cx, a.y - 4 - cy, w, 20)
          lg.setColor(0, 0, 0, 0.6)
          lg.rectangle("line", a.x - cx + 0.5, a.y - 4 - cy + 0.5, w - 1, 19)
        end
      end
    end
    local fo = self.actors.follower
    if fo then
      local c = COLORS.zelda
      lg.setColor(c[1], c[2], c[3], 1)
      lg.rectangle("fill", fo.x - cx, fo.y + 4 - cy, 16, 20)
    end
    self:drawOpenedLocks(cx, cy)
  end

  -- opened key doors / shutters: round 11 draws them with the cartridge's
  -- opened-door words (Interior:drawDoor, on the room maps); the black
  -- doorway is only the fallback for a cache without the door pictures
  function G:drawOpenedLocks(cx, cy)
    if self.data.roomIdx and self.data.roomIdx.doorTiles then return end
    if self.prioPass and self.prioPass ~= 3 then return end
    local lg = love.graphics
    lg.setColor(0, 0, 0, 1)
    for _, l in ipairs(self.interior.locks) do
      if l.open then
        for _, cell in ipairs(l.cells) do
          lg.rectangle("fill", (cell % 64) * 8 - cx, math.floor(cell / 64) * 8 - cy, 8, 8)
        end
      end
    end
    lg.setColor(1, 1, 1, 1)
  end

  function G:drawSword(cx, cy)
    local s = self.swing
    if not (s and s.box) then return end
    -- bug round: the cartridge's sword sprite is drawn with Link
    -- (Weapon.lua); this outline is only the fallback for an old cache
    if require("src.zelda.alttp.Weapon").available(self.data) then return end
    local b = s.box
    love.graphics.setColor(0.85, 0.9, 1, 1)
    love.graphics.rectangle("fill", b[1] - cx + b[3] / 2 - 2, b[2] - cy + b[4] / 2 - 2, 4, 4)
    love.graphics.rectangle("line", b[1] - cx + 0.5, b[2] - cy + 0.5, b[3] - 1, b[4] - 1)
    love.graphics.setColor(1, 1, 1, 1)
  end
end

return E
