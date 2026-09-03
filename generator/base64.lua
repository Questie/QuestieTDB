-- generator/base64.lua
--
-- Standard base64 for the plain-Lua generator and client emulator.

local base64 = {}

local alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local encodeCharacter = {}
local decodeCharacter = {}
for index = 1, #alphabet do
  local character = alphabet:sub(index, index)
  encodeCharacter[index - 1] = character
  decodeCharacter[character] = index - 1
end

local byte, char, concat, floor = string.byte, string.char, table.concat, math.floor

---@param bytes string
---@return string encoded
function base64.encode(bytes)
  if type(bytes) ~= "string" then error("base64.encode: expected a string", 2) end

  local output = {}
  for index = 1, #bytes, 3 do
    local first, second, third = byte(bytes, index, index + 2)
    local value = first * 65536 + (second or 0) * 256 + (third or 0)
    output[#output + 1] = encodeCharacter[floor(value / 262144) % 64]
    output[#output + 1] = encodeCharacter[floor(value / 4096) % 64]
    output[#output + 1] = second and encodeCharacter[floor(value / 64) % 64] or "="
    output[#output + 1] = third and encodeCharacter[value % 64] or "="
  end
  return concat(output)
end

---@param text string
---@return string decoded
function base64.decode(text)
  if type(text) ~= "string" then error("base64.decode: expected a string", 2) end
  if #text % 4 ~= 0 then error("base64.decode: invalid length", 2) end
  if text:find("[^A-Za-z0-9+/=]") or text:find("=[^=]") or text:find("===") then
    error("base64.decode: invalid encoding", 2)
  end

  local output = {}
  for index = 1, #text, 4 do
    local first = decodeCharacter[text:sub(index, index)]
    local second = decodeCharacter[text:sub(index + 1, index + 1)]
    local thirdCharacter = text:sub(index + 2, index + 2)
    local fourthCharacter = text:sub(index + 3, index + 3)
    local third = decodeCharacter[thirdCharacter]
    local fourth = decodeCharacter[fourthCharacter]

    if first == nil or second == nil or
       (third == nil and thirdCharacter ~= "=") or
       (fourth == nil and fourthCharacter ~= "=") or
       (thirdCharacter == "=" and fourthCharacter ~= "=") or
       ((thirdCharacter == "=" or fourthCharacter == "=") and index + 3 ~= #text) then
      error("base64.decode: invalid encoding", 2)
    end

    local value = first * 262144 + second * 4096 + (third or 0) * 64 + (fourth or 0)
    output[#output + 1] = char(floor(value / 65536) % 256)
    if third ~= nil then output[#output + 1] = char(floor(value / 256) % 256) end
    if fourth ~= nil then output[#output + 1] = char(value % 256) end
  end
  return concat(output)
end

return base64
