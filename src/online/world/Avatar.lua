-- THE PLAYER'S ONLINE LOOK: which overworld sheet other players see, and in
-- what colour.  Chosen on src/ui/online/AvatarScreen.lua (WORLDS -> MY LOOK,
-- ONLINE settings -> MY LOOK, and OPTIONS -> MY LOOK offline), kept in
-- save.options.looks[<game>] (one look offline and online; see `slot`), sent in
-- presence as `look.av` (worlds: w_hello / w_look; link rooms: lr_pos).
--
-- THE ART IS NEVER OURS.  Every choice is a sheet out of the running game's
-- own imported cache (`data.sprites`, `data.field.playerForms`); the tint is
-- baked at runtime from that same image.  Nothing here names a file.
--
-- WIRE (inside `look`, so the old fields keep working):
--   av = { v = 1,                 this table's version
--          g = "platinum",        the game the sheet key belongs to
--          s = "SPRITE_G4_090",   the sheet key in that game
--          r = "boy"|"girl"|"npc",  protagonist form, or another trainer
--          t = { h = 0..359, k = 0..100, m = "tint"|"shift" } }  colour
-- Old builds run WorldProtocol.cleanLook, which copies walk/bike/surf/gender
-- only, so `av` simply never reaches them (and an old host drops it in
-- transit: everyone then sees that player's own default sheet, as before).
-- A peer with no `av` is drawn exactly as before this file existed.
--
-- CROSS-GAME.  Sheet keys are per cartridge -- SPRITE_G3_000 is Brendan in
-- Emerald and Red in FireRed -- so a key is only trusted when `g` matches
-- the viewer's game.  Otherwise the viewer's own protagonist of the same
-- gender stands in, still wearing the chosen colour.

local Avatar = {}
local Parts = require("src.online.world.AvatarParts")
Avatar.Parts = Parts

Avatar.WIRE_V = 1
Avatar.ROLES = { boy = true, girl = true, npc = true }
Avatar.MODES = { tint = true, shift = true }

-- The colour presets.  `tint` colourises toward hue h at strength k;
-- `shift` turns every coloured pixel's hue by h degrees.  Outlines and
-- near-greys keep their value, so the sprite stays readable.
Avatar.PRESETS = {
  { id = "none", label = "ORIGINAL" },
  { id = "red", label = "RED", h = 0, k = 70, m = "tint" },
  { id = "orange", label = "ORANGE", h = 28, k = 70, m = "tint" },
  { id = "yellow", label = "YELLOW", h = 52, k = 65, m = "tint" },
  { id = "green", label = "GREEN", h = 120, k = 65, m = "tint" },
  { id = "teal", label = "TEAL", h = 172, k = 65, m = "tint" },
  { id = "blue", label = "BLUE", h = 218, k = 70, m = "tint" },
  { id = "purple", label = "PURPLE", h = 275, k = 65, m = "tint" },
  { id = "pink", label = "PINK", h = 322, k = 60, m = "tint" },
  { id = "shift", label = "HUE SWAP", h = 180, k = 100, m = "shift" },
  { id = "custom", label = "CUSTOM" },
}
Avatar.PRESET_BY_ID = {}
for i, p in ipairs(Avatar.PRESETS) do Avatar.PRESET_BY_ID[p.id] = i end

Avatar.HUE_STEP = 15
Avatar.STRENGTH_STEP = 10

-- ------------------------------------------------------------ pure parts

local function isInt(v, lo, hi)
  return type(v) == "number" and v == math.floor(v) and v >= lo and v <= hi
end

local function keyOk(v)
  return type(v) == "string" and #v > 0 and #v <= 64 and v:match("^[%w_%-:]+$") ~= nil
end

-- a tint table, checked and copied; nil = no tint
function Avatar.cleanTint(t)
  if type(t) ~= "table" then return nil end
  local h = tonumber(t.h)
  local k = tonumber(t.k)
  if not (h and k) then return nil end
  h = math.floor(h) % 360
  k = math.floor(k)
  if k <= 0 then return nil end
  if k > 100 then k = 100 end
  local m = Avatar.MODES[t.m] and t.m or "tint"
  return { h = h, k = k, m = m }
end

-- an `av` from the wire (or the save), checked and copied; nil when it is
-- not one.  Unknown keys are dropped; a future `v` is accepted (its known
-- fields still mean the same thing), so a newer peer is never refused.
function Avatar.clean(av)
  if type(av) ~= "table" then return nil end
  if not isInt(av.v, 1, 999) then return nil end
  local out = { v = av.v }
  if keyOk(av.g) and #av.g <= 24 then out.g = av.g end
  if keyOk(av.s) then out.s = av.s end
  if Avatar.ROLES[av.r] then out.r = av.r end
  out.t = Avatar.cleanTint(av.t)
  -- per-part colours (AvatarParts): skin / hair / outfit / accent
  out.c = Parts.clean(av.c)
  if not (out.s or out.t or out.c) then return nil end
  return out
end

-- one string per look, so a change can be told apart from no change
function Avatar.signature(av)
  if type(av) ~= "table" then return "" end
  local t = av.t or {}
  return ("%s|%s|%s|%s|%s|%s|%s"):format(tostring(av.g or ""), tostring(av.s or ""), tostring(av.r or ""),
    tostring(t.h or ""), tostring(t.k or ""), tostring(t.m or ""), Parts.signature(av.c))
end

local function clamp01(v) if v < 0 then return 0 elseif v > 1 then return 1 end return v end

function Avatar.rgbToHsv(r, g, b)
  local mx, mn = math.max(r, g, b), math.min(r, g, b)
  local d = mx - mn
  local h = 0
  if d > 1e-6 then
    if mx == r then h = ((g - b) / d) % 6
    elseif mx == g then h = (b - r) / d + 2
    else h = (r - g) / d + 4 end
    h = h * 60
  end
  local s = mx > 1e-6 and d / mx or 0
  return h, s, mx
end

function Avatar.hsvToRgb(h, s, v)
  h = (h % 360) / 60
  local c = v * s
  local x = c * (1 - math.abs(h % 2 - 1))
  local r, g, b
  if h < 1 then r, g, b = c, x, 0
  elseif h < 2 then r, g, b = x, c, 0
  elseif h < 3 then r, g, b = 0, c, x
  elseif h < 4 then r, g, b = 0, x, c
  elseif h < 5 then r, g, b = x, 0, c
  else r, g, b = c, 0, x end
  local m = v - c
  return r + m, g + m, b + m
end

-- Value under this is an outline (or a shadow inside one) and is kept.
Avatar.OUTLINE_V = 0.24
-- Saturation under this is a grey/white and only half-tinted.
Avatar.GREY_S = 0.12

-- tintPixel(r, g, b, a, tint, gb) -> r, g, b, a   (all 0..1)
--
-- `gb`: a Game Boy sheet in DMG shades (white = transparent colour 0,
-- light, dark, black).  Those are painted as a four-step ramp of the
-- chosen hue, black kept black, so a GB sprite reads like a GBC one.
function Avatar.tintPixel(r, g, b, a, tint, gb)
  if not tint or a == 0 then return r, g, b, a end
  local k = (tint.k or 0) / 100
  if gb then
    if r > 0.83 then return r, g, b, 0 end
    local cr, cg, cb = Avatar.hsvToRgb(tint.h, 0.35 + 0.5 * k, 0.95)
    if r > 0.5 then
      return 1 - (1 - cr) * 0.35, 1 - (1 - cg) * 0.35, 1 - (1 - cb) * 0.35, a
    elseif r > 0.17 then
      return cr * 0.8, cg * 0.8, cb * 0.8, a
    end
    return 0.06, 0.06, 0.08, a
  end
  local h, s, v = Avatar.rgbToHsv(r, g, b)
  if v < Avatar.OUTLINE_V then return r, g, b, a end
  if tint.m == "shift" then
    if s < Avatar.GREY_S then return r, g, b, a end
    local nr, ng, nb = Avatar.hsvToRgb(h + tint.h, s, v)
    return r + (nr - r) * k, g + (ng - g) * k, b + (nb - b) * k, a
  end
  -- colourise: the pixel's own brightness in the target hue
  local lum = 0.299 * r + 0.587 * g + 0.114 * b
  local tr, tg, tb = Avatar.hsvToRgb(tint.h, 0.72, clamp01(lum * 1.25 + 0.05))
  local w = k
  if s < Avatar.GREY_S then
    w = k * 0.5
    if v > 0.92 then w = k * 0.2 end   -- highlights stay light
  end
  return r + (tr - r) * w, g + (tg - g) * w, b + (tb - b) * w, a
end

-- ------------------------------------------------------------ choices

local function shortLabel(s, max)
  s = tostring(s or "?"):upper():gsub("_", " ")
  max = max or 14
  if #s > max then s = s:sub(1, max) end
  return s
end

-- a readable name for a sheet from its own record
function Avatar.sheetLabel(def, key)
  local img = type(def) == "table" and type(def.image) == "string" and def.image or ""
  local base = img:match("([^/]+)%.png$") or ""
  -- numbered rips (Gen 3 g3_012, Gen 5 bw_104) have no name in the cache
  local num = base:match("^g3_(%d+)$") or base:match("^bw_(%d+)$")
  if num then return "TRAINER " .. num end
  if base ~= "" and base ~= "placeholder_sprite" and not base:match("^%d+$") then
    return shortLabel(base)
  end
  local id = tostring(key or ""):gsub("^SPRITE_", "")
  if id:match("^G%d_%d+$") then return "TRAINER " .. id:match("(%d+)$") end
  return shortLabel(id)
end

-- sheets that are not people a player could plausibly be
local NOT_PEOPLE = {
  "MON", "BALL", "BOULDER", "TREE", "ROCK", "REFLECT", "_RUN", "BIKE", "SURF",
  "FOSSIL", "SIGN", "DOLL", "TROPHY", "PAPER", "POKEDEX", "BOOK", "CLEFAIRY",
  "OLD_AMBER", "BIG_", "ITEM", "FRUIT", "GAMEBOY", "FAMICOM", "MONSTER",
  "BIRD", "FAIRY", "DRAGON", "LAPRAS", "SNORLAX", "ONIX", "ENTEI", "RAIKOU",
  "SUICUNE", "LUGIA", "HO_OH", "SUDOWOODO", "SILVER_TROPHY", "GOLD_TROPHY",
  "PLACEHOLDER",
}

local function looksLikePerson(key, def, maxW, maxH)
  if type(def) ~= "table" or type(def.image) ~= "string" then return false end
  if not def.walker then return false end
  if (tonumber(def.frames) or 0) < 3 and not def.facings then return false end
  if def.big or def.monIcon or def.fullCycle then return false end
  local w = tonumber(def.frameWidth) or 16
  if w > (maxW or 32) then return false end
  -- no bigger than the player's own cell: a 32-wide Gen 3 sheet is a bike
  -- or a vehicle, not a person
  if maxH and (tonumber(def.frameHeight) or 16) > maxH then return false end
  local up = (tostring(key) .. "|" .. def.image):upper()
  for _, bad in ipairs(NOT_PEOPLE) do
    if up:find(bad, 1, true) then return false end
  end
  return true
end

-- choices(data) -> { { key, label, role, gender }, ... }: the protagonist
-- forms first (both genders where the cartridge has them), then the other
-- trainer sheets of this game when `withTrainers` is not false.
function Avatar.choices(data, withTrainers)
  local out, seen = {}, {}
  local sprites = (data and data.sprites) or {}
  local forms = data and data.field and data.field.playerForms
  if type(forms) == "table" then
    local order = type(forms.order) == "table" and forms.order or { "boy", "girl" }
    for _, name in ipairs(order) do
      local f = forms[name]
      if type(f) == "table" and f.walk and sprites[f.walk] and not seen[f.walk] then
        seen[f.walk] = true
        local role = (name == "girl") and "girl" or "boy"
        out[#out + 1] = { key = f.walk, role = role, gender = role,
                          label = "PLAYER " .. shortLabel(f.label or name, 8) }
      end
    end
  end
  if #out == 0 then
    local ok, FieldDefaults = pcall(require, "src.world.FieldDefaults")
    local walk = ok and FieldDefaults.fieldValue and FieldDefaults.fieldValue(data, "playerSprites", "walk")
    if walk and sprites[walk] then
      seen[walk] = true
      out[#out + 1] = { key = walk, role = "boy", gender = "boy", label = "PLAYER" }
    end
  end
  if withTrainers ~= false then
    -- the protagonists' OTHER sheets (bike, surf, field move, diving...) are
    -- not trainers: numbered rips (g3_001) give no name to filter them by
    local own = {}
    local function collect(t)
      if type(t) ~= "table" then return end
      for _, v in pairs(t) do
        if type(v) == "string" then own[v] = true elseif type(v) == "table" then collect(v) end
      end
    end
    if type(forms) == "table" then collect(forms) end
    collect(data and data.field and data.field.playerSprites)
    local maxW, maxH
    local hero = out[1] and sprites[out[1].key]
    if type(hero) == "table" then
      maxW = tonumber(hero.frameWidth) or 16
      maxH = tonumber(hero.frameHeight) or 16
    end
    local keys = {}
    for key, def in pairs(sprites) do
      if not seen[key] and not own[key] and looksLikePerson(key, def, maxW, maxH) then keys[#keys + 1] = key end
    end
    table.sort(keys)
    for _, key in ipairs(keys) do
      out[#out + 1] = { key = key, role = "npc", label = Avatar.sheetLabel(sprites[key], key) }
    end
  end
  return out
end

-- ------------------------------------------------------------ save

local function onlineOpts(game, create)
  local opts = game and game.save and game.save.options
  if type(opts) ~= "table" then return nil end
  if type(opts.online) ~= "table" then
    if not create then return nil end
    opts.online = {}
  end
  return opts.online
end

-- options are shared by every game, and sheet keys are not (SPRITE_G4_000 is
-- a different person in Platinum and HeartGold), so the choice is kept per
-- game.
--
-- ONE LOOK, OFFLINE AND ONLINE: options.looks[<game id>].  The same choice
-- dresses your own character in single-player (SelfLook, BattleLook) and is
-- what other players see.  It used to live in options.online.avatars[<game>]
-- (online-only MY LOOK); that slot is still READ when options.looks has
-- nothing for the game (migrated on first read, so nobody loses a look), and
-- every store MIRRORS into it so an older build still finds the same look.
local function slot(game)
  local ok, GameVersion = pcall(require, "src.core.GameVersion")
  local id = ok and GameVersion.get and GameVersion.get()
  return type(id) == "string" and id or "default"
end
Avatar.slot = slot

-- the raw stored entry for this game (options.looks, else the old
-- options.online.avatars slot, copied over), or nil
function Avatar.rawSaved(game)
  local opts = game and game.save and game.save.options
  if type(opts) ~= "table" then return nil end
  local id = slot(game)
  local a = type(opts.looks) == "table" and opts.looks[id] or nil
  if type(a) == "table" then return a end
  local o = type(opts.online) == "table" and opts.online or nil
  local old = o and type(o.avatars) == "table" and o.avatars[id] or nil
  if type(old) ~= "table" then return nil end
  -- migrate: the online-only look becomes the one look
  if type(opts.looks) ~= "table" then opts.looks = {} end
  opts.looks[id] = old
  return old
end

-- the saved choice: { s, r, p = preset id, t = tint } or nil
function Avatar.saved(game)
  local a = Avatar.rawSaved(game)
  if type(a) ~= "table" then return nil end
  local out = { p = type(a.p) == "string" and a.p or nil, t = Avatar.cleanTint(a.t),
                c = Parts.clean(a.c) }
  -- which preset each part was picked from (the screen's own memory)
  if type(a.cp) == "table" then
    out.cp = {}
    for id in pairs(Parts.IDS) do
      if type(a.cp[id]) == "string" and #a.cp[id] <= 16 then out.cp[id] = a.cp[id] end
    end
  end
  if keyOk(a.s) then out.s = a.s end
  if Avatar.ROLES[a.r] then out.r = a.r end
  return out
end

function Avatar.store(game, choice)
  local opts = game and game.save and game.save.options
  if type(opts) ~= "table" then return false end
  local id = slot(game)
  local entry = nil
  if choice ~= nil then
    entry = { s = choice.s, r = choice.r, p = choice.p, t = Avatar.cleanTint(choice.t),
              c = Parts.clean(choice.c), cp = choice.cp }
  end
  if type(opts.looks) ~= "table" then opts.looks = {} end
  opts.looks[id] = entry
  -- mirrored into the old online slot (older builds read it; and a cleared
  -- look must not come back from there through the migration)
  local o = onlineOpts(game, entry ~= nil)
  if o then
    if type(o.avatars) ~= "table" then o.avatars = {} end
    o.avatars[id] = entry
  end
  if game.writeOptions then pcall(game.writeOptions, game) end
  return true
end

local function gameId()
  local ok, GameVersion = pcall(require, "src.core.GameVersion")
  local id = ok and GameVersion.get and GameVersion.get()
  return type(id) == "string" and id or nil
end
Avatar.gameId = gameId

-- the `av` this player sends, or nil when they never chose anything (an
-- untouched player looks exactly as before, on the wire too)
function Avatar.wire(game)
  local c = Avatar.saved(game)
  if not c or not (c.s or c.t or c.c) then return nil end
  local data = game and game.data
  local sprites = (data and data.sprites) or {}
  local s, r = c.s, c.r
  if not (s and sprites[s]) then
    -- the chosen sheet is not in this game (a save moved between games):
    -- the colour still travels, on the player's own sheet
    local gender = game.save and game.save.player and game.save.player.gender
    r = gender == "girl" and "girl" or "boy"
    local forms = data and data.field and data.field.playerForms
    local f = type(forms) == "table" and (forms[r] or forms.boy)
    s = type(f) == "table" and f.walk or nil
  end
  return Avatar.clean({ v = Avatar.WIRE_V, g = gameId(), s = s, r = r, t = c.t, c = c.c })
end

-- ------------------------------------------------------------ resolve

local function formOf(data, gender)
  local forms = data and data.field and data.field.playerForms
  if type(forms) ~= "table" then return nil end
  local f = forms[gender] or forms.boy
  return type(f) == "table" and f or nil
end

local function modeKey(f, mv)
  if not f then return nil end
  if mv == "bike" then return f.bike end
  if mv == "surf" then return f.surf end
  return f.walk
end

-- resolve(data, look, mv, viewerGame) -> sheet key or nil (nil: the caller
-- keeps its old rule, which is what an `av`-less peer gets)
function Avatar.resolve(data, look, mv, viewerGame)
  local av = type(look) == "table" and look.av
  if type(av) ~= "table" then return nil end
  local sprites = (data and data.sprites) or {}
  viewerGame = viewerGame or gameId()
  local gender = (av.r == "girl" or av.r == "boy") and av.r
                 or (look.gender == "girl" and "girl") or "boy"
  local same = av.g ~= nil and av.g == viewerGame
  if same and av.s and sprites[av.s] then
    if av.r == "npc" then
      if mv == "bike" or mv == "surf" then
        local k = modeKey(formOf(data, gender), mv)
        if k and sprites[k] then return k end
      end
      return av.s
    end
    local k = modeKey(formOf(data, gender), mv)
    if mv ~= "walk" and mv ~= "run" and k and sprites[k] then return k end
    return av.s
  end
  -- another game's sheet, or a key this cache lacks: the closest thing
  -- here, the same-gender protagonist
  local f = formOf(data, gender)
  local k = modeKey(f, mv)
  if k and sprites[k] then return k end
  if f and f.walk and sprites[f.walk] then return f.walk end
  return nil
end

-- the PAINT a look asks for: { t = whole-sprite tint, c = part colours },
-- or nil when it asks for none.  (Named for history: it used to be the tint.)
function Avatar.tintOf(look)
  local av = type(look) == "table" and look.av
  if type(av) ~= "table" then return nil end
  return Avatar.paint({ t = av.t, c = av.c })
end

-- normalise: a bare tint {h,k,m}, or {t, c}; nil when it paints nothing
function Avatar.paint(x)
  if type(x) ~= "table" then return nil end
  if x.k ~= nil or x.m ~= nil then x = { t = x } end
  local t, c = Avatar.cleanTint(x.t), Parts.clean(x.c)
  if not (t or c) then return nil end
  return { t = t, c = c }
end

function Avatar.paintSig(p)
  p = Avatar.paint(p)
  if not p then return "" end
  local t = p.t
  return (t and ("%d:%d:%s"):format(t.h, t.k, t.m) or "-") .. "/" .. Parts.signature(p.c)
end

-- ------------------------------------------------------------ hand maps

-- which protagonist a sheet or pic belongs to in this cache ("boy"/"girl"),
-- found by its key or its path among data.field.playerForms and the DS
-- trainer classes 0 / 1 and back throws
function Avatar.genderOf(data, keyOrPath)
  if type(keyOrPath) ~= "string" then return nil end
  local forms = data and data.field and data.field.playerForms
  local sprites = data and data.sprites or {}
  if type(forms) == "table" then
    for _, g in ipairs({ "boy", "girl" }) do
      local f = forms[g]
      if type(f) == "table" then
        for _, v in pairs(f) do
          if v == keyOrPath then return g end
          local d = type(v) == "string" and sprites[v]
          if type(d) == "table" and (d.image == keyOrPath or d.run == keyOrPath) then return g end
        end
      end
    end
  end
  local ts = data and data.gen4_trainer_sprites
  if type(ts) == "table" then
    local cl = type(ts.classes) == "table" and ts.classes or {}
    if cl[0] and cl[0].path == keyOrPath then return "boy" end
    if cl[1] and cl[1].path == keyOrPath then return "girl" end
    -- Black / White's trfgra pictures 0 / 1 (Hilbert, Hilda)
    local pics = type(ts.pictures) == "table" and ts.pictures or {}
    if pics[0] and pics[0].path == keyOrPath then return "boy" end
    if pics[1] and pics[1].path == keyOrPath then return "girl" end
    local throws = type(ts.backThrows) == "table" and ts.backThrows or {}
    for still, rec in pairs(throws) do
      if type(rec) == "table" and rec.path == keyOrPath then return Avatar.genderOf(data, still) end
    end
  end
  return nil
end

-- the hand map for a sheet (nil: the classifier decides), and its gender
function Avatar.handFor(data, keyOrPath, game)
  local g = Avatar.genderOf(data, keyOrPath)
  local maps = Parts.HAND_MAPS[game or Avatar.gameId() or ""]
  return g and maps and maps[g] or nil, g
end

-- ------------------------------------------------------------ baking

local cache = {}

function Avatar.invalidate() cache = {} end

local function q(v) return math.floor(v * 255 + 0.5) end

-- recolour an ImageData in place by a paint; `hand` a part map or nil;
-- `gb` a Game Boy four-shade sheet (parts do not apply there).  Returns how
-- the parts were found ("hand" / "auto" / nil).
-- which pixels of a plan's `near` colours to recolour: each 8-connected
-- patch of near colours that touches a pixel of the part it follows (the
-- hand's shade beside the hand's skin), not the patches elsewhere (the same
-- grey shading white cloth).  -> { [y * w + x] = true } or nil
function Avatar.nearMask(id, plan, map)
  if not (plan and map) then return nil end
  local any = false
  for _, to in pairs(plan) do if to.near then any = true break end end
  if not any then return nil end
  local w, h = id:getDimensions()
  local near, part = {}, {}
  for y = 0, h - 1 do
    for x = 0, w - 1 do
      local r, g, b, a = id:getPixel(x, y)
      if a > 0 then
        local key = Parts.hexOf(r, g, b)
        local to = plan[key]
        if to and to.near then near[y * w + x] = to.near
        else
          local m = map[key]
          if m then part[y * w + x] = m end
        end
      end
    end
  end
  local accept, seen = {}, {}
  for start, want in pairs(near) do
    if not seen[start] then
      -- one patch
      local stack, members, touches = { start }, {}, false
      seen[start] = true
      while #stack > 0 do
        local i = table.remove(stack)
        members[#members + 1] = i
        local x, y = i % w, math.floor(i / w)
        for dy = -1, 1 do
          for dx = -1, 1 do
            local nx, ny = x + dx, y + dy
            if (dx ~= 0 or dy ~= 0) and nx >= 0 and ny >= 0 and nx < w and ny < h then
              local j = ny * w + nx
              if near[j] and not seen[j] then seen[j] = true stack[#stack + 1] = j
              elseif part[j] == want then touches = true end
            end
          end
        end
      end
      if touches then for _, i in ipairs(members) do accept[i] = true end end
    end
  end
  return accept
end

function Avatar.paintImageData(id, paint, hand, gb, cellH)
  paint = Avatar.paint(paint)
  if not paint then return nil end
  local plan, how, accept = nil, nil, nil
  if paint.c and not gb then
    local counts, order = {}, {}
    local w, h = id:getDimensions()
    cellH = math.max(1, math.floor(tonumber(cellH) or h))
    -- where each frame's figure starts and ends: "the top of the figure" is
    -- what HAIR means, not the top of a cell that is mostly empty
    local tops, bots = {}, {}
    for y = 0, h - 1 do
      local f = math.floor(y / cellH)
      for x = 0, w - 1 do
        local _, _, _, a = id:getPixel(x, y)
        if a > 0 then
          if not tops[f] then tops[f] = y end
          bots[f] = y
          break
        end
      end
    end
    for y = 0, h - 1 do
      local f = math.floor(y / cellH)
      local t0, b0 = tops[f] or (f * cellH), bots[f] or (f * cellH + cellH - 1)
      local fy = (y - t0) / math.max(1, b0 - t0 + 1)
      for x = 0, w - 1 do
        local r, g, b, a = id:getPixel(x, y)
        if a > 0 then
          local key = Parts.hexOf(r, g, b)
          local e = counts[key]
          if not e then
            e = { key = key, r = q(r) / 255, g = q(g) / 255, b = q(b) / 255, n = 0, ysum = 0 }
            counts[key] = e
            order[#order + 1] = e
          end
          e.n = e.n + 1
          e.ysum = e.ysum + fy
        end
      end
    end
    for _, e in ipairs(order) do e.y = e.ysum / e.n end
    local map
    plan, how, map = Parts.plan(order, paint.c, hand)
    accept = Avatar.nearMask(id, plan, map)
  end
  local t = paint.t
  local iw = id:getWidth()
  id:mapPixel(function(x, y, r, g, b, a)
    if a == 0 then return r, g, b, a end
    if plan then
      local to = plan[Parts.hexOf(r, g, b)]
      if to and (not to.near or (accept and accept[y * iw + x])) then r, g, b = to[1], to[2], to[3] end
    end
    if t then return Avatar.tintPixel(r, g, b, a, t, gb) end
    return r, g, b, a
  end)
  return how
end

-- pathImageData(path, paint, hand, gb) -> a fresh recoloured ImageData
function Avatar.pathImageData(path, paint, hand, gb, cellH)
  local id = require("src.render.Assets").imageData(path)
  Avatar.paintImageData(id, paint, hand, gb, cellH)
  return id
end

-- tintedImage(def, paint) -> love Image (same size as the sheet) or nil
function Avatar.tintedImage(def, paint, game)
  paint = Avatar.paint(paint)
  if not (paint and type(def) == "table" and type(def.image) == "string") then return nil end
  if not (love and love.image and love.image.newImageData and love.graphics) then return nil end
  local gb = not def.trueColor
  local G = package.loaded["src.core.Game"]
  local hand = Avatar.handFor(G and G.data, def.id or def.image, game)
  local key = def.image .. "#av" .. Avatar.paintSig(paint) .. (gb and "g" or "") .. (hand and "h" or "")
  local hit = cache[key]
  if hit ~= nil then return hit or nil end
  local ok, img = pcall(function()
    return love.graphics.newImage(Avatar.pathImageData(def.image, paint, hand, gb,
                                                       tonumber(def.frameHeight) or 16))
  end)
  cache[key] = ok and img or false
  return ok and img or nil
end

-- the same for a battle pic by path (cached; nil when nothing to paint)
function Avatar.paintedPathImage(path, paint, data)
  paint = Avatar.paint(paint)
  if not (paint and type(path) == "string") then return nil end
  if not (love and love.image and love.image.newImageData and love.graphics) then return nil end
  local hand = Avatar.handFor(data, path)
  local key = path .. "#pic" .. Avatar.paintSig(paint) .. (hand and "h" or "")
  local hit = cache[key]
  if hit ~= nil then return hit or nil end
  local ok, img = pcall(function()
    local im = love.graphics.newImage(Avatar.pathImageData(path, paint, hand, false))
    im:setFilter("nearest", "nearest")
    return im
  end)
  cache[key] = ok and img or false
  return ok and img or nil
end

-- dress(spriteRenderer, paint) -> the same renderer, wearing the paint.
--
-- Only the INSTANCE changes: its image becomes the baked copy (same size,
-- so every quad still lands) and a Game Boy sheet's record is copied with
-- trueColor set, so it draws the bake as-is instead of re-shading the raw
-- sheet.  The shared record in data.sprites is never written.  The draw
-- path is untouched otherwise -- which is what keeps the Gen 4/5 billboard
-- depth shader working: no shader of ours is ever set around it.
function Avatar.dress(sr, paint)
  if not (sr and sr.def) then return sr end
  paint = Avatar.paint(paint)
  local img = paint and Avatar.tintedImage(sr.def, paint)
  if not img then return sr end
  sr.image = img
  if not sr.def.trueColor then
    local copy = {}
    for k, v in pairs(sr.def) do copy[k] = v end
    copy.trueColor = true
    sr.def = copy
  end
  -- the water reflection is a sheet of its own (def.reflect): same colour
  if type(sr.def.reflect) == "string" then
    local G = package.loaded["src.core.Game"]
    local rdef = G and G.data and G.data.sprites and G.data.sprites[sr.def.reflect]
    local rimg = rdef and Avatar.tintedImage(rdef, paint)
    if rimg then
      local iw, ih = img:getDimensions()
      local rw, rh = rimg:getDimensions()
      if iw == rw and ih == rh then sr._reflectImage = rimg end
    end
  end
  sr.avatarTint = Avatar.paintSig(paint)
  return sr
end

pcall(function() require("src.render.Assets").register(Avatar.invalidate) end)

return Avatar
