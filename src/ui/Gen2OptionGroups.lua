-- Gen1Recomp's Gen2 option-page vocabulary, backed by native row handlers.
-- Group ids/order follow reference 535a5ec0 src/ui/gen2/OptionsMenu.lua.
-- Original reference rights and the existing project licenses remain applicable.
local Strings = require("src.core.Strings")
local M = {}
M.groups = {
  {id="group.speed", label=Strings.source("SPEED"), members={"textSpeed","speed"}},
  {id="group.video", label=Strings.source("VIDEO"), members={"videoMode","orientation","faithfulRes","screenPos","fpsCap","vsync","logicClock"}},
  {id="group.graphics", label=Strings.source("GRAPHICS"), members={"color","colors","gbcColorCorrection","gbcfx","shaderPreset","uiLetterbox","shaderfx","shaderfx2","frame"}},
  {id="group.audio", label=Strings.source("AUDIO"), members={"sound","stereo","musicVol","sfxVol","musicFilter","audioMode"}},
  {id="group.battle", label=Strings.source("BATTLE OPTIONS"), members={"battleScene","battleAnim","animations","battleStyle","battleLayout","battleHud","battleFit","battleBg"}},
  {id="group.extras", label=Strings.source("EXTRAS"), members={"zoom","voidFill","tilt"}},
}
function M.build(rows, open)
  local owners, picked, made, byId = {}, {}, {}, {}
  for _, group in ipairs(M.groups) do
    picked[group.id] = {}
    for _, id in ipairs(group.members) do owners[id] = group.id end
  end
  for _, row in ipairs(rows) do
    local owner = owners[row.id]
    if owner then picked[owner][#picked[owner]+1] = row
    elseif row.id then byId[row.id] = row end
  end
  for _, group in ipairs(M.groups) do
    local members = picked[group.id]
    if #members > 0 then
      made[group.id] = {id=group.id, label=group.label, group=true,
        activate=function() return open(members) end}
    end
  end
  local view, taken = {}, {}
  for _, id in ipairs({"group.speed","group.video","group.graphics","group.audio",
                       "performance","group.battle","group.extras"}) do
    local row = made[id] or byId[id]
    if row then view[#view+1] = row; taken[id] = true end
  end
  for _, row in ipairs(rows) do
    if not row.cancel and not owners[row.id] and not taken[row.id] then view[#view+1] = row end
  end
  view[#view+1] = {id="cancel", label=Strings("BACK"), cancel=true}
  return view
end
return M
