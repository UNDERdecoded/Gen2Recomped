-- Additive information needed to observe original script operands after the
-- native importer has normalized cross-edition command ids.
local M={SCHEMA=1}
function M.row(line,row)
  row.sourceOpcode=line.op
  row.sourceAddress=line.address and line.address+0x08000000
  row.sourceSpecial=line.sourceSpecial
  row.sourceBytes=line.sourceBytes
  row.sourceSpec=line.sourceSpec
  return row
end
function M.header(edition,sha1)
  return {schema=M.SCHEMA,edition=edition,romSha1=sha1}
end
return M
