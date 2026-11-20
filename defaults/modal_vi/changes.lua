local core = require "core"
local config = require "core.config"
local Doc = require "core.doc"
local translate = require "core.doc.translate"
local modal = require "plugins.modal"

---@alias modal.insert_kind "insert"|"open"
---@alias modal.translate fun(doc: core.doc, line: integer, col: integer):
---integer, integer
---@alias modal.undo_stack { idx: integer, force_group?: boolean }

---A repeatable edit, recorded after it changes the document.
---@class modal.change
---@field action modal.action
---@field count integer
---@field input? string Wildcard input captured when the edit was made.
---@field prefix? string Original numeric prefix, empty for an implicit count.

---An edit that entered Insert mode. Byte positions track its primary span.
---@class modal.insertion : modal.change
---@field kind? modal.insert_kind Counted insertion or repeated line opening.
---@field changed boolean Whether the action edited text before insertion.
---@field stack? modal.undo_stack Original stack while tracking edits.
---@field undo_index? integer Expected next stack position.
---@field l1 integer Start line of the inserted text.
---@field c1 integer Start byte column.
---@field l2 integer End line of the inserted text.
---@field c2 integer Exclusive end byte column.
---@field left integer Graphemes removed before the insertion.
---@field right integer Graphemes removed after the insertion.
---@field text? string Committed insertion text captured on leaving Insert.
---@field back? integer Cursor distance in graphemes from its end.

---Record and replay Vi edits, including text entered through native input.
---@class plugins.modal.vi.changes
local changes = {}
---@type modal.change|modal.insertion|nil
local last_change
local next_char, prev_char = translate.next_char, translate.previous_char

---Compare two document positions in reading order.
---@param l integer
---@param c integer
---@param line integer
---@param col integer
---@return boolean
local function before(l, c, line, col)
  return l < line or (l == line and c < col)
end

---Count grapheme steps from a start position to an end position.
---@param doc core.doc
---@param l integer
---@param c integer
---@param line integer
---@param col integer
---@return integer
local function distance(doc, l, c, line, col)
  local n = 0
  while before(l, c, line, col) do
    local next_line, next_col = next_char(doc, l, c)
    if l == next_line and c == next_col then break end
    l, c = next_line, next_col
    n = n + 1
  end
  return n
end

---Walk up to the given number of graphemes, stopping at a document boundary.
---@param doc core.doc
---@param line integer
---@param col integer
---@param fn modal.translate
---@param count integer
---@return integer line
---@return integer col
local function step(doc, line, col, fn, count)
  for _ = 1, count do
    local l, c = fn(doc, line, col)
    if l == line and c == col then break end
    line, col = l, c
  end
  return line, col
end

---Start tracking the primary inserted span and its undo-stack position.
---@param doc core.doc
---@param action modal.action
---@param count integer
---@param kind modal.insert_kind?
---@param changed boolean
---@param input string?
---@param prefix string?
---@return modal.insertion
local function insertion(doc, action, count, kind, changed, input, prefix)
  local line, col = doc:get_selection()
  return {
    action = action, count = count, kind = kind, changed = changed,
    input = input, prefix = prefix, left = 0, right = 0,
    l1 = line, c1 = col, l2 = line, c2 = col,
    stack = doc.undo_stack, undo_index = doc.undo_stack.idx,
  }
end

---Enter Insert mode to replay a new insertion after a caret move.
local function enter_insert()
  modal.set_mode("INS")
end

---Materialize deferred block padding before the first edit and restart capture
---beyond the padding.
---@param doc core.doc
function changes.prepare_insert(doc)
  local view = core.active_view
  local state = view and view.modal
  if not state or view.doc ~= doc or not state.prepare_block_insert then
    return
  end
  local prepare, pending = state.prepare_block_insert, state.pending_change
  state.prepare_block_insert, state.pending_change = nil, nil
  prepare()
  if pending then
    state.pending_change = insertion(doc, pending.action, pending.count,
      pending.kind, pending.changed, pending.input, pending.prefix)
  end
end

for _, name in ipairs({ "text_input", "ime_text_editing" }) do
  local original = Doc[name]
  Doc[name] = function(doc, text, ...)
    if text ~= "" then changes.prepare_insert(doc) end
    return original(doc, text, ...)
  end
end

---Get the active insertion record for this undo stack, discarding stale history
---or restarting after a caret move.
---@param doc core.doc
---@param stack modal.undo_stack
---@overload fun(doc: core.doc, stack: modal.undo_stack): modal.insertion?
---@param line integer
---@param col integer
---@param end_line integer
---@param end_col integer
---@return modal.insertion?
local function recording(doc, stack, line, col, end_line, end_col)
  local view = core.active_view
  if view and view.doc == doc and view.modal
    and config.plugins.modal.enabled then
    local s = view.modal.pending_change
    if s and (doc.replaying or doc.undo_stack ~= s.stack
      or s.stack.idx ~= s.undo_index) then
      view.modal.pending_change = nil
    elseif stack == doc.undo_stack then
      -- Typing again after moving to a different part of the document starts
      -- a new insertion. Edits for other cursors still shift the primary span.
      if s and line and (before(end_line, end_col, s.l1, s.c1)
        or before(s.l2, s.c2, line, col)) then
        local l, c = doc:get_selection()
        if (l == line and c == col) or (l == end_line and c == end_col) then
          s = insertion(doc, enter_insert, 1, "insert", false, nil, "")
          view.modal.pending_change = s
        end
      end
      return s
    end
  end
end

---Map a position after an edit by translating its line and column relative to
---the old boundary.
---@param l integer
---@param c integer
---@param from integer
---@param at integer
---@param to integer
---@param finish integer
---@return integer line
---@return integer col
local function shifted(l, c, from, at, to, finish)
  if l == from then return to, finish + c - at end
  return l + to - from, c
end

-- Track the primary insertion as a range. This captures the committed text
-- from typing, paste, completion and IME, including corrections with Backspace.
local raw_insert = Doc.raw_insert
---Track how a raw insertion shifts the recorded span before delegating to
---Pragtical.
---@param line integer
---@param col integer
---@param text string
---@param stack modal.undo_stack
---@param ... any Forwarded host edit arguments.
function Doc:raw_insert(line, col, text, stack, ...)
  local s = recording(self, stack, line, col, line, col)
  if s and text ~= "" then
    local rows, finish = 0, col + #text
    for newline in text:gmatch("()\n") do
      rows, finish = rows + 1, #text - newline + 1
    end
    if before(line, col, s.l1, s.c1) then
      s.l1, s.c1 = shifted(s.l1, s.c1, line, col, line + rows, finish)
    end
    if not before(s.l2, s.c2, line, col) then
      s.l2, s.c2 = shifted(s.l2, s.c2, line, col, line + rows, finish)
    end
  end
  local result = raw_insert(self, line, col, text, stack, ...)
  if s then s.undo_index = stack.idx end
  return result
end

---Map a position through a removal, collapsing positions inside it to the
---start.
---@param l integer
---@param c integer
---@param l1 integer
---@param c1 integer
---@param l2 integer
---@param c2 integer
---@return integer line
---@return integer col
local function after_remove(l, c, l1, c1, l2, c2)
  if before(l, c, l1, c1) then return l, c end
  if before(l, c, l2, c2) then return l1, c1 end
  return shifted(l, c, l2, c2, l1, c1)
end

local raw_remove = Doc.raw_remove
---Track removed graphemes and adjust the captured span around a native
---deletion.
---@param l1 integer
---@param c1 integer
---@param l2 integer
---@param c2 integer
---@param stack modal.undo_stack
---@param ... any Forwarded host edit arguments.
function Doc:raw_remove(l1, c1, l2, c2, stack, ...)
  local s = recording(self, stack, l1, c1, l2, c2)
  if s then
    if not before(l2, c2, s.l1, s.c1) and not before(s.l2, s.c2, l1, c1) then
      s.left = s.left + distance(self, l1, c1, s.l1, s.c1)
      s.right = s.right + distance(self, s.l2, s.c2, l2, c2)
    end
    s.l1, s.c1 = after_remove(s.l1, s.c1, l1, c1, l2, c2)
    s.l2, s.c2 = after_remove(s.l2, s.c2, l1, c1, l2, c2)
  end
  local result = raw_remove(self, l1, c1, l2, c2, stack, ...)
  if s then s.undo_index = stack.idx end
  return result
end

---Run an edit and remember its replay action or begin tracking the following
---insertion.
---@param action modal.action
---@param count integer
---@param kind? modal.insert_kind
---@param replay? modal.action Reconstructs the original selection on repeat.
function changes.perform(action, count, kind, replay)
  local view = core.active_view
  local cmd = view.modal.current_command or { n_repeat = "" }
  local old = view.doc:get_change_id()
  modal.eval_cmd(action, kind and 1 or count)
  local changed = view.doc:get_change_id() ~= old
  action = replay or action
  if view.modal.mode == "INS" then
    view.modal.pending_change = insertion(view.doc, action, count, kind,
      changed, cmd.input, cmd.n_repeat)
  elseif changed then
    last_change = {
      action = action, count = count, input = cmd.input, prefix = cmd.n_repeat
    }
  end
end

---Create a counted binding that records successful edits for dot repeat.
---@param action modal.action
---@param kind? modal.insert_kind
---@return modal.counted_action
function changes.track(action, kind)
  ---Execute and record the wrapped editing action.
  ---@param count integer
  local function perform(count) changes.perform(action, count, kind) end
  modal.fns[perform] = modal.describe_action(action)
  return modal.with_count(perform)
end

---Replay captured replacement text, deletions and cursor movement at each
---caret.
---@param doc core.doc
---@param s modal.insertion
local function insert_again(doc, s)
  if s.text ~= "" then changes.prepare_insert(doc) end
  for idx, line, col in doc:get_selections(false, true) do
    local l1, c1 = step(doc, line, col, prev_char, s.left)
    local l2, c2 = step(doc, line, col, next_char, s.right)
    doc:set_selections(idx, l1, c1, l2, c2)
    doc:text_input(s.text, idx)
    line, col = doc:get_selection_idx(idx)
    if line then
      doc:set_selections(idx, step(doc, line, col, prev_char, s.back))
    end
  end
end

---Finish block insertion if active, step back one character and enter Normal
---mode.
---@param view modal.docview
local function leave_insert(view)
  if view.modal.finish_block_insert then
    view.modal.finish_block_insert(view)
    modal.set_mode("NOR")
    return
  end
  view.doc:move_to(function(doc, line, col)
    if col > 1 then return prev_char(doc, line, col) end
    return line, col
  end)
  modal.set_mode("NOR")
end

---Commit the insertion record, apply any remaining repetitions and leave Insert
---mode.
function changes.finish()
  local view = core.active_view
  local doc = view.doc
  local s = recording(doc, doc.undo_stack)
  view.modal.pending_change = nil
  if s then
    s.stack, s.undo_index = nil, nil
    s.text = doc:get_text(s.l1, s.c1, s.l2, s.c2)
    local line, col = doc:get_selection()
    s.back = before(line, col, s.l1, s.c1) and 0
      or distance(doc, line, col, s.l2, s.c2)
    if s.changed or s.text ~= "" or s.left > 0 or s.right > 0 then
      if s.kind then
        for _ = 2, s.count do
          if s.kind == "open" then modal.eval_cmd(s.action) end
          insert_again(doc, s)
        end
      end
      last_change = s
    end
  end
  leave_insert(view)
end

---Replay the last successful edit, using an explicit count when supplied.
---@param count integer
local function repeat_change(count)
  local view, s = core.active_view, last_change
  if not s then return end
  local cmd = view.modal.current_command
  local explicit = cmd.n_repeat ~= ""
  count = explicit and count or s.count
  local old_input = view.modal.last_input
  view.modal.current_command = { cmd = s.action, num = count, input = s.input,
    n_repeat = explicit and tostring(count) or s.prefix }
  view.modal.last_input = s.input
  view.doc.undo_stack.force_group = true
  local ok, err = pcall(function()
    modal.eval_cmd(s.action, s.kind and 1 or count)
    if s.text and view.modal.mode == "INS" then
      ---@cast s modal.insertion
      insert_again(view.doc, s)
      for _ = 2, s.kind and count or 1 do
        if s.kind == "open" then modal.eval_cmd(s.action) end
        insert_again(view.doc, s)
      end
      leave_insert(view)
    end
  end)
  view.modal.current_command, view.modal.last_input = cmd, old_input
  if not ok then error(err, 0) end
  if explicit then s.count, s.prefix = count, tostring(count) end
end

---Repeat the last recorded change with its original or an explicit count.
changes.repeat_last = modal.with_count(repeat_change)
modal.fns[changes.repeat_last] = "Repeat last change"
return changes
