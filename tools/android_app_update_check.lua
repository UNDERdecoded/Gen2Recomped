-- Run:  python tools/run_lua_check.py tools/android_app_update_check.lua
--
-- THE ANDROID APP UPDATE (src/update/Check.lua, check_worker's doAppDownload):
-- an in-app update on Android installs the release's APK over the app, so a
-- release that needs new native code reaches players without an uninstall.
-- Driven here with a stub love.system standing in for the app's Java bridge.

package.path = './?.lua;./?/init.lua;' .. package.path
local PASS, FAIL = 0, 0
local function check(c, l) if c then PASS = PASS + 1 else FAIL = FAIL + 1; print('FAIL: ' .. l) end end

local calls = {}
local function system(os, extra)
  local s = { getOS = function() return os end, openURL = function(u) calls.opened = u; return true end }
  for k, v in pairs(extra or {}) do s[k] = v end
  return s
end
love = { system = system('Android'), filesystem = { isFused = function() return true end } }

local Payload = require('src.update.Payload')
local Check = require('src.update.Check')
local Json = require('src.link.Json')

check(Payload.apkName('0.8.16') == 'Gen2Recomped-0.8.16-android.apk', 'the APK name matches release.yml\'s asset')
check(Payload.apkRel('0.8.16') == 'updates/Gen2Recomped-0.8.16-android.apk', 'the APK downloads into updates/')
check(not Payload.isName(Payload.apkName('0.8.16')), 'Boot never mistakes the APK for a payload')

local release = Json.encode({ tag_name = 'v0.8.16', assets = {
  { name = 'Gen2Recomped-0.8.16.love', browser_download_url = 'https://x/love', size = 21103555 },
  { name = 'Gen2Recomped-0.8.16-android.apk', browser_download_url = 'https://x/apk', size = 125329811 },
  { name = 'sha256sums.txt', browser_download_url = 'https://x/sums', size = 1183 } } })
local rel = Check.parseRelease(release, Json)
check(rel and rel.apk and rel.apk.url == 'https://x/apk' and rel.apk.size == 125329811, 'the release\'s APK is picked up')

-- which apps are out of date
local full = { installApk = function() return true end, canInstallApks = function() return true end,
               requestInstallPermission = function() return true end, translateOffline = function() return '' end }
love.system = system('Android', {})
check(Check.appOutdated(), 'an app without the new Java calls is out of date')
love.system = system('Android', full)
check(not Check.appOutdated(), 'an app with all of them is current')
love.system = system('Windows', {})
check(not Check.appOutdated(), 'only Android has an app to update')

-- an app too old to install updates: the browser downloads the APK
love.system = system('Android', { translateOffline = full.translateOffline })
Check._setStateForTests({ status = 'available', latest = '0.8.16', app = true, apkUrl = 'https://x/apk' })
Check.download()
check(calls.opened == 'https://x/apk', 'an older app opens the APK link')
check(Check.state().status == 'browser', 'and says to open the downloaded APK')
check(Check.STATUS.browser and Check.STATUS.install, 'both new states are drawn by the banner')

-- installing: permission first, then the installer
local allowed, asked, installed = false, false, nil
love.system = system('Android', {
  installApk = function(p) installed = p; return true end,
  canInstallApks = function() return allowed end,
  requestInstallPermission = function() asked = true; return true end,
  translateOffline = full.translateOffline })
Check._setStateForTests({ status = 'install', latest = '0.8.16', app = true, path = '/data/x/updates/a.apk' })
Check.install()
check(asked and not installed and Check.state().needsPermission, 'without permission, the setting opens first')
allowed = true
Check.install()
check(installed == '/data/x/updates/a.apk' and Check.state().installStarted, 'with it, the installer opens on the APK')
check(not Check.state().needsPermission, 'and the permission note clears')

-- the banner handles every state Check can draw
local src = io.open('src/import/RomImporter.lua', 'rb'):read('*a')
for state, drawn in pairs(Check.STATUS) do
  if drawn then check(src:find('upStatus == "' .. state .. '"', 1, true), 'the launcher banner draws "' .. state .. '"') end
end
check(src:find('action == "install"', 1, true) and src:find('action == "openapk"', 1, true), 'the banner\'s new buttons are wired')

-- the native side exists in the app sources
local java = io.open('mobile/android/love/src/main/java/org/love2d/android/GameActivity.java', 'rb'):read('*a')
local wrap = io.open('mobile/android/love/src/jni/love/src/modules/system/wrap_System.cpp', 'rb'):read('*a')
local manifest = io.open('mobile/android/app/src/main/AndroidManifest.xml', 'rb'):read('*a')
for _, name in ipairs(Check.ANDROID_NATIVE) do
  check(wrap:find('"' .. name .. '"', 1, true), 'love.system.' .. name .. ' is registered')
  if name ~= 'translateOffline' then check(java:find('public static boolean ' .. name, 1, true), 'GameActivity.' .. name .. ' exists') end
end
check(manifest:find('REQUEST_INSTALL_PACKAGES', 1, true) and manifest:find('${applicationId}.updates', 1, true),
  'the manifest asks for install permission and shares the APK')
check(io.open('mobile/android/app/src/main/res/xml/update_paths.xml', 'rb') ~= nil, 'the FileProvider paths exist')

print(('%d checks, %d failed'):format(PASS + FAIL, FAIL))
if FAIL > 0 then os.exit(1) end
