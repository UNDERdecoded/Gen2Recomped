-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
function love.conf(t)
  t.identity=assert(os.getenv('PACK_QA_IDENTITY'),'an isolated PACK_QA_IDENTITY is required')
  assert(t.identity:match('^oasc%-') and t.identity:find('%-qa'), 'only an owned QA identity is allowed')
  t.window=false;t.modules.graphics=false;t.modules.audio=false;t.modules.sound=false
end
