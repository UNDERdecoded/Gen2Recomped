-- Round 14: pots and the Gust Jar (src/object/pot.c Pot_Action1 case $13,
-- Pot_Action3).
--
-- CARTRIDGE BEHAVIOUR:
--   * A gust touching a resting pot (contactFlags $13) puts it in Action3:
--     subAction 0 sets gustJarTolerance 48; 1 wiggles (sub_0806F4E8) while
--     the jar keeps touching it -- the grab handler takes the charge off
--     the tolerance each contact frame -- and goes back to rest if the
--     contact stops; 2 (tolerance 0): the pot's own tile is put back
--     (SetTile(unk_70)), it flies at the mouth (sub_0806F3E4: speed + 64 x
--     the charge a frame, max $500) and BREAKS if the contact stops on the
--     way; within 4x4 of the mouth its gustJarFlags ($12: bit 2, catchable)
--     attach it to the jar (SFX_ED); 3: held -- it breaks when the jar is
--     put away (gustJarState 0); fired with the jar's blow it flies with
--     PLAYER_ITEM_GUST_BIG and breaks where that shot ends (subAction 5).
--   * BreakPot: FX_POT_SHATTER and the pot's drop (Objects:shatter).
local PG = {}

local OBJ_POT = 0x05
local TOL = 48
local SFX_ED = 0xED

local function isPot(e)
  return e.kind == 6 and e.id == OBJ_POT and (e.liftable or e.potGust) and not e.deleted and not e.thrown
end

local function breakPot(f, e)
  e.deleted = true
  e.jarSub = nil
  f:objects():shatter(e, e.form or 0, e.potParam)
end
PG.breakPot = breakPot

-- GJ.frame (the jar sucking): contact with the gust boxes
function PG.contact(f, p, j)
  local GJ = require("src.zelda.tmc.GustJar")
  for _, e in ipairs(f.entities) do
    if isPot(e) and (e.jarSub or 0) < 3 and GJ.touching(f, e.x, e.y - 3, 6, 6) then
      if not e.jarSub then
        e.jarSub, e.jarTol, e.jarKb = 1, TOL, 0
      elseif e.jarSub == 1 then
        e.jarTol = e.jarTol - j.charge
        if e.jarTol <= 0 then
          e.jarSub, e.jarKb = 2, 0
          e.solid = false -- SetTile(unk_70): its tile is a floor again
          e.liftable = false
          e.potGust = true
        end
      end
      e.jarSeen = f.frame
    end
  end
end

-- every frame (GustJar.tick)
function PG.tick(f)
  local p = f.player
  local j = p and p.jar
  for i = #f.entities, 1, -1 do
    local e = f.entities[i]
    if e.kind == 6 and e.id == OBJ_POT and e.jarSub and not e.deleted then
      local seen = j and j.state == "suck" and (e.jarSeen or 0) >= f.frame - 1
      if e.jarSub == 1 then
        if not seen then e.jarSub, e.spriteOX = nil, nil
        else e.spriteOX = ({ [0] = 1, 0, -1, 0 })[e.jarTol % 4] end
      elseif e.jarSub == 2 then
        e.spriteOX = nil
        if not seen then breakPot(f, e)
        else
          local GJ = require("src.zelda.tmc.GustJar")
          e.jarKb = math.min(0x500, e.jarKb + 64 * j.charge)
          local mx, my = GJ.mouth(p)
          local dx, dy = mx - e.x, my - e.y
          local d = math.sqrt(dx * dx + dy * dy)
          local sp = e.jarKb / 256
          if d <= sp then e.x, e.y = mx, my else e.x, e.y = e.x + dx / d * sp, e.y + dy / d * sp end
          if math.abs(e.x - mx) < 4 and math.abs(e.y - my) < 4 then
            e.jarSub, e.hidden = 3, true
            j.held, j.state = e, "attached"
            f:sound(SFX_ED)
          end
        end
      elseif e.jarSub == 3 then
        if not j or j.held ~= e then
          -- sub_080827F8: the jar is put away (or the pot left it): it breaks
          if not (e.inShot) then breakPot(f, e) end
        else
          local GJ = require("src.zelda.tmc.GustJar")
          e.x, e.y = GJ.mouth(p)
        end
      end
    end
  end
end

return PG
