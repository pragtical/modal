local config = require "core.config"
local modal = require "plugins.modal" -- modal function
local modal_utils = require "plugins.modal.utils" -- modal utilities
modal.mode_labels = { Move = "MOVE", Edit = "EDIT", Jump = "JUMP" }

---Mode IDs used by this example preset.
config.plugins.modal.modes = { "Move", "Edit", "Jump" }
---Mode given to newly opened documents.
config.plugins.modal.base_mode = "Move"

-- config.plugins.modal.on_key_callbacks.YOUR_MODE = modal.on_key_YOUR_CHOICE
config.plugins.modal.on_key_callbacks.Move = modal.on_key_command_only
config.plugins.modal.on_key_callbacks.Jump = modal.on_key_command_only
config.plugins.modal.on_key_callbacks.Edit = modal.on_key_passthrough

-- config.plugins.modal.keymaps.YOUR_MODE = YOUR_KEYMAP
---Movement bindings in the example preset use compact notation.
config.plugins.modal.keymaps.Move = {  -- configure keymap of mode [Move]
  -- A sequence can run a callback, a command ID, or an ordered list of both.
  ["e"] = modal.go_to_mode("Edit"), -- change mode to [Edit]
  ["j"] = modal.go_to_mode("Jump"), -- change mode to [Jump]
  ["right"] = "doc:move-to-next-char", -- move right
  ["left"] = "doc:move-to-previous-char", -- move left
  ["up"] = "doc:move-to-previous-line", -- move up
  ["down"] = "doc:move-to-next-line", -- move down
}

---Edit mode also accepts native Pragtical shortcuts.
config.plugins.modal.keymaps.Edit = {
  ["escape"] = modal.go_to_mode("Move"), -- go back to default mode
  ["C+S+;"] = "core:find-command", -- open command bar
  ["C+S+/"] = "modal:help", -- open modal help
}

config.plugins.modal.keymaps.Jump = { -- configure keymap of mode [Jump]
  ["escape"] = modal.go_to_mode("Move"), -- go back to default mode
  ["e"] = modal.go_to_mode("Edit"), -- go to mode [Edit]
  -- jump to next word end
  ["right"] = { "doc:select-none", "doc:select-to-next-word-end" },
  -- jump to previous word start
  ["left"] = { "doc:select-none", "doc:select-to-previous-word-start" },
  -- jump to last word of previous line
  ["up"] = {
    "doc:select-none", "doc:move-to-previous-line",
    "doc:move-to-end-of-line", "doc:select-to-previous-word-start"
  },
  -- jump to first word of next line
  ["down"] = {
    "doc:select-none", "doc:move-to-next-line",
    "doc:move-to-start-of-line", "doc:select-to-next-word-end"
  },
}

---Commands shared by the Move and Jump modes.
---@type modal.keymap
local common_bindings = {
  ["S+;"] = "core:find-command", -- open command bar
  ["space S+/"] = "modal:help", -- show modal help
  ["space q"] = "root:close", -- close tab
}

config.plugins.modal.keymaps.Move =
  modal_utils.concat(common_bindings, config.plugins.modal.keymaps.Move)
config.plugins.modal.keymaps.Jump =
  modal_utils.concat(common_bindings, config.plugins.modal.keymaps.Jump)


---Next-key captions shared by the Move and Jump modes.
---@type modal.helpers
local common_helpers = {
  -- ["SUB_SEQUENCE"] = {
  --   {"REST_OF_SEQUENCE", "DESCRIPTION"},
  --   ...
  -- }
  ["space"] = {
    {"S+/", "show help"},
    {"q", "close document"},
  }
}

-- config.plugins.modal.helpers.YOUR_MODE = YOUR_HELPERS
config.plugins.modal.helpers.Move = common_helpers -- set helpers
config.plugins.modal.helpers.Jump = common_helpers -- set helpers


-- local kb_model = require "plugins.modal.bindings_models.YOUR_CHOICE"
local kb_model = require "plugins.modal.bindings_models.compact"
modal.load_bindings(kb_model, nil, "example")
