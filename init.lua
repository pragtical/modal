-- mod-version:3
local core = require "core"
local command = require "core.command"
local keymap = require "core.keymap"
local style = require "core.style"
local StatusView = require "core.statusview"
local CommandView = require "core.commandview"
local DocView = require "core.docview"

local modal = {}
core.modal = modal


modal.mode = 0
modal.modes = {}

modal.keymaps = {}
modal.on_key_callbacks = {}

modal.caret_style = { NORMAL = 0, BAR = 1, }
modal.carets = {}
modal.keystrokes = {}


function modal.go_to_mode(mode)
  return function()
    modal.set_mode(mode)
  end
end

local function dv()
  return core.active_view
end

-- local function doc()
--   return core.active_view.doc
-- end

local key_mapping = {
  ['escape'] = "<ESC>",
  ['ctrl'] = 'C-',
  ['alt'] = 'A-',
  ['shift'] = '',    -- modifier
  ['capslock'] = '', -- modifier
  ['gui'] = 'M-',
  ['space'] = '<space>',
  ['backspace'] = '<bkspc>',
  ['delete'] = '<del>'
}

local key_modifiers = {
  ["left shift"] = false,
  ["right shift"] = false,
  ["capslock"] = false,
}

local shift_keys = {
  [";"] = ":",
  ["§"] = "±",
  ["`"] = "~",
  ["1"] = "!",
  ["2"] = "@",
  ["3"] = "#",
  ["4"] = "$",
  ["5"] = "%",
  ["6"] = "^",
  ["7"] = "&",
  ["8"] = "*",
  ["9"] = "(",
  ["0"] = ")",
  ["-"] = "_",
  ["="] = "+",
  ["["] = "{",
  ["]"] = "}",
  ["'"] = "\"",
  ["\\"] = "|",
  [","] = "<",
  ["."] = ">",
  ["/"] = "?",
}

local function apply_mods(key)
  local shift = key_modifiers['left shift'] or key_modifiers['right shift']
  if shift and shift_keys[key] then
    return shift_keys[key]
  end
  local capslock = key_modifiers['capslock']
  if not (shift == capslock) then
    return string.upper(key)
  end
  return key
end

function modal.convert_stroke(key)
  if key_modifiers[key] ~= nil then
    key_modifiers[key] = not key_modifiers[key]
    return ''
  end
  for seq, val in pairs(key_mapping) do
    if string.find(key, seq) then
      return val
    end
  end
  if #key > 1 then
    return "<" .. key .. ">"
  end
  return apply_mods(key)
end

local function is_number(x)
  return x >= '0' and x <= '9'
end

function modal.is_partial_command(seq)
  local len = #seq
  for key, _ in pairs(modal.keymaps[modal.mode]) do
    local skey = string.sub(key, 1, len)
    if skey == seq then
      return true
    end
  end
  return false
end

local function eval_cmd(cmd)
  if type(cmd) == "table" then
    for _, scmd in pairs(cmd) do
      eval_cmd(scmd)
    end
  elseif type(cmd) == "string" then
    if string.find(cmd, ":") then
      command.perform(cmd)
    elseif modal.keymaps[modal.mode][cmd] ~= nil then
      eval_cmd(modal.keymaps[modal.mode][cmd])
    end
  elseif type(cmd) == "function" then
    cmd()
  end
end

function modal.eval_current_strokes()
  local N_repeat = ''
  local seq = ''
  local cmd = nil
  for i = 1, #modal.keystrokes do
    if #seq == 0 and is_number(modal.keystrokes[i]) then
      N_repeat = N_repeat .. modal.keystrokes[i]
    else
      seq = seq .. modal.keystrokes[i]
    end
  end
  if modal.keymaps[modal.mode][seq] ~= nil then
    cmd = modal.keymaps[modal.mode][seq]
    local N = 1
    modal.keystrokes = {}
    if #N_repeat > 0 then
      N = math.floor(tonumber(N_repeat) or error("String is not a number"))
    end
    for _ = 1, N do
      eval_cmd(cmd)
    end
  elseif not modal.is_partial_command(seq) then
    cmd = nil
    modal.keystrokes = {}
  end

  return cmd ~= nil
end

modal.on_key_released__orig = keymap.on_key_released

function keymap.on_key_released(k)
  if modal.mode ~= 0 then
    if k == 'left shift' or k == 'right shift' then
      key_modifiers[k] = false
    end
  end
  return modal.on_key_released__orig(k)
end

modal.on_key_pressed__orig = keymap.on_key_pressed

function modal.on_key_passtrought(k, ...)
  local key = modal.convert_stroke(k)
  if key and #key > 1 then
    modal.keystrokes[#modal.keystrokes + 1] = key
    if modal.eval_current_strokes() then
      return true
    end
  end
  return modal.on_key_pressed__orig(k, ...)
end

function modal.on_key_command_only(k, ...)
  if string.find(k, 'click') or string.find(k, 'wheel') then
    return modal.on_key_pressed__orig(k, ...)
  end
  local key = modal.convert_stroke(k)
  if key and #key > 0 then
    modal.keystrokes[#modal.keystrokes + 1] = key
    modal.eval_current_strokes()
  end
  return true
end

local caret_width__orig = style.caret_width
core.log(">> %d", style.caret_width)
function modal.set_mode(mode_index)
  modal.mode = mode_index
  local c_style = modal.carets[mode_index]
  core.log("STYLE: %s", tostring(c_style))
  if c_style == nil then
    c_style = modal.caret_style.NORMAL
  end
  local width = caret_width__orig
  if c_style == modal.caret_style.BAR and core.active_view.get_font then
    width = core.active_view:get_font():get_width(' ')
  end
  style.caret_width = width
  core.log(style.caret_width)
end

function keymap.on_key_pressed(k, ...)
  if dv():is(CommandView) or modal.mode == 0 then
    return modal.on_key_pressed__orig(k, ...)
  end
  if modal.on_key_callbacks[modal.mode] then
    return modal.on_key_callbacks[modal.mode](k, ...)
  else
    return modal.on_key_pressed__orig(k, ...)
  end
end

local DocView__update__orig = DocView.update
function DocView:update(...)
  if dv():is(CommandView) or modal.mode == 0 then
    style.caret_width = caret_width__orig
  else
    local c_style = modal.carets[modal.mode]
    if c_style == nil then
      c_style = modal.caret_style.NORMAL
    end
    local width = caret_width__orig
    if c_style == modal.caret_style.BAR and core.active_view.get_font then
      width = core.active_view:get_font():get_width(' ')
    end
    style.caret_width = width
  end
  DocView__update__orig(self, ...)
end

core.status_view:add_item({
  name = "status:mode",
  alignment = StatusView.Item.LEFT,
  get_item = function()
    if modal.mode == 0 then
      return { "NO MODE", }
    else
      return { modal.modes[modal.mode], }
    end
  end,
  position = -1,
  tooltip = "mode",
  separator = core.status_view.separator2
})

modal.set_mode(modal.mode)
return modal
