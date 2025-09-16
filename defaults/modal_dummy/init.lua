local config = require "core.config"
local modal = require "plugins.modal" -- modal function
local modal_utils = require "plugins.modal.utils" -- modal utilities

config.plugins.modal.modes = { "Move", "Edit" , "Jump"} -- List of modes (3 modes for the example but any number of mode is supproted)
config.plugins.modal.base_mode = "Normal" -- DEFAULT MODE (used when starting lite-xl or opening a file)

-- config.plugins.modal.on_key_callbacks.YOUR_MODE = modal.on_key_YOUR_CHOICE
config.plugins.modal.on_key_callbacks.Move = modal.on_key_command_only -- to navigate
config.plugins.modal.on_key_callbacks.Jump = modal.on_key_command_only -- to navigate but quickly
config.plugins.modal.on_key_callbacks.Edit = modal.on_key_passthrough -- to edit your file

-- config.plugins.modal.keymaps.YOUR_MODE = YOUR_KEYMAP
config.plugins.modal.keymaps.Normal = {  -- configure keymap of mode [Normal]
  -- ["SEQUENCE_TO_MATCH"] = callback/"COMMAND"/{callback/"COMMAND"...} -- you can mix both callback and command
  ["e"] = modal.go_to_mode("Edit"), -- change mode to [Edit]
  ["j"] = modal.go_to_mode("Jump"), -- change mode to [Jump] 
  ["right"] = "doc:move-to-next-char", -- move right
  ["left"] = "doc:move-to-previous-char", -- move left
  ["up"] = "doc:move-to-previous-line", -- move up
  ["down"] = "doc:move-to-next-line", -- move down
}

config.plugins.modal.keymaps.Edit = { -- configure keymap of mode [Edit]
  ["escape"] = modal.go_to_mode("Move"), -- go back to default mode
  ["C+S+;"] = "core:find-command", -- open command bar
  ["C+S+/"] = "modal:help", -- open modal help
} -- NOTE that this mode is passtrought so you can use the lite-xl **default shortcuts as well**

config.plugins.modal.keymaps.Jump = { -- configure keymap of mode [Jump]
  ["escape"] = modal.go_to_mode("Move"), -- go back to default mode 
  ["e"] = modal.go_to_mode("Edit"), -- go to mode [Edit]
  ["right"] = { "doc:select-none", "doc:select-to-next-word-end" }, -- jump to next word end
  ["left"] = { "doc:select-none", "doc:select-to-previous-word-start" }, -- jump to previous word start
  ["up"] = { "doc:select-none", "doc:move-to-previous-line", "doc:move-to-end-of-line", "doc:select-to-previous-word-start" }, -- jump to last word of previous line
  ["down"] = { "doc:select-none", "doc:move-to-next-line", "doc:move-to-start-of-line", "doc:select-to-next-word-end" }, -- jump to first word of next line
}

local common_bindings = {
  ["S+;"] = "core:find-command", -- open command bar
  ["space S+/"] = "modal:help", -- show modal help
  ["space q"] = "root:close", -- close tab}
}

config.plugins.modal.keymaps.Normal = modal_utils.concat(common_bindings, config.plugins.modal.keymaps.Normal) -- add common binds
config.plugins.modal.keymaps.Jump = modal_utils.concat(common_bindings, config.plugins.modal.keymaps.Jump) -- add common binds


-- helper definition
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
config.plugins.modal.helpers.Normal = common_helpers -- set helpers
config.plugins.modal.helpers.Jump = common_helpers -- set helpers


-- 
-- local kb_model = require "plugins.modal.bindings_models.YOUR_CHOICE"
local kb_model = require "plugins.modal.bindings_models.compact"
modal.load_bindings(kb_model) -- store the keybindings and helpers in the internal representation

-- config.plugins.modal.status_bar.mode = true -- show current mode (default is true)
config.plugins.modal.status_bar.strokes = false -- disable current strokes in status bar
modal.set_status_bar() -- update statusbar

