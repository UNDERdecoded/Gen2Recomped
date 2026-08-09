-- Cerulean City flavor dialogue (pokered/scripts/CeruleanCity.asm)
--
-- Both NPCs use text_asm with an hRandomAdd roll to pick one of several
-- flavor lines (no flags, no branching outcome) -- ported as a weighted
-- math.random pick each time the NPC is talked to.
--
-- Yellow renames Slowbro -> Electrode in the text labels (see
-- tools/yellow_symbol_aliases.py); look up both so Red/Blue and Yellow
-- share this script.

local M = {}

local function push(game, ow, npc, done, text)
  local TextBox = require("src.render.TextBox")
  npc:facePlayer(ow.player)
  game.stack:push(TextBox.new(game, text, done))
end

-- CeruleanCitySlowbroText / CeruleanCityElectrodeText
-- cp 180 -> 76/256 chance of 1st; cp 120 -> 60/256 chance of 2nd;
-- cp 60 -> 60/256 chance of 3rd; else 60/256 chance of 4th.
local function talkMon(game, ow, npc, done)
  local t = game.data.text
  local roll = math.random(0, 255)
  local text
  if roll >= 180 then
    text = t._CeruleanCitySlowbroTookASnoozeText
        or t._CeruleanCityElectrodeTookASnoozeText
  elseif roll >= 120 then
    text = t._CeruleanCitySlowbroIsLoafingAroundText
        or t._CeruleanCityElectrodeIsLoafingAroundText
  elseif roll >= 60 then
    text = t._CeruleanCitySlowbroTurnedAwayText
        or t._CeruleanCityElectrodeTurnedAwayText
  else
    text = t._CeruleanCitySlowbroIgnoredOrdersText
        or t._CeruleanCityElectrodeIgnoredOrdersText
  end
  push(game, ow, npc, done, text)
end

M.CERULEAN_CITY = {
  talk = {
    -- CeruleanCityCooltrainerF1Text (scripts/CeruleanCity.asm:362-393)
    -- cp 180 -> 76/256 chance of 1st; cp 100 -> 80/256 chance of 2nd;
    -- else 100/256 chance of 3rd.
    TEXT_CERULEANCITY_COOLTRAINER_F1 = function(game, ow, npc, done)
      local t = game.data.text
      local roll = math.random(0, 255)
      local text
      if roll >= 180 then
        text = t._CeruleanCityCooltrainerF1SlowbroUseSonicboomText
            or t._CeruleanCityCooltrainerF1ElectrodeUseSonicboomText
      elseif roll >= 100 then
        text = t._CeruleanCityCooltrainerF1SlowbroPunchText
            or t._CeruleanCityCooltrainerF1ElectrodePunchText
      else
        text = t._CeruleanCityCooltrainerF1SlowbroWithdrawText
            or t._CeruleanCityCooltrainerF1ElectrodeWithdrawText
      end
      push(game, ow, npc, done, text)
    end,

    TEXT_CERULEANCITY_SLOWBRO = talkMon,
    -- Yellow map object uses TEXT_CERULEANCITY_ELECTRODE
    TEXT_CERULEANCITY_ELECTRODE = talkMon,
  },
}

return M
