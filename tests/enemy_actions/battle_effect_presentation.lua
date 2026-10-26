-- Real native VM / host queue, complete tick states and measured sound controls.
local M = {}
function M.run(root, backend, version, options)
  options = options or {}
  local native = backend == "gen1"
  local f = dofile(root .. "/tests/enemy_actions/assist.lua").fixture(root, backend, version)
  local hardware = dofile(root .. "/tests/native_sound/fixture.lua").install(root, native, f)
  local Anim, Seq, Runtime, picPath, savedPic
  if native then
    Anim, Seq = require("src.core.game3.battle.anim"), require("src.core.game3.battle.anim_seq")
    Runtime = require("src.core.game3.runtime")
    Runtime.session = { version = version }
    local Pic = require("src.core.game3.battle.pic_coords")
    picPath = require("src.core.GameVersion").cachePrefix() .. Pic.PACK
    savedPic = love.filesystem.read(picPath)
    love.filesystem.write(picPath, "return {front={[4]={y=13}},back={[4]={y=8}},elevation={[4]=0}}")
    Pic.reset()
    assert(Pic.active().front[4] == 13, "owned native pic coordinates must be readable")
    assert(
      Pic.active().back[4] == (version == "firered" and 10 or 8),
      "native back coordinates must be readable"
    )
    local generalNames = {}
    for i = 0, 8 do
      generalNames[i] = "UNUSED_" .. i
    end
    generalNames[9] = "FOCUS_BAND"
    generalNames[2] = "SUBSTITUTE_FADE"
    Anim.loadPack({
      version = 5,
      tags = {},
      generalNames = generalNames,
      general = {
        [2] = {
          { op = "monbg", battler = "attacker" },
          { op = "createvisualtask", task = "SubstituteFadeToInvisible", priority = 5, args = {} },
          {
            op = "createvisualtask",
            task = "BlendBattleAnimPal",
            priority = 10,
            args = { 2, 0, 0, 16, 32767 },
          },
          { op = "waitforvisualfinish" },
          { op = "delay", frames = 1 },
          { op = "clearmonbg", battler = "attacker" },
          { op = "delay", frames = 2 },
          { op = "blendoff" },
          {
            op = "createvisualtask",
            task = "BlendBattleAnimPal",
            priority = 10,
            args = { 2, 0, 0, 0, 32767 },
          },
          { op = "createvisualtask", task = "SwapMonSpriteToFromSubstitute", priority = 2, args = { 1 } },
          { op = "end" },
        },
        [9] = {
          {
            op = "createsprite",
            template = "gSimplePaletteBlendSpriteTemplate",
            callback = "SimplePaletteBlend",
            animBattler = "attacker",
            args = { 2, 7, 0, 9, 31 },
            noGfx = true,
            w = 8,
            h = 8,
            subpriority = 0,
          },
          { op = "playsewithpan", pan = -64, se = version == "firered" and 164 or 171 },
          {
            op = "createvisualtask",
            task = "SlideMonForFocusBand",
            priority = 5,
            args = { 30, 128, 0, 1, 2, 0, 1 },
          },
          { op = "waitforvisualfinish" },
          {
            op = "createsprite",
            template = "gSimplePaletteBlendSpriteTemplate",
            callback = "SimplePaletteBlend",
            animBattler = "attacker",
            args = { 2, 4, 9, 0, 31 },
            noGfx = true,
            w = 8,
            h = 8,
            subpriority = 0,
          },
          { op = "waitforvisualfinish" },
          { op = "delay", frames = 6 },
          {
            op = "createsprite",
            template = "gSlideMonToOriginalPosSpriteTemplate",
            callback = "SlideMonToOriginalPos",
            animBattler = "attacker",
            args = { 0, 0, 15 },
            noGfx = true,
            w = 8,
            h = 8,
            subpriority = 0,
          },
          { op = "end" },
        },
      },
      statusNames = { [0] = "STATUS_PSN" },
      status = {
        [0] = {
          { op = "loopsewithpan", pan = 63, se = version == "firered" and 141 or 148, times = 6, wait = 13 },
          { op = "createvisualtask", task = "ShakeMon2", priority = 2, args = { 0, 1, 0, 18, 2 } },
          {
            op = "createvisualtask",
            task = "BlendColorCycle",
            priority = 2,
            args = { 2, 2, 2, 0, 12, 31774 },
          },
          { op = "end" },
        },
      },
    })
  end
  local rows = {}
  for _, double in ipairs({ false, true }) do
    for actor = 0, double and 3 or 1 do
      for _, scene in ipairs({ false, true }) do
        for _, stereo in ipairs({ false, true }) do
          for _, name in ipairs(options.names or { "POISON", "FOCUS_BAND" }) do
            for _, kind in
              ipairs(options.kinds or { "ordinary", "substitute", "lowered-substitute", "hidden" })
            do
              local b = f.field(double)
              local user, draws = f.actor(actor), 0
              user.substituteHP = (kind == "substitute" or kind == "lowered-substitute") and 100 or nil
              user.mon.status = "PSN"
              local fading = name == "SUBSTITUTE_FADE"
              local showing = kind == "substitute" or fading and (kind == "ordinary" or kind == "hidden")
              local hidden = kind == "hidden" or kind == "hidden-mon"
              b.rng = function()
                draws = draws + 1
                error("presentation cannot draw battle RNG")
              end
              hardware.reset()
              hardware.stereo(stereo)
              if native then
                require("src.core.game3.battle")._st = b
                user.status = "PSN"
                user.semiInvulnerable = hidden and "ON_AIR" or nil
                Runtime.session = { version = version, options = { battleScene = scene and 0 or 1 } }
                Anim.reset({ headless = false, double = double })
                for id = 0, double and 3 or 1 do
                  Anim.present(id).visible = true
                end
                Anim.setSubstitute(actor, showing)
                if hidden then
                  Anim.present(actor).visible = false
                end
                Seq.beginEvents({
                  {
                    kind = "anim",
                    anim = name == "POISON" and "status" or "general",
                    name = name,
                    attackerId = actor,
                    targetId = actor,
                  },
                }, function() end)
              else
                f.game.save.options.animations = scene
                user.invulnerable = hidden or nil
                b.picFx = hidden and { [user] = { hidden = true } } or nil
                f.data.constants.gen3BattlerCoords = {
                  singles = { { x = 72, y = 80 }, { x = 176, y = 40 } },
                  doubles = {
                    { x = 32, y = 80 },
                    { x = 200, y = 40 },
                    { x = 90, y = 88 },
                    { x = 152, y = 32 },
                  },
                }
                b.current, b.waitFrames, b.nextInsert = nil, nil, 0
                b._gbaEffectPresentation = nil
                b._gbaSubstitutePresentation = kind == "lowered-substitute"
                    and { [user] = { substitute = false, lowered = true, x = 0 } }
                  or nil
                if fading then
                  b._gbaSubstitutePresentation = { [user] = { substitute = showing, x = 0 } }
                end
                b.queue = {
                  {
                    anim = name,
                    gbaNativeEffect = true,
                    attackerPosition = actor,
                    targetPosition = actor,
                    attackerIsPlayer = user.isPlayer,
                  },
                }
              end
              local frames, done = {}, false
              for tick = 0, 200 do
                hardware.tick(tick)
                if native then
                  if tick > 0 then
                    Anim.update(1 / 60)
                  end
                  if not Anim.busy() then
                    done = Seq.update()
                  end
                else
                  done = not b:updateQueue()
                end
                local states = {}
                for id = 0, double and 3 or 1 do
                  local a = f.actor(id)
                  local state
                  if native then
                    local p = Anim.present(id)
                    state = {
                      x = p.ox or 0,
                      y = p.oy or 0,
                      alpha = p.alpha or 1,
                      visible = p.visible ~= false,
                      substitute = p.substitute or false,
                      monbg = p.monbg or false,
                      coeff = p.blendCoeff or 0,
                      color = p.blendColor or { 0, 0, 0 },
                    }
                  else
                    local x, y = b:gen3AnimShake(a)
                    local r, g, blue, coeff = b:gen3AnimTint(a)
                    local special = b:gen3AnimSpecialMonState(a)
                    state = {
                      x = x,
                      y = y,
                      alpha = special and special.alpha or 1,
                      visible = not (b.picFx and b.picFx[a] and b.picFx[a].hidden),
                      substitute = b:substituteVisible(a),
                      monbg = require("src.battle.Gen3EffectPresentation").monBg(b, a),
                      coeff = coeff or 0,
                      color = { r or 0, g or 0, blue or 0 },
                    }
                  end
                  state.hp, state.substituteHP = a.mon.hp, a.substituteHP or 0
                  state.status = a.mon.status
                  states[#states + 1] = state
                end
                frames[#frames + 1] = { tick = tick, done = done, states = states, rng = draws }
                if done then
                  break
                end
              end
              assert(
                done,
                ("native %s must finish: actor %d, scene %s, stereo %s, %s"):format(
                  name,
                  actor,
                  tostring(scene),
                  tostring(stereo),
                  kind
                )
              )
              f.T.eq(
                #hardware.trace(),
                name ~= "SUBSTITUTE_FADE"
                    and scene
                    and (kind == "ordinary" or name == "FOCUS_BAND" and kind == "lowered-substitute")
                    and (name == "POISON" and 6 or 1)
                  or 0,
                "actual native effect sound sequence"
              )
              rows[#rows + 1] = {
                double = double,
                actor = actor,
                scene = scene,
                stereo = stereo,
                case = kind,
                name = name,
                frames = frames,
                sounds = hardware.trace(),
              }
            end
          end
        end
      end
    end
  end
  hardware.close()
  if native then
    if savedPic then
      love.filesystem.write(picPath, savedPic)
    else
      love.filesystem.remove(picPath)
    end
    require("src.core.game3.battle.pic_coords").reset()
  end
  f.close()
  return rows
end
return M
