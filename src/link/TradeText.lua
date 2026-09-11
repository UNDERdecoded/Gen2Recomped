-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- WHAT A TRADE SAYS, in whichever cartridge's words the dataset is.
--
-- Reported from play: "ensure the trading menus and text are extracted and
-- presented properly".  Two things were wrong and they had the same cause --
-- the link screens were written against Gen 2's text keys and nothing else.
--
--   * On a GEN 3 dataset those keys do not exist, and the helper that looked
--     them up returned THE KEY ITSELF when it missed.  So an Emerald trade
--     did not fall back to English; it printed `_TradeForText` on the screen,
--     four times, in the middle of the animation.
--
--   * Emerald has every one of those lines written down in its own wording,
--     and extractTradeText now reads them.  There is no reason to say
--     "The trade was cancelled." at a player whose cartridge says "The trade
--     has been canceled."
--
-- HOW THE TWO VOCABULARIES LINE UP.  Gen 2 plays the trade out in six boxes
-- and Emerald in four, so the map below is not one-to-one: two of Gen 2's
-- keys have no Emerald beat at all and resolve to nothing, and a caller that
-- gets nothing shows no box rather than an empty one.  That is the whole of
-- the difference -- the beats that do line up carry the same names in the
-- same places.
--
-- The three placeholders are the cartridge's own: {VAR1} is the other
-- TRAINER, {VAR2} is the POKéMON leaving and {VAR3} is the one arriving.

local TradeText = {}

-- Gen 2's key -> the Emerald line that says the same thing, or false where
-- Emerald has no such beat.
local GEN3_ROLE = {
  _TradeWentToText = "sending",
  _TradeForText = "goodbye",
  _TradeSendsText = "arrived",
  _TradeWavesFarewellText = false,
  _TradeTransferredText = false,
  _TradeTakeCareText = "takeCare",
}

function TradeText.record(data)
  return data and data.constants and data.constants.gen3Trade or nil
end

-- One of the screen's own words, or nil when the dataset has none.  Callers
-- fall back to the engine's Strings() themselves, so a missing line is never
-- a blank box or a key on the screen.
function TradeText.line(data, role)
  local record = TradeText.record(data)
  local text = record and record[role]
  if type(text) == "string" and text ~= "" then return text end
  return nil
end

-- A line with the three names spliced in.  `subs` is keyed by role name --
-- trainer / sent / received -- rather than by the cartridge's placeholder
-- numbers, so a caller does not have to know which is which.
local PLACEHOLDER = { trainer = "{VAR1}", sent = "{VAR2}", received = "{VAR3}" }

function TradeText.filled(data, role, subs)
  local text = TradeText.line(data, role)
  if not text then return nil end
  for key, token in pairs(PLACEHOLDER) do
    local value = subs and subs[key]
    if value then
      text = text:gsub(token:gsub("[{}]", "%%%0"), tostring(value))
    end
  end
  return text
end

-- The Gen 3 line for one of Gen 2's trade keys, or nil -- which is both "this
-- dataset is not Gen 3" and "Emerald has no box here".
function TradeText.forKey(data, key, subs)
  if not TradeText.record(data) then return nil end
  local role = GEN3_ROLE[key]
  if not role then return nil end
  return TradeText.filled(data, role, subs)
end

-- Does this dataset carry the cartridge's trade vocabulary at all?
function TradeText.has(data)
  return TradeText.record(data) ~= nil
end

TradeText.GEN3_ROLE = GEN3_ROLE

return TradeText
