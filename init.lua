-- mod-version:3
local core = require "core"
local command = require "core.command"
local keymap = require "core.keymap"
local style = require "core.style"
local StatusView = require "core.statusview"
local CommandView = require "core.commandview"
local DocView = require "core.docview"

require "plugins.modal.helper"

local modal = {}
core.modal = modal

modal.base_mode = 0
modal.modes = {}
modal.last_command = nil

modal.keymaps = {}
modal.on_key_callbacks = {}

modal.caret_style = { NORMAL = 0, BAR = 1, }
modal.carets = {}
modal.keystrokes = {}
modal.helpers = {}

modal.active_help = nil

modal.align = {
  LEFT = 1, CENTER = 2, RIGHT = 3
}
modal.config = {
  ["helper"] = {
    ["show"] = true,
    ["alignement"] = modal.align.RIGHT,
  }
}

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

local function get_mode()
  if dv().doc ~= nil then
    return dv().doc.modal
  else
    return 0
  end
end

local function get_mode_str()
  local mode = get_mode()
  if mode == nil or mode == 0 then
    return nil
  end
  for k, v in pairs(modal.modes) do
    if v == mode then
      return k
    end
  end
  return nil
end

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
  local mode = get_mode()
  for key, _ in pairs(modal.keymaps[mode]) do
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
    local mode = get_mode()
    if string.find(cmd, ":") then
      command.perform(cmd)
    elseif modal.keymaps[mode][cmd] ~= nil then
      eval_cmd(modal.keymaps[mode][cmd])
    end
  elseif type(cmd) == "function" then
    cmd()
  end
end

function modal.redo_command()
  if modal.last_command ~= nil then
    eval_cmd(modal.last_command)
  end
end

function modal.eval_helper(seq)
  local mode = get_mode()
  if modal.config.helper.show == true and modal.helpers[mode] ~= nil then
    modal.active_help = modal.helpers[mode][seq]
  end
end

function modal.eval_current_strokes()
  modal.active_help = nil
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
  local mode = get_mode()
  if modal.keymaps[mode][seq] ~= nil then
    cmd = modal.keymaps[mode][seq]
    local N = 1
    modal.keystrokes = {}
    modal.last_command = seq
    if #N_repeat > 0 then
      N = math.floor(tonumber(N_repeat) or error("String is not a number"))
    end
    for _ = 1, N do
      eval_cmd(cmd)
    end
  elseif not modal.is_partial_command(seq) then
    cmd = nil
    modal.keystrokes = {}
  else
    modal.eval_helper(seq)
  end
  return cmd ~= nil
end

modal.on_key_released__orig = keymap.on_key_released

function keymap.on_key_released(k)
  local mode = get_mode()
  if mode ~= 0 then
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
function modal.set_mode(mode_index)
  if dv().doc ~= nil then
    dv().doc.modal = mode_index
    local c_style = modal.carets[mode_index]
    if c_style == nil then
      c_style = modal.caret_style.NORMAL
    end
    local width = caret_width__orig
    if c_style == modal.caret_style.BAR and core.active_view.get_font then
      width = core.active_view:get_font():get_width(' ')
    end
    style.caret_width = width
  end
end

function keymap.on_key_pressed(k, ...)
  local mode = get_mode()
  if dv():is(CommandView) or mode == 0 then
    return modal.on_key_pressed__orig(k, ...)
  end
  if modal.on_key_callbacks[mode] then
    return modal.on_key_callbacks[mode](k, ...)
  else
    return modal.on_key_pressed__orig(k, ...)
  end
end

local DocView__update__orig = DocView.update
function DocView:update(...)
  local mode = get_mode()
  if dv():is(CommandView) then
    style.caret_width = caret_width__orig
  else
    if mode == nil or mode == 0 then
      modal.set_mode(modal.base_mode)
      mode = modal.base_mode
    end
    local c_style = modal.carets[mode]
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

if core.status_view:get_item("status:mode") == nil then
  core.status_view:add_item({
    name = "status:mode",
    alignment = StatusView.Item.LEFT,
    get_item = function()
      local mode_str = get_mode_str()
      if mode_str == nil then
        return { "NO MODE", }
      else
        return { mode_str, }
      end
    end,
    position = 1,
    tooltip = "mode",
    separator = core.status_view.separator2
  })
end

core.log("MODAL Ready")
return modal
