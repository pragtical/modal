---Compile Helix-style keys and modifiers into native strokes.
---@class plugins.modal.model.modal : modal.model
local kb_modal = {}

local shift_keys = {
  [":"] = ";",
  ["±"] = "§",
  ["~"] = "`",
  ["!"] = "1",
  ["@"] = "2",
  ["#"] = "3",
  ["$"] = "4",
  ["%"] = "5",
  ["^"] = "6",
  ["&"] = "7",
  ["*"] = "8",
  ["("] = "9",
  [")"] = "0",
  ["_"] = "-",
  ["+"] = "=",
  ["{"] = "[",
  ["}"] = "]",
  ["\""] = "'",
  ["|"] = "\\",
  ["<"] = ",",
  [">"] = ".",
  ["?"] = "/",
}

kb_modal.shifted_symbols = {}
for symbol, key in pairs(shift_keys) do
  kb_modal.shifted_symbols[key] = symbol
end

local key_mapping = {
  ['<ESC>'] = 'escape',
  ['<space>'] = 'space',
  ['<bkspc>'] = 'backspace',
  ['<del>'] = 'delete',
  ['<.>'] = '$',
  ['\\<'] = 'shift+,',
  ['$'] = '\\$',
}

local mods_key = {
  ['C-'] = 'ctrl',
  ['A-'] = 'alt',
  ['M-'] = 'gui',
}
local mods = {
  ['ctrl'] = false,
  ['alt'] = false,
  ['gui'] = false,
}

---Clear the pending modifier flags after consuming a stroke.
local function reinitialise_mod()
  for key, _ in pairs(mods) do
    mods[key] = false
  end
end

---Test for an uppercase ASCII letter.
---@param ch string
---@return boolean
local function is_capital(ch)
  return #ch == 1 and ch >= 'A' and ch <= 'Z'
end

---Translate one notation token and consume its pending modifiers.
---@param str string
---@return string stroke
local function process(str)
  if #str == 0 then
    return ''
  end
  local res = ''
  for key, flg in pairs(mods) do
    if flg then
      res = res .. key .. '+'
    end
  end
  reinitialise_mod()
  if key_mapping[str] ~= nil then
    return res .. key_mapping[str]
  end
  if shift_keys[str] ~= nil then
    return res .. 'shift+' .. shift_keys[str]
  end
  if #str > 1 and str:sub(1, 1) == '<' and str:sub(#str) == '>' then
    return res .. str:sub(2, #str - 1)
  end
  if is_capital(str) then
    return res .. 'shift+' .. str:lower()
  end
  return res .. str
end

---Append a nonempty stroke to the space-separated result.
---@param res string
---@param key string
---@return string
local function append(res, key)
  if #key == 0 then
    return res
  end
  if #res > 0 then
    return res .. ' ' .. key
  else
    return key
  end
end

---Compile adjacent keys, modifier prefixes and angle-bracket key names into
---native strokes.
---@param str string
---@return string strokes
function kb_modal.convert(str)
  local subs = ''
  local res = ''
  local prev = str:sub(1, 1)
  for i = 2, #str do
    local c = str:sub(i, i)
    if prev == '<' then
      prev = ''
      subs = '<' .. c
    elseif c == '<' and prev ~= '\\' then
      res = append(res, process(prev))
      prev = ''
      subs = '<'
    elseif #subs > 0 and c == '>' then
      subs = subs .. '>'
      res = append(res, process(subs))
      subs = ''
      prev = ''
    elseif #subs > 0 then
      subs = subs .. c
    else
      if prev ~= '' then
        local cmp = prev .. c
        if key_mapping[cmp] ~= nil then
          res = append(res, process(key_mapping[cmp]))
          prev = ''
        elseif mods_key[cmp] ~= nil then
          mods[mods_key[cmp]] = true
          prev = ''
        else
          res = append(res, process(prev))
          prev = c
        end
      else
        prev = c
      end
    end
  end
  if prev ~= '' then
    res = append(res, process(prev))
  end
  return res
end

return kb_modal
