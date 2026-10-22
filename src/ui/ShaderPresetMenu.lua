-- Shared small options UI, also reachable through the GBA/DS extra rows.
local Presets = require("src.render.ShaderPresets")
local OptionRows = require("src.ui.OptionRows")
local Menu = {}
Menu.__index = Menu
Menu.isOpaque = true
Menu.shaderPresetBypass = true
local function short(s, n)
  s = tostring(s or "")
  return #s > n and s:sub(1, n - 1) .. "~" or s
end
local function save(game)
  if game.writeOptions then
    game:writeOptions()
  end
end
function Menu:sgbPalettes(game)
  return require("src.render.PaletteFX").wholeNamed(game.data, "MEWMON")
end
function Menu.parameters(game, presets)
  presets = presets or Presets
  local self = setmetatable(
    { game = game, presets = presets, index = 1, scroll = 0, rows = {}, isParameters = true },
    Menu
  )
  local entryId = presets.entry and presets.entry.id
  local function current()
    return presets.entry and presets.entry.id == entryId and presets.values
  end
  for _, parameter in ipairs(presets.entry and presets.entry.parameters or {}) do
    local p = parameter
    self.rows[#self.rows + 1] = {
      label = short(p.name, 17),
      value = function()
        local values = current()
        return values and ("%.3g"):format(values[p.id]) or "OFF"
      end,
      reset = function()
        if not current() then
          return
        end
        presets:setParameter(game.save.options, p.id, p.default)
        save(game)
      end,
      step = function(_, dir)
        local values = current()
        if not values then
          return
        end
        presets:setParameter(game.save.options, p.id, values[p.id] + dir * p.step)
        save(game)
      end,
    }
  end
  return self
end
function Menu.new(game, presets)
  presets = presets or Presets
  local self = setmetatable({ game = game, presets = presets, index = 1, scroll = 0, rows = {} }, Menu)
  self.rows[1] = {
    label = "OFF",
    activate = function()
      presets:select(game.save.options, "off")
      save(game)
    end,
  }
  for _, record in ipairs(presets:refresh()) do
    local entry = record
    self.rows[#self.rows + 1] = {
      presetId = entry.id,
      label = short(entry.name, 17),
      value = function()
        return entry.error and "INVALID"
          or (presets.entry and presets.entry.id == entry.id and "ACTIVE" or "SELECT")
      end,
      activate = function()
        local ok = presets:select(game.save.options, entry.id)
        if ok then
          save(game)
        else
          game.stack:push(Menu.message(game, presets.error))
        end
      end,
    }
  end
  self.rows[#self.rows + 1] = {
    label = "BROWSE SHADERS",
    activate = function()
      game.stack:push(Menu.browser(game, presets))
    end,
  }
  return self
end
function Menu.browser(game, presets, browser)
  browser = browser or require("src.render.ShaderBrowser").new()
  local self = setmetatable({
    game = game,
    presets = presets,
    index = 1,
    scroll = 0,
    rows = {},
    browserJob = browser,
    isBrowser = true,
  }, Menu)
  local function listing()
    self.rows = {}
    for _, record in ipairs(browser.entries or {}) do
      local entry = record
      self.rows[#self.rows + 1] = {
        label = short(entry.name, 17),
        value = function()
          if browser.busy and browser.path == entry.path then
            return "..."
          end
          return browser.installed[entry.path] and "SELECT" or "DOWNLOAD"
        end,
        activate = function()
          if browser.busy then
            return
          end
          local id = browser.installed[entry.path]
          if id then
            presets:refresh()
            local ok, why = presets:select(game.save.options, id)
            if ok then
              save(game)
            else
              game.stack:push(Menu.message(game, why))
            end
          else
            local ok, why = browser:start("install", entry.path)
            if not ok then
              game.stack:push(Menu.message(game, why))
            end
          end
        end,
      }
    end
  end
  local ok, why = browser:start("catalog")
  if not ok then
    return Menu.message(game, why)
  end
  self.rows = { {
    label = "LOADING CATALOG",
    value = function()
      return "..."
    end,
  } }
  function self:browserUpdate()
    browser:poll()
    if browser.result == "catalog" then
      listing()
      browser.result = nil
    end
    if browser.error then
      local reason = browser.error
      browser.error = nil
      game.stack:push(Menu.message(game, reason))
    end
  end
  return self
end
function Menu.message(game, reason)
  local self = setmetatable({ game = game, index = 1, scroll = 0, rows = {}, isMessage = true }, Menu)
  reason = tostring(reason):gsub("[^ -~]", " ")
  for i = 1, math.min(136, #reason), 34 do
    local text = reason:sub(i, i + 33)
    self.rows[#self.rows + 1] = {
      label = text:sub(1, 17),
      value = function()
        return text:sub(18, 34)
      end,
    }
  end
  return self
end
function Menu:update()
  if self.browserUpdate then
    self:browserUpdate()
  end
  local input = self.game.input
  local bottom = #self.rows + 1
  if input:wasPressed("b") or input:wasPressed("start") then
    if self.browserJob then
      self.browserJob:cancel()
    end
    self.game.stack:pop()
    return
  end
  if input:wasPressed("up") then
    self.index = self.index > 1 and self.index - 1 or bottom
  elseif input:wasPressed("down") then
    self.index = self.index < bottom and self.index + 1 or 1
  elseif input:wasPressed("select") then
    local row = self.rows[self.index]
    if self.isParameters and row and row.reset then
      row.reset()
    elseif not self.isMessage and self.presets.entry and row and row.presetId == self.presets.entry.id then
      self.game.stack:push(Menu.parameters(self.game, self.presets))
    end
  elseif input:wasPressed("a") or input:wasPressed("left") or input:wasPressed("right") then
    local row = self.rows[self.index]
    if not row then
      if input:wasPressed("a") then
        if self.browserJob then
          self.browserJob:cancel()
        end
        self.game.stack:pop()
      end
    elseif row.step then
      row.step(self.game, input:wasPressed("left") and -1 or 1)
    elseif row.activate and input:wasPressed("a") then
      row.activate(self.game)
    end
  end
  self.scroll = OptionRows.clampScroll(self.index, self.scroll, #self.rows, bottom)
end
function Menu:exit()
  if self.browserJob then
    self.browserJob:cancel()
  end
end
function Menu:draw()
  local footer = self.isMessage and "BACK"
    or (self.isBrowser and (self.browserJob.busy and "BACK / WORKING" or "BACK / A SELECT"))
    or (self.isParameters and "BACK / SEL RESET" or "BACK / SEL PARAMS")
  OptionRows.draw(self.game, self.rows, self.index, self.scroll, footer, #self.rows + 1)
end
return Menu
