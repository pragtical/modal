local modal = require "plugins.modal"
local kb_model = require "plugins.modal.bindings_models.compact"
local mu = require "plugins.modal.utils"

local config = require "core.config"

local reuired_plugins = {
  "braketmatch",
}


local function go_page_top()
end

local function go_page_middle()

end

local function go_page_bottom()

end

local set_mode__orig = modal.set_mode
function modal.set_mode(mode_id)
  if mode_id then
    set_mode__orig(mode_id)
    modal.notify(mode_id, false)
  end
end


local mode = { NOR = "NOR", INS = "INS", VIS = "VIS" }
config.plugins.modal.on_key_callbacks.NOR = modal.on_key_command_only
config.plugins.modal.on_key_callbacks.VIS = modal.on_key_command_only
config.plugins.modal.on_key_callbacks.INS = modal.on_key_passtrought


config.plugins.modal.carets.NOR = modal.caret_style.BAR
config.plugins.modal.carets.VIS = modal.caret_style.BAR
config.plugins.modal.carets.INS = modal.caret_style.NORMAL

config.plugins.modal.base_mode = mode.NOR
config.plugins.modal.modes = { mode.NOR, mode.INS, mode.VIS }
config.plugins.modal.keymaps = {
  NOR = {
    ["escape"] = modal.clean,
    -- movement
    ["left"] = { "doc:move-to-previous-char", "dialog:previous-entry" },
    ["right"] = { "doc:move-to-next-char", "dialog:next-entry" },
    ["up"] = { "command:select-previous", "doc:move-to-previous-line" },
    ["down"] = { "command:select-next", "doc:move-to-next-line" },
    ["h"] = "doc:move-to-previous-char",
    ["l"] = "doc:move-to-next-char",
    ["k"] = "doc:move-to-previous-line",
    ["j"] = "doc:move-to-next-line",
    ["pageup"] = "doc:move-to-previous-page",
    ["pagedown"] = "doc:move-to-next-page",
    ["g j"] = "doc:move-to-next-line",
    ["g k"] = "doc:move-to-previous-line",
    ["S+h"] = go_page_top,
    ["S+m"] = go_page_middle,
    ["S+l"] = go_page_bottom,
    ["w"] = mu.move_to_next_word_start,
    ["S+w"] = mu.move_to_next_WORD_start,
    ["e"] = "doc:move-to-next-word-end",
    ["S+e"] = "doc:move-to-next-word-end",
    ["b"] = "doc:move-to-previous-word-start",
    ["S+b"] = "doc:move-to-previous-word-start",
    -- ["g e"] = "doc:move-to-previous-word-end", -- to implement
    -- ["g S+e"] = "doc:move-to-previous-WORD-end", -- to implement
    ["0"] = "doc:move-to-start-of-line",
    ["S+4"] = "doc:move-to-end-of-line",
    ["S+5"] = "bracket-match:move-to-matching",
    ["S+6"] = { "doc:move-to-start-of-line", mu.move_to_next_word_start },
    ["g S+-"] = { "doc:move-to-end-of-line", "doc:move-to-previous-word-end" },
    ["g g"] = "doc:move-to-start-of-doc",
    ["S+g"] = { "doc:move-to-end-of-doc", "doc:move-to-start-of-line" },
    ["f $"] = { mu.move_next_char, mu.unselect},
    ["S+f $"] = { mu.move_prev_char, mu.unselect},
    ["t $"] = { mu.move_till_next_char, mu.unselect},
    ["S+t $"] = { mu.move_till_prev_char, mu.unselect},
    ["S+]"] = "doc:move-to-next-block-end",
    ["S+["] = "doc:move-to-previous-block-start",

    -- base command
    ["S+;"] = "core:find-command",
    ["return"] = { "command:submit", "dialog:select" },
    ["."] = "modal:redo",

    -- mode change
    ["i"] = { mu.go_to_selection_start, modal.go_to_mode(mode.INS) },
    ["S+i"] = { "doc:move-to-start-of-line", modal.go_to_mode(mode.INS) },
    ["a"] = { mu.go_to_selection_end, modal.go_to_mode(mode.INS) },
    ["S+a"] = { "doc:move-to-end-of-line", mu.go_to_selection_start, modal.go_to_mode(mode.INS) },
    ["o"] = { "doc:newline-below", mu.go_to_selection_start, modal.go_to_mode(mode.INS) },
    ["S+o"] = { "doc:newline-above", mu.go_to_selection_start, modal.go_to_mode(mode.INS) },
    ["e a"] = { "doc:move-to-next-word-end", modal.go_to_mode(mode.INS) },

    ["v"] = modal.go_to_mode(mode.VIS),

    -- actions
    ["r $"] = mu.replace,
    ["S+r"] = "doc:paste",
    ["S+j"] = "doc:join-lines",
    ["u"] = "doc:undo",
    ["S+u"] = "doc:redo",
    ["p"] = mu.paste_after,
    ["S+p"] = mu.paste_before,
    ["y y"] = { "doc:select-lines", mu.copy },
    ["d d"] = { "doc:select-lines", mu.copy, "doc:delete-lines" },
    ["x"] = { mu.copy, "doc:delete" },

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
    ["f11"] = "core:toogle-full-screen",
    ["space w v"] = { "root:split-right", "root:switch-to-right" },
    ["space w s"] = { "root:split-down", "root:switch-to-down" },
    ["space w q"] = "root:close-node",
    ["space w S+q"] = "core:quit",
    ["space w left"] = "root:switch-to-left",
    ["space w right"] = "root:switch-to-right",
    ["space w up "] = "root:switch-to-up",
    ["space w down"] = "root:switch-to-down",
    ["space w S+="] = "root:grow",
    ["space w -"] = "root:shrink",

    -- LITE
    ["space \\"] = "treeview:toggle",
    ["space l l"] = "core:open-log",
    ["space l s+L"] = "log:open-as-doc",
    ["space l u"] = "core:open-user-module",
    ["space l r"] = "core:reload-module",
    ["space l S+r"] = "core:restart",
    ["space l s"] = "ui:settings",

    -- Modal
    ["space S+/"] = "modal:help",

    -- LSP (Require lintplus and LSP plugins)
    ["space k"] = "lsp:show-symbol-info",
    ["space r"] = "lsp:rename-symbol",
    ["space S+d"] = "lsp:view-all-diagnostics",
    ["space d"] = "lsp:view-document-diagnostics",
    ["space S+s"] = "lsp:find-workspace-symbol",
    ["space s"] = "lsp:view-document-symbols",
    -- -- Go To(LSP)
    ["g d"] = "lsp:goto-definition",
    ["g i"] = "lsp:goto-implementation",
    ["g r"] = "lsp:find-references",
  },
  VIS = {
    ["escape"] = modal.go_to_mode(mode.NOR),
    -- movement
    ["left"] = { "doc:select-to-previous-char", "dialog:previous-entry" },
    ["right"] = { "doc:select-to-next-char", "dialog:next-entry" },
    ["up"] = { "command:select-previous", "doc:select-to-previous-line" },
    ["down"] = { "command:select-next", "doc:select-to-next-line" },
    ["h"] = "doc:select-to-previous-char",
    ["l"] = "doc:select-to-next-char",
    ["k"] = "doc:select-to-previous-line",
    ["j"] = "doc:select-to-next-line",
    ["pageup"] = "doc:select-to-previous-page",
    ["pagedown"] = "doc:select-to-next-page",
    ["g j"] = "doc:select-to-next-line",
    ["g k"] = "doc:select-to-previous-line",
    ["w"] = mu.select_to_next_word_start,
    ["S+w"] = mu.select_to_next_WORD_start,
    ["e"] = "doc:select-to-next-word-end",
    ["S+e"] = "doc:select-to-next-word-end",
    ["b"] = "doc:select-to-previous-word-start",
    ["S+b"] = "doc:select-to-previous-word-start",
    -- ["g e"] = "doc:move-to-previous-word-end", -- to implement
    -- ["g S+e"] = "doc:move-to-previous-WORD-end", -- to implement
    ["0"] = "doc:select-to-start-of-line",
    ["S+4"] = "doc:select-to-end-of-line",
    ["S+5"] = "bracket-match:select-to-matching",
    ["S+6"] = { "doc:select-to-start-of-line", mu.select_to_next_word_start },
    ["g S+-"] = { "doc:select-to-end-of-line", "doc:select-to-previous-word-end" },
    ["g g"] = "doc:select-to-start-of-doc",
    ["S+g"] = { "doc:select-to-end-of-doc", "doc:select-to-start-of-line" },
    ["f $"] = mu.select_next_char,
    ["S+f $"] = mu.select_prev_char,
    ["t $"] = mu.select_till_next_char,
    ["S+t $"] = mu.select_till_prev_char,
    ["S+]"] = "doc:select-to-next-block-end",
    ["S+["] = "doc:select-to-previous-block-start",

    -- base command
    ["return"] = { "command:submit", "dialog:select" },

    -- actions
    ["r $"] = mu.replace,
    ["S+r"] = "doc:paste",
    ["S+j"] = "doc:join-lines",
    ["u"] = "doc:undo",
    ["S+u"] = "doc:redo",
    ["p"] = mu.paste_after,
    ["S+p"] = mu.paste_before,
    ["y"] = { mu.copy },
    ["d"] = { mu.copy, "doc:delete-lines" },
    ["x"] = { mu.copy, "doc:delete" },
  },
  INS = {
    ["escape"] = modal.go_to_mode(mode.NOR)
  },
}

modal.load_bindings(kb_model)
