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

local key_mapping = {
  ['<ESC>'] = 'escape',
  ['<space>'] = 'space',
  ['<bkspc>'] = 'backspace',
  ['<del>'] = 'delete',
  ['\\<'] = 'shift+,',
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

local function reinitialise_mod()
  for key, _ in pairs(mods) do
    mods[key] = false
  end
end

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
  if #str>1 and str:sub(1,1) == '<' and str:sub(#str) == '>' then
    return res .. str:sub(2, #str-1)
  end
  if str:upper() == str then
    return res .. 'shift+' .. str:lower()
  end
  return res .. str
end

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

local test = {
  "<space>Q",
  "<space>C-x",
  "C-?",
  "A-\\<",
  "<ESC>",
  ":",
  "C-<left>"
}

for _, e in ipairs(test) do
  print(e, kb_modal.convert(e))
end

return kb_modal
