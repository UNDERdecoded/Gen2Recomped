-- Run:  texlua tools/gen4_tablet_check.lua <cache dir>
--
-- THE ROUTE 224 TABLET (Oak's Letter -> Shaymin) and the link-sync opcode
-- 0x135, per scrcmd.c (OpenShayminTabletNamingScreen, ScrCmd_135),
-- scrcmd_strings.c (BufferTabletName) and unk_0203D1B8.c.

package.path = './?.lua;./?/init.lua;' .. package.path
love = love or {}
love.math = love.math or { random = math.random }
package.loaded['src.core.Sound'] = { play = function() end }
local PASS, FAIL = 0, 0
local function check(c, l) if c then PASS = PASS + 1 else FAIL = FAIL + 1 print('FAIL: ' .. l) end end
local dir = (arg and arg[1] or ''):gsub('[/\\]$', '')
local function load(n) local f = loadfile(dir .. '/' .. n .. '.lua') return f and f() end
local text = load('text')

local C = require('src.script.Commands')
require('src.script.Gen4Commands')
local save = { gen4Vars = {} }
local opened
package.loaded['src.ui.Screens'] = { push = function(_, id, opts) opened = { id = id, opts = opts } end }
local game = { data = { text = text }, save = save, stack = {}, stringBuffers = {} }
local ctx = { game = game, save = save, runner = { resume = function() end, yield = function() end } }
local function var(v) return save.gen4Vars[v] end

C.g4_tablet_naming(ctx, 0x800C)
check(opened and opened.id == 'NamingScreen' and opened.opts.maxLen == 10, 'the naming screen, ten characters')
check(opened.opts.title == 'Thank who?', 'titled from bank 422 #6, the {YESNO} stripped: ' .. tostring(opened.opts.title))
opened.opts.onDone('')
check(var(0x800C) == 1 and save.gen4TabletName == nil, 'nothing entered: returnCode 1, nothing saved')
C.g4_tablet_naming(ctx, 0x800C)
opened.opts.onDone('ROWAN')
check(var(0x800C) == 0 and save.gen4TabletName == 'ROWAN', 'a name: 0, kept in the save')
C.g4_buffer_tablet_name(ctx, 1)
check(game.stringBuffers[2] == 'ROWAN', 'buffertabletname 1')

local VM = require('src.script.Gen4ScriptVM')
local sdata = { constants = { gen = 4 }, maps = load('maps'), map_scripts = load('map_scripts'), text = text }
local bad, syncRows = {}, 0
for label in pairs(sdata.map_scripts.scripts) do
  local p = label:sub(1, 5)
  if p == 'M0485' or p == 'M0000' then
    for _, row in ipairs(VM.compile(sdata, label) or {}) do
      if row[1] == 'g4_unimplemented' and (p == 'M0485' or row[2] == '135') then
        bad[#bad + 1] = label .. ':' .. tostring(row[2])
      end
    end
  end
end
check(#bad == 0, 'the tablet scripts and every 0x135 in the common scripts lower: ' .. table.concat(bad, ', '))
print(('%d checks, %d failed'):format(PASS + FAIL, FAIL))
if FAIL > 0 then os.exit(1) end
