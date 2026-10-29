package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.modkit")
local D = require("src.import.DataLiteral")
local Writer = require("src.import.LuaWriter")
local Serializer = require("src.core.SaveSerializer")
local data = { a = { 1, 2, false, "hello\n\0\255", { quoted = "a'\"b" } }, [0] = 17, bytes = "\1\127", map = {
  name = "MEW",
} }
for _, encode in ipairs({ Writer.encode, Serializer.encode }) do
  local value, why = D.decode(encode(data))
  T.check(value ~= nil, "native writer accepted: " .. tostring(why))
  T.same(value, data, "native literal roundtrip")
end
local value, why = D.decode(
  "-- heading\nreturn {a='x', b=[=[\nlong]=], --[=[block]=]\n c={true,false,nil}, [false]=0x10, n=-2.5e2};-- tail"
)
T.check(value ~= nil, "arrays/comments/long strings/hex: " .. tostring(why))
T.eq(value and value.b, "long", "long string newline convention")
T.eq(value and value.n, -250, "finite exponent")
T.eq(value and value[false], 16, "literal boolean key")
for _, text in ipairs({
  "return 1",
  "return {} extra",
  "return {a=1+2}",
  "return os.execute('x')",
  "return {a=1e999}",
  "return {a=0/0}",
  "return {a='\\999'}",
  "return {a='\\x0g'}",
  "return {a='\\q'}",
  "return {a='bad\n'}",
  "return {a=1,a=2}",
  "return {[{}]=1}",
  "return {a=}",
  "return {",
  "--[[unterminated",
  "return {[=[bad}",
  "return {function() while true do end end}",
  "return {a=1}; while true do end",
}) do
  local result, reason = D.decode(text)
  T.eq(result, nil, "invalid/executable literal refused")
  T.check(type(reason) == "string", "invalid literal has reason")
end
local limits = { bytes = 1000, depth = 2, nodes = 10, string = 4, entries = 3 }
for _, text in ipairs({
  string.rep(" ", 1001),
  "return {{{}}}",
  "return {'longstring'}",
  "return {a=1,b=2,c=3,d=4}",
  "return {{1,2,3},{4,5,6}}",
}) do
  T.eq(D.decode(text, limits), nil, "literal parser resource bound")
end
T.finish()
