-- The file select (src/fileselect.c), drawn through Ppu.lua.
--
-- HandleFileScreenEnter: ResetScreenRegs' BG controls (BG0 $1F0C, BG1
-- $1C01, BG2 $1D02), BG3 $1E0B; LoadGfxGroup(5) + LoadPaletteGroup(9);
-- BG2 blended over BG3 at 15/10; every BG and OBJ on; BGM_FILE_SELECT; a
-- black fade in at speed 8.  sub_0805066C cycles the sparkle palettes
-- (banks 11-14 from gUnk_080FC8DE every 16 frames, a random rest at 0).
-- Each state loads its own gfx group (sub_080503A8): the file list 7,
-- name entry 8 + the keyboard page 9 + column, and so on.
--
-- Files.  The runtime gives the game one save slot; the cartridge has
-- three files.  The three files live inside that one slot: the active
-- file is the save table itself, the other two are kept in its
-- `fileSlots` table ([i] = a file table, or "active" for the one being
-- played).  Copy and erase work on those three.

local bit = require("bit")
local band, bor, lshift, rshift = bit.band, bit.bor, bit.lshift, bit.rshift
local Ppu = require("src.zelda.tmc.Ppu")

local FileSelect = {}
FileSelect.__index = FileSelect

FileSelect.SPARKLE = 0x080FC8DE   -- gUnk_080FC8DE: 15 u16 palette offsets
local SFX_CHOICE, SFX_SELECT, SFX_6B, SFX_CANCEL, SFX_ERROR = 0x69, 0x6A, 0x6B, 0x6C, 0x6D
local NAME_LEN = 6

-- ---------------------------------------------------------------------------
-- the three files inside one runtime save
-- ---------------------------------------------------------------------------
function FileSelect.files(save)
  local out = {}
  if type(save) ~= "table" then return out, nil end
  local slots = save.fileSlots
  if type(slots) ~= "table" then
    out[1] = save
    return out, 1
  end
  local active
  for i = 1, 3 do
    local v = slots[i]
    if v == "active" then out[i] = save; active = i
    elseif type(v) == "table" then out[i] = v end
  end
  if not active and not save.noFile then
    -- an old save without its own slot: it is file 1 unless that is taken
    for i = 1, 3 do if not out[i] then out[i] = save; active = i break end end
  end
  return out, active
end

-- the table the runtime keeps: file `k` with the others beside it
function FileSelect.pack(files, k)
  local root = files[k]
  if not root then return nil end
  local slots = {}
  for i = 1, 3 do
    if i == k then slots[i] = "active"
    elseif files[i] then
      local copy = {}
      for key, v in pairs(files[i]) do if key ~= "fileSlots" then copy[key] = v end end
      slots[i] = copy
    end
  end
  root.fileSlots = slots
  return root
end

local function deepCopy(t, seen)
  if type(t) ~= "table" then return t end
  seen = seen or {}
  if seen[t] then return seen[t] end
  local c = {}
  seen[t] = c
  for k, v in pairs(t) do if k ~= "fileSlots" then c[deepCopy(k, seen)] = deepCopy(v, seen) end end
  return c
end
FileSelect.deepCopy = deepCopy

-- ---------------------------------------------------------------------------
function FileSelect.new(game)
  local self = setmetatable({ game = game, A = game.assets }, FileSelect)
  self.files, self.active = FileSelect.files(game.saveData)
  self.row = self.active and self.active - 1 or 0
  self.counter = 0
  self.sparkle, self.sparkleTimer = 0, 1
  self.ppu = Ppu.new(self.A)
  self:enter()
  return self
end

function FileSelect:sound(id)
  local au = self.game.audio
  if au and au.playSfx then pcall(au.playSfx, au, id) end
end

function FileSelect:enter()
  local p = self.ppu
  p.bg[0].control, p.bg[1].control, p.bg[2].control = 0x1F0C, 0x1C01, 0x1D02
  p.bg[3].control = 0x1E0B
  p:loadGfxGroup(5)
  p:loadPaletteGroup(9)
  -- FileSelectTask's first frame: unk3 (7) != the language, so
  -- sub_080503A8(6) and sub_080503A8($F) load the language's letters
  p:loadGfxGroup(6)
  p:loadGfxGroup(0xF)
  -- the HUD palette (ui.c LoadPaletteGroup($C): bank 15, the hearts)
  p:loadPaletteGroup(0xC)
  p.blend = { t1 = 0x04, eva = 15, evb = 10 }
  p.dispcnt = 0x1F40
  for n = 0, 2 do p.bg[n].updated = true end -- BG3's map is loaded into VRAM ($0600F000)
  self.fade = { level = 256, speed = 8 }
  local au = self.game.audio
  if au then pcall(au.playBgm, au, 0x07) end
  self:setState("list")
end

-- SetFileSelectState: clear BG0 / BG1, the state's own gfx group
function FileSelect:setState(st)
  local p = self.ppu
  self.state = st
  p:clearBuffers({ [0] = true, true })
  for n = 0, 2 do p.bg[n].x, p.bg[n].y = 0, 0 end
  if st == "list" then
    p:loadGfxGroup(7)
  end
  -- sub_080503A8 flags BG1 and BG2 only: gBG3Buffer is the keyboard
  -- pages' scratch, never copied to BG3's screen
  for n = 0, 2 do p.bg[n].updated = true end
end

-- sub_0805066C
function FileSelect:updateSparkle()
  local load = false
  self.sparkleTimer = self.sparkleTimer - 1
  if self.sparkleTimer == 0 then
    self.sparkleTimer = 16
    self.sparkle = (self.sparkle + 1) % 15
    load = true
  end
  if self.sparkle == 0 then
    self.sparkle = 1
    self.sparkleTimer = math.random(0, 7) * 16 + 8
    load = true
  end
  if load then
    local t = Ppu.table({ A = self.A }, "fileSparkle")
    if t then
      local off = t.u16(FileSelect.SPARKLE + 2 * self.sparkle)
      -- LoadPalettes(&gGlobalGfxAndPalettes[off + $11AA0 + k * $100], 11 + k, 1)
      for k = 0, 3 do self:loadPalOffset(off + 0x11AA0 + k * 0x100, 11 + k) end
    end
  end
end

function FileSelect:loadPalOffset(off, bank)
  local raw = self.A.palRaw or self.A.store:read("pal.bin") or ""
  self.A.palRaw = raw
  -- pal.bin is gGlobalGfxAndPalettes' palette area from its start
  -- (Ppu.loadPalettes: id * 32); off is a byte offset into the same blob
  for c = 0, 15 do
    local lo, hi = raw:byte(off + 2 * c + 1), raw:byte(off + 2 * c + 2)
    if lo and hi then self.ppu.pal[bank * 16 + c] = lo + 256 * hi end
  end
  self.ppu.dirty = true
end

-- ---------------------------------------------------------------------------
-- persistence: the runtime keeps one table (the active file + fileSlots)
-- ---------------------------------------------------------------------------
function FileSelect:commit()
  local k = self.active
  if not (k and self.files[k]) then
    k = nil
    for i = 1, 3 do if self.files[i] then k = i break end end
  end
  self.active = k
  local root
  if k then root = FileSelect.pack(self.files, k)
  else root = { noFile = true, fileSlots = {} } end
  self.game.saveData = root
  local host = self.game.opts and self.game.opts.host
  if host and host.requestSave then pcall(host.requestSave, host) end
end

-- CreateDialogBox (fileselect.c): font gUnk_080FC844 with the dialog's
-- palette in gfx_src, ShowTextBox(text) into BG0, the dialog's sound
function FileSelect:dialog(n)
  local p = self.ppu
  p:clearBuffers({ [0] = true })
  local t = p:table("dialogBox")
  if t then
    local e = 0x080FC85C + 6 * n
    local font = p:font("dialogBox", 0x080FC844)
    if font then
      font.gfx_src = bor(font.gfx_src, lshift(t.u16(e), 12))
      p:showTextBox(t.u16(e + 2), font)
    end
    local sfx = t.u16(e + 4)
    if sfx ~= 0 then self:sound(sfx) end
  end
  p.bg[0].updated = true
  self.dialogOn = true
end

function FileSelect:closeDialog()
  self.ppu:clearBuffers({ [0] = true })
  self.ppu.bg[0].updated = true
  self.dialogOn = false
end

-- ---------------------------------------------------------------------------
-- states (gUI.state): list 0, new 1, view 4, copy 5, erase 6, start 7
-- ---------------------------------------------------------------------------
local STATE_NUM = { list = 0, new = 1, view = 4, copy = 5, erase = 6, start = 7 }

function FileSelect:update(input)
  self.counter = self.counter + 1
  if self.fade then
    local fd = self.fade
    fd.level = fd.out and (fd.level + fd.speed) or (fd.level - fd.speed)
    if (fd.out and fd.level >= 256) or (not fd.out and fd.level <= 0) then
      self.fade = nil
      if self.exitTo then
        local k = self.exitTo
        self.exitTo = nil
        return self:start(k)
      end
    end
  end
  self:updateSparkle()
  local moving = self:objects()
  if self.fade or moving then return nil end
  if self.wait then
    if self.wait > 0 then self.wait = self.wait - 1 return nil end
    if input.pressed("a") or input.pressed("start") then
      self.wait = nil
      self:closeDialog()
      if self.afterWait then local f = self.afterWait; self.afterWait = nil; f() end
    end
    return nil
  end
  local st = self.state
  if st == "list" then return self:updateList(input)
  elseif st == "view" then return self:updateView(input)
  elseif st == "copy" then return self:updateCopy(input)
  elseif st == "erase" then return self:updateErase(input)
  elseif st == "new" then return self:updateNew(input) end
end

-- sub_08050940
function FileSelect:updateList(input)
  local row = self.row
  if input.pressed("up") and row > 0 then row = row - 1
  elseif input.pressed("down") and row < 2 then row = row + 1 end
  if row ~= self.row then
    self.row = row
    self:sound(SFX_CHOICE)
  end
  if input.pressed("a") or input.pressed("start") then
    self:sound(SFX_SELECT)
    if self.files[self.row + 1] then
      self.column = 0
      self:setState("view")
    else
      self:setState("new")
    end
  end
end

-- sub_08050C54 / sub_08050D68: Start / Copy / Erase
function FileSelect:updateView(input)
  if self.viewTimer then
    self.viewTimer = self.viewTimer - 1
    if self.viewTimer > 0 then return end
    self.viewTimer = nil
    local c = self.column
    if c == 1 then return self:enterCopy() end
    if c == 2 then self.column = 0; return self:setState("erase") end
    self:setState("start")
    self.fade = { level = 0, speed = 8, out = true } -- SetFade(FADE_IN_OUT | FADE_INSTANT, 8)
    self.exitTo = self.row + 1
    return
  end
  local c = self.column
  if input.pressed("a") or input.pressed("start") then
    self.viewTimer = 15
    self:sound(SFX_SELECT)
    return
  elseif input.pressed("b") then
    self:sound(SFX_CANCEL)
    return self:setState("list")
  elseif input.pressed("left") then c = math.max(0, c - 1)
  elseif input.pressed("right") then c = math.min(2, c + 1) end
  if c ~= self.column then self.column = c; self:sound(SFX_CHOICE) end
end

-- sub_08051738: the targets (a[i]: 0 the source, 4 another valid file,
-- else the empty files numbered 1..)
function FileSelect:enterCopy()
  self:setState("copy")
  local a, n = {}, 0
  for i = 0, 2 do
    if self.files[i + 1] then a[i] = (i == self.row) and 0 or 4
    else n = n + 1; a[i] = n end
  end
  self.copyA, self.copyN = a, n + 1
  self.target = 4
  if n == 0 then
    self:dialog(1)
    self.wait, self.afterWait = 60, function() self:setState("list") end
  else
    self.target = self:copyStep(1, 4) ~= 4 and self:copyStep(1, 4) or 4
    for i = 0, 2 do if a[i] == 1 then self.target = i end end
  end
end

-- sub_080517B4
function FileSelect:copyStep(d, from)
  local i = from or self.target
  if d ~= 0 then
    local j = i + d
    while j >= 0 and j < 5 do
      local v = (j <= 2) and self.copyA[j] or (j == 4 and 0 or 0)
      if j <= 2 and v ~= 0 and v ~= 4 then return j end
      j = j + d
    end
  end
  return i
end

function FileSelect:updateCopy(input)
  local d = 0
  if input.pressed("up") then d = -1 elseif input.pressed("down") then d = 1 end
  if input.pressed("a") or input.pressed("start") then
    if self.target < 3 then
      self:dialog(2)
      self:sound(SFX_SELECT)
      -- sub_08051874: HandleSave into the target, a copy of the source
      self.files[self.target + 1] = FileSelect.deepCopy(self.files[self.row + 1])
      self:commit()
      self.namesDrawn = false
      self.wait, self.afterWait = 30, function() self:setState("list") end
      return
    end
    self:sound(SFX_CANCEL)
    return self:setState("list")
  elseif input.pressed("b") then
    self:sound(SFX_CANCEL)
    return self:setState("list")
  end
  local t = self:copyStep(d)
  if d > 0 and t == self.target then t = 4 end
  if d < 0 and self.target == 4 then
    for j = 2, 0, -1 do local v = self.copyA[j] if v ~= 0 and v ~= 4 then t = j break end end
  end
  if t ~= self.target then self.target = t; self:sound(SFX_CHOICE) end
end

-- sub_080515D4: No (0) / Yes (1)
function FileSelect:updateErase(input)
  local c = self.column
  if input.pressed("a") or input.pressed("start") or input.pressed("b") then
    if input.pressed("b") then c = 0 end
    if c == 1 then
      self:dialog(4)
      self:sound(SFX_SELECT)
      local k = self.row + 1
      self.files[k] = nil
      if self.active == k then self.active = nil end
      self:commit()
      self.namesDrawn = false
      self.wait, self.afterWait = 30, function() self:setState("list") end
    else
      self:sound(SFX_CANCEL)
      self:setState("list")
    end
    return
  elseif input.pressed("left") then c = 0
  elseif input.pressed("right") then c = 1 end
  if c ~= self.column then self.column = c; self:sound(SFX_CHOICE) end
end

-- ---------------------------------------------------------------------------
-- name entry (sub_08051090, sub_080610B8): gfx group 8, the keyboard page
-- 9 + column into BG3 then BG1 ($100 entries on), every glyph drawn into
-- BG VRAM (sub_08050790: 16 rows of 16 8x16 cells, $400 bytes a row).
-- The character under the cursor is gBG3Buffer[a0 * 2 + $C3 + a1 * $40]
-- >> 1.  USA: 13 x 5 keys, row 5 = {page 1, page 2, back, END} at
-- columns gUnk_080FC9A0+8, actions gUnk_080FC970+8.
-- ---------------------------------------------------------------------------
-- the keyboard tables (Layout.MENU_DATA keyboardTables, USA = language 1)
function FileSelect:kb(addr) local t = Ppu.table({ A = self.A }, "keyboardTables") return t and t.u8(addr) or 0 end
local function ROW5_COLS(self, k) return self:kb(0x080FC9A0 + 8 + k) end   -- gUnk_080FC9A0 + 8
local function ROW5_ACT(self, k) return self:kb(0x080FC970 + 8 + k) end    -- gUnk_080FC970 + 8
local function COL_TO_ROW5(self, c) return self:kb(0x080FC980 + 0x10 + c) end -- gUnk_080FC980 + $10

function FileSelect:loadKeyboardGlyphs()
  local ffi = require("ffi")
  local p = self.ppu
  for i = 0, 15 do
    local buf = ffi.new("uint8_t[?]", 0x400)
    for j = 0, 15 do p:drawGlyphs(buf, 0x400, { { i * 16 + j } }, j * 8, j * 8 + 8, 5, 0, 0, true) end
    p:write(0x06000000 + i * 0x400, ffi.string(buf, 0x400))
  end
end

-- sub_08051458
function FileSelect:loadPage()
  local p = self.ppu
  p:loadGfxGroup(self.page + 9)
  local b3, b1 = p.bg[3].buf, p.bg[1].buf
  for k = 0, 0x3FF, 2 do p:set16(b1 + 0x100 + k, p:u16(b3 + 0x100 + k)) end
  p.bg[1].updated = true
end

function FileSelect:enterNew()
  local p = self.ppu
  p:loadGfxGroup(8)
  self:loadKeyboardGlyphs()
  self.page = 0
  self:loadPage()
  p.bg[1].y, p.bg[2].y = 0xFF, 0xFF
  self.key = { [0] = 0, 0, 0, 0 }   -- gGenericMenu.unk10.a: column, row, row-5 slot, name length
  self.newName = {}
end

function FileSelect:charAt(a0, a1)
  local p = self.ppu
  local e = p:u16(p.bg[3].buf + 2 * (a0 * 2 + 0xC3 + a1 * 0x40))
  return band(rshift(e, 1), 0xFF) -- u8 tmp2
end

function FileSelect:addChar(c)
  local k = self.key
  local i = math.min(k[3], NAME_LEN - 1)
  self.newName[i + 1] = c
  k[3] = i + 1
  self:sound(SFX_6B)
  self:redrawNewName()
end

function FileSelect:redrawNewName()
  local t = {}
  for i = 1, NAME_LEN do if self.newName[i] and self.newName[i] ~= 0 then t[#t + 1] = string.char(self.newName[i]) end end
  self.pendingName = table.concat(t)
  self.namesDrawn = false
end

function FileSelect:updateNew(input)
  local k = self.key
  local action = 0
  if input.pressed("b") then
    if k[3] ~= 0 then action = 5 else k[0], k[1], k[2] = 0xB, 5, 3; self:sound(0x67) end
  elseif input.pressed("start") then
    if k[1] == 5 and k[2] == 3 then action = 8 else k[0], k[1], k[2] = 0xB, 5, 3; self:sound(0x67) end
  elseif input.pressed("a") then
    action = k[1] == 5 and ROW5_ACT(self, k[2]) or 6
  elseif input.pressed("l") then action = 1
  elseif input.pressed("r") then action = 2
  else
    local dy, dx = 0, 0
    if input.pressed("up") then dy = -1 elseif input.pressed("down") then dy = 1
    elseif input.pressed("left") then dx = -1 elseif input.pressed("right") then dx = 1 end
    k[1] = (k[1] + dy + 6) % 6
    if dx ~= 0 or dy ~= 0 then self:sound(0x67) end -- SFX_TEXTBOX_NEXT
    if dx ~= 0 then
      if k[1] ~= 5 then
        k[0] = (k[0] + dx + 13) % 13
        k[2] = COL_TO_ROW5(self, k[0])
      else
        k[2] = (k[2] + dx + 4) % 4
        k[0] = ROW5_COLS(self, k[2])
      end
    end
  end
  local page = self.page
  if action == 1 then page = 0
  elseif action == 2 then page = 1
  elseif action == 5 then
    if k[3] ~= 0 then
      k[3] = k[3] - 1
      self.newName[k[3] + 1] = nil
      self:sound(SFX_CANCEL)
      self:redrawNewName()
    end
  elseif action == 6 then
    self:addChar(self:charAt(k[0], k[1]))
  elseif action == 8 then
    -- trailing spaces off; an empty name stays on the keyboard
    while #self.newName > 0 and (self.newName[#self.newName] == 0x20) do self.newName[#self.newName] = nil end
    self:redrawNewName()
    self:sound(SFX_SELECT)
    if (self.pendingName or "") ~= "" then
      -- sub_0805138C: "saving" (dialog 5), HandleSave, back to the list
      local Game = require("src.zelda.tmc.Game")
      self.files[self.row + 1] = Game.newSave(self.pendingName)
      self.pendingName = nil
      self:commit()
      self:dialog(5)
      self.wait, self.afterWait = 30, function() self:setState("list") end
    end
    return
  end
  if page ~= self.page then
    self.page = page
    self:loadPage()
    self:sound(0x68) -- SFX_TEXTBOX_SWAP
  end
end

function FileSelect:start(k)
  self.active = k
  local save = FileSelect.pack(self.files, k)
  self.game:startGame(save)
  return "start"
end

-- ---------------------------------------------------------------------------
-- FILE_SCREEN_OBJECTS (object $48, sprite $145, common OBJ VRAM; frames
-- carry their tile high byte, $2xx = $06014000).  gUnk_08121D54 gives each
-- type its start, speed, OAM priority and frame ($80 | frame).
-- ---------------------------------------------------------------------------
FileSelect.SPRITE = 0x145

-- sub_0805070C: each file's name drawn with the cartridge font (charColor
-- 0, bgColor 5) into OBJ VRAM $06014000 + file * $200
function FileSelect:drawNames()
  local ffi = require("ffi")
  local p = self.ppu
  for i = 0, 2 do
    local buf = ffi.new("uint8_t[?]", 0x200)
    local f = self.files[i + 1]
    local name = f and tostring(f.name or "") or nil
    if self.state == "new" and i == self.row then name = self.pendingName or "" end
    if name then
      local chars = {}
      for k = 1, math.min(NAME_LEN, #name) do chars[#chars + 1] = { name:byte(k) } end
      p:drawGlyphs(buf, 0x200, chars, 0, 64, 5, 0, 0, true)
    end
    p:write(0x06014000 + i * 0x200, ffi.string(buf, 0x200))
  end
end

-- the plates' and buttons' targets (sub_0808EABC, gUnk_08121CD4)
-- fileScreenObjects.c tables (Layout.MENU_DATA fileObjTables)
local T_BUTTONS, T_BOB, T_NEWX, T_NEWF, T_INIT = 0x08121CD4, 0x08121D10, 0x08121D18, 0x08121D38, 0x08121D54
local BUTTON_ROW = { [0] = 0, [4] = 1, [5] = 2, [6] = 3, [7] = 4 }  -- FileScreenObjects_Type4's state switch
function FileSelect:ot()
  self.objTbl = self.objTbl or Ppu.table({ A = self.A }, "fileObjTables") or false
  return self.objTbl or nil
end
-- gUnk_08121CD4[row][k] = {column, x, y}
function FileSelect:button(st, k)
  local t = self:ot()
  if not t then return { 9, 0, 0xB0 } end
  local a = T_BUTTONS + ((BUTTON_ROW[st] or 0) * 4 + k) * 3
  return { t.u8(a), t.u8(a + 1), t.u8(a + 2) }
end
-- gUnk_08121D54[type]: {speed, x, y, prio:3 | sortPrio:3 | flipY:2, frame}
function FileSelect:initEntry(ty)
  local t = self:ot()
  if not t then return { speed = 0x400, x = 0, y = 0xB0 } end
  local a = T_INIT + 8 * ty
  return { speed = t.u16(a), x = t.s16(a + 2), y = t.u16(a + 4), frame = t.u8(a + 7) }
end

-- sub_0808EF6C: towards (tx, ty) at `speed` (1/256 px) a frame
local function slide(e)
  local dx, dy = e.tx - e.x, e.ty - e.y
  if math.abs(dx) < 2 then e.x, dx = e.tx, 0 end
  if math.abs(dy) < 2 then e.y, dy = e.ty, 0 end
  if dx == 0 and dy == 0 then return false end
  local d = math.sqrt(dx * dx + dy * dy)
  local v = math.min((e.speed or 0x400) / 256, d)
  e.x, e.y = e.x + dx / d * v, e.y + dy / d * v
  return true
end

function FileSelect:objects()
  self.objs = self.objs or {}
  local o, st = self.objs, STATE_NUM[self.state] or 0
  local moving = false
  -- types 0-2: the file plates
  for t = 0, 2 do
    local e = o[t]
    if not e then
      local d = self:initEntry(t)
      e = { x = d.x, y = d.y, speed = d.speed, frame = t }
      o[t] = e
    end
    local tx, ty = -72, t * 32 + 40
    local chosen = t == self.row
    if st == 0 then tx = 24
    elseif st == 4 or st == 6 or st == 7 then if chosen then tx, ty = 42, 56 end
    elseif st == 5 then
      local a = self.copyA and self.copyA[t]
      if a == 0 then tx, ty = 42, 40
      elseif a == 1 or a == 2 then tx, ty = 20, 144 - (self.copyN - a) * 32 end
    elseif st == 1 then if chosen then tx, ty = 8, 35 end end
    e.tx, e.ty = tx, ty
    moving = slide(e) or moving
    if chosen then e.pal, e.prio = 12, 1
    elseif st == 5 and t == self.target then e.pal, e.prio = 13, 2
    else e.pal, e.prio = 14, 2 end
  end
  -- types 4-7: Start / Copy / Erase / the copy and erase buttons
  local col = (st == 5) and self.target or (self.column or 0)
  for t = 4, 7 do
    local e = o[t]
    if not e then
      local d = self:initEntry(t)
      e = { x = d.x, y = d.y, speed = d.speed, frame = t }
      o[t] = e
    end
    local b = self:button(st, t - 4)
    e.tx, e.ty = b[2], b[3]
    e.pal, e.prio = (b[1] == col) and 13 or 14, 1
    moving = slide(e) or moving
  end
  -- name entry: the key cursor (type 8), the name cursor (9), the row-5
  -- buttons (10-14)
  if st == 1 and self.key then
    local k = self.key
    o.cursor = (k[1] ~= 5) and { x = k[0] * 16 + 28, y = k[1] * 16 + 58 } or nil
    o.caret = { x = math.min(k[3], 5) * 8 + 27, y = 24 }
    local ot = self:ot()
    for i = 1, 5 do
      o[9 + i] = { x = ot and ot.u16(T_NEWX + 16 + 2 * (i - 1)) or 0, y = 140,
                   frame = ot and ot.u8(T_NEWF + 8 + (i - 1)) or 0xFF,
                   pal = (k[1] == 5 and (i - 2) == k[2]) and 11 or 9, prio = 1 }
    end
  else
    o.cursor, o.caret = nil, nil
    for i = 10, 14 do o[i] = nil end
  end
  return moving
end

-- SetFileSelectState with the round-5 states
local baseSetState = FileSelect.setState
function FileSelect:setState(st)
  baseSetState(self, st)
  if st == "new" then self:enterNew() end
  self.namesDrawn = false
  self.heartsKey = nil
end


-- sub_08050AFC / sub_08050B3C: the chosen file's hearts into gBG1Buffer
-- at entry $14E -- $F24C, then full ($F251) / empty ($F24D) hearts, ten a
-- row, the partial heart $F24D + quarters
function FileSelect:hearts()
  local p = self.ppu
  local f = self.files[self.row + 1]
  local key = (self.state == "new") and "none" or tostring(f) .. (f and f.stats and (f.stats.health .. "/" .. f.stats.maxHealth) or "")
  if key == self.heartsKey then return end
  self.heartsKey = key
  local base = p.bg[1].buf
  if self.state ~= "new" then p:fill(base, 0x800, 0) end
  if f and self.state ~= "new" and f.stats then
    local cur = math.floor((f.stats.health or 0) / 2)
    if cur == 0 then cur = 1 end
    local max = math.floor((f.stats.maxHealth or 0) / 2)
    if max > 0 then
      cur = math.min(cur, max)
      local part, full = cur % 4, math.floor(cur / 4)
      local maxH = math.floor(max / 4)
      local t = base + 0x14E * 2
      for r = 0, 1 do
        local n = math.min(10, math.max(0, maxH - r * 10))
        if n > 0 then
          p:set16(t + r * 0x40, 0xF24C)
          local fullHere = math.min(10, math.max(0, full - r * 10))
          for k = 1, n do p:set16(t + r * 0x40 + 2 * k, k <= fullHere and 0xF251 or 0xF24D) end
        end
      end
      if part ~= 0 then
        local r = full >= 10 and 1 or 0
        p:set16(t + r * 0x40 + 2 * (full - r * 10 + 1), 0xF24D + part)
      end
    end
  end
  p.bg[1].updated = true
end

-- sub_08050A64: the four elements of a valid file
local ELEMENTS = { { 0x40, 0xA2, 0x36, 0x24 }, { 0x41, 0x96, 0x3D, 0x22 }, { 0x42, 0xAE, 0x3D, 0x23 }, { 0x43, 0xA2, 0x44, 0x21 } }
function FileSelect:elements()
  local f = self.files[self.row + 1]
  if not (f and f.items) then return end
  for _, e in ipairs(ELEMENTS) do
    if (f.items[e[1]] or 0) ~= 0 then
      self.ppu:drawDirect(FileSelect.SPRITE, e[4], { x = e[2], y = e[3], _4 = 0, _6 = 0, _8 = 0x400 })
    end
  end
end

function FileSelect:draw()
  local p = self.ppu
  p:flush()
  if not self.namesDrawn then self:drawNames(); self.namesDrawn = true end
  if not self.objs then self:objects() end
  local o = self.objs
  local function obj(frame, x, y, pal, prio)
    if frame == 0xFF then return end
    p:drawDirect(FileSelect.SPRITE, frame, { x = math.floor(x), y = math.floor(y), _4 = 0, _6 = 0,
      _8 = bor(lshift(pal, 12), lshift(prio, 10)) })
  end
  if self.state == "list" or self.state == "view" or self.state == "copy" or self.state == "erase" then
    self:hearts()
    self:elements()
  elseif self.state == "new" then
    self.heartsKey = nil
  end
  if o.cursor then obj(8, o.cursor.x, o.cursor.y, 0, 2) end
  if o.caret then
    local s = self.A:sprite(FileSelect.SPRITE)
    local keys = s and s.anims and s.anims[0]
    local f = keys and keys[1] and keys[1][1] or 9
    local ot = self:ot()
    local bob = ot and ot.s8(T_BOB + math.floor(self.counter / 4) % 8) or 0 -- gUnk_08121D10
    obj(f, o.caret.x, o.caret.y + bob, 0, 1)
  end
  for i = 10, 14 do local e = o[i] if e then obj(e.frame, e.x, e.y, e.pal, e.prio) end end
  for t = 0, 7 do
    local e = o[t]
    if e then obj(e.frame, e.x, e.y, e.pal, e.prio) end
  end
  local g = love.graphics
  g.setColor(1, 1, 1, 1)
  g.draw(p:render(), 0, 0)
  if self.fade then
    local lv = self.fade.level
    g.setColor(0, 0, 0, math.max(0, math.min(1, lv / 256)))
    g.rectangle("fill", 0, 0, 240, 160)
    g.setColor(1, 1, 1, 1)
  end
end

return FileSelect
