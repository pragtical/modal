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

local KeyMapView = require "plugins.modal.keymapview"
local keyhelp = require "plugins.modal.keyhelp"
local modalkm = require "plugins.modal.keymap"
local kb_modal = require "plugins.modal.bindings_models.modal"

---A binding may name a command or another binding, call Lua, or run a list.
---@alias modal.action string|function|modal.action_list

---Actions in a list run in numeric order for each repetition.
---@class modal.action_list
---@field [integer] modal.action

---A callback registered with with_count receives the entire prefix once.
---@alias modal.counted_action fun(count: integer)
---@alias modal.keymap table<string, modal.action>
---@alias modal.help_row string[] # Key or suffix followed by its caption.
---@alias modal.helpers table<string, modal.help_row[]> # Rows by prefix.
---@alias modal.key_handler fun(key: string, mod: boolean?, ...): boolean?
---@alias modal.operator_modes table<string, table<string, string>>

---Converts preset notation to space-separated Pragtical strokes.
---@class modal.model
---@field convert fun(sequence: string): string

---One resolved binding, retained by the view for modal:redo.
---@class modal.command
---@field cmd modal.action
---@field num integer Effective count, including any operator and motion counts.
---@field n_repeat string Empty for an implicit count.
---@field input? string Committed text for a wildcard binding.
---@field seq? string Compiled sequence, omitted when replaying a change.

---A transient or persistent message in a document view.
---@class modal.notification
---@field text string
---@field mode? boolean Keep the message visible.
---@field timestamp number Creation time from system.get_time().

---Input and selection state attached to an initialized document view.
---@class modal.state
---@field mode string Preset mode ID.
---@field callback modal.key_handler
---@field caret integer Preset caret style.
---@field keymap modal.keymap Compiled bindings of the current mode.
---@field helpers modal.helpers Compiled help prefixes for that mode.
---@field keystrokes string[] Pending strokes in input order.
---@field keyhelper string Display text for the stroke sequence.
---@field notifications modal.notification[]
---@field last_input? string Last committed character in command mode.
---@field active_help? modal.overlay
---@field current_command? modal.command
---@field last_command? modal.command
---@field visual_shape? modal.shape
---@field pending_change? modal.insertion
---@field suspend_selection? fun(view: modal.docview, discard?: boolean)
---@field resume_selection? fun(view: modal.docview)
---@field draw_cursor_index? integer Next native caret in the draw order.
---@field select_cursor? boolean Select the character under a command cursor.
---@field vertical_goals? table<integer, modal.vertical_goal>
---@field saved_cursors? modal.saved_cursors
---@field insert_text? fun(doc: core.doc, text: string)
---@field hx_insert? modal.hx_insertion
---@field append_cursor? boolean Retract an appended Helix range on Escape.
---@field before_insert_key? fun(key: string)
---@field prepare_block_insert? fun()
---@field finish_block_insert? fun(view: modal.docview)

---The plugin checks for modal state on any focused Pragtical view.
---@class (partial) core.view
---@field modal? modal.state Present on initialized document views only.

---An editable Pragtical document view after a mode has been applied.
---@class modal.docview : core.docview
---@field modal modal.state

---Modal editing API exported by the plugin and through core.modal.
---@class plugins.modal
---@field kb_model modal.model
---@field bindings table<string, modal.keymap>
---@field helper_bindings table<string, modal.helpers>
---@field fns table<function, string> Display names for binding callbacks.
---@field mode_labels table<string, string> Display names by preset mode ID.
---@field active_preset? string ID of the loaded bundled preset.
local modal = {}
modal.selection = require "plugins.modal.selection"


core.modal = modal

---Mode tables supplied by a preset or a user's Lua configuration.
---@class modal.modes_config
---@field base_mode? string Initial mode for newly opened documents.
---@field modes string[] Mode IDs available in this preset.
---@field on_key_callbacks table<string, modal.key_handler>
---@field carets table<string, integer> Values from modal.caret_style by mode.
---@field select_cursor table<string, boolean> Select one grapheme at rest.
---@field helpers table<string, modal.helpers> Captions by mode and prefix.
---@field keymaps table<string, modal.keymap> Bindings in the preset's notation.

---Configuration options for the modal editing plugin.
---@class config.plugins.modal : modal.modes_config
---@field enabled boolean Enable modal input handling in document views.
---@field preset "vi"|"hx"|"example"|"custom" Preset restored at startup.
---@field show_helpers boolean Show possible continuations of a key sequence.
---@field key_helper_delay number Seconds to wait before showing the overlay.
---@field notification { show: boolean, timeout: number, fading: number }
---@field status_bar { mode: boolean, strokes: boolean }
---@field config_spec? modal.settings_spec

---Settings accepts string control types for plugin-provided options.
---@class modal.setting
---@field label string
---@field path string Path relative to config.plugins.modal.
---@field type "toggle"|"selection"|"number"
---@field description? string
---@field default boolean|string|number
---@field min? number
---@field step? number
---@field values? string[][] Display label and preset ID.
---@field get_value? fun(value: any): any
---@field on_apply? fun(value: any)

---@class modal.settings_spec
---@field [integer] modal.setting
---@field name string Settings section name.

---@type config.plugins.modal
config.plugins.modal = common.merge({
  enabled = true,
  preset = "vi",
  base_mode = nil,
  modes = {},
  on_key_callbacks = {},
  carets = {},
  select_cursor = {},
  helpers = {},
  keymaps = {},
  show_helpers = true,
  key_helper_delay = 0,
  notification = { show = true, timeout = 0.5, fading = 0.1 },
  status_bar = {
    mode = true,
    strokes = true,
  }
}, config.plugins.modal)

modal.kb_model = kb_modal
modal.bindings = {}
---Operator prefixes are retained when a preset reuses a compiled map.
local operators_by_keymap = setmetatable({}, { __mode = "k" })
modal.helper_bindings = {}
local labels_by_keymap = setmetatable({}, { __mode = "k" })
modal.ignore_text = true

---Caret styles available to preset configurations.
modal.caret_style = { NORMAL = 0, BAR = 1, }

---Horizontal positions shared by the notification and overlay renderers.
---@class modal.alignment
modal.align = {
  LEFT = 1, CENTER = 2, RIGHT = 3
}
modal.config = {
  helper = {
    show = true,
  },
  notification = config.plugins.modal.notification
}

modal.fns = {}
modal.mode_labels = {}

-- Helper styling
style.helper = setmetatable({
  padding = 10, margin = 10, alignement = modal.align.LEFT,
}, {
  __index = function(_, key)
    if key == "background" then return style.background2 end
    if key == "text" then return style.text end
  end,
})

---Get the preset's display name for a mode, falling back to its ID.
---@param mode string
---@return string
local function mode_label(mode)
  return modal.mode_labels[mode] or mode
end

---Create a binding that switches the focused document to the given mode.
---@param mode? string Mode ID.
---@return fun()? action
---@overload fun(mode: string): fun()
function modal.go_to_mode(mode)
  if mode ~= nil then
    local fn = function()
      modal.set_mode(mode)
    end
    local key = "modal:set-mode-" .. mode_label(mode)
    modal.fns[fn] = key
    return fn
  end
end

---Get the currently focused Pragtical view.
---@return core.view?
local function dv()
  return core.active_view
end


---Get the active mode ID when modal editing is enabled for the focused view.
---@return string? mode
function modal.get_mode()
  if config.plugins.modal.enabled and dv() ~= nil and dv().modal ~= nil then
    return dv().modal.mode
  else
    return nil
  end
end


---Build the mode indicator for the status bar, including disabled and unfocused
---states.
---@return string[]
local function statusbar_mode()
  if not config.plugins.modal.enabled then return { "MODAL OFF" } end
  local mode_str = modal.get_mode()
  if mode_str == nil or type(mode_str) ~= "string" then
    return { "NO MODE", }
  else
    return { mode_label(mode_str), }
  end
end

---Build the status bar text for the active document's pending key sequence.
---@return string[]
local function statusbar_strokes()
  if not config.plugins.modal.enabled then return {} end
  local view = dv()
  local str = ""
  if view ~= nil and view.modal ~= nil then
    str = view.modal.keyhelper
  end
  return { str }
end

---Open the command picker with the commands valid for the current modal view.
---@param button string Mouse button.
local function open_modal_commands(button)
  if button ~= "left" or core.command_view:is_open() then return end
  local names = {}
  for name in pairs(command.map) do
    if name:match("^modal:") and command.is_valid(name) then
      table.insert(names, name)
    end
  end
  core.command_view:enter("Modal Commands", {
    restore_state = { text = "", suggestion_id = "modal:toggle" },
    get_suggestion_id = function(item) return item.text end,
    suggest = function(text) return common.fuzzy_match(names, text) end,
    submit = function(_, item)
      if item then command.perform(item.text) end
    end,
  })
end

---Apply the configured visibility of the mode and keystroke status items.
function modal.set_status_bar()
  if config.plugins.modal.status_bar.mode == true
    and core.status_view:get_item("status:modal_mode") == nil then
    core.status_view:add_item({
      name = "status:modal_mode",
      alignment = StatusView.Item.LEFT,
      get_item = statusbar_mode,
      position = 1,
      tooltip = "Choose a modal command",
      command = open_modal_commands,
      separator = core.status_view.separator2
    })
  elseif config.plugins.modal.status_bar.mode == false
    and core.status_view:get_item("status:modal_mode") ~= nil then
    core.status_view:remove_item("status:modal_mode")
  end

  if config.plugins.modal.status_bar.strokes == true
    and core.status_view:get_item("status:modal_strokes") == nil then
    core.status_view:add_item({
      name = "status:modal_strokes",
      alignment = StatusView.Item.LEFT,
      get_item = statusbar_strokes,
      position = 2,
      tooltip = "current keystrokes",
      separator = core.status_view.separator2
    })
  elseif config.plugins.modal.status_bar.strokes == false
    and core.status_view:get_item("status:modal_strokes") ~= nil then
    core.status_view:remove_item("status:modal_strokes")
  end
end

---Split a compiled key sequence into its space-separated strokes.
---@param cmd string
---@return string[] strokes
function modal.split_command(cmd)
  local array = {}
  for str in string.gmatch(cmd, '([^ ]+)') do
    table.insert(array, str)
  end
  return array
end

---Match a sequence against a binding, treating a dollar stroke as a wildcard.
---@param split_seq string[] Already split input.
---@param cmd string Compiled binding.
---@param full boolean Require equal sequence lengths.
---@return boolean matches
---@return string[]? strokes Matched binding, split into strokes.
local function match_command(split_seq, cmd, full)
  local split_cmd = modal.split_command(cmd)
  if (full and #split_seq == #split_cmd)
    or (not full and #split_seq <= #split_cmd) then
    for i = 1, #split_seq do
      if split_seq[i] ~= split_cmd[i] and split_cmd[i] ~= "$" then
        return false
      end
    end
    return true, split_cmd
  end
  return false
end

---Check whether a binding in the current mode begins with the supplied
---sequence.
---@param seq string
---@return boolean
function modal.is_partial_command(seq)
  local view = dv()
  ---@cast view modal.docview
  local prefix = modal.split_command(seq)
  for key, _ in pairs(view.modal.keymap) do
    if match_command(prefix, key, false) then
      return true
    end
  end
  return false
end

---Resolve an exact binding first, then a full-length wildcard binding.
---@param seq string
---@return modal.action? action
---@return string? binding Matched pattern.
local function find_binding(seq)
  local view = dv()
  ---@cast view modal.docview
  if view.modal.keymap[seq] ~= nil then
    return view.modal.keymap[seq], seq
  end
  local prefix = modal.split_command(seq)
  for key, cmd in pairs(view.modal.keymap) do
    if match_command(prefix, key, true) then
      return cmd, key
    end
  end
  return nil
end

---Resolve the action bound to a sequence in the focused document's mode.
---@param seq string
---@return modal.action? action
function modal.get_command(seq)
  local action = find_binding(seq)
  return action
end

local counted_actions = setmetatable({}, { __mode = "k" })

---Mark a callback to receive the numeric prefix once. The implicit count is
---one.
---@param fn modal.counted_action
---@return modal.counted_action callback The original function.
function modal.with_count(fn)
  counted_actions[fn] = true
  return fn
end

---Execute a command ID, binding alias, callback or ordered list using the
---repeat count.
---@param cmd modal.action?
---@param count? integer
function modal.eval_cmd(cmd, count)
  if not config.plugins.modal.enabled or cmd == nil or count == 0 then
    return
  elseif counted_actions[cmd] then
    cmd(count or 1)
  elseif type(cmd) == "string" and not command.map[cmd] then
    local view = dv()
    if view and view.modal and view.modal.keymap[cmd] ~= nil then
      modal.eval_cmd(view.modal.keymap[cmd], count)
    elseif view then
      core.warn("Modal: command %s is unavailable", cmd)
    end
  elseif count and count ~= 1 then
    for _ = 1, count do
      modal.eval_cmd(cmd)
    end
  elseif type(cmd) == "table" then
    for _, scmd in ipairs(cmd) do
      modal.eval_cmd(scmd)
    end
  elseif type(cmd) == "string" then
    command.perform(cmd)
  elseif type(cmd) == "function" then
    cmd()
  end
end

---Replay the last modal command and count recorded for the focused view.
function modal.redo_command()
  local view = dv()
  if view and view.modal and view.modal.last_command ~= nil then
    local last_cmd = view.modal.last_command
    ---@cast last_cmd modal.command
    local cmd, input = view.modal.current_command, view.modal.last_input
    view.modal.current_command, view.modal.last_input = last_cmd, last_cmd.input
    local ok, err = pcall(modal.eval_cmd, last_cmd.cmd, last_cmd.num)
    view.modal.current_command, view.modal.last_input = cmd, input
    if not ok then error(err, 0) end
  end
end

---Clear pending input and dismiss the keymap overlay for a view.
---@param view core.view?
local function clear_strokes(view)
  if view and view.modal then
    if view.modal.active_help then core.redraw = true end
    view.modal.last_input = nil
    view.modal.keystrokes = {}
    view.modal.keyhelper = ""
    view.modal.active_help = nil
  end
end

---Build next-key suggestions for an incomplete sequence and schedule their
---display.
---@param seq string
---@param already_visible? boolean Keep the overlay open for the new prefix.
function modal.eval_helper(seq, already_visible)
  local state = dv().modal
  ---@cast state modal.state
  if config.plugins.modal.show_helpers and seq ~= "" then
    local help = keyhelp.collect(state, modal.split_command(seq), match_command,
      labels_by_keymap[state.keymap] or {}, modal)
    state.active_help = help
    local delay = config.plugins.modal.key_helper_delay
    if help and not already_visible and delay > 0 then
      help.waiting = true
      core.add_thread(function()
        coroutine.yield(delay)
        if state.active_help == help then
          help.waiting = nil
          core.redraw = true
        end
      end)
    elseif help then
      core.redraw = true
    end
  end
end

---Read consecutive digit strokes starting at the given index.
---@param strokes string[]
---@param start integer
---@param zero_is_motion boolean Treat an initial zero as a motion.
---@return string digits Empty when no count is present.
---@return integer next_index
local function read_count(strokes, start, zero_is_motion)
  local i = start
  if not zero_is_motion or strokes[i] ~= "0" then
    while strokes[i] and strokes[i]:match("^%d$") do i = i + 1 end
  end
  return table.concat(strokes, "", start, i - 1), i
end

---Resolve queued strokes, multiply operator and motion counts, and dispatch or
---show continuations.
---@return boolean? handled True for a completed binding or cancellation.
function modal.eval_current_strokes()
  local view = dv()
  ---@cast view core.view
  if view.modal then
    ---@cast view modal.docview
    local previous_help = view.modal.active_help
    if previous_help then core.redraw = true end
    view.modal.active_help = nil
    local strokes = view.modal.keystrokes
    view.modal.keyhelper = table.concat(strokes, " ")
    local prefix, first = read_count(strokes, 1, view.modal.keymap["0"] ~= nil)
    local count = tonumber(prefix) or 1
    local seq = table.concat(strokes, " ", first)
    local operators = operators_by_keymap[view.modal.keymap]
    local operator = strokes[first]
    if operators and operators[operator] then
      local inner, motion = read_count(strokes, first + 1, true)
      if inner ~= "" then
        count = count * tonumber(inner)
        prefix = tostring(count)
        seq = operator
        if strokes[motion] then
          seq = seq .. " " .. table.concat(strokes, " ", motion)
        end
      end
    end
    local cmd, binding = find_binding(seq)
    if #strokes > 1 and strokes[#strokes] == "escape"
      and not (binding and binding:match("escape$")) then
      clear_strokes(view)
      return true
    elseif cmd ~= nil then
      view.modal.keystrokes = {}
      view.modal.current_command = {
        num = count,
        n_repeat = prefix,
        cmd = cmd,
        seq = seq,
        input = view.modal.last_input,
      }
      modal.eval_cmd(cmd, count)
      if config.plugins.modal.enabled and cmd ~= "modal:redo" then
        view.modal.last_command = view.modal.current_command
      end
    elseif not modal.is_partial_command(seq) then
      view.modal.keystrokes = {}
      view.modal.keyhelper = ""
    else
      modal.eval_helper(seq, previous_help and not previous_help.waiting)
    end
    return cmd ~= nil
  end
end

local doc_on_text_input = DocView.on_text_input
---Supply committed text to a pending modal stroke or forward it to the
---document.
---@param text string
---@return boolean? handled
function DocView:on_text_input(text)
  local callback = self.modal and self.modal.callback
  if config.plugins.modal.enabled and self == dv() and callback
    and callback ~= modal.on_key_passthrough
    and (callback == modal.on_key_command_only or modal.ignore_text) then
    self.modal.last_input = text
    modal.eval_current_strokes()
    return true
  end
  if config.plugins.modal.enabled and self == dv() and self.modal
    and self.modal.insert_text then
    self.doc:clear_search_selections()
    self.modal.insert_text(self.doc, text)
    return true
  end
  return doc_on_text_input(self, text)
end

modal.on_key_released__orig = keymap.on_key_released

---Release the modal modifier and forward the release to Pragtical.
---@param k string
function keymap.on_key_released(k)
  modalkm.released_modifiers(k)
  return modal.on_key_released__orig(k)
end

modal.on_key_pressed__orig = keymap.on_key_pressed

---Try modal shortcuts while allowing ordinary typing and host shortcuts.
---@param k string
---@param mod? boolean Modifier-only keypress.
---@param ... any Additional host event arguments.
---@return boolean? handled
function modal.on_key_passthrough(k, mod, ...)
  if dv().modal.before_insert_key then dv().modal.before_insert_key(k) end
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

local set_active_view = core.set_active_view
---Cancel a pending sequence when the host moves focus away from its document.
---@param view core.view
---@param ... any Forwarded host arguments.
function core.set_active_view(view, ...)
  local previous = core.active_view
  local result = set_active_view(view, ...)
  local state = previous and previous.modal
  if previous ~= core.active_view and state and #state.keystrokes > 0 then
    clear_strokes(previous)
  end
  return result
end

---Discard pending input and the keymap overlay in the active view.
function modal.clean()
  clear_strokes(dv())
end

local apply_preset, pending_preset

---Apply the editing toggle to open documents and suspend or restore their modal
---selections.
---@param enabled boolean
local function apply_enabled(enabled)
  config.plugins.modal.enabled = enabled
  if not enabled then
    for _, view in ipairs(core.root_view.root_node:get_children()) do
      clear_strokes(view)
      if view.modal then
        if view.modal.suspend_selection then
          view.modal.suspend_selection(view)
        end
        modal.selection.collapse_cursor(view, true)
        view.modal.pending_change = nil
      end
    end
  else
    if pending_preset then apply_preset(pending_preset) end
    for _, view in ipairs(core.root_view.root_node:get_children()) do
      modal.selection.restore_cursors(view)
      if view.modal and view.modal.resume_selection then
        view.modal.resume_selection(view)
      end
    end
    if dv() and not dv().modal then
      modal.set_mode(config.plugins.modal.base_mode)
    end
  end
  core.redraw = true
end

---Set overlay visibility and dismiss a pending overlay when hiding it.
---@param show boolean
local function apply_overlay(show)
  config.plugins.modal.show_helpers = show
  local view = dv()
  if not show and view and view.modal then view.modal.active_help = nil end
  core.redraw = true
end

---Queue printable strokes until text input arrives and resolve navigation keys
---immediately.
---@param k string
---@param mod? boolean Modifier-only keypress.
---@param ... any Additional host event arguments.
---@return boolean? handled
function modal.on_key_command_only(k, mod, ...)
  if mod or string.find(k, 'click') or string.find(k, 'wheel') then
    return modal.on_key_pressed__orig(k, ...)
  end
  modal.ignore_text = true
  local stroke = modalkm.key_to_stroke(k)
  if stroke and #stroke > 0 then
    dv().modal.keystrokes[#dv().modal.keystrokes + 1] = stroke
    if modalkm.non_text_keys[k] or k:match("^f%d+$")
      or modalkm.active_modifiers() then
      dv().modal.last_input = nil
      modal.eval_current_strokes()
      return true
    end
    return false
  end
  return true
end

---Describe a binding for the help tab or overlay, using registered callback
---names when available.
---@param action modal.action
---@param pretty? boolean Produce a human-readable caption.
---@return string
function modal.describe_action(action, pretty)
  if type(action) == "table" then
    local names = {}
    for _, part in ipairs(action) do
      names[#names + 1] = modal.describe_action(part, pretty)
    end
    return table.concat(names, ", ")
  end
  if type(action) == "function" then
    local name = modal.fns[action]
    if type(name) ~= "string" then
      for k, fn in pairs(package.loaded["plugins.modal.utils"] or {}) do
        if fn == action then name = k break end
      end
    end
    if type(name) ~= "string" then
      for k, fn in pairs(modal) do
        if fn == action then name = k break end
      end
    end
    action = name
  end
  if type(action) ~= "string" then return "Custom action" end
  if not pretty or action:find(" ", 1, true) then return action end
  action = (action:match("^[^:]+:(.+)$") or action):gsub("_", "-")
  return command.prettify_name(action)
end

---Open a sorted, scrollable help tab for a mode's bindings.
---@param mode string
---@param keys modal.keymap
local function show_help(mode, keys)
  if dv() ~= nil and dv().modal ~= nil then
    local helper = {}
    for strokes, action in pairs(keys) do
      helper[#helper + 1] = { strokes, modal.describe_action(action) }
    end
    table.sort(helper, function(a, b) return a[1] < b[1] end)
    local node = core.root_view:get_active_node_default()
    node:add_view(KeyMapView(mode_label(mode), helper))
  end
end

---Show the compiled keymap for the active mode.
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

---Get a mode's compiled bindings or an empty map.
---@param mode_id string
---@return modal.keymap
local function get_keymap(mode_id)
  local map = modal.bindings[mode_id]
  if map ~= nil then
    return map
  end
  return {}
end

---Get a mode's compiled helper prefixes and their label entries.
---@param mode_id string
---@return modal.helpers
local function get_helpers(mode_id)
  local helpers = modal.helper_bindings[mode_id]
  if helpers ~= nil then
    return helpers
  end
  return {}
end

---Get a mode's input handler, falling back to native typing.
---@param mode_id string
---@return modal.key_handler
local function get_callback(mode_id)
  local fn = config.plugins.modal.on_key_callbacks[mode_id]
  if fn == nil then
    return modal.on_key_passthrough
  else
    return fn
  end
end

---Check whether the view is an editable document eligible for modal state.
---@param view core.view?
---@return boolean?
local function is_modal_document(view)
  return view and view:extends(DocView) and not view:extends(CommandView)
    and not view.disable_save
end

---Initialize a document's mode, input callback, caret and keymap, then clear
---its pending keys.
---@param view core.view?
---@param mode_id string?
local function set_view_mode(view, mode_id)
  if not config.plugins.modal.enabled or not mode_id or mode_id == 0
    or not is_modal_document(view) then
    return
  end
  ---@cast view modal.docview
  view.modal = view.modal or { keystrokes = {}, notifications = {} }
  if view.modal.mode ~= mode_id and view.modal.suspend_selection then
    view.modal.suspend_selection(view, true)
  end
  view.modal.select_cursor = config.plugins.modal.select_cursor[mode_id]
  if view.modal.select_cursor then
    modal.selection.ensure_characters(view.doc)
  end
  if view.modal.mode ~= mode_id then view.modal.insert_text = nil end
  view.modal.mode = mode_id
  view.modal.callback = get_callback(mode_id)
  view.modal.helpers = get_helpers(mode_id)
  view.modal.keymap = get_keymap(mode_id)
  view.modal.caret = config.plugins.modal.carets[mode_id]
    or modal.caret_style.NORMAL
  view.modal.keystrokes = {}
  view.modal.keyhelper = ""
  view.modal.active_help = nil
  if view == dv() then modal.notify(mode_label(mode_id), false) end
end

---Switch the focused editable document to a configured mode ID.
---@param mode_id string
function modal.set_mode(mode_id)
  set_view_mode(dv(), mode_id)
end

---Route a keypress through the active modal document or the host's native
---handler.
---@param k string
---@param ... any Additional host event arguments.
---@return boolean? handled
function keymap.on_key_pressed(k, ...)
  local mod = modalkm.pressed_modifiers(k)
  if not config.plugins.modal.enabled then
    return modal.on_key_pressed__orig(k, ...)
  end
  local view = dv()
  local root = core.root_view
  if view and not view.modal and config.plugins.modal.base_mode then
    modal.set_mode(config.plugins.modal.base_mode)
  end
  if view and view.modal and view.modal.callback
    and not (root.get_modal_view and root:get_modal_view()) then
    if config.plugins.modal.show_helpers and view.modal.active_help and not mod
      and keyhelp.page_key(
        view.modal.active_help, modalkm.key_to_stroke(k)) then
      return true
    end
    if view.modal.select_cursor then
      modal.selection.ensure_characters(view.doc)
    end
    return view.modal.callback(k, mod, ...)
  else
    return modal.on_key_pressed__orig(k, ...)
  end
end

local DocView__update__orig = DocView.update
---Initialize the focused document's base mode before the normal view update.
---@param ... any Forwarded host arguments.
function DocView:update(...)
  if config.plugins.modal.enabled and self == dv() and not self.modal
    and config.plugins.modal.base_mode then
    modal.set_mode(config.plugins.modal.base_mode)
  end
  if config.plugins.modal.enabled and self.modal and self.modal.select_cursor
    and self == dv() then modal.selection.ensure_characters(self.doc) end
  DocView__update__orig(self, ...)
end

-- Native selections cover whole graphemes. A rectangle can also highlight
-- part of a tab or wide character before the document draws its text.
local doc_draw_line_text = DocView.draw_line_text
---Draw fractional selection edges behind the document text.
---@param line integer Document line.
---@param ... any Forwarded drawing coordinates.
---@return integer height
function DocView:draw_line_text(line, ...)
  if config.plugins.modal.enabled and self.modal then
    modal.selection.draw_edges(self, line)
  end
  return doc_draw_line_text(self, line, ...)
end

local doc_draw_caret = DocView.draw_caret
---Draw the preset's caret at the moving selection corner or native caret
---position.
---@param x number
---@param y number
---@param line integer
---@param col integer
function DocView:draw_caret(x, y, line, col)
  local shape = config.plugins.modal.enabled and modal.selection.current(self)
  if shape then
    local head_line, head_col = self.doc:get_selection()
    if line ~= head_line or col ~= head_col then return end
    line, col = shape.line, shape.col
    x, y = self:get_line_screen_position(line, col)
  elseif config.plugins.modal.enabled and self.modal
    and (self.modal.select_cursor or self.modal.insert_text) then
    local total = #self.doc.selections / 4
    local idx = math.min(self.modal.draw_cursor_index or 1, total)
    for _ = 1, total do
      local l, c = self.doc:get_selection_idx(idx)
      if l == line and c == col then
        self.modal.draw_cursor_index = idx % total + 1
        line, col = modal.selection.characters(self.doc, idx)
        x, y = self:get_line_screen_position(line, col)
        break
      end
      idx = idx % total + 1
    end
  end
  if config.plugins.modal.enabled and self.modal
    and self.modal.caret == modal.caret_style.BAR
    and not self.doc.overwrite then
    renderer.draw_rect(
      x, y, self:get_font():get_width(" "), self:get_line_height(), style.caret)
  else
    doc_draw_caret(self, x, y, line, col)
  end
end

---Show a message on the active modal document, optionally keeping it visible.
---@param msg string
---@param persistent? boolean Keep the notification past its normal timeout.
function modal.notify(msg, persistent)
  if not modal.config.notification.show then return end
  table.insert(dv().modal.notifications, {
    text = msg,
    mode = persistent,
    timestamp = system.get_time(),
  })
end

---Expire old messages and compute the opacity of the newest visible
---notification.
---@return modal.notification? notification
---@return number opacity
local function get_last_notification()
  local view = dv()
  ---@cast view core.view
  if view.modal then
    ---@cast view modal.docview
    local time = system.get_time()
    local to_remove = 0
    local result, fading = nil, 1.0
    for i = #view.modal.notifications, 1, -1 do
      local notification = view.modal.notifications[i]
      local t = time - notification.timestamp
      if notification.mode or t <= modal.config.notification.timeout then
        result = notification
        break
      elseif t < (
        modal.config.notification.timeout
        + modal.config.notification.fading) then
        result = notification
        fading =
          1.0 - (t - modal.config.notification.timeout)
          / modal.config.notification.fading
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

---Copy a theme color before changing its opacity.
---@param color renderer.color
---@return renderer.color
local function copy_color(color)
  return { color[1], color[2], color[3], color[4] }
end



local rvDraw = RootView.draw
---Draw mode notifications above the editor when the keymap overlay is hidden.
---@param ... any Forwarded host arguments.
function RootView:draw(...)
  rvDraw(self, ...)
  if config.plugins.modal.enabled and dv() and dv().modal then
    local help = dv().modal.active_help
    if modal.config.notification.show
      and not (config.plugins.modal.show_helpers and help
      and not help.waiting) then
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
  end
end

local draw_doc = DocView.draw
---Draw next-key suggestions after the active document's contents.
---@param ... any Forwarded host arguments.
function DocView:draw(...)
  draw_doc(self, ...)
  local help = self.modal and self.modal.active_help
  local root = core.root_view
  if help and not help.waiting and self == dv() and config.plugins.modal.enabled
    and config.plugins.modal.show_helpers
    and not (root.get_modal_view and root:get_modal_view()) then
    keyhelp.draw(self, help, modal.align)
  end
end

local doc_wheel = DocView.on_mouse_wheel
---Page the overlay under the pointer or scroll the document normally.
---@param y number Vertical delta.
---@param x number Horizontal delta.
---@param ... any Additional host event arguments.
---@return boolean? handled
function DocView:on_mouse_wheel(y, x, ...)
  local mouse = core.root_view.mouse
  if self == dv() and self.modal and config.plugins.modal.enabled
    and config.plugins.modal.show_helpers
    and keyhelp.wheel(self.modal.active_help, mouse.x, mouse.y, y) then
      return true
    end
  return doc_wheel(self, y, x, ...)
end

---Mode configuration retained by reference for live preset switches.
---@class modal.profile : modal.modes_config
---@field model modal.model
---@field labels table<string, string>
---@field fns table<function, string>
---@field preset? string

---@type table<string, modal.profile>
local profiles = {}
local mode_tables = {
  "modes", "keymaps", "helpers", "carets", "select_cursor", "on_key_callbacks"
}
---Capture the current preset's configuration tables, labels and binding model
---by reference.
---@return modal.profile
local function current_profile()
  local cfg = config.plugins.modal
  local profile = { base_mode = cfg.base_mode, model = modal.kb_model,
    labels = modal.mode_labels, fns = modal.fns, preset = modal.active_preset }
  for _, field in ipairs(mode_tables) do profile[field] = cfg[field] end
  return profile
end

---Compile configured bindings and helper prefixes with the selected notation.
---Bundled presets also pass their operator prefixes and ID to support live
---switching.
---@param kb_model? modal.model Retain the current model if omitted.
---@param operator_prefixes? modal.operator_modes
---@param preset? string Preset ID to cache.
function modal.load_bindings(kb_model, operator_prefixes, preset)
  if kb_model ~= nil then
    modal.kb_model = kb_model
  end
  modal.bindings = {}
  for mode, m_keymap in pairs(config.plugins.modal.keymaps) do
    modal.bindings[mode] = {}
    if operator_prefixes then
      operators_by_keymap[m_keymap] = operator_prefixes[mode]
    end
    operators_by_keymap[modal.bindings[mode]] = operators_by_keymap[m_keymap]
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
    if modal.bindings[mode] then
      labels_by_keymap[modal.bindings[mode]] =
        keyhelp.labels(modal.helper_bindings[mode], modal.kb_model)
    end
  end
  if preset then
    modal.active_preset = preset
    profiles[preset] = current_profile()
  end
end

---Read the preset ID saved before the Example preset was renamed.
---@param id string
---@return string
local function preset_id(id)
  return id == "dummy" and "example" or id
end

local selected_preset
---Restore a cached profile or load a bundled preset and reinitialize open modal
---documents.
---@param preset string
---@param startup? boolean Apply during startup even if editing is disabled.
apply_preset = function(preset, startup)
  preset = preset_id(preset)
  if not startup and not config.plugins.modal.enabled then
    pending_preset = preset
    return
  end
  pending_preset = nil
  if preset == selected_preset then return end
  local cfg = config.plugins.modal
  local profile = profiles[preset]
  if not profile and preset ~= "vi" and preset ~= "hx"
    and preset ~= "example" then
    return
  end
  for _, field in ipairs(mode_tables) do
    cfg[field] = profile and profile[field] or {}
  end
  cfg.base_mode = profile and profile.base_mode
  modal.mode_labels = profile and profile.labels or {}
  modal.fns = profile and profile.fns or {}
  modal.active_preset = profile and profile.preset
  if profile then
    modal.load_bindings(profile.model)
  else
    require("plugins.modal.defaults.modal_" .. preset)
  end
  selected_preset = preset
  for _, view in ipairs(core.root_view.root_node:get_children()) do
    if is_modal_document(view) then
      if view.modal and view.modal.suspend_selection then
        view.modal.suspend_selection(view)
      end
      modal.selection.collapse_cursor(view)
      view.modal = nil
      set_view_mode(view, cfg.base_mode)
    end
  end
  core.redraw = true
end

command.add(nil, {
  ["modal:toggle"] = function()
    apply_enabled(not config.plugins.modal.enabled)
  end,
  ["modal:toggle-keymap-overlay"] = function()
    apply_overlay(not config.plugins.modal.show_helpers)
  end,
})

command.add(function() return modal.get_mode() ~= nil end, {
  ["modal:help"] = modal_help,
  ["modal:redo"] = modal.redo_command,
})

---Settings controls use the same live callbacks as the modal commands.
config.plugins.modal.config_spec = {
  name = "Modal",
  {
    label = "Enable Modal Editing", path = "enabled",
    type = "toggle", default = true,
    description = "Use modal editing in documents. "
      .. "Turning it back on resumes each document’s mode.",
    on_apply = apply_enabled,
  },
  {
    label = "Preset", path = "preset", type = "selection", default = "vi",
    description = "Switch keymaps when modal editing is enabled. "
      .. "Custom uses your Lua configuration.",
    values = {
      { "Custom", "custom" }, { "Helix", "hx" },
      { "Vi", "vi" }, { "Example", "example" }
    },
    get_value = preset_id,
    on_apply = function(value)
      config.plugins.modal.preset = preset_id(value)
      if profiles.custom then apply_preset(value) end
    end,
  },
  {
    label = "Show Keymap Overlay", path = "show_helpers",
    type = "toggle", default = true,
    description = "Show the available next keys while typing a modal sequence.",
    on_apply = apply_overlay,
  },
  {
    label = "Keymap Overlay Delay", path = "key_helper_delay", type = "number",
    description =
      "Seconds to wait after a prefix. Zero shows the overlay immediately.",
    default = 0, min = 0, step = 0.1,
  },
  {
    label = "Show Mode in Status Bar",
    path = "status_bar.mode", type = "toggle",
    default = true, on_apply = modal.set_status_bar,
  },
  {
    label = "Show Keystrokes in Status Bar",
    path = "status_bar.strokes", type = "toggle",
    default = true, on_apply = modal.set_status_bar,
  },
  {
    label = "Show Mode Notifications", path = "notification.show",
    type = "toggle", default = true,
    description = "Display a notification when the mode changes.",
  },
  {
    label = "Notification Duration",
    path = "notification.timeout", type = "number",
    description = "Seconds before a notification starts fading.",
    default = 0.5, min = 0, step = 0.1,
  },
  {
    label = "Notification Fade Time",
    path = "notification.fading", type = "number",
    description = "Seconds to fade a notification out.",
    default = 0.1, min = 0, step = 0.1,
  },
}

modal.set_status_bar()

-- Settings restores saved options before the editor starts running threads.
core.add_thread(function()
  config.plugins.modal.preset = preset_id(config.plugins.modal.preset)
  profiles.custom = current_profile()
  selected_preset = "custom"
  if not config.plugins.modal.base_mode then
    apply_preset(config.plugins.modal.preset, true)
  end
end)

return modal
