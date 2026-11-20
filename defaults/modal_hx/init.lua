-- mod-version:3
local modal = require "plugins.modal"
local kb_modal = require "plugins.modal.bindings_models.modal"
local mu = require "plugins.modal.utils"
local movement = require "plugins.modal.defaults.modal_hx.movement"
local bind_insert = require "plugins.modal.defaults.modal_hx.insert"
local bind_lsp = require "plugins.modal.defaults.lsp"

local core = require "core"
local config = require "core.config"
local command = require "core.command"

---Helix preset state shared by the select and split prompts.
---@class plugins.modal.hx
---@field last_select string Most recent search pattern.
local modal_hx = {}
modal_hx.last_select = ""
-- TODO implement registers
modal_hx.target_register = nil
modal_hx.registers = {}

local mode = { NOR = "NOR", INS = "INS", SEL = "SEL" }
modal.mode_labels = { NOR = "NORMAL", INS = "INSERT", SEL = "SELECT" }

---Preview regex selections and restore their primary range on cancellation.
---@param label string
---@param action modal.search_action
local function regex_prompt(label, action)
  local doc = mu.get_doc()
  local ranges = { primary = doc.last_selection }
  for idx, l, c, a, b in doc:get_selections() do
    ranges[idx] = { idx, l, c, a, b }
  end
  core.command_view:enter(label, {
    text = modal_hx.last_select,
    select_text = true,
    show_suggestions = false,
    submit = function(text)
      modal_hx.last_select = text
      mu.blob_action(doc, text, action, ranges)
    end,
    cancel = function()
      core.status_view:remove_tooltip()
      mu.reset_selections(doc, ranges)
    end,
    suggest = function(text)
      if text and text ~= "" then
        mu.blob_action(doc, text, action, ranges)
      else
        mu.reset_selections(doc, ranges)
      end
    end,
  })
end

---Select the matches of a regular expression within the current selections.
local function search_select() regex_prompt("select", mu.select_in_blob) end

---Split the current selections on matches of a regular expression.
local function search_split() regex_prompt("split", mu.split_in_blob) end

modal.fns = {
  [mu.unselect] = "hx:unselect",
  [mu.copy] = "hx:copy",
  [mu.paste_after] = "hx:paste-after",
  [mu.paste_before] = "hx:paste-before",
  [mu.indent] = "hx:indent",
  [mu.unindent] = "hx:unindent",
  [mu.replace] = "hx:replace",
  [mu.delete] = "hx:delete",
  [search_select] = "hx:search",
  [search_split] = "hx:split",
}

config.plugins.modal.base_mode = mode.NOR
config.plugins.modal.modes = { mode.NOR, mode.INS, mode.SEL }

config.plugins.modal.select_cursor = { NOR = true, SEL = true }
local go_to_sel = modal.go_to_mode(mode.SEL)
local go_to_nor = modal.go_to_mode(mode.NOR)

config.plugins.modal.keymaps = {
  NOR = {
    [":"] = "core:find-command",
    ["<return>"] = { "command:submit", "dialog:select" },
    -- mode change
    ["v"] = go_to_sel,
    -- actions
    ["u"] = "doc:undo",
    ["U"] = "doc:redo",
    ["J"] = "doc:join-lines",
    ["\\<"] = mu.unindent,
    [">"] = mu.indent,
    ["R"] = "doc:paste",
    -- search
    ["<space>/"] = "project-search:find",
    ["/"] = "find-replace:find",
    ["n"] = "find-replace:repeat-find",
    ["N"] = "find-replace:previous-find",

    -- movements
    ["<pageup>"] = { mu.unselect, "doc:move-to-previous-page" },
    ["<pagedown>"] = { mu.unselect, "doc:move-to-next-page" },
    ["C-<left>"] = {mu.unselect, "navigate:previous"},
    ["C-h"] = {mu.unselect, "navigate:previous"},
    ["C-<right>"] = {mu.unselect, "navigate:next"},
    ["C-l"] = {mu.unselect, "navigate:next"},

    -- movement + selection
    ["%"] = "doc:select-all",

    -- multi cursors and selections
    ["s"] = search_select,
    ["S"] = search_split,
    -- Go To
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
    ["<space>f"] = "core:find-file",
    ["<space>F"] = "core:open-file",
    ["<space>p"] = "core:change-project-folder",
    ["<space>P"] = "core:open-project-folder",
    ["<space>b"] = "tab-switcher:tab-list",
    ["<space>c"] = "doc:toggle-line-comments",
    ["C-c"] = "doc:toggle-line-comments",

    -- WINDOWS operations
    ["<f11>"] = "core:toggle-fullscreen",
    ["<space>wv"] = { "root:split-right", "root:switch-to-right" },
    ["<space>ws"] = { "root:split-down", "root:switch-to-down" },
    ["<space>wq"] = "root:close",
    ["<space>wQ"] = "core:quit",
    ["<space>w<left>"] = "root:switch-to-left",
    ["<space>w<right>"] = "root:switch-to-right",
    ["<space>w<up>"] = "root:switch-to-up",
    ["<space>w<down>"] = "root:switch-to-down",
    ["<space>w+"] = "root:grow",
    ["<space>w-"] = "root:shrink",

    -- PRAGTICAL
    ["<space>\\"] = "treeview:toggle",
    ["<space>el"] = "core:open-log",
    ["<space>eL"] = "log:open-as-doc",
    ["<space>eu"] = "core:open-user-module",
    ["<space>er"] = "core:reload-module",
    ["<space>eR"] = "core:restart",
    ["<space>es"] = "ui:settings",

    -- HX
    ["<space>?"] = "modal:help",

  },
  INS = {},
  SEL = {
    ["v"] = go_to_nor,
    ["<ESC>"] = go_to_nor,
  },
}

config.plugins.modal.carets.NOR = modal.caret_style.BAR
config.plugins.modal.carets.INS = modal.caret_style.NORMAL
config.plugins.modal.carets.SEL = modal.caret_style.BAR

config.plugins.modal.on_key_callbacks.NOR = modal.on_key_command_only
config.plugins.modal.on_key_callbacks.SEL = modal.on_key_command_only
config.plugins.modal.on_key_callbacks.INS = modal.on_key_passthrough


---Next-key captions shared by Helix Normal and Select modes.
---@type modal.helpers
local helpers = {
  ["<space>"] = {
    { "f",  "open project file picker" },
    { "F",  "open file picker" },
    { "p",  "change project folder" },
    { "P",  "open project folder" },
    { "b",  "switch to an open tab" },
    { "w",  "Windows" },
    { "c",  "comment line" },
    { "\\", "toggle project tree" },
    { "e",  "Editor" },
    { "?",  "show keymap" },
  },
  ["<space>w"] = {
    { "q",     "close view" },
    { "Q",     "quit Pragtical" },
    { "v",     "vertical right split" },
    { "s",     "horizontal down split" },
    { "left",  "jump to left split" },
    { "right", "jump to right split" },
    { "up",    "jump to split above" },
    { "down",  "jump to split below" },
    { "+",     "grow view" },
    { "-",     "shrink view" }
  },
  ["<space>e"] = {
    { "l", "open log" },
    { "L", "open log as doc" },
    { "u", "open user module" },
    { "s", "open UI settings" },
    { "r", "reload a module" },
    { "R", "restart Pragtical" },
  },
  ["g"] = {
    { "g", "Goto file start" },
    { "e", "Goto file end" },
    { "h", "Goto line start" },
    { "l", "Goto line end" },
    { "_", "Goto first character of line" },
    { ":", "Goto line" },
  },
  ["m"] = {
    { "m", "Go to matching bracket" },
    { "s", "Select to matching bracket" },
  }
}

---Reduce each selection to its own block cursor.
local function collapse()
  local doc = core.active_view.doc
  for idx in doc:get_selections() do
    local l, c = modal.selection.characters(doc, idx)
    modal.selection.set_characters(doc, idx, l, c, l, c)
  end
end

---Keep only the primary range.
local function keep_primary()
  local doc = core.active_view.doc
  doc:set_selection(doc:get_selection())
  modal.set_mode("NOR")
end

modal.fns[collapse] = "Collapse selections"
modal.fns[keep_primary] = "Keep primary selection"
modal.fns[modal.selection.copy_below] = "Copy selections to next line"
local maps = config.plugins.modal.keymaps
bind_lsp(maps.NOR, helpers, "<space>")
mu.concat(maps.NOR, maps.SEL)
maps.SEL["<pageup>"] = "doc:select-to-previous-page"
maps.SEL["<pagedown>"] = "doc:select-to-next-page"
bind_insert(maps)
for _, id in ipairs({ "NOR", "SEL" }) do
  local map = maps[id]
  for _, key in ipairs({
    "h", "j", "k", "l", "<left>", "<right>", "<up>", "<down>",
    "w", "W", "b", "B", "e", "E", "f<.>", "F<.>", "t<.>", "T<.>",
    "gh", "gl", "gg", "ge", "g_", "G", "x", "X",
  }) do
    map[key] = movement(key, id == "SEL")
  end
  map[";"], map[","] = collapse, keep_primary
  map.C = modal.with_count(modal.selection.copy_below)
  map.p = { mu.paste_after, go_to_nor }
  map.P = { mu.paste_before, go_to_nor }
  map.y = { mu.copy, go_to_nor }
  map.d = { mu.copy, mu.delete, go_to_nor }
  map.c = { mu.copy, mu.delete, map.i }
  map["r<.>"] = { mu.replace, go_to_nor }
end
config.plugins.modal.helpers.NOR = helpers
config.plugins.modal.helpers.SEL = helpers

command.add(function() return modal.active_preset == "hx"
  and config.plugins.modal.enabled end, {
  ["w"] = function() command.perform "doc:save" end,
  ["wq"] = function()
    command.perform "doc:save"
    command.perform "core:quit"
  end,
  ["q"] = function() command.perform "core:quit" end

})

modal.load_bindings(kb_modal, nil, "hx")

return modal_hx
