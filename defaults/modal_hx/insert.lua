local core = require "core"
local command = require "core.command"
local translate = require "core.doc.translate"
local modal = require "plugins.modal"
local selection = modal.selection
local next_char, prev_char = translate.next_char, translate.previous_char

---Recorded Insert events. Each entry is a text edit or cursor movement.
---@class modal.hx_insertion
---@field action modal.action The command that entered Insert mode.
---@field events table[] Arguments for a text edit or an arrow binding.
local last_insert
local replaying = false

---Record a committed edit before applying it at every inclusive cursor.
---@param doc core.doc
---@param text string
---@param erase? string
local function edit(doc, text, erase)
  local state = core.active_view.modal
  if state.hx_insert then
    table.insert(state.hx_insert.events, { text = text, erase = erase })
  end
  selection.edit_at_cursors(doc, text, erase, state.append_cursor)
end

---Enter Insert at either edge of a range or at a line insertion point.
---@param key string
local function enter(key)
  local view = core.active_view
  local doc = view.doc
  if view.modal.mode ~= "INS" and not replaying then
    view.modal.hx_insert = { action = view.modal.current_command.cmd,
      events = {} }
  end
  if key == "o" or key == "O" then
    command.perform(key == "o" and "doc:newline-below" or "doc:newline-above")
  end
  for idx, l, c, a, b in doc:get_selections(true, true) do
    if key == "a" then
      if a == #doc.lines and b == #doc.lines[a] and (a ~= l or b ~= c) then
        doc:insert(a, b, "\n")
      end
      local row, col = next_char(doc, a, b)
      doc:set_selections(idx, row, col, l, c)
    elseif key == "i" and (l ~= a or c ~= b) then
      doc:set_selections(idx, l, c, a, b)
    else
      if key == "I" then c = doc.lines[l]:find("%S") or 1 end
      if key == "A" then l, c = a, #doc.lines[a] end
      local row, col = next_char(doc, l, c)
      doc:set_selections(idx, l, c, row, col)
    end
  end
  modal.set_mode("INS")
  view.modal.append_cursor = key == "a"
  view.modal.insert_text = edit
end

---Restore the appended range and return to Normal with its selection intact.
local function finish()
  local view = core.active_view
  if view.modal.append_cursor then
    local doc = view.doc
    for idx, l, c, a, b in doc:get_selections() do
      if l ~= a or c ~= b then l, c = prev_char(doc, l, c) end
      doc:set_selections(idx, l, c, a, b)
    end
  end
  if view.modal.hx_insert then
    last_insert, view.modal.hx_insert = view.modal.hx_insert, nil
  end
  view.modal.append_cursor = nil
  modal.set_mode("NOR")
end

---Install selection-aware insertion commands in the Helix mode maps.
---@param maps table<string, modal.keymap>
return function(maps)
  for _, key in ipairs({ "i", "I", "a", "A", "o", "O" }) do
    local action = function() enter(key) end
    modal.fns[action] = "Enter Insert with " .. key
    maps.NOR[key], maps.SEL[key] = action, action
  end
  for _, key in ipairs({ "backspace", "delete" }) do
    local action = function() edit(core.active_view.doc, "", key) end
    modal.fns[action] = "Erase with " .. key
    maps.INS["<" .. key .. ">"] = action
  end
  maps.INS["<return>"] = function()
    edit(core.active_view.doc, "\n")
  end
  maps.INS["<tab>"] = function()
    local doc = core.active_view.doc
    local kind, size = doc:get_indent_info()
    edit(doc, kind == "soft" and (" "):rep(size) or "\t")
  end
  local move = require "plugins.modal.defaults.modal_hx.movement"
  for _, key in ipairs({ "<left>", "<right>", "<up>", "<down>" }) do
    local action = move(key, false)
    maps.INS[key] = function()
      local recording = core.active_view.modal.hx_insert
      if recording then table.insert(recording.events, { key = key }) end
      action(1)
      enter("i")
    end
  end
  ---Repeat the command that entered Insert mode and its committed inputs.
  local function repeat_insert()
    if not last_insert then return end
    replaying = true
    local ok, err = pcall(function()
      modal.eval_cmd(last_insert.action)
      for _, event in ipairs(last_insert.events) do
        if event.key then
          maps.INS[event.key]()
        else
          edit(core.active_view.doc, event.text, event.erase)
        end
      end
      finish()
    end)
    replaying = false
    if not ok then error(err, 0) end
  end
  maps.NOR["."], maps.SEL["."] = repeat_insert, repeat_insert
  modal.fns[repeat_insert] = "Repeat last insertion"
  modal.fns[finish] = "Return to Normal"
  maps.INS["<ESC>"] = finish
end
