function love.conf(t)
  t.identity=os.getenv('PACK_QA_IDENTITY') or 'oasc-asset-pack-runtime-qa'
  t.window=false
  t.modules.graphics=false
  t.modules.audio=false
  t.modules.sound=false
end
