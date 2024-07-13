-- mod-version:3
local core = require "core"
local command = require "core.command"
local keymap = require "core.keymap"
local style = require "core.style"
local StatusView = require "core.statusview"
local CommandView = require "core.commandview"
local DocView = require "core.docview"
local RootView = require "core.rootview"
local common = require "core.common"
local config = require "core.config"

local modal = {}
core.modal = modal

config.plugins.modal = common.merge({
  base_mode = nil,
  modes = {},
  on_key_callbacks = {},
  carets = {},
  helpers = {},
  show_helpers = true,
}, config.plugins.modal)

modal.caret_style = { NORMAL = 0, BAR = 1, }

modal.align = {
  LEFT = 1, CENTER = 2, RIGHT = 3
}
modal.config = {
  ["helper"] = {
    ["show"] = true,
  }
}
-- Helper styling
style["helper"] = {
  ["background"] = { 0, 0, 0, 200 },
  ["text"] = { 255, 255, 255, 220 },
  ["padding"] = 10,
  ["margin"] = 10,
  ["alignement"] = modal.align.LEFT,
}

modal.internal = {}
modal.internal.last_command = nil
modal.internal.keystrokes = {}
modal.internal.active_help = nil

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
  if dv() ~= nil and dv().modal ~= nil then
    return dv().modal.mode
  else
    return nil
  end
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
  local view = dv()
  local len = #seq
  for key, _ in pairs(view.modal.keymap) do
    local skey = string.sub(key, 1, len)
    if skey == seq then
      return true
    end
  end
  return false
end

local function eval_cmd(cmd)
  if cmd == nil then
    return nil
  elseif type(cmd) == "table" then
    for _, scmd in pairs(cmd) do
      eval_cmd(scmd)
    end
  elseif type(cmd) == "string" then
    if command.map[cmd] then
      command.perform(cmd)
    else
      local view = dv()
      if view then
        for i = 1, #cmd do
          local scmd = string.sub(cmd, i, i)
          eval_cmd(view.modal.keymap[scmd])
        end
      end
    end
  elseif type(cmd) == "function" then
    cmd()
  end
end

function modal.redo_command()
  if modal.internal.last_command ~= nil then
    for _ in 1, modal.internal.last_command.num do
      eval_cmd(modal.internal.last_command.cmd)
    end
  end
end

function modal.eval_helper(seq)
  local view = dv()
  if config.plugins.modal.show_helpers == true and view.modal.helpers ~= nil then
    modal.internal.active_help = view.modal.helpers[seq]
  end
end

function modal.eval_current_strokes()
  modal.internal.active_help = nil
  local view = dv()
  local N_repeat = ''
  local seq = ''
  local cmd = nil
  for i = 1, #modal.internal.keystrokes do
    if #seq == 0 and is_number(modal.internal.keystrokes[i]) then
      N_repeat = N_repeat .. modal.internal.keystrokes[i]
    else
      seq = seq .. modal.internal.keystrokes[i]
    end
  end
  if view.modal.keymap[seq] ~= nil then
    cmd = view.modal.keymap[seq]
    local N = 1
    modal.internal.keystrokes = {}
    if #N_repeat > 0 then
      N = math.floor(tonumber(N_repeat) or error("String is not a number"))
    end
    modal.internal.last_command = {
      num = N,
      cmd = seq
    }
    for _ = 1, N do
      eval_cmd(cmd)
    end
  elseif not modal.is_partial_command(seq) then
    cmd = nil
    modal.internal.keystrokes = {}
  else
    modal.eval_helper(seq)
  end
  return cmd ~= nil
end

modal.on_key_released__orig = keymap.on_key_released

function keymap.on_key_released(k)
  if k == 'left shift' or k == 'right shift' then
    key_modifiers[k] = false
  end
  return modal.on_key_released__orig(k)
end

modal.on_key_pressed__orig = keymap.on_key_pressed

function modal.on_key_passtrought(k, ...)
  local key = modal.convert_stroke(k)
  if key and #key > 1 then
    modal.internal.keystrokes[#modal.internal.keystrokes + 1] = key
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
    modal.internal.keystrokes[#modal.internal.keystrokes + 1] = key
    modal.eval_current_strokes()
  end
  return true
end

local caret_width__orig = style.caret_width
function modal.set_mode(mode_id)
  local view = dv()
  if view ~= nil then
    local c_style = config.plugins.modal.carets[mode_id]
    if c_style == nil then
      c_style = modal.caret_style.NORMAL
    end
    local width = caret_width__orig
    if c_style == modal.caret_style.BAR and core.active_view.get_font then
      width = core.active_view:get_font():get_width(' ')
    end
    style.caret_width = width
    view.modal = {
      mode = mode_id,
      callback = config.plugins.modal.on_key_callbacks[mode_id],
      helpers = config.plugins.modal.helpers[mode_id],
      keymap = config.plugins.modal.keymaps[mode_id],
      caret = width
    }
    if view.modal.callback == nil then
      view.modal.callback = modal.on_key_pressed__orig
    end
  end
end

function keymap.on_key_pressed(k, ...)
  local view = dv()
  if view:is(CommandView) then
    return modal.on_key_pressed__orig(k, ...)
  end

  if view.modal and view.modal.callback then
    return view.modal.callback(k, ...)
  else
    return modal.on_key_pressed__orig(k, ...)
  end
end

local DocView__update__orig = DocView.update
function DocView:update(...)
  local view = dv()
  if view:is(CommandView) then
    style.caret_width = caret_width__orig
  else
    if view.modal == nil or view.modal.mode == nil then
      modal.set_mode(config.plugins.modal.base_mode)
    end
    if view.modal and view.modal.caret ~= nil then
      style.caret_width = view.modal.caret
    else
      style.caret_width = caret_width__orig
    end
  end
  DocView__update__orig(self, ...)
end

if core.status_view:get_item("status:mode") == nil then
  core.status_view:add_item({
    name = "status:mode",
    alignment = StatusView.Item.LEFT,
    get_item = function()
      local mode_str = get_mode()
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

local function pos(win_size, width, height)
  local y = win_size.y - style.helper.margin - style.helper.padding * 2 - height
  if style.helper.alignement == modal.align.RIGHT then
    return style.helper.margin, y
  elseif style.helper.alignement == modal.align.CENTER then
    return win_size.x / 2 - width / 2 - style.helper.padding, y
  else
    return win_size.x - style.helper.margin - style.helper.padding * 2 - width, y
  end
end

local function spaces(key_len, spacing)
  local res = ''
  for _ = 1, spacing - key_len do
    res = res .. ' '
  end
  return res
end

local rvDraw = RootView.draw
function RootView:draw(...)
  rvDraw(self, ...)
  if modal.internal.active_help ~= nil then
    local font = style.code_font
    local lines = {}
    local box_h = 0
    local box_w = 0
    for _, kv in ipairs(modal.internal.active_help) do
      local line = kv[1] .. spaces(#kv[1], 8) .. kv[2]
      local line_w = font:get_width(line)
      lines[#lines + 1] = line
      box_h = box_h + font:get_height()

      if line_w > box_w then
        box_w = line_w
      end
    end

    local x, y = pos(self.size, box_w, box_h)
    local w = box_w + style.helper.padding * 2
    local h = box_h + style.helper.padding * 2
    core.redraw = true
    local bg = style.helper.background
    local fg = style.helper.text
    renderer.draw_rect(x, y, w, h, bg)
    x = x + style.helper.padding
    y = y + style.helper.padding
    for _, line in ipairs(lines) do
      renderer.draw_text(font, line, x, y, fg)
      y = y + font:get_height()
    end
  end
end

core.log("MODAL Ready")
return modal
