-- Who owns the bottom of the screen.
--
-- The text box and the YES/NO choice box both live in the bottom strip, and
-- so does anything a mod draws there instead of them -- STADIUM2's translucent
-- Stadium-style dialogue, a wide-battle layout, a cinematic that wants the
-- strip clear for a beat.  Without somewhere to ask, each of those either
-- draws over the others or hard-patches them out, and two mods doing that at
-- once produce a stack of boxes nobody asked for.
--
-- So: one question, asked by whoever is about to draw down there.
--
--     if not UIVisibility.bottomVisible(box, isTextBox) then return end
--
-- The default is YES.  Nothing is hidden until something claims the strip,
-- which keeps this invisible to the vanilla game: with no claims registered
-- every caller gets the answer it would have assumed anyway.
--
-- A claim is a named predicate rather than a boolean so the owner can decide
-- per frame ("hide the box only while my camera is diving") without having to
-- drive claim/release on exactly the right frames.  Predicates receive the
-- same (box, isTextBox) the asker passed, so one claim can hide the text box
-- and leave the choice box alone.
--
-- `box` is the TextBox / ChoiceBox instance about to draw and may be nil;
-- `isTextBox` is true for the text box and false for the choice box.  Both are
-- passed unchanged to every legacy claim. The public hook below uses
-- isTextBox to decide whether to query that individual state as well.
--
-- A predicate that throws is treated as "no opinion" and its claim is dropped,
-- because this is called from inside a draw and a broken claim must not be
-- able to take the frame down -- or to hide the dialogue for the rest of the
-- session, which would leave the game unplayable with no error on screen.

local Logger = require("src.core.Logger")
local Runtime = require("src.mods.Runtime")

local UIVisibility = {}

-- owner id -> predicate.  Insertion order does not matter: any single claim
-- answering "hide" hides, so this is an AND over "may I draw".
local bottomClaims = {}

-- Claim the bottom strip. `owner` is any stable key (a mod id); claiming
-- twice with the same owner replaces the predicate rather than stacking, so
-- an install that runs again after a reload cannot leak a claim.
function UIVisibility.claimBottom(owner, predicate)
  if owner == nil or type(predicate) ~= "function" then
    return false
  end
  bottomClaims[owner] = predicate
  return true
end

function UIVisibility.releaseBottom(owner)
  if owner == nil then
    return false
  end
  local had = bottomClaims[owner] ~= nil
  bottomClaims[owner] = nil
  return had
end

local function visibleByDefault()
  return true
end

local function enclosingBattle(state)
  local stack = state and state.game and state.game.stack
  local states = stack and stack.states
  if not states then
    return nil
  end
  local found = false
  for i = #states, 1, -1 do
    local candidate = states[i]
    if candidate == state then
      found = true
    end
    if found and candidate and (candidate.isBattle or candidate.isBattleState) then
      return candidate
    end
  end
end

-- TextBox is queried individually too. ChoiceBox only inherits an enclosing
-- battle, so a field YES/NO never becomes a battle-hook state.
local function hookBottomVisible(state, queryState)
  if not Runtime.wantsHook("battle.bottom_ui_visible") then
    return true
  end
  local battle = enclosingBattle(state)
  if
    battle
    and battle ~= state
    and Runtime.call("battle.bottom_ui_visible", visibleByDefault, battle) == false
  then
    return false
  end
  if queryState or battle == state then
    return Runtime.call("battle.bottom_ui_visible", visibleByDefault, state) ~= false
  end
  return true
end

-- Whoever is asking is allowed to draw the bottom box, unless a claim says no.
function UIVisibility.bottomVisible(box, isTextBox)
  for owner, predicate in pairs(bottomClaims) do
    local ok, visible = pcall(predicate, box, isTextBox)
    if not ok then
      bottomClaims[owner] = nil
      Logger.warn(
        "UIVisibility: bottom claim %s failed and was dropped: %s",
        tostring(owner),
        tostring(visible)
      )
    elseif visible == false then
      return false
    end
  end
  return hookBottomVisible(box, isTextBox)
end

-- Introspection for the mod manager / a diagnostic overlay: who is currently
-- holding the strip.  Returns a fresh array of owner ids.
function UIVisibility.bottomClaimants()
  local out = {}
  for owner in pairs(bottomClaims) do
    out[#out + 1] = owner
  end
  table.sort(out, function(a, b)
    return tostring(a) < tostring(b)
  end)
  return out
end

-- Test/reload hygiene: forget every claim.
function UIVisibility.reset()
  bottomClaims = {}
end

return UIVisibility
