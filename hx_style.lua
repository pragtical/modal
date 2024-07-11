local modal = require "plugins.modal"

local core = require "core"
local command = require "core.command"
local search = require "core.doc.search"
local config = require "core.config"

local hx_info = {}
hx_info.last_select = ""
-- TODO implement registers
hx_info.target_register = nil
hx_info.registers = {}

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

local function select(text)
  local opt = {}
  opt.regex = config.find_regex
  local results = {}
  local initials = {}
  for idx, line1, col1, line2, col2 in doc_multiline_selections(true) do
    initials[#initials + 1] = { line1, col1, line2, col2 }
    if line1 ~= line2 or col1 ~= col2 then
      local r = select_in_blob(idx, line1, col1, line2, col2, text, opt)
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
      core.log(tostring(text) .. " - " .. tostring(item))
      select(text)
    end,
    cancel = function(explicit)
      core.status_view:remove_tooltip()
    end
  })
end

local function concat(t1, t2)
  for k, v in pairs(t1) do
    if t2[k] == nil then
      t2[k] = v
    end
  end
  return t2
end



local mode = { NOR = 1, INS = 2, SEL = 3 }
modal.base_mode = mode.NOR

modal.modes = mode -- { "NOR", "INS", "SEL" }
modal.keymaps = {
  [mode.NOR] = {
    [":"] = "core:find-command",

    -- mode change
    ["i"] = modal.go_to_mode(mode.INS),
    ["v"] = modal.go_to_mode(mode.SEL),
    ["O"] = { "doc:newline-above", modal.go_to_mode(mode.INS) },
    ["o"] = { "doc:newline-below", modal.go_to_mode(mode.INS) },

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
    ["r"] = { delete, modal.go_to_mode(mode.INS) },
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
    -- Go To
    ["gh"] = { unselect, "doc:move-to-start-of-line" },
    ["g_"] = { unselect, "doc:move-to-fisrt-line-character" },
    ["gl"] = { unselect, "doc:move-to-end-of-line" },
    ["gg"] = { unselect, "doc:move-to-start-of-doc" },
    ["ge"] = { unselect, "doc:move-to-end-of-doc" },

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
  [mode.INS] = {
    ["<ESC>"] = modal.go_to_mode(mode.NOR),
  },
  [mode.SEL] = {
    ["i"] = modal.go_to_mode(mode.VIS),
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

modal.keymaps[mode.SEL] = concat(modal.keymaps[mode.NOR], modal.keymaps[mode.SEL])
modal.keymaps[mode.SEL] = concat(modal.keymaps[mode.SEL], sel_movements)

modal.carets = {
  modal.caret_style.BAR,
  modal.caret_style.NORMAL,
  modal.caret_style.BAR,
}
modal.on_key_callbacks = {
  [1] = modal.on_key_command_only,
  [2] = modal.on_key_passtrought,
  [3] = modal.on_key_command_only,
}


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
  }
}

modal.helpers[1] = helpers
modal.helpers[3] = helpers

return modal
