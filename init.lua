-- mod-version:3
local core = require "core"
local command = require "core.command"
local keymap = require "core.keymap"
local style = require "core.style"
local StatusView = require "core.statusview"
local CommandView = require "core.commandview"
local NagView = require "core.nagview"
local DocView = require "core.docview"
local RootView = require "core.rootview"
local common = require "core.common"
local config = require "core.config"

local KeyMapView = require "plugins.modal.keymapview"
local modalkm = require "plugins.modal.keymap"
local kb_modal = require "plugins.modal.bindings_models.modal"

local modal = {}


core.modal = modal

config.plugins.modal = common.merge({
  base_mode = nil,
  modes = {},
  on_key_callbacks = {},
  carets = {},
  helpers = {},
  keymaps = {},
  show_helpers = true,
  status_bar = {
    mode = true,
    strokes = true,
  }
}, config.plugins.modal)

modal.kb_model = kb_modal
modal.bindings = {}
modal.helper_bindings = {}
modal.ignore_text = true

modal.caret_style = { NORMAL = 0, BAR = 1, }

modal.align = {
  LEFT = 1, CENTER = 2, RIGHT = 3
}
modal.config = {
  helper = {
    show = true,
  },
  notification = {
    timeout = 0.5,
    fading = 0.1,
    show = true,
  }
}

modal.fns = {}

-- Helper styling
style["helper"] = {
  ["background"] = { 0, 0, 0, 200 },
  ["text"] = { 255, 255, 255, 220 },
  ["padding"] = 10,
  ["margin"] = 10,
  ["alignement"] = modal.align.LEFT,
}

function modal.go_to_mode(mode)
  if mode ~= nil then
    local fn = function()
      modal.set_mode(mode)
    end
    local key = "modal:set-mode-" .. mode
    modal.fns[fn] = key
    return fn
  end
end

local function dv()
  return core.active_view
end


function modal.get_mode()
  if dv() ~= nil and dv().modal ~= nil then
    return dv().modal.mode
  else
    return nil
  end
end

local function apply_mods(key)
  local shift = modal.key_modifiers['left shift'] or modal.key_modifiers['right shift']
  if shift and modal.shift_keys[key] then
    return modal.shift_keys[key]
  end
  local capslock = modal.key_modifiers['capslock']
  if not (shift == capslock) and #key == 1 then
    key = string.upper(key)
  end
  for label, state in pairs(modal.key_modifiers) do
    if state and modal.key_mapping[label] then
      key = modal.key_mapping[label] .. key
    end
  end
  return key
end

function modal.convert_stroke(key)
  if modal.key_modifiers[key] ~= nil then
    modal.key_modifiers[key] = not modal.key_modifiers[key]
    return ''
  end

  key = apply_mods(key)
  return key
end

local function statusbar_mode()
  local mode_str = modal.get_mode()
  if mode_str == nil or type(mode_str) ~= "string" then
    return { "NO MODE", }
  else
    return { mode_str, }
  end
end

local function statusbar_strokes()
  local view = dv()
  local str = ""
  if view ~= nil and view.modal ~= nil then
    str = view.modal.keyhelper
  end
  return { str }
end

function modal.set_status_bar()
  if config.plugins.modal.status_bar.mode == true and core.status_view:get_item("status:modal_mode") == nil then
    core.status_view:add_item({
      name = "status:modal_mode",
      alignment = StatusView.Item.LEFT,
      get_item = statusbar_mode,
      position = 1,
      tooltip = "mode",
      separator = core.status_view.separator2
    })
  elseif config.plugins.modal.status_bar.mode == false and core.status_view:get_item("status:modal_mode") ~= nil then
    core.status_view:remove_item("status:modal_mode")
  end

  if config.plugins.modal.status_bar.strokes == true and core.status_view:get_item("status:modal_strokes") == nil then
    core.status_view:add_item({
      name = "status:modal_strokes",
      alignment = StatusView.Item.LEFT,
      get_item = statusbar_strokes,
      position = 2,
      tooltip = "current keystrokes",
      separator = core.status_view.separator2
    })
  elseif config.plugins.modal.status_bar.strokes == false and core.status_view:get_item("status:modal_strokes") ~= nil then
    core.status_view:remove_item("status:modal_strokes")
  end
end

local function is_number(x)
  return x >= '0' and x <= '9'
end

function modal.split_command(cmd)
  local array = {}
  for str in string.gmatch(cmd, '([^ ]+)') do
    table.insert(array, str)
  end
  return array
end

local function match_command(seq, cmd, full)
  local split_seq = modal.split_command(seq)
  local split_cmd = modal.split_command(cmd)
  if (full and #split_seq == #split_cmd) or (not full and #split_seq <= #split_cmd) then
    for i = 1, #split_seq do
      if split_seq[i] ~= split_cmd[i] and split_cmd[i] ~= "$" then
        return false
      end
    end
    return true
  end
  return false
end

function modal.is_partial_command(seq)
  local view = dv()
  for key, _ in pairs(view.modal.keymap) do
    if match_command(seq, key, false) then
      return true
    end
  end
  return false
end

function modal.get_command(seq)
  local view = dv()
  if view.modal.keymap[seq] ~= nil then
    return view.modal.keymap[seq]
  end
  for key, cmd in pairs(view.modal.keymap) do
    if match_command(seq, key, true) then
      return cmd
    end
  end
  return nil
end

function modal.eval_cmd(cmd)
  if cmd == nil then
    return nil
  elseif type(cmd) == "table" then
    for _, scmd in pairs(cmd) do
      modal.eval_cmd(scmd)
    end
  elseif type(cmd) == "string" then
    if command.map[cmd] then
      command.perform(cmd)
    else
      local view = dv()
      if view and view.modal.keymap[cmd] ~= nil then
        modal.eval_cmd(view.modal.keymap[cmd])
      elseif view then
        error("Command `" .. cmd .. "` not found")
      end
    end
  elseif type(cmd) == "function" then
    cmd()
  end
end

function modal.redo_command()
  local view = dv()
  if view.modal.last_command ~= nil then
    local last_cmd = view.modal.last_command
    view.modal.current_command = last_cmd
    for _ = 1, last_cmd.num do
      modal.eval_cmd(last_cmd.cmd)
    end
  end
end

function modal.eval_helper(seq)
  local view = dv()
  if config.plugins.modal.show_helpers == true and view.modal.helpers ~= nil then
    view.modal.active_help = view.modal.helpers[seq]
  end
end

function modal.eval_current_strokes()
  local view = dv()
  if view.modal then
    view.modal.active_help = nil
    local N_repeat = ''
    local seq = ''
    view.modal.keyhelper = ''
    for i = 1, #view.modal.keystrokes do
      if #seq == 0 and is_number(view.modal.keystrokes[i]) then
        N_repeat = N_repeat .. view.modal.keystrokes[i]
      else
        if #seq > 0 then
          seq = seq .. ' ' .. view.modal.keystrokes[i]
        else
          seq = view.modal.keystrokes[i]
        end
      end
      if #view.modal.keyhelper > 0 then
        view.modal.keyhelper = view.modal.keyhelper .. " " .. view.modal.keystrokes[i]
      else
        view.modal.keyhelper = view.modal.keystrokes[i]
      end
    end
    local cmd = modal.get_command(seq)
    if cmd ~= nil then
      local N = 1
      view.modal.keystrokes = {}
      if #N_repeat > 0 then
        N = math.floor(tonumber(N_repeat) or error("String is not a number"))
      end
      view.modal.current_command = {
        num = N,
        n_repeat = N_repeat,
        cmd = cmd,
        seq = seq,
      }
      for _ = 1, view.modal.current_command.num do
        modal.eval_cmd(cmd)
      end
      view.modal.last_command = view.modal.current_command
    elseif not modal.is_partial_command(seq) then
      view.modal.keystrokes = {}
    else
      modal.eval_helper(seq)
    end
    return cmd ~= nil
  end
end

local root_on_text_input = RootView.on_text_input

function RootView.on_text_input(dview, text)
  if not modal.ignore_text then
    root_on_text_input(dview, text)
  else
    local view = dv()
    if view ~= nil and view.modal ~= nil then
      view.modal.last_input = text
      modal.eval_current_strokes()
    end
  end
end

modal.on_key_released__orig = keymap.on_key_released

function keymap.on_key_released(k)
  modalkm.released_modifiers(k)
  return modal.on_key_released__orig(k)
end

modal.on_key_pressed__orig = keymap.on_key_pressed

function modal.on_key_passthrough(k, mod, ...)
  if not mod then
    local stroke = modalkm.key_to_stroke(k)
    if stroke and #stroke > 1 then
      dv().modal.keystrokes[#dv().modal.keystrokes + 1] = stroke
      if modal.eval_current_strokes() then
        return true
      end
    end
  end
  modal.ignore_text = false
  return modal.on_key_pressed__orig(k, ...)
end

function modal.on_key_command_only(k, mod, ...)
  if string.find(k, 'click') or string.find(k, 'wheel') then
    return modal.on_key_pressed__orig(k, ...)
  end
  if not mod then
    modal.ignore_text = true
    local stroke = modalkm.key_to_stroke(k)
    if stroke and #stroke > 0 then
      dv().modal.keystrokes[#dv().modal.keystrokes + 1] = stroke
      -- if #k > 1 and k == stroke then
      --   modal.eval_current_strokes()
      -- end
      return false
    end
  end
  return true
end

local function convert_action_to_string(action)
  if type(action) == "string" then
    return action
  elseif type(action) == "function" then
    if modal.fns[action] ~= nil then
      return modal.fns[action]
    end
    for k, v in pairs(modal) do
      if v == action then
        return k
      end
    end
    return "unknow:" .. tostring(action)
  else
    return "ERROR<" .. tostring(action) .. ">"
  end
end

local function show_help(mode, keys)
  if dv() ~= nil and dv().modal ~= nil then
    local helper = {}
    for strokes, action in pairs(keys) do
      local action_str = ""
      if type(action) == "table" then
        for i, v in pairs(action) do
          if i > 1 then
            action_str = action_str .. ", "
          end
          action_str = action_str .. convert_action_to_string(v)
        end
      else
        action_str = convert_action_to_string(action)
      end
      helper[#helper + 1] = { strokes, action_str }
    end
    local node = core.root_view:get_active_node_default()
    node:add_view(KeyMapView(mode, helper))
  end
end

local function modal_help()
  local mode = modal:get_mode()
  if mode ~= nil then
    local key_map = modal.bindings[mode]
    if key_map ~= nil then
      show_help(mode, key_map)
    end
  end
end

modal.help = modal_help

local function get_keymap(mode_id)
  local map = modal.bindings[mode_id]
  if map ~= nil then
    return map
  end
  return {}
end

local function get_helpers(mode_id)
  local helpers = modal.helper_bindings[mode_id]
  if helpers ~= nil then
    return helpers
  end
  return {}
end

local function get_callback(mode_id)
  local fn = config.plugins.modal.on_key_callbacks[mode_id]
  if fn == nil then
    return modal.on_key_passthrough
  else
    return fn
  end
end

local caret_width__orig = style.caret_width
function modal.set_mode(mode_id)
  if mode_id ~= nil and mode_id ~= 0 then
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
      if view.modal == nil then
        view.modal = {
          mode = mode_id,
          callback = get_callback(mode_id),
          helpers = get_helpers(mode_id),
          keymap = get_keymap(mode_id),
          caret = width,
          keystrokes = {},
          last_command = nil,
          last_input = nil,
          current_command = nil,
          keyhelper = "",
          active_help = nil,
          notifications = {},
        }
      else
        view.modal.keyhelper = ""
        view.modal.mode = mode_id
        view.modal.callback = get_callback(mode_id)
        view.modal.helpers = get_helpers(mode_id)
        view.modal.keymap = get_keymap(mode_id)
        view.modal.caret = width
      end
      if view.modal.callback == nil then
        core.log("MODAL: no callback for mode %s", mode_id)
        view.modal.callback = modal.on_key_pressed__orig
      end
    end
    modal.notify(mode_id, false)
  end
end

function keymap.on_key_pressed(k, ...)
  local mod = modalkm.pressed_modifiers(k)
  local view = dv()
  if view:is(CommandView) or view:is(NagView) then
    return modal.on_key_pressed__orig(k, ...)
  end
  if view.modal and view.modal.callback then
    return view.modal.callback(k, mod, ...)
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


function modal.notify(msg, persistent)
  table.insert(dv().modal.notifications, {
    text = msg,
    mode = persistent,
    timestamp = system.get_time(),
  })
end

local function get_last_notification()
  local view = dv()
  if view.modal then
    local time = system.get_time()
    local to_remove = 0
    local result, fading = nil, 1.0
    for i = #view.modal.notifications, 1, -1 do
      local notification = view.modal.notifications[i]
      local t = time - notification.timestamp
      if notification.mode or t <= modal.config.notification.timeout then
        result = notification
        break
      elseif t < (modal.config.notification.timeout + modal.config.notification.fading) then
        result = notification
        fading = 1.0 - (t - modal.config.notification.timeout) / modal.config.notification.fading
        break
      else
        to_remove = to_remove + 1
      end
    end
    if to_remove > 0 then
      for _ = 1, to_remove do
        table.remove(view.modal.notifications, #view.modal.notifications)
      end
    end
    return result, fading
  else
    return nil, 1.0
  end
end

local function copy_color(color)
  return { color[1], color[2], color[3], color[4] }
end



local rvDraw = RootView.draw
function RootView:draw(...)
  rvDraw(self, ...)
  if dv().modal then
    if modal.config.notification.show then
      local notification, fading = get_last_notification()
      if notification ~= nil then
        local msg = notification.text
        local font = style.code_font
        local h = font:get_height() + style.helper.padding * 2
        local w = font:get_width(msg) + style.helper.padding * 2
        local x = dv().position.x + style.helper.margin
        local y = dv().position.y + dv().size.y - style.helper.margin - h
        local bg = copy_color(style.helper.background)
        local fg = copy_color(style.helper.text)
        bg[4] = math.floor(bg[4] * fading)
        fg[4] = math.floor(fg[4] * fading)
        core.redraw = true
        renderer.draw_rect(x, y, w, h, bg)
        x = x + style.helper.padding
        y = y + style.helper.padding
        renderer.draw_text(font, msg, x, y, fg)
      end
    end
    if dv().modal.active_help then
      local font = style.code_font
      local lines = {}
      local box_h = 0
      local box_w = 0
      local spacing = 8
      for _, kv in ipairs(dv().modal.active_help) do
        if #kv[1] >= spacing - 1 then
          spacing = #kv[1] + 1
        end
      end
      for _, kv in ipairs(dv().modal.active_help) do
        local line = kv[1] .. spaces(#kv[1], spacing) .. kv[2]
        local line_w = font:get_width(line)
        lines[#lines + 1] = line
        box_h = box_h + font:get_height()

        if line_w > box_w then
          box_w = line_w
        end
      end
      local x, y = pos(dv().size, box_w, box_h)
      x = dv().position.x + x
      y = dv().position.y + y
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
end

function modal.load_bindings(kb_model)
  if kb_model ~= nil then
    modal.kb_model = kb_model
  end
  modal.bindings = {}
  for mode, m_keymap in pairs(config.plugins.modal.keymaps) do
    modal.bindings[mode] = {}
    for ks, fn in pairs(m_keymap) do
      local conv = modal.kb_model.convert(ks)
      modal.bindings[mode][conv] = fn
    end
  end
  modal.helper_bindings = {}
  for mode, m_helpers in pairs(config.plugins.modal.helpers) do
    modal.helper_bindings[mode] = {}
    for ks, tuple in pairs(m_helpers) do
      local conv = modal.kb_model.convert(ks)
      modal.helper_bindings[mode][conv] = tuple
    end
  end
end

command.add(nil, {
  ["modal:help"] = modal_help,
  ["modal:redo"] = modal.redo_command,
})

modal.set_status_bar()

return modal
