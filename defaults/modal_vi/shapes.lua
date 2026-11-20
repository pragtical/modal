local core = require "core"
local modal = require "plugins.modal"
local block = require "plugins.modal.block"
local selection = modal.selection
local changes = require "plugins.modal.defaults.modal_vi.changes"
local operators = require "plugins.modal.defaults.modal_vi.operators"
local register = require "plugins.modal.defaults.modal_vi.register"
local translate = require "core.doc.translate"
local common = require "core.common"

---Vi motions and edits on linewise and blockwise visual selections.
---@class plugins.modal.vi.shapes
local shapes = {}
shapes.line = "VLINE"
shapes.block = "VBLOCK"

local kinds = { [shapes.line] = "line", [shapes.block] = "block" }

---Get the active line or block corners, initializing them from native
---selections if needed.
---@param view modal.docview
---@return modal.shape
local function corners(view)
  return selection.get(view) or selection.set(view, kinds[view.modal.mode])
end

---Enter linewise or blockwise Visual mode and extend the initial selection by
---the count.
---@param view modal.docview
---@param mode string Vi shape mode ID.
---@param count integer
function shapes.enter(view, mode, count)
  local doc = view.doc
  local line, col, a, b = doc:get_selection()
  local s = { line = line, col = col, anchor_line = a, anchor_col = b }
  if count > 1 then
    if mode == shapes.line then
      s.line = math.min(#doc.lines, line + count - 1)
      s.col = block.at(doc, s.line, block.cells(doc, line, col))
    else
      s.col = block.at(doc, line, block.cells(doc, line, col) + count - 1)
    end
  end
  modal.set_mode(mode)
  selection.set(view, kinds[mode], s)
end

local vertical = { j = 1, down = 1, k = -1, up = -1 }
local horizontal = { l = 1, right = 1, h = -1, left = -1 }

---Adapt a normal-mode motion to move a selection's active corner.
---@param action modal.action? Fallback motion for the active corner.
---@param key string Binding in compact notation.
---@return modal.counted_action
function shapes.motion(action, key)
  ---Move the active corner, retaining the desired display column on vertical
  ---motions.
  ---@param count integer
  local function move(count)
    local view = core.active_view
    local doc, s = view.doc, corners(view)
    if vertical[key] then
      local cell, after = block.cells(doc, s.line, s.col)
      s.goal = s.goal or math.max(cell, after - 1)
      s.line = math.max(1, math.min(#doc.lines, s.line + vertical[key] * count))
      s.col = block.at(doc, s.line, s.to_eol and math.huge or s.goal)
    else
      if horizontal[key] then
        local step = horizontal[key] == 1 and translate.next_char
          or translate.previous_char
        for _ = 1, count do
          local l, c = step(doc, s.line, s.col)
          if l ~= s.line or c == s.col then break end
          s.col = c
          s.goal, s.to_eol = nil, nil
        end
      elseif key == "S+g" or key == "g g" then
        local cmd = view.modal.current_command
        s.line = key == "S+g" and cmd.n_repeat == "" and #doc.lines
          or math.min(count, #doc.lines)
        s.col = doc.lines[s.line]:find("%S") or 1
        s.goal, s.to_eol = nil, nil
      else
        doc:set_selection(s.line, s.col)
        modal.eval_cmd(action, count)
        s.line, s.col = doc:get_selection()
        s.goal, s.to_eol = nil, key == "S+4"
      end
    end
    selection.set(view, s.kind, s)
  end
  modal.fns[move] = "Extend selection with " .. key
  return modal.with_count(move)
end

---Exchange the head and anchor, or just their columns in a block.
---@param horizontal_only boolean
function shapes.swap(horizontal_only)
  local view = core.active_view
  local s = corners(view)
  if horizontal_only and view.modal.mode == shapes.block then
    local a = block.cells(view.doc, s.anchor_line, s.anchor_col)
    local b = block.cells(view.doc, s.line, s.col)
    s.col = block.at(view.doc, s.line, a)
    s.anchor_col = block.at(view.doc, s.anchor_line, b)
  else
    s.line, s.anchor_line = s.anchor_line, s.line
    s.col, s.anchor_col = s.anchor_col, s.col
  end
  s.goal = nil
  selection.set(view, s.kind, s)
end

---Store rectangular rows and their display widths in the clipboard register.
---@param rows modal.block_row[]
---@param width integer
---@param to_eol boolean Rows were selected through end of line.
local function write_block(rows, width, to_eol)
  local parts, whole = { block_width = width, widths = {} }, {}
  for i, row in ipairs(rows) do
    if row.short then
      local padding = width + (to_eol and 1 or 0)
      parts[i], parts.widths[i] = (" "):rep(padding), padding
    else
      parts[i], parts.widths[i] = row.text, row.width
    end
    whole[i] = false
  end
  register.write(table.concat(parts, "\n"), parts, whole)
end

---Apply an operator, paste, or replacement to a contiguous range of whole
---lines.
---@param view modal.docview
---@param op string
---@param top integer
---@param bottom integer
---@param paste modal.paste?
---@param replacement string?
local function line_edit(view, op, top, bottom, paste, replacement)
  local doc = view.doc
  local last = #doc.lines[bottom]
  if op == ">" or op == "<" then
    doc:indent_text(op == "<", top, 1, bottom, last)
    doc:set_selection(top, doc.lines[top]:find("%S") or 1)
  elseif op == "r" then
    for line = top, bottom do
      local count = 0
      for _ in common.utf8_graphemes(doc.lines[line]:sub(1, -2)) do
        count = count + 1
      end
      doc:remove(line, 1, line, #doc.lines[line])
      doc:insert(line, 1, replacement:rep(count))
    end
  elseif op == "p" or op == "P" then
    if op == "p" then
      local old = doc:get_text(top, 1, bottom, last)
      register.write(old .. "\n", { old }, { true })
    end
    local text = paste.linewise and paste.text:sub(1, -2) or paste.text
    doc:remove(top, 1, bottom, last)
    doc:insert(top, 1, text)
    doc:set_selection(top, doc.lines[top]:find("%S") or 1)
  else
    operators.apply_ranges(
      view, op, { { top, 1, bottom, last, linewise = true } })
  end
end

---Indent or unindent one line at a rectangle's left edge.
---@param doc core.doc
---@param line integer
---@param left integer
---@param unindent boolean
local function shift_block(doc, line, left, unindent)
  local col = block.at(doc, line, left)
  if col == #doc.lines[line] then return end
  local _, size = doc:get_indent_info()
  if unindent then
    local stop = doc.lines[line]:match("^[ \t]*()", col)
    local right = math.min(left + size, block.cells(doc, line, stop))
    if right <= left then return end
    local row = block.row(doc, line, left, right)
    doc:remove(line, row.first, line, row.finish)
    doc:insert(line, row.first, (" "):rep(row.leading + row.trailing))
  else
    doc:insert(line, block.insertion_col(doc, line, left), (" "):rep(size))
  end
end

---Restore one caret after editing a rectangle and remove its temporary input
---hooks.
---@param view modal.docview
local function finish_block_insert(view)
  local doc, state = view.doc, view.modal
  local line, col = doc:get_selection_idx(1)
  doc:set_selection(line, col)
  state.finish_block_insert, state.suspend_selection = nil, nil
  state.prepare_block_insert, state.before_insert_key = nil, nil
end

---Create per-line insertion carets and defer tab expansion or padding until
---text is entered.
---@param view modal.docview
---@param top integer
---@param bottom integer
---@param left integer
---@param right number
---@param append boolean Insert at the right edge instead of the left.
local function begin_block_insert(view, top, bottom, left, right, append)
  local doc = view.doc
  local cursors, needs_padding = {}, false
  for line = top, bottom do
    local eol = block.cells(doc, line, #doc.lines[line])
    if append or left <= eol then
      local cell = append and (right == math.huge and eol or right) or left
      local byte, start = block.at(doc, line, cell)
      cursors[#cursors + 1] = {line, byte, cell}
      doc:set_selections(#cursors, line, byte)
      needs_padding = needs_padding or cell > start
    end
  end
  doc.last_selection = 1
  if needs_padding then
    local revision = doc:get_change_id()
    view.modal.prepare_block_insert = function()
      if revision ~= doc:get_change_id() or #doc.selections ~= #cursors * 4 then
        return
      end
      for i, pos in ipairs(cursors) do
        local l, c, a, b = doc:get_selection_idx(i)
        if l ~= pos[1] or c ~= pos[2] or l ~= a or c ~= b then return end
      end
      for i, pos in ipairs(cursors) do
        doc:set_selections(i, pos[1], block.insertion_col(doc, pos[1], pos[3]))
      end
    end
    view.modal.before_insert_key = function(key)
      if key == "return" or key == "tab" or key == "delete"
        or key == "backspace" then
        changes.prepare_insert(doc)
      end
    end
  end
  modal.set_mode("INS")
  view.modal.finish_block_insert = function(target)
    finish_block_insert(target)
    doc:set_selection(top, (block.at(doc, top, left)))
  end
  view.modal.suspend_selection = finish_block_insert
end

---Insert captured clipboard contents according to their rectangular, linewise
---or characterwise shape.
---@param doc core.doc
---@param top integer
---@param bottom integer
---@param left integer
---@param paste modal.paste
local function paste_over_block(doc, top, bottom, left, paste)
  if paste.parts and paste.parts.block_width then
    local col = register.put_block(doc, top, left, paste.parts, 1)
    doc:set_selection(top, col)
  elseif paste.linewise then
    doc:insert(bottom, #doc.lines[bottom], "\n" .. paste.text:sub(1, -2))
    doc:set_selection(bottom + 1, 1)
  else
    local multiline = paste.text:find("\n", 1, true)
    for line = top, multiline and top or bottom do
      local col = block.insertion_col(doc, line, left)
      doc:insert(line, col, paste.text)
      if line == top then
        if not multiline then
          col = select(2, translate.previous_char(doc, line, col + #paste.text))
        end
        doc:set_selection(line, col)
      end
    end
  end
end

---Apply an editing operation to the selected cells of each row.
---@param view modal.docview
---@param op string
---@param top integer
---@param bottom integer
---@param left integer
---@param right number
---@param paste modal.paste?
---@param replacement string?
local function block_edit(
  view, op, top, bottom, left, right, paste, replacement)
  local doc = view.doc
  if op == "I" or op == "A" then
    return begin_block_insert(view, top, bottom, left, right, op == "A")
  elseif op == ">" or op == "<" then
    for line = top, bottom do shift_block(doc, line, left, op == "<") end
    return
  end
  local rows, max_width = {}, 0
  for line = top, bottom do
    local row = block.row(doc, line, left, right)
    rows[#rows + 1] = row
    max_width = math.max(max_width, row.width)
  end
  if op ~= "r" and op ~= "P" then
    write_block(rows, right == math.huge and max_width
      or right - left, right == math.huge)
  end
  if op ~= "y" then
    for i, row in ipairs(rows) do
      if row.first ~= row.finish then
        local line = top + i - 1
        local fill = op == "r" and replacement:rep(row.width) or ""
        doc:remove(line, row.first, line, row.finish)
        doc:insert(line, row.first,
          (" "):rep(row.leading) .. fill .. (" "):rep(row.trailing))
      end
    end
  end
  if paste then
    paste_over_block(doc, top, bottom, left, paste)
  elseif op == "c" then
    begin_block_insert(view, top, bottom, left, right, false)
  else
    local col = block.at(doc, top, left)
    if col > 1 and col == #doc.lines[top] then
      col = select(2, translate.previous_char(doc, top, col))
    end
    doc:set_selection(top, col)
  end
end

---Perform a Visual line or block operation and capture its dimensions for dot
---repeat.
---@param op string Vi operator or editing key.
function shapes.operate(op)
  local view = core.active_view
  local mode = view.modal.mode
  local top, bottom, left, right = selection.bounds(view.doc, corners(view))
  local replacement = view.modal.last_input
  if op == "r" and not replacement then return end
  if op == "C" or op == "D" then
    if mode == shapes.block then right = math.huge end
    op = op:lower()
  end
  local paste
  if op == "p" or op == "P" then
    local text, parts, _, linewise = register.read()
    if not text then return end
    paste = { text = text, parts = parts, linewise = linewise }
  end
  local height, width = bottom - top + 1, right - left
  ---Apply the captured operation at another document position with the original
  ---extent.
  ---@param target modal.docview
  ---@param line integer
  ---@param cell integer
  local function edit(target, line, cell)
    local last = math.min(#target.doc.lines, line + height - 1)
    target.doc:set_selection(line, mode == shapes.line and 1
      or block.at(target.doc, line, cell))
    if op ~= "y" then target.doc.undo_stack.force_group = true end
    if mode == shapes.line then
      line_edit(target, op, line, last, paste, replacement)
    else
      block_edit(target, op, line, last, cell, cell + width, paste, replacement)
    end
  end
  selection.release(view)
  modal.set_mode("NOR")
  if op == "y" then edit(view, top, left) return end
  ---Repeat the shaped edit with its upper-left corner at the current caret.
  local function replay()
    local target = core.active_view
    local l, c = target.doc:get_selection()
    edit(target, l, block.cells(target.doc, l, c))
  end
  changes.perform(
    function() edit(view, top, left) end, 1, nil, modal.with_count(replay))
end

return shapes
