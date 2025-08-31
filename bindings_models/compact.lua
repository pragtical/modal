-- C-? => C+S+/ => ctrl+shift+/
-- C-<space> => C+space => ctrl+space
-- gg => g g => g g
-- gG => g S+g => g shift+g

---------------
-- C+ -> ctrl+
-- S+ -> shift+
-- A+ -> alt+
-- M+ -> gui+
---------------

local key_mapping = {
  ['C+'] = 'ctrl+',
  ['S+'] = 'shift+',
  ['A+'] = 'alt+',
  ['M+'] = 'gui+'
}

local kb_compact = {}

function kb_compact.convert(str)
  local res = ''
  local prev = str:sub(1, 1)
  for i = 2, #str do
    if #prev > 0 then
      local c = str:sub(i, i)
      local cmp = prev .. c
      if key_mapping[cmp] ~= nil then
        res = res .. key_mapping[cmp]
        prev = ''
      else
        res = res .. prev
        prev = c
      end
    else
      prev = str:sub(i, i)
    end
  end
  if prev ~= '' then
    res = res .. prev
  end
  return res
end

return kb_compact
