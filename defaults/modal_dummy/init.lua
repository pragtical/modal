local config = require "core.config"

local modal = require "plugins.modal"
local kb_style = require "plugins.modal.bindings_models.modal"

config.plugins.modal.status_bar.strokes = false
modal.set_status_bar()

config.plugins.modal.modes = { "Move", "Edit", "Jump" }
config.plugins.modal.base_mode = "Move"

config.plugins.modal.on_key_callbacks.Move = modal.on_key_command_only
config.plugins.modal.on_key_callbacks.Edit = modal.on_key_passthrough
config.plugins.modal.on_key_callbacks.Jump = modal.on_key_command_only

config.plugins.modal.keymaps.Move = {
  ["e"] = modal.go_to_mode("Edit"),
  ["j"] = modal.go_to_mode("Jump"),
  ["<right>"] = "doc:move-to-next-char",
  ["<left>"] = "doc:move-to-previous-char",
  ["<up>"] = "doc:move-to-previous-line",
  ["<down>"] = "doc:move-to-next-line",
  [":"] = "core:find-command",
  ["<space>?"] = "modal:help",
  ["<space>q"] = "root:close",
}

config.plugins.modal.keymaps.Edit = {
  ["<ESC>"] = modal.go_to_mode("Move"),
  ["C-P"] = "core:find-command",
  ["C-?"] = "modal:help",
}

config.plugins.modal.keymaps.Jump = {
  ["<ESC>"] = modal.go_to_mode("Move"),
  ["e"] = modal.go_to_mode("Edit"),
  ["<right>"] = { "doc:select-none", "doc:select-to-next-word-end" },
  ["<left>"] = { "doc:select-none", "doc:select-to-previous-word-start" },
  ["<up>"] = { "doc:select-none", "doc:move-to-previous-line", "doc:move-to-end-of-line", "doc:select-to-previous-word-start" },
  ["<down>"] = { "doc:select-none", "doc:move-to-next-line", "doc:move-to-start-of-line", "doc:select-to-next-word-end" },
  [":"] = "core:find-command",
  ["<space>?"] = "modal:help",
}
modal.load_bindings(kb_style)
