-- Keyboard actions registered by the optional Pragtical LSP plugin.
local bindings = {
  a = "code-action", c = "complete", f = "format-document",
  k = "show-symbol-info", K = "show-symbol-info-in-tab",
  h = "show-signature", H = "view-call-hierarchy", r = "rename-symbol",
  d = "view-document-diagnostics", D = "view-all-diagnostics",
  s = "view-document-symbols", S = "find-workspace-symbol",
  gd = "goto-definition", gi = "goto-implementation", gr = "find-references",
  td = "toggle-diagnostics", ts = "toggle-symbols-tree",
  ta = "enable-symbols-tree-auto-hide",
  vs = "start-servers", vx = "stop-servers", vr = "restart-servers",
}

---Add the common language-server shortcuts and group captions in the preset's
---notation.
---@param keymap modal.keymap
---@param helpers modal.helpers
---@param space string Space-key spelling for this preset.
return function(keymap, helpers, space)
  ---Build the language-server prefix and suffix in the preset's binding
  ---notation.
  ---@param suffix string
  ---@return string
  local function sequence(suffix)
    if space == "<space>" then return space .. "l" .. suffix end
    local keys = { space, "l" }
    for key in suffix:gmatch(".") do
      keys[#keys + 1] = key:match("%u") and "S+" .. key:lower() or key
    end
    return table.concat(keys, " ")
  end
  for key, action in pairs(bindings) do
    keymap[sequence(key)] = "lsp:" .. action
  end
  helpers[space] = helpers[space] or {}
  table.insert(helpers[space], { "l", "Language Server" })
  helpers[sequence("")] = {
    { "g", "Navigation" }, { "t", "Display" }, { "v", "Servers" },
  }
end
