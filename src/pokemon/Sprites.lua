-- Runtime Pokémon art resolution.  Content registries freeze after load,
-- so a mod that lets the player pick an alternate skin mid-session cannot
-- patch pokemon.spriteFront / icons.bySpecies.  These helpers are the
-- sanctioned seam: every battle pic and party icon load goes through
-- pokemon.sprite / pokemon.icon, which stay live for the whole process.
--
-- playerPath is the same seam for the player's own trainer art, whose
-- vanilla paths are data (field.playerPics) rather than a species record.

local Runtime = require("src.mods.Runtime")
local FieldDefaults = require("src.world.FieldDefaults")

local Sprites = {}

local function samePath(path) return path end

-- (dv & 6) >> 1 -- the middle two bits GetUnownLetter (20:$5749) keeps
local function mid2(dv) return math.floor((dv or 0) / 2) % 4 end

-- GetUnownLetter packs the middle two bits of the atk/def/spd/spc DVs into
-- one byte and divides by 10, giving letter 1..26.  A species record only
-- carries `forms` when the ROM has per-form pics (UNOWN).
function Sprites.formIndex(def, mon)
  local forms = def and def.forms
  if not (forms and mon) then return nil end
  local dvs = mon.dvs
  if type(dvs) ~= "table" then return nil end
  local packed = mid2(dvs.attack) * 64 + mid2(dvs.defense) * 16
    + mid2(dvs.speed) * 4 + mid2(dvs.special)
  local index = math.floor(packed / 10) + 1
  if not forms[index] then return nil end
  return index
end

-- Resolve a battle / menu front or back pic path for `species`.
-- side: "front" | "back"
-- opts.mon: the live mon when available (per-instance skins)
-- opts.kind: "battle" | "summary" | "dex" | "evolution" | "hof" | "trade"
--            | "title" | "oak" | "credits" | "overworld" (informational
--            for wrappers)
-- Returns path, trueColor.
function Sprites.path(data, species, side, opts)
  opts = opts or {}
  local def = data and data.pokemon and data.pokemon[species]
  if not def then return nil, false end
  local path = side == "back" and def.spriteBack or def.spriteFront
  local formIndex = Sprites.formIndex(def, opts.mon)
  if formIndex then
    local form = def.forms[formIndex]
    path = (side == "back" and form.spriteBack or form.spriteFront) or path
  end
  local ctx = {
    species = species,
    side = side == "back" and "back" or "front",
    kind = opts.kind or "battle",
    mon = opts.mon,
    form = formIndex,
    trueColor = def.trueColor and true or false,
    data = data,
  }
  if path and Runtime.wantsHook("pokemon.sprite") then
    local hooked = Runtime.call("pokemon.sprite", samePath, path, ctx)
    if type(hooked) == "string" and hooked ~= "" then path = hooked end
  end
  return path, ctx.trueColor and true or false
end

-- Resolve the player's own trainer pic path.
-- side: "back" (the battle intro pic) | "front" (intro / card / Hall of Fame)
-- opts.kind: "battle" | "intro" | "trainer_card" | "hof"
-- opts.demo: the catch tutorial, where the old man fights in the player's
--            place and stands in for the back pic
-- opts.oakDemo: the Yellow variant of that demo (BATTLE_TYPE_PIKACHU), where
--            PROF.OAK fights in the player's place behind his own back pic
-- opts.battle: the live battle, for kind == "battle"
-- Returns path, trueColor.
function Sprites.playerPath(data, side, opts)
  opts = opts or {}
  side = side == "back" and "back" or "front"
  -- one key per pic, so a conversion can replace the back and inherit the
  -- rest; fieldValue folds data.field over FieldDefaults per key.  The two
  -- demo keys mirror LoadPlayerBackPic's wBattleType branch (#557).
  local key = side == "front" and "front"
              or (opts.oakDemo and "oakBack")
              or (opts.demo and "demoBack" or "back")
  local path = FieldDefaults.fieldValue(data, "playerPics", key)
  -- ProfOakPicBack is a Yellow-only rip, so a cache imported before it
  -- existed has no file there; fall back to the old man rather than hand a
  -- missing path to getImage (#557)
  if key == "oakBack" and path
     and not require("src.render.Assets").exists(path) then
    path = FieldDefaults.fieldValue(data, "playerPics", "demoBack")
  end
  local ctx = {
    side = side,
    kind = opts.kind or "battle",
    demo = opts.demo and true or false,
    oakDemo = opts.oakDemo and true or false,
    battle = opts.battle,
    trueColor = false,
    data = data,
  }
  if path and Runtime.wantsHook("player.sprite") then
    local hooked = Runtime.call("player.sprite", samePath, path, ctx)
    if type(hooked) == "string" and hooked ~= "" then path = hooked end
  end
  return path, ctx.trueColor and true or false
end

-- Resolve a party-menu icon image path for `mon`.
-- vanillaPath is the path PartyMenu already picked from icons.bySpecies /
-- def.icon / icons.byDex; the hook may replace it.
-- Returns path (possibly nil).
function Sprites.iconPath(data, mon, vanillaPath, opts)
  opts = opts or {}
  if not vanillaPath and not Runtime.wantsHook("pokemon.icon") then
    return vanillaPath
  end
  local species = mon and mon.species
  local ctx = {
    species = species,
    mon = mon,
    name = opts.name,
    data = data,
    kind = "icon",
  }
  if not Runtime.wantsHook("pokemon.icon") then return vanillaPath end
  local hooked = Runtime.call("pokemon.icon", samePath, vanillaPath, ctx)
  if type(hooked) == "string" and hooked ~= "" then return hooked end
  if hooked == nil or hooked == false then return nil end
  return vanillaPath
end

return Sprites
