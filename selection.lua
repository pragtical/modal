-- Project line and rectangular selections onto Pragtical's native ranges.
local core = require "core"
local common = require "core.common"
local translate = require "core.doc.translate"
local style = require "core.style"
local block = require "plugins.modal.block"

---@alias modal.shape_kind "line"|"block"

---Inclusive document positions. Lines and UTF-8 byte columns start at one.
---@class modal.corners
---@field line integer Moving corner's line.
---@field col integer Moving corner's byte column.
---@field anchor_line integer Fixed corner's line.
---@field anchor_col integer Fixed corner's byte column.
---@field to_eol? boolean Extend the selection to the end of every row.

---Logical selection and its most recent native projection.
---@class modal.shape : modal.corners
---@field kind modal.shape_kind
---@field edges? table<integer, modal.block_edge[]> Partial graphemes by line.
---@field selections? integer[] Native selection table at projection time.
---@field revision? integer Document change ID at projection time.
---@field suspended? boolean Projection collapsed while modal editing is off.
---@field goal? integer Desired display cell when moving vertically.

---Project linewise and blockwise selections for any modal preset.
---@class plugins.modal.selection
local selection = {}

---Get the inclusive head and anchor of a native half-open selection.
---@param doc core.doc
---@param idx integer
---@return integer line
---@return integer col
---@return integer anchor_line
---@return integer anchor_col
function selection.characters(doc, idx)
  local l, c, a, b = doc:get_selection_idx(idx)
  if l > a or l == a and c > b then
    l, c = translate.previous_char(doc, l, c)
  elseif l ~= a or c ~= b then
    a, b = translate.previous_char(doc, a, b)
  end
  return l, c, a, b
end

---Project two inclusive cursor positions onto a native selection.
---@param doc core.doc
---@param idx integer
---@param l integer
---@param c integer
---@param a integer
---@param b integer
function selection.set_characters(doc, idx, l, c, a, b)
  if l < a or l == a and c < b then
    a, b = translate.next_char(doc, a, b)
  else
    l, c = translate.next_char(doc, l, c)
  end
  doc:set_selections(idx, l, c, a, b)
end

---Expand empty carets to one grapheme when the mode selects its cursor.
---@param doc core.doc
function selection.ensure_characters(doc)
  for idx, l, c, a, b in doc:get_selections() do
    if l == a and c == b then selection.set_characters(doc, idx, l, c, a, b) end
  end
end

---Native ranges before and after temporarily collapsing block cursors.
---@class modal.saved_cursors
---@field ranges integer[]
---@field carets integer[]
---@field revision integer

---Leave a native caret at each block cursor when disabling its preset.
---@param view modal.docview
---@param remember? boolean Restore unchanged ranges on re-enabling editing.
function selection.collapse_cursor(view, remember)
  local state, doc = view.modal, view.doc
  if not state or not (state.select_cursor or state.insert_text) then return end
  if state.saved_cursors then return end
  local saved
  if remember then
    saved = { ranges = common.merge(doc.selections),
      revision = doc:get_change_id() }
  end
  for idx in doc:get_selections() do
    local l, c = selection.characters(doc, idx)
    doc:set_selections(idx, l, c)
  end
  if saved then
    saved.carets = common.merge(doc.selections)
    state.saved_cursors = saved
  end
end

---Resume a suspended range if the document and its carets are still current.
---@param view core.view
function selection.restore_cursors(view)
  local state = view.modal
  local saved = state and state.saved_cursors
  if not saved then return end
  state.saved_cursors = nil
  local doc = view.doc
  if doc:get_change_id() == saved.revision
    and #doc.selections == #saved.carets then
    local same = true
    for i, v in ipairs(doc.selections) do
      if v ~= saved.carets[i] then same = false break end
    end
    if same then doc.selections = saved.ranges return end
  end
  if state.insert_text then state.append_cursor = false end
  selection.ensure_characters(doc)
end

---Insert or erase at each block cursor without replacing its selection.
---@param doc core.doc
---@param text string
---@param erase? string Backspace or forward delete.
---@param append? boolean Keep the starting anchor for forward insertion.
function selection.edit_at_cursors(doc, text, erase, append)
  for idx in doc:get_selections(false, true) do
    local l, c = selection.characters(doc, idx)
    local a, b, last, stop = doc:get_selection_idx(idx, true)
    local suffix = #doc:get_text(l, c, last, stop)
    local value = text
    if text == "\n" then
      value = text .. doc.lines[l]:sub(1, c - 1):match("^[ \t]*")
    end
    if erase then
      local step = erase == "backspace" and translate.previous_char
        or translate.next_char
      local row, col = step(doc, l, c)
      doc:remove(l, c, row, col)
      if erase == "backspace" then
        l, c = row, col
        if a > l or a == l and b > c then a, b = l, c end
      elseif not append then
        suffix = math.max(0, suffix - (row == l and col - c or 1))
      end
    else
      doc:set_selections(idx, l, c)
      doc:text_input(value, idx)
      l, c = doc:get_selection_idx(idx)
    end
    if append and suffix > 0 then
      local row, col = translate.next_char(doc, l, c)
      doc:set_selections(idx, row, col, a, b)
    else
      local row, col = doc:position_offset(l, c, suffix)
      doc:set_selections(idx, l, c, row, col)
    end
  end
end

---Copy each inclusive selection to the next lines with matching display cells.
---@param count integer Number of copies of each original range.
function selection.copy_below(count)
  local doc = core.active_view.doc
  local copies, primary = {}, doc.last_selection
  for idx in doc:get_selections() do
    local l, c, a, b = selection.characters(doc, idx)
    local head, anchor = block.cells(doc, l, c), block.cells(doc, a, b)
    local height, remaining = math.abs(l - a) + 1, count
    while remaining > 0 do
      l, a = l + height, a + height
      if math.max(l, a) > #doc.lines then break end
      local hc, reached = block.at(doc, l, head)
      local ac, other = block.at(doc, a, anchor)
      if reached == head and other == anchor then
        copies[#copies + 1] = { l, hc, a, ac, idx == primary }
        remaining = remaining - 1
      end
    end
  end
  local mark
  for _, copy in ipairs(copies) do
    local l, c, a, b = table.unpack(copy)
    doc:add_selection(l, c, a, b)
    selection.set_characters(doc, doc.last_selection, l, c, a, b)
    if copy[5] then mark = { doc:get_selection() } end
  end
  doc:merge_cursors()
  if mark then
    for idx, l, c in doc:get_selections() do
      if l == mark[1] and c == mark[2] then doc.last_selection = idx end
    end
  end
end

---Compute inclusive line bounds and half-open display-cell bounds from the two
---corners.
---@param doc core.doc
---@param s modal.shape
---@return integer top
---@return integer bottom
---@return integer left
---@return number right Infinite when extending to end of line.
function selection.bounds(doc, s)
  local top, bottom = math.min(s.line, s.anchor_line),
    math.max(s.line, s.anchor_line)
  local h1, h2 = block.cells(doc, s.line, s.col)
  local a1, a2 = block.cells(doc, s.anchor_line, s.anchor_col)
  local left = math.min(h1, a1)
  local right = s.to_eol and math.huge or math.max(h2, a2, h1 + 1, a1 + 1)
  return top, bottom, left, right
end

---Represent a line or rectangular selection with native ranges and scroll the
---moving corner into view.
---@param view modal.docview
---@param s modal.shape
local function project(view, s)
  local doc = view.doc
  local top, bottom, left, right = selection.bounds(doc, s)
  if s.kind == "line" then
    s.edges = nil
    local last, col = bottom, #doc.lines[bottom]
    if bottom < #doc.lines then last, col = bottom + 1, 1 end
    doc:set_selection(last, col, top, 1, s.line < s.anchor_line)
  else
    -- Keep the native ranges ordered. Only the moving corner is the primary
    -- selection, even when extending a block upwards.
    doc:set_selection(top, 1)
    s.edges = {}
    local backwards = block.cells(doc, s.line, s.col)
      < block.cells(doc, s.anchor_line, s.anchor_col)
    for line = top, bottom do
      local first, finish, edges = block.row(doc, line, left, right, true)
      s.edges[line] = edges
      doc:set_selections(line - top + 1, line, finish, line, first, backwards)
    end
    doc.last_selection = s.line - top + 1
  end
  s.selections, s.revision = doc.selections, doc:get_change_id()
  view:scroll_to_make_visible(s.line, s.col)
  view.last_line1, view.last_col1, view.last_line2, view.last_col2 =
    doc:get_selection()
  core.redraw = true
end

---Get the projection while its document revision and native selections are
---current. Suspended projections are hidden.
---@param view core.docview
---@return modal.shape?
function selection.current(view)
  local s = view.modal and view.modal.visual_shape
  if s and not s.suspended and s.selections == view.doc.selections
    and s.revision == view.doc:get_change_id() then return s end
end

---Paint the selected fraction of tabs and wide graphemes at a rectangle's
---edges.
---@param view core.docview
---@param line integer
function selection.draw_edges(view, line)
  local s = view.modal and view.modal.visual_shape
  local edges = s and s.edges and s.edges[line]
  if edges and selection.current(view) then
    for _, edge in ipairs(edges) do
      ---@cast edge modal.block_edge
      local x, y = view:get_line_screen_position(line, edge[1])
      local w = view:get_col_x_offset(line, edge[2], true)
        - view:get_col_x_offset(line, edge[1])
      renderer.draw_rect(x + w * edge[3], y, w * (edge[4] - edge[3]),
        view:get_line_height(), style.selection)
    end
  end
end

---Get the logical corners, reanchoring at the caret if an edit or external
---selection invalidated them.
---@param view core.docview
---@return modal.shape?
function selection.get(view)
  local s = view.modal and view.modal.visual_shape
  if s and (s.selections ~= view.doc.selections
    or s.revision ~= view.doc:get_change_id()) then
    local line, col = view.doc:get_selection()
    s = {
      kind = s.kind, line = line, col = col,
      anchor_line = line, anchor_col = col
    }
    view.modal.visual_shape = s
  end
  return s
end

---Restore one native selection between the logical corners and remove the
---projection.
---@param view modal.docview
function selection.release(view)
  local s = selection.get(view)
  if not s then return end
  view.modal.visual_shape = nil
  view.modal.suspend_selection, view.modal.resume_selection = nil, nil
  view.doc:set_selection(s.line, s.col, s.anchor_line, s.anchor_col)
  core.redraw = true
end

---Collapse projected selections while editing is disabled or the view changes
---mode.
---@param view modal.docview
---@param discard? boolean Drop the corners when switching mode or preset.
local function suspend(view, discard)
  local state = view.modal
  if not state.visual_shape.suspended then
    local s = selection.get(view)
    ---@cast s modal.shape
    view.doc:set_selection(s.line, s.col)
    s.selections, s.suspended = view.doc.selections, true
  end
  if discard then
    state.visual_shape, state.suspend_selection, state.resume_selection =
      nil, nil, nil
  end
end

---Restore a suspended selection, using the current caret if it moved while
---suspended.
---@param view modal.docview
local function resume(view)
  local s = view.modal.visual_shape
  if not s or not s.suspended then return end
  s = selection.get(view)
  ---@cast s modal.shape
  local line, col = view.doc:get_selection()
  if line ~= s.line or col ~= s.col then
    s = {
      kind = s.kind, line = line, col = col,
      anchor_line = line, anchor_col = col
    }
    view.modal.visual_shape = s
  end
  s.suspended = nil
  project(view, s)
end

---Project inclusive head and anchor positions onto an editable modal document.
---Omit the corners to use the native endpoints, or reuse the returned table to
---extend the selection.
---@param view modal.docview
---@param kind modal.shape_kind
---@param corners? modal.corners
---@return modal.shape shape Corners with their projection state attached.
function selection.set(view, kind, corners)
  assert(kind == "line"
    or kind == "block", "expected a line or block selection")
  if not corners then
    local line, col, a, b = view.doc:get_selection()
    corners = { line = line, col = col, anchor_line = a, anchor_col = b }
  end
  corners.line, corners.col =
    view.doc:sanitize_position(corners.line, corners.col)
  corners.anchor_line, corners.anchor_col =
    view.doc:sanitize_position(corners.anchor_line, corners.anchor_col)
  ---@cast corners modal.shape
  corners.kind, corners.suspended = kind, nil
  view.modal.visual_shape = corners
  view.modal.suspend_selection, view.modal.resume_selection = suspend, resume
  project(view, corners)
  return corners
end

return selection
