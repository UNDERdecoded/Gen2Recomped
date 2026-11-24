-- Round 54: the Ezlo talk after the first Ocarina travel (src/object/bird.c
-- Bird_Type9, action 1 -> 2): when the bird lets Link go and global flag
-- WARP_1ST ($52) is clear, CreateObject(CUTSCENE_ORCHESTRATOR, 0, 0) runs
-- StartCutscene(script_EzloTalkOcarina) and the flag is set.
-- script_EzloTalkOcarina (data/scripts/lakeHylia/script_EzloTalkOcarina.inc)
-- is a cartridge script: EndBlock, SetPlayerIdle, WaitForPlayerNormalOrTalkEzlo,
-- DisablePauseMenuAndPutAwayItems, EzloMessage TEXT_EZLO $5F, ...; its USA
-- address is below (the script runs from the player's ROM).
local M = {}
M.WARP_1ST = 0x52
M.SCRIPT = 0x0800B0AC -- script_EzloTalkOcarina (USA)
M.CUTSCENE_ORCHESTRATOR = 0x69

function M.afterDrop(f)
  if f:flag("global", M.WARP_1ST) then return nil end
  local e = f:spawn({ kind = 6, collision = 0, pool = 0x4F, id = M.CUTSCENE_ORCHESTRATOR, paramA = 0, paramB = 0,
                      x = 0, y = 0, paramC = M.SCRIPT })
  f:setFlag("global", M.WARP_1ST, true)
  return e
end

return M
