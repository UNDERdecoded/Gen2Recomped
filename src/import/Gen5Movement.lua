-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- BLACK AND WHITE'S MOVEMENT ACTIONS, read off the cartridge's own table.
--
-- `applymovement` (0x64) lists are Gen 4's `{ u16 action, u16 count }` ending
-- at 0xFE (Gen5ScriptLink), and they had been played through Platinum's
-- action table. The first 0x4C actions agree with it, the rest do not.
--
-- THE TABLE: overlay 21 (field, loaded at 0x02187F00) holds an array of
-- pointers at 0x021D5F58, one per action, each to a list of thumb functions
-- ending at 0x02197F5D (the common "done"). The first function is the
-- action's init; what it hands to the shared helpers says what it does
-- (Black USA; White's overlay has the same shape):
--
--   0x00-0x03  0x2197F6C(dir)                     face
--   0x04-0x17  0x2197FC0(dir, speed, frames, anim) walk one cell: 32 / 16 /
--              8 / 4 / 2 frames (speed x frames = 16 px)
--   0x18-0x2B  0x2198318(dir, frames, ...)        walk on the spot: 32 / 16
--              / 8 / 4 / 2 frames
--   0x2C-0x3B  0x219852C(dir, speed, frames, ...) jumps: on the spot in 16
--              and 8 frames, one cell in 8, two cells in 16
--   0x3C-0x42  0x2198960(frames)                  wait 1 2 4 8 15 16 32
--   0x45-0x4A  object flags 4 / 8 / 0x10, set and cleared: hide, show, lock
--              the facing, unlock it, pause and resume the animation
--   0x4B 0x67 0x99 / 0x9F / 0xA0 / 0xA1  0x2198B4C(kind) the emote, kind
--              0 / 1 / 2 / 3 -- "!", "?", the note, "..." (Gen5FieldEffects'
--              sisen_ef members 50..53, in that order)
--   0x4C-0x63 0xA3-0xAA  0x2198C08(dir, frames, anim) walk one cell on a
--              per-frame speed table: 6 frames (0x21D4A68), 3 (0x21D4A44),
--              7 (0x21D4A80), 12 (0x21D4A9C); 0x54-0x5B and 0x9B-0x9E are
--              0x2197FC0 again (1, 4 and 16 frames)
--   0x5C-0x5F 0x75-0x78  jumps sideways: one cell in 16 frames, three in 12;
--              three cells in 24
--   0x64 0xB5-0xBB  play the character's own model animation 0xA / 0xB /
--              0xC to its end (0xB8 / 0xB9 with sound 0x7B7 first)
--   0x66 0x68 0xA2  animation 1 / 2 / 0 held for 40 / 40 / 12 frames
--
-- FRAMES ARE FIELD FRAMES; the field runs at 30 a second (Gen4Emotes.ticksFor)
-- so each is two engine ticks. `frames` below is per cell for a walk or jump,
-- per repetition for everything else.
--
-- NOT PLAYED: 0x43 / 0x44 (warp up / down; no script in Black uses them),
-- 0x69-0x74 0x79-0x98 (walks with a second direction; none used), 0x65
-- (one use, the trainer-eye script M0863 S0CBC; the approach itself is
-- Gen4Commands' g4_start_approach) and 0xAB-0xB4 0xBC (one-off animations,
-- one or two uses each) -- `action` answers nil for them and the executor
-- skips the step, as it does on Platinum.

local M = {}

M.TICKS_PER_FRAME = 2
-- the engine's ordinary NPC step, a normal walk (8 field frames)
M.NORMAL_TICKS = 16

local DIR = { [0] = "up", [1] = "down", [2] = "left", [3] = "right" }
M.DIR = DIR

local A = {}

local function four(first, row)
  for i = 0, 3 do
    local r = {}
    for k, v in pairs(row) do r[k] = v end
    r.dir = DIR[i]
    A[first + i] = r
  end
end

four(0x00, { kind = "face" })
-- walks
four(0x04, { kind = "walk", tiles = 1, frames = 32 })
four(0x08, { kind = "walk", tiles = 1, frames = 16 })
four(0x0C, { kind = "walk", tiles = 1, frames = 8 })
four(0x10, { kind = "walk", tiles = 1, frames = 4 })
four(0x14, { kind = "walk", tiles = 1, frames = 2 })
-- on the spot
four(0x18, { kind = "spot", frames = 32 })
four(0x1C, { kind = "spot", frames = 16 })
four(0x20, { kind = "spot", frames = 8 })
four(0x24, { kind = "spot", frames = 4 })
four(0x28, { kind = "spot", frames = 2 })
-- jumps
four(0x2C, { kind = "hop", frames = 16 })
four(0x30, { kind = "hop", frames = 8 })
four(0x34, { kind = "jump", tiles = 1, frames = 8 })
four(0x38, { kind = "jump", tiles = 2, frames = 8 })
-- waits
local WAITS = { 1, 2, 4, 8, 15, 16, 32 }
for i, f in ipairs(WAITS) do A[0x3B + i] = { kind = "wait", frames = f } end
A[0x45] = { kind = "hide" }
A[0x46] = { kind = "show" }
A[0x47] = { kind = "lock" }
A[0x48] = { kind = "unlock" }
-- 0x49 / 0x4A set / clear object flag 0x10 (READ FROM CODE: 0x216D548 /
-- 0x216D550 with r1 = 0x10, as 0x45-0x48 do 4 and 8): the character's
-- animation held, so a walk after it glides on the standing frame (N's
-- Castle, M0556 S1211: `3F 49 0D*10`). That 0x10 is the animation pause is
-- the earlier reading of the field's flag word, not a decompiled name
A[0x49] = { kind = "animpause" }
A[0x4A] = { kind = "animresume" }
-- emotes
local EMOTES = { [0x4B] = "exclamation", [0x67] = "exclamation", [0x99] = "exclamation",
                 [0x9F] = "question", [0xA0] = "note", [0xA1] = "ellipsis" }
for id, kind in pairs(EMOTES) do A[id] = { kind = "emote", emote = kind } end
-- walks on a speed table, and the other speeds
four(0x4C, { kind = "walk", tiles = 1, frames = 6 })
four(0x50, { kind = "walk", tiles = 1, frames = 3 })
four(0x54, { kind = "walk", tiles = 1, frames = 1 })
four(0x58, { kind = "walk", tiles = 1, frames = 4 })   -- run
four(0x60, { kind = "walk", tiles = 1, frames = 7 })
four(0x9B, { kind = "walk", tiles = 1, frames = 16 })
four(0xA3, { kind = "walk", tiles = 1, frames = 6 })
four(0xA7, { kind = "walk", tiles = 1, frames = 12 })
-- sideways jumps: 0x5C / 0x5D one cell left / right (0x1000 x 16 frames),
-- 0x5E / 0x5F three (0x4000 x 12); 0x75-0x78 three cells in 24 (0x2000 x 24)
A[0x5C] = { kind = "jump", dir = "left", tiles = 1, frames = 16 }
A[0x5D] = { kind = "jump", dir = "right", tiles = 1, frames = 16 }
A[0x5E] = { kind = "jump", dir = "left", tiles = 3, frames = 4 }
A[0x5F] = { kind = "jump", dir = "right", tiles = 3, frames = 4 }
four(0x75, { kind = "jump", tiles = 3, frames = 8 })
-- the character's own animations: held for their length. The model
-- animations' lengths live in each character's own data, which the 2D sheets
-- here do not carry, so a 16-frame beat stands in (said, not measured)
for _, id in ipairs({ 0x64, 0xB5, 0xB6, 0xB7, 0xB8, 0xB9, 0xBA, 0xBB }) do
  A[id] = { kind = "anim", frames = 16, approximate = true }
end
-- 0xB8 / 0xB9 play sound 0x7B7 as they start (READ FROM CODE: ov21
-- 0x02198E98 / 0x02198EB0 call 0x020061E4(0x7B7) before 0x64's / 0xB6's
-- init) -- 43 steps in Black (M0508, Z254)
A[0xB8].se, A[0xB9].se = 0x7B7, 0x7B7
-- 0x9A: animation 1 for 20 frames (READ FROM CODE: init 0x021990B8 sets
-- animation 1, update 0x021990D4 counts to 0x14), lifting the character by
-- a 10-entry table (0x021D4C1C: 0 0 0 0 0 4 4 3 1 0 units) -- the hop the
-- player gives on the item-gift scripts (M0862 S0592, M0864 S23E3). The
-- 20 frames are played; the 4-unit lift is not drawn
A[0x9A] = { kind = "anim", frames = 20 }
A[0x66] = { kind = "anim", frames = 40 }
A[0x68] = { kind = "anim", frames = 40 }
A[0xA2] = { kind = "anim", frames = 12 }

M.ACTIONS = A

function M.action(id)
  return A[tonumber(id) or -1]
end

-- Engine ticks one repetition of `a` takes (per cell for a walk / jump).
function M.ticks(a)
  return math.max(1, (a and a.frames or 8) * M.TICKS_PER_FRAME)
end

return M
