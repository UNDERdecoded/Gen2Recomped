-- API-3 source text over the host's native string registry. Native API 1/2
-- keeps its keys and bytes; the VM continues reading its original table.
local Merge = require("src.mods.Merge")
local Text = {}
local previous = setmetatable({}, { __mode = "k" })
local BREAKS = { n = "\n", p = "\f", f = "\f", l = "\v" }
local function set(words)
  local out = {}
  for word in words:gmatch("%S+") do
    out[word] = true
  end
  return out
end
-- Public cartridge placeholder/symbol names, not cartridge prose. Validation
-- mirrors the source-language boundary, not the permissive native token bus.
local PH =
  set("UNKNOWN PLAYER STR_VAR_1 STR_VAR_2 STR_VAR_3 KUN RIVAL VERSION AQUA MAGMA ARCHIE MAXIE KYOGRE GROUDON")
local TAG = set([[
 A_BUTTON B_BUTTON DOWN_ARROW DPAD_ANY DPAD_DOWN DPAD_LEFT DPAD_LEFTRIGHT DPAD_RIGHT DPAD_UP DPAD_UPDOWN
 EMOJI_ACUTE EMOJI_ANGRY EMOJI_AT EMOJI_BALL EMOJI_BIGANGER EMOJI_BIGSMILE EMOJI_BIGWHEEL EMOJI_BOLT
 EMOJI_CIRCLE EMOJI_EQUALS EMOJI_EVIL EMOJI_FIRE EMOJI_GRAVE EMOJI_GREATER_THAN EMOJI_HAPPY EMOJI_HEART
 EMOJI_HIGHBAR EMOJI_IRRITATED EMOJI_LEAF EMOJI_LEFT_EYE EMOJI_LEFT_FIST EMOJI_LEFT_PAREN EMOJI_MINUS
 EMOJI_MISCHIEVOUS EMOJI_MOON EMOJI_NEUTRAL EMOJI_NOTE EMOJI_PIPE EMOJI_PLUS EMOJI_RIGHT_EYE
 EMOJI_RIGHT_FIST EMOJI_RIGHT_PAREN EMOJI_SEMICOLON EMOJI_SHOCKED EMOJI_SMALLWHEEL EMOJI_SPHERE
 EMOJI_SPIRAL EMOJI_SQUARE EMOJI_SURPRISED EMOJI_TILDE EMOJI_TIRED EMOJI_TONGUE EMOJI_TRIANGLE
 EMOJI_TRIANGLE_OUTLINE EMOJI_UNDERSCORE EMOJI_UNION EMOJI_WATER ID LEFT_ARROW LEFT_PAREN LV LV_2
 L_BUTTON MN PK PKMN PLUS POKEBLOCK PP RIGHT_ARROW RIGHT_PAREN R_BUTTON SELECT_BUTTON START_BUTTON
 UNK_SPACER UP_ARROW
]])
local BATTLE = set([[
 B_BUFF1 B_BUFF2 B_COPY_VAR_1 B_COPY_VAR_2 B_COPY_VAR_3 B_PLAYER_MON1_NAME
 B_OPPONENT_MON1_NAME B_PLAYER_MON2_NAME B_OPPONENT_MON2_NAME B_LINK_PLAYER_MON1_NAME
 B_LINK_OPPONENT_MON1_NAME B_LINK_PLAYER_MON2_NAME B_LINK_OPPONENT_MON2_NAME
 B_ATK_NAME_WITH_PREFIX_MON1 B_ATK_PARTNER_NAME B_ATK_NAME_WITH_PREFIX
 B_DEF_NAME_WITH_PREFIX B_EFF_NAME_WITH_PREFIX B_ACTIVE_NAME_WITH_PREFIX
 B_SCR_ACTIVE_NAME_WITH_PREFIX B_CURRENT_MOVE B_LAST_MOVE B_LAST_ITEM
 B_LAST_ABILITY B_ATK_ABILITY B_DEF_ABILITY B_SCR_ACTIVE_ABILITY B_EFF_ABILITY
 B_TRAINER1_CLASS B_TRAINER1_NAME B_LINK_PLAYER_NAME B_LINK_PARTNER_NAME
 B_LINK_OPPONENT1_NAME B_LINK_OPPONENT2_NAME B_LINK_SCR_TRAINER_NAME B_PLAYER_NAME
 B_TRAINER1_LOSE_TEXT B_TRAINER1_WIN_TEXT B_26 B_PC_CREATOR_NAME B_ATK_PREFIX1
 B_DEF_PREFIX1 B_ATK_PREFIX2 B_DEF_PREFIX2 B_ATK_PREFIX3 B_DEF_PREFIX3
 B_TRAINER2_LOSE_TEXT B_TRAINER2_WIN_TEXT B_BUFF3
]])
local EMERALD = set("B_TRAINER2_CLASS B_TRAINER2_NAME B_PARTNER_CLASS B_PARTNER_NAME")
local function refuse(reason)
  error("unsupported: " .. reason, 0)
end
local function identifier(id)
  assert(type(id) == "string" and id ~= "", "text: registry id is required")
end

local function convert(value, generation, version, native, writing)
  assert(type(value) == "string", "invalid unified content: text must be a source string")
  if value:find("[\r\252]") then
    refuse("unrepresentable text control")
  end
  if generation ~= 3 then
    return (value:gsub("\\([nplf])", BREAKS))
  end
  -- The host's imported FD 02..04 uses VARn. Authored unified text uses the
  -- reference's STR_VAR_n, while native overrides retain the old spelling.
  local out, i = {}, 1
  while i <= #value do
    local c = value:sub(i, i)
    if c == "\\" and i < #value then
      local nextChar = value:sub(i + 1, i + 1)
      out[#out + 1] = BREAKS[nextChar] or (c .. nextChar)
      i = i + 2
    elseif c == "{" and value:find("}", i, true) then
      local stop = value:find("}", i, true)
      local name = value:sub(i + 1, stop - 1)
      if native then
        name = name:gsub("^VAR([123])$", "STR_VAR_%1")
      end
      if not (PH[name] or TAG[name] or BATTLE[name] or version == "emerald" and EMERALD[name]) then
        refuse("unknown text placeholder or printer control: " .. name)
      end
      if writing then
        name = name:gsub("^STR_VAR_([123])$", "VAR%1")
      end
      out[#out + 1] = "{" .. name .. "}"
      i = stop + 1
    else
      out[#out + 1] = c
      i = i + 1
    end
  end
  return table.concat(out)
end

function Text.source(value, generation, version, native)
  return convert(value, generation, version, native, false)
end
function Text.write(value, generation, version)
  if value == Merge.DELETE then
    return value
  end
  return convert(value, generation, version, false, true)
end

local function addresses(id)
  local bank, addr = id:match("^(%x%x):(%x%x%x%x)$")
  if not bank then
    bank, addr = id:match("^TEXT_S(%x%x)_(%x%x%x%x)$")
  end
  if not bank then
    return id, id
  end
  bank, addr = tonumber(bank, 16), tonumber(addr, 16)
  local canonical, physical = ("%02x:%04x"):format(bank, addr), ("TEXT_S%02X_%04X"):format(bank, addr)
  -- Only these two exact spellings are the imported/native address pair.
  -- A differently-cased authored label is a distinct ID in the reference.
  if id ~= canonical and id ~= physical then
    return id, id
  end
  return canonical, physical
end
function Text.api(loader, mod, native, generation)
  local registry = loader.content.text
  local version = require("src.core.GameVersion").get()
  local function keys(id)
    identifier(id)
    if generation ~= 2 then
      return id, id
    end
    local canonical, physical = addresses(id)
    if
      canonical == physical
      and loader._romTextLabels
      and (
        loader._romTextLabels[id]
        or id:sub(1, #loader._privateScriptTextPrefix) == loader._privateScriptTextPrefix
      )
    then
      local physical = loader._privateScriptTextPrefix .. id
      loader._privateScriptTextIds = loader._privateScriptTextIds or {}
      loader._privateScriptTextIds[physical] = id
      return id, physical
    end
    if canonical ~= physical and registry:get(canonical) ~= nil then
      if registry:get(physical) ~= nil then
        refuse("ambiguous script text ID: " .. canonical)
      end
      physical = canonical
    end
    return canonical, physical
  end
  local function get(id)
    local _, physical = keys(id)
    local value = native:get(physical)
    if value == nil then
      return nil
    end
    return Text.source(value, generation, version, true)
  end
  local api = {
    available = true,
    supports = function()
      return true
    end,
  }
  function api:get(id)
    return get(id)
  end
  function api:has(id)
    return get(id) ~= nil
  end
  function api:each()
    local ids, seen = {}, {}
    for physical in native:each() do
      local private = loader._privateScriptTextIds and loader._privateScriptTextIds[physical]
      local canonical = private or (generation == 2 and addresses(physical) or physical)
      if generation == 2 and loader._romTextLabels[physical] and not private then
        canonical = nil
      end
      if canonical and not seen[canonical] then
        seen[canonical] = true
        ids[#ids + 1] = canonical
      end
    end
    table.sort(ids)
    local i = 0
    return function()
      while i < #ids do
        i = i + 1
        local value = get(ids[i])
        if value ~= nil then
          return ids[i], value
        end
      end
    end
  end
  for _, verb in ipairs({ "register", "override", "patch", "remove" }) do
    api[verb] = function(_, id, value)
      local ok, result = pcall(function()
        -- Frozen writes fail before conversion, as in the reference SDK.
        assert(not registry.frozen, "text: content is frozen after load")
        local _, physical = keys(id)
        local payload = verb ~= "remove" and Text.write(value, generation, version) or nil
        native[verb](native, physical, payload)
        loader._unifiedTextKeys = loader._unifiedTextKeys or {}
        loader._unifiedTextKeys[physical] = loader._unifiedTextKeys[physical] or {}
        loader._unifiedTextKeys[physical][mod.manifest.id] = true
        return get(id)
      end)
      if ok then
        return result
      end
      if type(result) == "string" and result:sub(1, 13) == "unsupported: " then
        return nil, result
      end
      error(result, 0)
    end
  end
  return api
end
-- Retire only this adapter's successful writes when the same mounted dataset
-- is loaded again. An intervening external edit or replacement table wins.
function Text.prepare(loader, data)
  local undo = data and previous[data]
  for _, row in ipairs(undo or {}) do
    if
      data[row.namespace or "text"] == row.target
      and row.target[row.key] == row.after
      and (not row.private or row.after.value == row.snapshot)
    then
      row.target[row.key] = row.before
    end
  end
  if data then
    previous[data] = nil
  end
  loader._unifiedTextKeys = nil
  loader._privateScriptTextIds, loader._privateScriptTextRows = nil, nil
end
function Text.capture(loader, data)
  if not data or not loader._unifiedTextKeys then
    return
  end
  local registry, undo = loader.content.text, {}
  for key, owners in pairs(loader._unifiedTextKeys) do
    local active = false
    for _, op in ipairs(registry.ops[key] or {}) do
      if owners[op.owner] then
        active = true
        break
      end
    end
    if active then
      local logical = loader._privateScriptTextIds and loader._privateScriptTextIds[key]
      if logical then
        data._portableScriptText = data._portableScriptText or {}
        loader._privateScriptTextRows = loader._privateScriptTextRows or {}
        local row = { value = registry:get(key) }
        loader._privateScriptTextRows[key] = row
        undo[#undo + 1] = {
          target = data._portableScriptText,
          key = logical,
          before = data._portableScriptText[logical],
          after = row,
          private = true,
          namespace = "_portableScriptText",
          snapshot = row.value,
        }
      else
        data.text = data.text or {}
        undo[#undo + 1] =
          { target = data.text, key = key, before = data.text[key], after = registry:get(key) }
      end
    end
  end
  previous[data] = undo
end
return Text
