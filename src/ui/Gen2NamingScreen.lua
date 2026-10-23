-- Public Gen1Recomp screen ID used by API-2 mods on a Gen-2 save.
-- Reuse this engine's native keyboard while preserving the caller-owned
-- completion contract: unlike NamingScreen, this screen never pops itself.
local NamingScreen = require("src.ui.NamingScreen")
local Font = require("src.render.Font")

local Compat = {}
local TYPES = {
  player = { prompt = "YOUR NAME?", length = 7, kind = "player" },
  rival = { prompt = "RIVAL'S NAME?", length = 7, kind = "rival" },
  mom = { prompt = "MOTHER'S NAME?", length = 7 },
  box = { prompt = "BOX NAME?", length = 8 },
  nickname = { prompt = "NICKNAME?", length = 10, kind = "mon" },
}
local function glyphs(text, limit)
  text = type(text) == "string" and text or ""
  local out = {}
  for _, span in ipairs(Font.split(text)) do
    if #out >= limit then
      break
    end
    out[#out + 1] = text:sub(span.from, span.to)
  end
  return out
end
local function accept(self)
  if self.onDone then
    self.onDone(table.concat(self.glyphs))
  end
end
local meta = {
  __index = function(self, key)
    if key == "text" then
      return table.concat(self.glyphs)
    end
    if key == "accept" or key == "confirm" then
      return accept
    end
    return NamingScreen[key]
  end,
  __newindex = function(self, key, value)
    if key == "text" then
      self.glyphs = glyphs(value, self.maxLen)
    else
      rawset(self, key, value)
    end
  end,
}

function Compat.new(game, opts)
  opts = opts or {}
  local kind = TYPES[opts.type or "player"] or TYPES.player
  local screen = NamingScreen.new(game, {
    title = opts.prompt or require("src.core.Strings")(kind.prompt),
    maxLen = opts.maxLength or kind.length,
    kind = kind.kind,
    mon = opts.mon,
    onDone = opts.onDone,
  })
  screen.maxLength = screen.maxLen
  screen.prompt = screen.title
  screen.monName = opts.monName
  screen.onCancel = opts.onCancel
  screen.glyphs = glyphs(opts.initial, screen.maxLen)
  return setmetatable(screen, meta)
end

return Compat
