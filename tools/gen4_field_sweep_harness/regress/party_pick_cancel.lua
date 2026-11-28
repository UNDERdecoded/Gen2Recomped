-- Backing out of a "pick a Pokemon" screen a script opened must end the script.
--
-- Platinum's move tutors, NPC traders and the daycare ask for a party member
-- through g4_open_party_for_trade; B on the picker closed the screen and left
-- the script parked on its yield, with the field locked behind a fade. Found by
-- tools/gen4_field_sweep (seven tutor / trade maps; the engine's own watchdog
-- logged "parked for 360 frames ... g4_select_tutor_mon").
--
-- Run: python tools/gen4_field_sweep.py --install <cache> --regress

local S = _G.__sweep
local OW, Game = S.OW, S.Game
local failed = false
local function check(cond, what)
  if not cond then failed = true; print("REGRESS_FAIL party_pick_cancel: " .. what) end
end

S.enterMap("C01R0205", 4, 6, "down")
S.run(90)
S.settle(300)

-- talk to the tutor (the one object on the map whose script asks for a Pokemon)
local asked = false
for _, npc in ipairs(OW.npcs or {}) do
  if npc.def and not npc.hidden and not asked then
    local cells = S.standCells(OW.map, npc.cellX, npc.cellY, npc)
    if #cells > 0 then
      S.placePlayer(cells[1][1], cells[1][2], cells[1][3])
      S.run(3)
      S.press("a")
      -- A through the text until the party picker is up (or the script ends)
      for i = 1, 1500 do
        S.run(1)
        if i % 6 == 0 then S.press("a") end
        local t = S.top()
        if t and t.screenId == "Gen4PartyMenu" or (t and t.pickOnly) then asked = true break end
        if S.idle() then break end
      end
      if asked then
        -- B on the picker...
        for _ = 1, 12 do S.press("b"); S.run(8); if S.top() == OW then break end end
        -- ...and the script must run to its end on its own, with A only to
        -- read the lines that follow
        local ended = false
        local failsBefore = S.fails()
        for i = 1, 300 do
          S.run(1)
          if i % 7 == 0 then S.press("a") end
          if S.idle() then ended = true break end
        end
        -- (inside 300 frames: the engine's own watchdog puts a parked script
        -- down after 720, which would hide the bug)
        check(ended, "the script ends after B on the party picker (stack: " .. tostring(S.describeTop()) .. ")")
        check(S.fails() == failsBefore, "no parked-script warning")
      else
        -- this NPC's script never asked; try the next one from a fresh map
        S.enterMap("C01R0205", 4, 6, "down"); S.run(90); S.settle(300)
      end
    end
  end
end
check(asked, "some object on C01R0205 opens the party picker")

print(failed and "REGRESS_FAIL party_pick_cancel" or "REGRESS_OK party_pick_cancel")
