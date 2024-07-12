local modal = require "plugins.modal"

local core = require "core"
local command = require "core.command"
local search = require "core.doc.search"
local config = require "core.config"
local keymap = require "core.keymap"

local hx_info = {}
hx_info.last_select = ""
-- TODO implement registers
hx_info.target_register = nil
hx_info.registers = {}

local mode = { NOR = "NOR", INS = "INS", SEL = "SEL" }

local function dv()
  return core.active_view
end

local function doc()
  return dv().doc
end

local function doc_multiline_selections(sort)
  local iter, state, idx, line1, col1, line2, col2 = doc():get_selections(sort)
  return function()
    idx, line1, col1, line2, col2 = iter(state, idx)
    if idx and line2 > line1 and col2 == 1 then
      line2 = line2 - 1
      col2 = #doc().lines[line2]
    end
    return idx, line1, col1, line2, col2
  end
end

local function indent()
  local docview = core.active_view and core.active_view.doc
  if docview then
    for idx, line1, col1, line2, col2 in doc_multiline_selections(false) do
      local l1, c1, _, _ = docview:indent_text(false, line1, 1, line2, math.huge)
      if l1 then
        docview:set_selections(idx, line1, c1 - 1 + col1, line2, c1 - 1 + col2)
      end
    end
  end
end

local function unindent()
  local docview = core.active_view and core.active_view.doc
  if docview then
    for idx, line1, col1, line2, col2 in doc_multiline_selections(false) do
      local l1, c1, _, _ = docview:indent_text(true, line1, 1, line2, math.huge)
      if l1 then
        docview:set_selections(idx, line1, c1 - 1 + col1, line2, c1 - 1 + col2)
      end
    end
  end
end

local function unselect()
  for idx, _, _, line2, col2 in doc_multiline_selections(true) do
    doc():set_selections(idx, line2, col2, line2, col2)
  end
end

local function select_LINE()
  for idx, line1, col1, line2, col2 in doc_multiline_selections(false) do
    local lobj = doc().highlighter:get_line(line2)
    local eol = math.huge
    if line1 == line2 and (col1 - col2 ~= #lobj.text - 1) then
      doc():set_selections(idx, line2, eol, line1, 1)
    end
  end
end


local function select_line()
  for idx, line1, col1, line2, col2 in doc_multiline_selections(false) do
    local lobj = doc().highlighter:get_line(line2)
    local eol = math.huge
    if line1 == line2 and (col1 - col2 ~= #lobj.text - 1) then
      doc():set_selections(idx, line2, eol, line1, 1)
    else
      doc():set_selections(idx, math.max(line1, line2) + 1, eol, math.min(line1, line2), 1)
    end
  end
end

local function delete()
  local text = doc():get_text(doc():get_selection())
  if #text > 1 then
    if hx_info.target_register then
      hx_info.registers[hx_info.target_register] = text
      -- aand zero it back for further actions
      hx_info.target_register = nil
    end
    system.set_clipboard(text)
  end
  command.perform("doc:delete")
end

local function select_in_blob(idx, line1, col1, line2, col2, text, opt)
  doc():remove_selection(idx)
  local results = {}
  local l1, c1, l2, c2 = search.find(doc(), line1, col1, text, opt)
  while l1 and (l1 < line2 or (l1 == line2 and c1 < col2)) and (l2 < line2 or (l2 == line2 and c2 <= col2)) do
    results[#results + 1] = { l1, c1, l2, c2 }
    l1, c1, l2, c2 = search.find(doc(), l2, c2, text, opt)
  end
  return results
end

local function split_in_blob(idx, line1, col1, line2, col2, text, opt)
  doc():remove_selection(idx)
  local l0, c0 = line1, col1
  local results = {}
  local l1, c1, l2, c2 = search.find(doc(), line1, col1, text, opt)
  while l1 and (l1 < line2 or (l1 == line2 and c1 < col2)) and (l2 < line2 or (l2 == line2 and c2 <= col2)) do
    results[#results + 1] = { l0, c0, l1, c1 }
    l0, c0 = l2, c2
    l1, c1, l2, c2 = search.find(doc(), l2, c2, text, opt)
  end
  if l0 < line2 or (l0 == line2 and c0 < col2) then
    results[#results + 1] = { l0, c0, line2, col2 }
  end
  return results
end

local function blob_action(text, fn)
  local opt = {}
  opt.regex = config.find_regex
  local results = {}
  local initials = {}
  for idx, line1, col1, line2, col2 in doc_multiline_selections(true) do
    initials[#initials + 1] = { line1, col1, line2, col2 }
    if line1 ~= line2 or col1 ~= col2 then
      local r = fn(idx, line1, col1, line2, col2, text, opt)
      if #r >= 1 then
        results[#results + 1] = r
      end
    end
  end
  if #results == 0 then
    for _, sel in ipairs(initials) do
      doc():add_selection(sel[1], sel[2], sel[3], sel[4])
    end
  else
    for i, res in ipairs(results) do
      for j, sel in ipairs(res) do
        if i == 1 and j == 1 then
          doc():set_selection(sel[3], sel[4], sel[1], sel[2])
        else
          doc():add_selection(sel[3], sel[4], sel[1], sel[2])
        end
      end
    end
  end
end


local function search_select()
  core.command_view:enter("select", {
    text = hx_info.last_select,
    select_text = true,
    show_suggestions = false,
    submit = function(text, item)
      hx_info.last_select = text
      blob_action(text, select_in_blob)
    end,
    cancel = function(_)
      core.status_view:remove_tooltip()
    end
  })
end

local function search_split()
  core.command_view:enter("split", {
    text = hx_info.last_select,
    select_text = true,
    show_suggestions = false,
    submit = function(text, item)
      hx_info.last_select = text
      blob_action(text, split_in_blob)
    end,
    cancel = function(_)
      core.status_view:remove_tooltip()
    end
  })
end

local function go_to_selection_start()
  for idx, line1, col1, _, _ in doc_multiline_selections(true) do
    doc():set_selections(idx, line1, col1)
  end
end

local function concat(t1, t2)
  for k, v in pairs(t1) do
    if t2[k] == nil then
      t2[k] = v
    end
  end
  return t2
end

-- local on_key_pressed__orig = keymap.on_key_pressed
local function listen_next()
  -- TODO implement some sort of one time listener
  core.log("<r> not implemented yet")
end

config.plugins.modal.base_mode = mode.NOR

config.plugins.modal.modes = { mode.NOR, mode.INS, mode.SEL }
config.plugins.modal.keymaps = {
  NOR = {
    [":"] = "core:find-command",

    -- mode change
    ["i"] = { go_to_selection_start, modal.go_to_mode(mode.INS) },
    ["v"] = modal.go_to_mode(mode.SEL),
    ["O"] = { "doc:newline-above", go_to_selection_start, modal.go_to_mode(mode.INS) },
    ["o"] = { "doc:newline-below", go_to_selection_start, modal.go_to_mode(mode.INS) },
    ["a"] = { "doc:move-to-next-char", go_to_selection_start, modal.go_to_mode(mode.INS) },
    ["A"] = { "doc:move-to-next-word-end", go_to_selection_start, modal.go_to_mode(mode.INS) },
    -- actions
    ["u"] = "doc:undo",
    ["U"] = "doc:redo",
    ["p"] = "doc:paste",
    ["P"] = "jp",
    ["y"] = "doc:copy",
    ["d"] = delete,
    ["J"] = "doc:join-lines",
    ["\\<"] = unindent,
    [">"] = indent,
    ["r"] = { delete, listen_next },
    ["R"] = "doc:paste",
    -- search
    ["<space>/"] = "project-search:find",
    ["/"] = "find-replace:find",
    ["n"] = "find-replace:repeat-find",
    ["N"] = "find-replace:previous-find",

    -- movements
    ["<left>"] = { unselect, "doc:move-to-previous-char", "dialog:previous-entry" },
    ["<right>"] = { unselect, "doc:move-to-next-char", "dialog:next-entry" },
    ["<up>"] = { unselect, "command:select-previous", "doc:move-to-previous-line" },
    ["<down>"] = { unselect, "command:select-next", "doc:move-to-next-line" },
    ["h"] = { unselect, "doc:move-to-previous-char" },
    ["l"] = { unselect, "doc:move-to-next-char" },
    ["k"] = { unselect, "doc:move-to-previous-line" },
    ["j"] = { unselect, "doc:move-to-next-line" },
    ["<pageup>"] = { unselect, "doc:move-to-previous-page" },
    ["<pagedown>"] = { unselect, "doc:move-to-next-page" },

    -- movement + selection
    ["x"] = select_line,
    ["X"] = select_LINE,
    ["w"] = { unselect, "doc:select-to-next-word-end" },
    ["W"] = { unselect, "doc:select-to-next-WORD-end" },
    ["e"] = { unselect, "doc:select-to-next-word-end" },
    ["E"] = { unselect, "doc:select-to-next-WORD-end" },
    ["b"] = { unselect, "doc:select-to-previous-word-start" },
    ["B"] = { unselect, "doc:select-to-previous-WORD-start" },
    ["%"] = "doc:select-all",

    -- multi cursors and selections
    ["C"] = "doc:create-cursor-next-line",
    [","] = "doc:select-none", -- slighty different then hx
    ["s"] = search_select,
    ["S"] = search_split,
    -- Go To
    ["gh"] = { unselect, "doc:move-to-start-of-line" },
    ["g_"] = { unselect, "doc:move-to-fisrt-line-character" },
    ["gl"] = { unselect, "doc:move-to-end-of-line" },
    ["gg"] = { unselect, "doc:move-to-start-of-doc" },
    ["ge"] = { unselect, "doc:move-to-end-of-doc" },

    -- match
    ["mm"] = { unselect, "bracket-match:move-to-matching" },
    ["ms"] = { unselect, "bracket-match:select-to-matching" },

    -- search
    -- FILE operations
    ["<space>f"] = "core:find-file",
    ["<space>F"] = "core:open-file",
    ["<space>P"] = "core:open-project-folder",
    ["<space>b"] = "tab-switcher:tab-list", -- need plugin tab-switcher

    -- WINDOWS operations
    ["<f11>"] = "core:toogle-full-screen",
    ["<space>wv"] = { "root:split-left", "root:switch-to-left" },
    ["<space>ws"] = { "root:split-down", "root:switch-to-down" },
    ["<space>wq"] = "root:close-or-quit",
    ["<space>w<left>"] = "root:switch-to-left",
    ["<space>w<right>"] = "root:switch-to-right",
    ["<space>w<up>"] = "root:switch-to-up",
    ["<space>w<down>"] = "root:switch-to-down",

    -- LITE
    ["<space>\\"] = "treeview:toggle",

    -- LSP (Require lintplus and LSP plugins)
    ["<space>k"] = "lsp:show-symbol-info",
    ["<space>r"] = "lsp:rename-symbol",
    ["<space>D"] = "lsp:view-all-diagnostics",
    ["<space>d"] = "lsp:view-document-diagnostics",
    ["<space>S"] = "lsp:find-workspace-symbol",
    ["<space>s"] = "lsp:view-document-symbols",
    -- Go To(LSP)
    ["gd"] = "lsp:goto-definition",
    ["gi"] = "lsp:goto-implementation",
    ["gr"] = "lsp:find-references",
  },
  INS = {
    ["<ESC>"] = modal.go_to_mode(mode.NOR),
  },
  SEL = {
    ["i"] = { go_to_selection_start, modal.go_to_mode(mode.INS) },
    ["v"] = modal.go_to_mode(mode.NOR),
    ["<ESC>"] = modal.go_to_mode(mode.NOR),
  },
}

local sel_movements = {
  ["<left>"] = { "doc:select-to-previous-char", "dialog:previous-entry" },
  ["<right>"] = { "doc:select-to-next-char", "dialog:next-entry" },
  ["<up>"] = { "command:select-previous", "doc:select-to-previous-line" },
  ["<down>"] = { "command:select-next", "doc:select-to-next-line" },
  ["h"] = { "doc:select-to-previous-char" },
  ["l"] = { "doc:select-to-next-char" },
  ["k"] = { "doc:select-to-previous-line" },
  ["j"] = { "doc:select-to-next-line" },
  ["<pageup>"] = { "doc:select-to-previous-page" },
  ["<pagedown>"] = { "doc:select-to-next-page" },

  -- movement + selection
  ["w"] = { "doc:select-to-next-word-end" },
  ["W"] = { "doc:select-to-next-WORD-end" },
  ["e"] = { "doc:select-to-next-word-end" },
  ["E"] = { "doc:select-to-next-WORD-end" },
  ["b"] = { "doc:select-to-previous-word-start" },
  ["B"] = { "doc:select-to-previous-WORD-start" },
  [","] = nil
}

config.plugins.modal.keymaps.SEL = concat(config.plugins.modal.keymaps.NOR,
  config.plugins.modal.keymaps.SEL)
config.plugins.modal.keymaps.SEL = concat(config.plugins.modal.keymaps.SEL, sel_movements)

config.plugins.modal.carets.NOR = modal.caret_style.BAR
config.plugins.modal.carets.INS = modal.caret_style.NORMAL
config.plugins.modal.carets.SEL = modal.caret_style.BAR

config.plugins.modal.on_key_callbacks.NOR = modal.on_key_command_only
config.plugins.modal.on_key_callbacks.SEL = modal.on_key_command_only
config.plugins.modal.on_key_callbacks.INS = modal.on_key_passtrought


local helpers = {
  ["<space>"] = {
    { "f", "open project file picker" },
    { "F", "open file picker" },
    { "P", "open project folder" },
    { "b", "open buffer picker" },
    { "s", "show symbol picker" },
    { "S", "show project symbol picer" },
    { "d", "show document diagnostic picker" },
    { "D", "show project diagnostic picker" },
    { "w", "window mode" },
    { "k", "show symbol information" },
    { "r", "rename symbol" },
    {"\\", "toggle project tree"},
  },
  ["<space>w"] = {
    { "q",     "close tab" },
    { "v",     "vertical right split" },
    { "s",     "horizontal down split" },
    { "left",  "jump to left split" },
    { "right", "jump to right split" },
    { "up",    "jump to split above" },
    { "down",  "jump to split below" },
  },
  ["g"] = {
    { "g", "Goto file start" },
    { "e", "Goto file end" },
    { "h", "Goto line start" },
    { "l", "Goto line end" },
    { "_", "Goto first character of line" },
    { "d", "Goto definition" },
    { "i", "Goto implementation" },
    { "r", "Goto references" },
  },
  ["m"] = {
    { "m", "Goto matching braket" },
    { "s", "Select to matching brakets" },
  }
}

config.plugins.modal.helpers.NOR = helpers
config.plugins.modal.helpers.SEL = helpers

return modal
