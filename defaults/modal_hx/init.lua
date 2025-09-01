-- mod-version:3
local modal = require "plugins.modal"
local kb_modal = require "plugins.modal.bindings_models.modal"
local mu = require "plugins.modal.utils"

local core = require "core"
local search = require "core.doc.search"
local config = require "core.config"
local command = require "core.command"

require "plugins.modal.defaults.modal_hx.interface"


local modal_hx = {}
modal_hx.last_select = ""
-- TODO implement registers
modal_hx.target_register = nil
modal_hx.registers = {}

local mode = { NOR = "NOR", INS = "INS", SEL = "SEL" }

local function search_select()
  local selections = {}
  for idx, line1, col1, line2, col2 in mu.doc_multiline_selections(false) do
    table.insert(selections, { idx, line1, col1, line2, col2 })
  end
  local last_doc = mu.get_doc()
  core.command_view:enter("select", {
    text = modal_hx.last_select,
    select_text = true,
    show_suggestions = false,
    submit = function(text, _)
      modal_hx.last_select = text
      mu.blob_action(last_doc, text, mu.select_in_blob, selections)
    end,
    cancel = function(_)
      core.status_view:remove_tooltip()
      mu.reset_selections(last_doc, selections)
    end,
    suggest = function(text)
      if text and #text > 0 then
        mu.blob_action(last_doc, text, mu.select_in_blob, selections)
      else
        mu.reset_selections(last_doc, selections)
      end
    end
  })
end

local function search_split()
  local selections = {}
  for idx, line1, col1, line2, col2 in mu.doc_multiline_selections(false) do
    table.insert(selections, { idx, line1, col1, line2, col2 })
  end
  local last_doc = mu.get_doc()
  core.command_view:enter("split", {
    text = modal_hx.last_select,
    select_text = true,
    show_suggestions = false,
    submit = function(text, _)
      modal_hx.last_select = text
      mu.blob_action(last_doc, text, mu.split_in_blob, selections)
    end,
    cancel = function(_)
      core.status_view:remove_tooltip()
      mu.reset_selections(last_doc, selections)
    end,
    suggest = function(text)
      if text and #text > 0 then
        core.log("Split %s", text)
        mu.blob_action(last_doc, text, mu.split_in_blob, selections)
      else
        mu.reset_selections(last_doc, selections)
      end
    end
  })
end

local set_mode__orig = modal.set_mode
function modal.set_mode(mode_id)
  if mode_id then
    set_mode__orig(mode_id)
    modal.notify(mode_id, false)
  end
end

modal.fns = {
  [mu.unselect] = "hx:unselect",
  [mu.copy] = "hx:copy",
  [mu.paste_after] = "hx:paste-after",
  [mu.paste_before] = "hx:paste-before",
  [mu.indent] = "hx:indent",
  [mu.unindent] = "hx:unindent",
  [mu.replace] = "hx:replace",
  [mu.go_to_line] = "hx:go-to-line",
  [mu.delete] = "hx:delete",
  [mu.select_LINE] = "hx:select-LINE",
  [mu.select_line] = "hx:select-line",
  [mu.select_next_char] = "hx:select-next-character",
  [mu.select_prev_char] = "hx:select-previous-character",
  [mu.select_till_next_char] = "hx:select-till-next-character",
  [mu.select_till_prev_char] = "hx:select-till-previous-character",
  [mu.move_next_char] = "hx:move-next-character",
  [mu.move_prev_char] = "hx:move-previous-character",
  [mu.move_till_next_char] = "hx:move-till-next-character",
  [mu.move_till_prev_char] = "hx:move-till-previous-character",
  [search_select] = "hx:search",
  [search_split] = "hx:split",
  [mu.go_to_selection_start] = "hx:go-to-selection-start",
  [mu.go_to_selection_end] = "hx:go-to-selection-end",
  [mu.next_word_start] = "hx:move-to-next-word-start",
  [mu.next_WORD_start] = "hx:move-to-next-WORD-start",
  [mu.select_to_next_word_start] = "hx:select-to-next-word-start",
  [mu.select_to_next_WORD_start] = "hx:select-to-next-WORD-start",
}

config.plugins.modal.base_mode = mode.NOR
config.plugins.modal.modes = { mode.NOR, mode.INS, mode.SEL }

local go_to_ins = modal.go_to_mode(mode.INS)
local go_to_sel = modal.go_to_mode(mode.SEL)
local go_to_nor = modal.go_to_mode(mode.NOR)

config.plugins.modal.keymaps = {
  NOR = {
    [":"] = "core:find-command",
    ["<return>"] = { "command:submit", "dialog:select" },
    ["."] = "modal:redo",
    -- mode change
    ["i"] = { mu.go_to_selection_start, go_to_ins },
    ["I"] = { "doc:move-to-start-of-line", go_to_ins },
    ["v"] = go_to_sel,
    ["O"] = { "doc:newline-above", mu.go_to_selection_start, go_to_ins },
    ["o"] = { "doc:newline-below", mu.go_to_selection_start, go_to_ins },
    ["a"] = { mu.go_to_selection_end, go_to_ins },
    ["A"] = { "doc:move-to-end-of-line", mu.go_to_selection_start, go_to_ins },
    -- actions
    ["u"] = "doc:undo",
    ["U"] = "doc:redo",
    ["p"] = mu.paste_after,
    ["P"] = mu.paste_before,
    ["y"] = mu.copy,
    ["d"] = { mu.copy, mu.delete },
    ["J"] = "doc:join-lines",
    ["\\<"] = mu.unindent,
    [">"] = mu.indent,
    ["r<.>"] = mu.replace,
    ["R"] = "doc:paste",
    -- search
    ["<space>/"] = "project-search:find",
    ["/"] = "find-replace:find",
    ["n"] = "find-replace:repeat-find",
    ["N"] = "find-replace:previous-find",

    -- movements
    ["<left>"] = { mu.unselect, "doc:move-to-previous-char", "dialog:previous-entry" },
    ["<right>"] = { mu.unselect, "doc:move-to-next-char", "dialog:next-entry" },
    ["<up>"] = { mu.unselect, "command:select-previous", "doc:move-to-previous-line" },
    ["<down>"] = { mu.unselect, "command:select-next", "doc:move-to-next-line" },
    ["h"] = { mu.unselect, "doc:move-to-previous-char" },
    ["l"] = { mu.unselect, "doc:move-to-next-char" },
    ["k"] = { mu.unselect, "doc:move-to-previous-line" },
    ["j"] = { mu.unselect, "doc:move-to-next-line" },
    ["<pageup>"] = { mu.unselect, "doc:move-to-previous-page" },
    ["<pagedown>"] = { mu.unselect, "doc:move-to-next-page" },
    ["C-<left>"] = {mu.unselect, "movestory:prev"},
    ["C-h"] = {mu.unselect, "movestory:prev"},
    ["C-<right>"] = {mu.unselect, "movestory:next"},
    ["C-l"] = {mu.unselect, "movestory:next"},

    -- movement + selection
    ["x"] = mu.select_line,
    ["X"] = mu.select_LINE,
    ["w"] = { mu.unselect, "doc:select-to-next-word-end" },
    ["W"] = { mu.unselect, "doc:select-to-next-WORD-end" },
    ["e"] = { mu.unselect, "doc:select-to-next-word-end" },
    ["E"] = { mu.unselect, "doc:select-to-next-WORD-end" },
    ["b"] = { mu.unselect, "doc:select-to-previous-word-start" },
    ["B"] = { mu.unselect, "doc:select-to-previous-WORD-start" },
    ["f<.>"] = mu.move_next_char ,
    ["F<.>"] = mu.move_prev_char ,
    ["t<.>"] = mu.move_till_next_char,
    ["T<.>"] = mu.move_till_prev_char,
    ["G"] = mu.go_to_line ,
    ["%"] = "doc:select-all",

    -- multi cursors and selections
    ["C"] = "doc:create-cursor-next-line",
    [","] = "doc:select-none", -- slighty different then hx
    ["s"] = search_select,
    ["S"] = search_split,
    -- Go To
    ["gh"] = { mu.unselect, "doc:move-to-start-of-line" },
    ["g_"] = { mu.unselect, "doc:move-to-start-of-line", mu.move_to_next_non_ws },
    ["gl"] = { mu.unselect, "doc:move-to-end-of-line" },
    ["gg"] = { mu.unselect, "doc:move-to-start-of-doc" },
    ["ge"] = { mu.unselect, "doc:move-to-end-of-doc" },
    ["g:"] = { mu.unselect, "doc:go-to-line" },

    -- match
    ["mm"] = { mu.unselect, "bracket-match:move-to-matching" },
    ["ms"] = { mu.unselect, "bracket-match:select-to-matching" },

    -- macro
    -- TODO implement macro
    -- ["q"] = { function() modal.notify("macro:play") end, "macro:play" },
    -- ["Q"] = { function()
    --   modal.notify("macro:toggle-record")
    -- end, "macro:toggle-record" },
    -- search
    -- FILE operations
    ["<space>f"] = "core:find-project-file",
    ["<space>F"] = "core:open-file",
    ["<space>p"] = "core:change-project-folder",
    ["<space>P"] = "core:open-project-folder",
    ["<space>b"] = "buffer:picker", -- need plugin tab-switcher
    ["<space>c"] = "doc:toggle-line-comments",
    ["C-c"] = "doc:toggle-line-comments",

    -- WINDOWS operations
    ["<f11>"] = "core:toogle-full-screen",
    ["<space>wv"] = { "root:split-right", "root:switch-to-right" },
    ["<space>ws"] = { "root:split-down", "root:switch-to-down" },
    ["<space>wq"] = "root:close-node",
    ["<space>wQ"] = "core:quit",
    ["<space>w<left>"] = "root:switch-to-left",
    ["<space>w<right>"] = "root:switch-to-right",
    ["<space>w<up>"] = "root:switch-to-up",
    ["<space>w<down>"] = "root:switch-to-down",
    ["<space>w+"] = "root:grow",
    ["<space>w-"] = "root:shrink",

    -- LITE
    ["<space>\\"] = "treeview:toggle",
    ["<space>ll"] = "core:open-log",
    ["<space>lL"] = "log:open-as-doc",
    ["<space>lu"] = "core:open-user-module",
    ["<space>lr"] = "core:reload-module",
    ["<space>lR"] = "core:restart",
    ["<space>ls"] = "ui:settings",

    -- HX
    ["<space>?"] = "modal:help",

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
    ["<ESC>"] = go_to_nor,
  },
  SEL = {
    ["i"] = { mu.go_to_selection_start, mu.go_to_ins },
    ["v"] = go_to_nor,
    ["<ESC>"] = go_to_nor,
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
  ["f<.>"] = mu.extend_next_char,
  ["F<.>"] = mu.extend_prev_char,
  ["t<.>"] = mu.extend_till_next_char,
  ["T<.>"] = mu.extend_till_prev_char,
  [","] = nil
}

config.plugins.modal.keymaps.SEL = mu.concat(config.plugins.modal.keymaps.NOR,
  config.plugins.modal.keymaps.SEL)
config.plugins.modal.keymaps.SEL = mu.concat(config.plugins.modal.keymaps.SEL, sel_movements)

config.plugins.modal.carets.NOR = modal.caret_style.BAR
config.plugins.modal.carets.INS = modal.caret_style.NORMAL
config.plugins.modal.carets.SEL = modal.caret_style.BAR

config.plugins.modal.on_key_callbacks.NOR = modal.on_key_command_only
config.plugins.modal.on_key_callbacks.SEL = modal.on_key_command_only
config.plugins.modal.on_key_callbacks.INS = modal.on_key_passtrought


local helpers = {
  ["<space>"] = {
    { "f",  "open project file picker" },
    { "F",  "open file picker" },
    { "p",  "change project folder" },
    { "P",  "open project folder" },
    { "b",  "open buffer picker" },
    { "s",  "show symbol picker" },
    { "S",  "show project symbol picer" },
    { "d",  "show document diagnostic picker" },
    { "D",  "show project diagnostic picker" },
    { "w",  "window mode" },
    { "k",  "show symbol information" },
    { "r",  "rename symbol" },
    { "c",  "comment line" },
    { "\\", "toggle project tree" },
    { "l",  "lite-xl mode" },
    { "?",  "show keymap" },
  },
  ["<space>w"] = {
    { "q",     "close view" },
    { "Q",     "quit Lite XL" },
    { "v",     "vertical right split" },
    { "s",     "horizontal down split" },
    { "left",  "jump to left split" },
    { "right", "jump to right split" },
    { "up",    "jump to split above" },
    { "down",  "jump to split below" },
    { "+",     "grow view" },
    { "-",     "shrink view" }
  },
  ["<space>l"] = {

    { "l", "open log" },
    { "L", "open log as doc" },
    { "u", "open user module" },
    { "s", "open UI settings" },
    { "r", "reload a module" },
    { "R", "restart lite-xl" },
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
    { ":", "Goto line" },
  },
  ["m"] = {
    { "m", "Goto matching braket" },
    { "s", "Select to matching brakets" },
  }
}

config.plugins.modal.helpers.NOR = helpers
config.plugins.modal.helpers.SEL = helpers

command.add(nil, {
  ["w"] = function() command.perform "doc:save" end,
  ["wq"] = function()
    command.perform "doc:save"
    command.perform "core:quit"
  end,
  ["q"] = function() command.perform "core:quit" end

})

modal.load_bindings(kb_modal)

return modal_hx
