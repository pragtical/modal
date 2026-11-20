---Track host modifiers and construct the strokes used for modal lookup.
---@class plugins.modal.keymap
local keymap = {}


local macos = PLATFORM == "Mac OS X"

local modkeys_os = require("core.modkeys-" .. (macos and "macos" or "generic"))

local modkey_map = modkeys_os.map

keymap.modkeys = { table.unpack(modkeys_os.keys) }


---Check whether a modifier other than Shift is held.
---@return boolean
function keymap.active_modifiers()
  for k, v in pairs(keymap.modkeys) do
    if k ~= "shift" and (v ~= nil and v == true) then
      return true
    end
  end
  return false
end


---Order the modifiers of one stroke using the platform's modifier precedence.
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

---Combine a key name with the currently pressed modifiers.
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

---Clear the pressed state for a physical modifier key.
---@param k string
function keymap.released_modifiers(k)
  local mk = modkey_map[k]
  if mk then
    keymap.modkeys[mk] = false
  end
end

---Record a physical modifier press, including the AltGr workaround.
---@param k string
---@return boolean handled True for a recognized modifier.
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
  ["end"] = true,
  ["tab"] = true,
  ["delete"] = true,
  ["backspace"] = true,
  ["insert"] = true,
}

return keymap
