local modal = require "plugins.modal"

local mode = { NOR = 1, INS = 2, SEL = 3 }
modal.mode = mode.NOR

modal.modes = { "NOR", "INS", "SEL" }
modal.keymaps = {
  [mode.NOR] = {
    ["i"] = modal.go_to_mode(mode.INS),
    ["o"] = { "doc:newline-below", modal.go_to_mode(mode.INS) },
    ["v"] = modal.go_to_mode(mode.SEL),
    ["u"] = "doc:undo",
    ["U"] = "doc:redo",
    ["p"] = "doc:paste",
    ["y"] = "doc:copy",
    [":"] = "core:find-command",
    ["<left>"] = { "doc:move-to-previous-char", "dialog:previous-entry" },
    ["<right>"] = { "doc:move-to-next-char", "dialog:next-entry" },
    ["<up>"] = { "command:select-previous", "doc:move-to-previous-line" },
    ["<down>"] = { "command:select-next", "doc:move-to-next-line" },
    ["<space>f"] = "core:find-file",
    ["<space>F"] = "core:open-file",
    ["<space>P"] = "core:open-project-folder",
    ["<f11>"] = "core:toogle-full-screen",
    ["<space>wv"] = { "root:split-left", "root:switch-to-left" },
    ["<space>ws"] = { "root:split-down", "root:switch-to-down" },
    ["<space>wq"] = "root:close-or-quit",
    ["<space>w<left>"] = "root:switch-to-left",
    ["<space>w<right>"] = "root:switch-to-right",
    ["<space>w<up>"] = "root:switch-to-up",
    ["<space>w<down>"] = "root:switch-to-down",
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
