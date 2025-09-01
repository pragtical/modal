local keymap = {}


local macos = PLATFORM == "Mac OS X"

local modkeys_os = require("core.modkeys-" .. (macos and "macos" or "generic"))

local modkey_map = modkeys_os.map

keymap.modkeys = modkeys_os.keys


function keymap.active_modifiers()
  for k, v in pairs(keymap.modkeys) do
    if k ~= "shift" and (v ~= nil and v == true) then
      return true
    end
  end
  return false
end


---Normalizes a stroke sequence to follow the modkeys table
---@param stroke string
---@return string
function keymap.normalize_stroke(stroke)
  local stroke_table = {}
  for key in stroke:gmatch("[^+]+") do
    table.insert(stroke_table, key)
  end
  table.sort(stroke_table, function(a, b)
    if a == b then return false end
    for _, mod in ipairs(keymap.modkeys) do
      if a == mod or b == mod then
        return a == mod
      end
    end
    return a < b
  end)
  return table.concat(stroke_table, "+")
end

---Generates a stroke sequence including currently pressed mod keys.
---@param key string
---@return string
function keymap.key_to_stroke(key)
  local keys = { key }
  for _, mk in ipairs(keymap.modkeys) do
    if keymap.modkeys[mk] then
      table.insert(keys, mk)
    end
  end
  return keymap.normalize_stroke(table.concat(keys, "+"))
end

function keymap.released_modifiers(k)
  local mk = modkey_map[k]
  if mk then
    keymap.modkeys[mk] = false
  end
end

function keymap.pressed_modifiers(k)
  local mk = modkey_map[k]
  if mk then
    keymap.modkeys[mk] = true
    -- work-around for windows where `altgr` is treated as `ctrl+alt`
    if mk == "altgr" then
      keymap.modkeys["ctrl"] = false
    end
    return true
  end
  return false
end

keymap.non_text_keys = {
  ["escape"] = true,
  ["left"] = true,
  ["right"] = true,
  ["up"] = true,
  ["down"] = true,
  ["pageup"] = true,
  ["pagedown"] = true,
  ["home"] = true,
  ["return"] = true,
}

return keymap
