local modal = require "plugins.modal"
local kb_model = require "plugins.modal.bindings_models.compact"
local mu = require "plugins.modal.utils"
local bind_lsp = require "plugins.modal.defaults.lsp"

local changes = require "plugins.modal.defaults.modal_vi.changes"
local register = require "plugins.modal.defaults.modal_vi.register"
local visual = require "plugins.modal.defaults.modal_vi.visual"
local shapes = require "plugins.modal.defaults.modal_vi.shapes"
local operators = require "plugins.modal.defaults.modal_vi.operators"
local motion = require "plugins.modal.motion"
local translate = require "core.doc.translate"
local core = require "core"
local config = require "core.config"

local mode = { NOR = "NOR", INS = "INS", VIS = "VIS" }
local window_edges = { H = "top", M = "middle", L = "bottom" }

---Create a viewport-relative motion that moves or extends a characterwise
---selection.
---@param edge modal.window_edge
---@return modal.counted_action
local function window_motion(edge)
  ---Move to the first nonblank of the requested visible line and preserve the
  ---viewport.
  ---@param count integer
  local function jump(count)
    local view = mu.get_dv()
    ---@cast view modal.docview
    local top = view.position.y
    local line, bottom = mu.visible_line(view, edge, count)
    local text = view.doc.lines[line]
    local col = text:find("%S") or math.max(1, #text - 1)
    if view.modal.mode == mode.VIS then
      view.doc:select_to(function() return line, col end)
    else
      view.doc:set_selection(line, col)
    end

    -- Preserve the viewport and scroll only far enough to reveal the caret.
    view:scroll_to_make_visible(line, col)
    local _, y = view:get_line_screen_position(line, col)
    view.scroll.to.y = view.scroll.y + math.min(0, y - top)
      + math.max(0, y + view:get_line_height() - bottom)
    -- DocView:update would otherwise reapply its usual cursor scroll margin.
    view.last_line1, view.last_col1, view.last_line2, view.last_col2 =
      view.doc:get_selection()
    core.blink_reset()
  end
  modal.fns[jump] = "Go to " .. edge .. " visible line"
  return modal.with_count(jump)
end

local go_page_top = window_motion("top")
local go_page_middle = window_motion("middle")
local go_page_bottom = window_motion("bottom")
modal.mode_labels = { NOR = "NORMAL", INS = "INSERT", VIS = "VISUAL",
  [shapes.line] = "VISUAL LINE", [shapes.block] = "VISUAL BLOCK" }
config.plugins.modal.on_key_callbacks.NOR = modal.on_key_command_only
config.plugins.modal.on_key_callbacks.VIS = modal.on_key_command_only
config.plugins.modal.on_key_callbacks.INS = modal.on_key_passthrough


config.plugins.modal.carets.NOR = modal.caret_style.BAR
config.plugins.modal.select_cursor.VIS = true
config.plugins.modal.carets.VIS = modal.caret_style.BAR
config.plugins.modal.carets.INS = modal.caret_style.NORMAL
for _, id in ipairs({ shapes.line, shapes.block }) do
  config.plugins.modal.on_key_callbacks[id] = modal.on_key_command_only
  config.plugins.modal.carets[id] = modal.caret_style.BAR
end

config.plugins.modal.base_mode = mode.NOR
config.plugins.modal.modes = {
  mode.NOR, mode.INS, mode.VIS, shapes.line, shapes.block
}
---Base Vi keymaps. Operator motions and visual variants are added below.
config.plugins.modal.keymaps = {
  NOR = {
    ["escape"] = modal.clean,
    -- movement
    ["pageup"] = "doc:move-to-previous-page",
    ["pagedown"] = "doc:move-to-next-page",
    ["g j"] = "doc:move-to-next-line",
    ["g k"] = "doc:move-to-previous-line",
    ["S+h"] = go_page_top,
    ["S+m"] = go_page_middle,
    ["S+l"] = go_page_bottom,
    -- ["g e"] = "doc:move-to-previous-word-end", -- to implement
    -- ["g S+e"] = "doc:move-to-previous-WORD-end", -- to implement
    ["0"] = "doc:move-to-start-of-line",
    ["S+5"] = "bracket-match:move-to-matching",
    ["g S+-"] = mu.move_to_last_non_ws,
    ["space g"] = "doc:go-to-line",
    ["S+]"] = "doc:move-to-next-block-end",
    ["S+["] = "doc:move-to-previous-block-start",

    -- base command
    ["S+;"] = "core:find-command",
    ["return"] = { "command:submit", "dialog:select" },
    ["."] = changes.repeat_last,

    -- mode change
    ["i"] = { mu.go_to_selection_start, modal.go_to_mode(mode.INS) },
    ["a"] = { function()
      mu.get_doc():move_to(function(doc, line, col)
        if col < #doc.lines[line] then
          return translate.next_char(doc, line, col)
        end
        return line, col
      end)
    end, modal.go_to_mode(mode.INS) },
    ["S+a"] = {
      "doc:move-to-end-of-line", mu.go_to_selection_start,
      modal.go_to_mode(mode.INS)
    },
    ["o"] = {
      "doc:newline-below", mu.go_to_selection_start, modal.go_to_mode(mode.INS)
    },
    ["S+o"] = {
      "doc:newline-above", mu.go_to_selection_start, modal.go_to_mode(mode.INS)
    },
    ["e a"] = { "doc:move-to-next-word-end", modal.go_to_mode(mode.INS) },

    -- actions
    ["r $"] = modal.with_count(visual.replace),
    ["S+r"] = "doc:paste",
    ["S+j"] = "doc:join-lines",
    ["u"] = "doc:undo",
    ["S+u"] = "doc:redo",
    ["p"] = modal.with_count(function(count) register.put(false, count) end),
    ["S+p"] = modal.with_count(function(count) register.put(true, count) end),
    ["x"] = "d l",

    ["S+."] = "doc:indent",
    ["S+,"] = "doc:unindent",
    -- search
    ["space /"] = "project-search:find",
    ["/"] = "find-replace:find",
    ["n"] = "find-replace:repeat-find",
    ["S+n"] = "find-replace:previous-find",

    -- file project ops
    ["space f"] = "core:open-file",
    ["space p"] = "core:change-project-folder",
    ["space S+p"] = "core:open-project-folder",
    ["C+c"] = "doc:toggle-line-comments",

    -- WINDOW S operations
    ["f11"] = "core:toggle-fullscreen",
    ["space w v"] = { "root:split-right", "root:switch-to-right" },
    ["space w s"] = { "root:split-down", "root:switch-to-down" },
    ["space w q"] = "root:close",
    ["space w S+q"] = "core:quit",
    ["space w left"] = "root:switch-to-left",
    ["space w right"] = "root:switch-to-right",
    ["space w up"] = "root:switch-to-up",
    ["space w down"] = "root:switch-to-down",
    ["space w S+="] = "root:grow",
    ["space w -"] = "root:shrink",

    -- PRAGTICAL
    ["space \\"] = "treeview:toggle",
    ["space e l"] = "core:open-log",
    ["space e S+l"] = "log:open-as-doc",
    ["space e u"] = "core:open-user-module",
    ["space e r"] = "core:reload-module",
    ["space e S+r"] = "core:restart",
    ["space e s"] = "ui:settings",

    -- Modal
    ["space S+/"] = "modal:help",

  },
  VIS = {
    -- movement
    ["pageup"] = "doc:select-to-previous-page",
    ["pagedown"] = "doc:select-to-next-page",
    ["g j"] = "doc:select-to-next-line",
    ["g k"] = "doc:select-to-previous-line",
    ["S+h"] = go_page_top,
    ["S+m"] = go_page_middle,
    ["S+l"] = go_page_bottom,
    -- ["g e"] = "doc:move-to-previous-word-end", -- to implement
    -- ["g S+e"] = "doc:move-to-previous-WORD-end", -- to implement
    ["0"] = "doc:select-to-start-of-line",
    ["S+5"] = "bracket-match:select-to-matching",
    ["g S+-"] = mu.select_to_last_non_ws,
    ["S+]"] = "doc:select-to-next-block-end",
    ["S+["] = "doc:select-to-previous-block-start",

  },
  INS = {
    ["escape"] = changes.finish
  },
}

config.plugins.modal.helpers.NOR = {
  ["r"] = { { "$", "Replace with character" } },
  ["f"] = { { "$", "Find character forwards" } },
  ["S+f"] = { { "$", "Find character backwards" } },
  ["t"] = { { "$", "Move to before character" } },
  ["S+t"] = { { "$", "Move to after character" } },
  ["space"] = {
    { "e", "Editor" }, { "w", "Windows" }, { "/", "Find in project" },
    { "S+/", "Keymap help" }, { "\\", "Toggle project tree" },
  },
}

---@type table<string, modal.keymap>
local keymaps = config.plugins.modal.keymaps
---Position the caret or Visual head using Vi line and horizontal motions.
---@param key string
---@param extend boolean
---@return modal.counted_action
local function line_motion(key, extend)
  ---Resolve a count once, including numbered document jumps.
  ---@param count integer
  local function move(count)
    local view = core.active_view
    local doc = view.doc
    local adjust = extend and doc.select_to or doc.move_to
    adjust(doc, function(_, l, c)
      if key == "g g" or key == "S+g" then
        local last = key == "S+g" and view.modal.current_command.n_repeat == ""
        l = last and #doc.lines or math.min(count, #doc.lines)
        c = doc.lines[l]:find("%S") or 1
      elseif key == "S+6" then
        c = doc.lines[l]:find("%S") or #doc.lines[l]
      elseif key == "S+4" then
        l = math.min(#doc.lines, l + count - 1)
        c = #doc.lines[l]
      else
        local step = key == "h" and translate.previous_char
          or translate.next_char
        for _ = 1, count do
          local row, col = step(doc, l, c)
          if row ~= l or col == c then break end
          c = col
        end
      end
      if not extend and c == #doc.lines[l] and c > 1 then
        return translate.previous_char(doc, l, c)
      end
      return l, c
    end)
    -- A failed horizontal motion leaves Vim's preferred column intact.
    local state = view.modal
    if (key == "h" or key == "l") and state.vertical_goals then
      for idx, goal in pairs(state.vertical_goals) do
        local l, c = doc:get_selection_idx(idx)
        if l == goal.line and c == goal.col
          and goal.command == state.last_command then
          goal.command = state.current_command
        end
      end
    end
  end
  modal.fns[move] = (extend and "Select with " or "Move with ") .. key
  return modal.with_count(move)
end

for _, id in ipairs({ "NOR", "VIS" }) do
  for _, key in ipairs({ "h", "l", "S+4", "S+6", "g g", "S+g" }) do
    keymaps[id][key] = line_motion(key, id == "VIS")
  end
  keymaps[id].left, keymaps[id].right = keymaps[id].h, keymaps[id].l
end
keymaps.NOR["S+i"] = { keymaps.NOR["S+6"], modal.go_to_mode(mode.INS) }
---Move vertically by logical lines, keeping one goal column per cursor.
---@param direction integer
---@param extend boolean
---@return modal.counted_action
local function vertical(direction, extend)
  ---Move each head and retain its anchor in Visual mode.
  ---@param count integer
  local function move(count)
    local view = core.active_view
    local doc = view.doc
    for idx, l, c, a, b in doc:get_selections() do
      l, c = motion.vertical(view, idx, l, c, direction * count, true)
      if not extend then a, b = l, c end
      doc:set_selections(idx, l, c, a, b)
    end
  end
  modal.fns[move] = direction > 0 and "Next line" or "Previous line"
  return modal.with_count(move)
end
for _, id in ipairs({ "NOR", "VIS" }) do
  local map = keymaps[id]
  map.j, map.k = vertical(1, id == "VIS"), vertical(-1, id == "VIS")
  map.down, map.up = map.j, map.k
end
---@type modal.keymap
local shaped_keys = {}
for key, action in pairs(keymaps.VIS) do
  shaped_keys[key] = shapes.motion(keymaps.NOR[key], key)
  keymaps.VIS[key] = visual.motion(action, key)
end
---Create a counted binding that applies an editing key to the current selection
---shape.
---@param op string
---@return modal.counted_action
local function operation(op)
  local fn = function() shapes.operate(op) end
  modal.fns[fn] = "Apply " .. op .. " to selection"
  return modal.with_count(fn)
end
for _, op in ipairs({ "d", "c", "y", "p" }) do
  shaped_keys[op] = operation(op)
end
shaped_keys.x, shaped_keys["S+p"] = shaped_keys.d, operation("P")
shaped_keys.s, shaped_keys["S+y"] = shaped_keys.c, shaped_keys.y
shaped_keys["S+c"], shaped_keys["S+d"] = operation("C"), operation("D")
shaped_keys["S+."], shaped_keys["S+,"] = operation(">"), operation("<")
shaped_keys["r $"] = operation("r")
shaped_keys.o = function() shapes.swap(false) end
shaped_keys["S+o"] = function() shapes.swap(true) end
keymaps[shapes.line], keymaps[shapes.block] = shaped_keys, {}
for key, action in pairs(shaped_keys) do keymaps[shapes.block][key] = action end
keymaps[shapes.block]["S+i"] = operation("I")
keymaps[shapes.block]["S+a"] = operation("A")

---Swap the ends of each inclusive Visual range.
local function swap_visual()
  local doc = core.active_view.doc
  for idx in doc:get_selections() do
    local l, c, a, b = modal.selection.characters(doc, idx)
    modal.selection.set_characters(doc, idx, a, b, l, c)
  end
end

local escape = visual.switch("NOR")
for key, id in
  pairs({ v = "VIS", ["S+v"] = shapes.line, ["C+v"] = shapes.block }) do
  local switch = visual.switch(id)
  for _, map in
    ipairs({ keymaps.NOR, keymaps.VIS, shaped_keys, keymaps[shapes.block] }) do
    map[key] = switch
  end
end
shaped_keys.escape, keymaps[shapes.block].escape = escape, escape
local visual_actions = {
  o = swap_visual,
  backspace = keymaps.VIS.h,
  ["escape"] = escape,
  ["return"] = { "command:submit", "dialog:select" },
  ["r $"] = modal.with_count(visual.replace),
  ["S+r"] = "doc:paste",
  ["S+j"] = "doc:join-lines",
  ["u"] = "doc:undo",
  ["S+u"] = "doc:redo",
  ["p"] = modal.with_count(function(n) visual.put(false, n) end),
  ["S+p"] = modal.with_count(function(n) visual.put(true, n) end),
  ["y"] = visual.yank,
  ["c"] = visual.change,
  ["d"] = visual.delete,
  ["x"] = visual.delete,
}
for key, action in pairs(visual_actions) do keymaps.VIS[key] = action end

for _, key in ipairs({ "i", "S+i", "a", "S+a", "e a", "o", "S+o" }) do
  local kind = (key == "o" or key == "S+o") and "open" or "insert"
  keymaps.NOR[key] = changes.track(keymaps.NOR[key], kind)
end
for _, key in
  ipairs({ "p", "S+p", "r $", "S+r", "S+j", "S+.", "S+,", "C+c" }) do
  keymaps.NOR[key] = changes.track(keymaps.NOR[key])
end

config.plugins.modal.helpers.VIS = {}
bind_lsp(keymaps.NOR, config.plugins.modal.helpers.NOR, "space")
bind_lsp(keymaps.VIS, config.plugins.modal.helpers.VIS, "space")

local prefixes = operators.bind(keymaps, function(view, motion, count)
  return mu.visible_line(view, window_edges[motion], count)
end)
modal.load_bindings(kb_model, prefixes, "vi")
