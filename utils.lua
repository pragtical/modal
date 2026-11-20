local core = require "core"
local common = require "core.common"
local search = require "core.doc.search"
local translate = require "core.doc.translate"


---@alias modal.window_edge "top"|"middle"|"bottom"
---The selection index and its two line/byte-column pairs, in document order
---when the iterator was requested with sorting enabled.
---@alias modal.selection_iterator fun():
---integer?, integer?, integer?, integer?, integer?
---A start line and byte column followed by an end line and byte column.
---@alias modal.text_range integer[]
---The native selection index followed by the four text range coordinates.
---@alias modal.saved_selection integer[]
---@alias modal.search_action fun(doc: core.doc, line1: integer, col1: integer,
---line2: integer, col2: integer, text: string, opt: core.doc.searchoptions):
---modal.text_range[]

---Movement, selection and clipboard helpers available to every preset.
---@class plugins.modal.utils
local modal_utils = {}

---Get the focused Pragtical view. A prompt or tool view can also have focus.
---@return core.view? view
local function get_dv()
  return core.active_view
end

---Get the document belonging to the focused view. Requires an active view.
---@return core.doc? document Nil when the view has no document.
local function get_doc()
  return get_dv().doc
end

modal_utils.get_doc = get_doc
modal_utils.get_dv = get_dv

---Resolve a visual row to its document position, including wrapped lines.
---@param view core.docview
---@param row integer
---@return integer line
---@return integer col
local function position_at_row(view, row)
  if view.position_from_offset then return view:position_from_offset(row) end
  -- Older DocViews report document lines directly.
  return row, 1
end

---Find a visible document line relative to a viewport edge.
---Count a wrapped document line once when walking from the top or bottom.
---@param view core.docview
---@param edge modal.window_edge
---@param count? integer Document lines from the edge, starting at one.
---@return integer line
---@return number bottom Screen Y immediately below the visible text.
function modal_utils.visible_line(view, edge, count)
  count = count or 1
  local _, _, _, scrollbar_height = view.h_scrollbar:get_track_rect()
  local bottom = view.position.y + view.size.y - scrollbar_height
  local first, last = view:get_visible_line_range()
  last = math.max(1, last)
  local last_line, last_col = position_at_row(view, last)
  local _, y = view:get_line_screen_position(last_line, last_col)
  first = math.min(first, last)
  if y >= bottom then
    last = math.max(first,
      last - 1 - math.floor((y - bottom) / view:get_line_height()))
  end

  if edge == "middle" then
    local line = position_at_row(view, math.floor((first + last) / 2))
    return line, bottom
  end

  local step = 1
  if edge == "bottom" then first, last, step = last, first, -1 end
  local line
  for row = first, last, step do
    local next_line = position_at_row(view, row)
    -- A wrapped document line counts once, and folded lines have no rows.
    if next_line ~= line then
      line = next_line
      count = count - 1
      if count == 0 then break end
    end
  end
  return line, bottom
end

---Order two document positions by line and then by byte column.
---@param line1 integer
---@param col1 integer
---@param line2 integer
---@param col2 integer
---@return integer start_line
---@return integer start_col
---@return integer end_line
---@return integer end_col
---@return boolean reversed
function modal_utils.sort_positions(line1, col1, line2, col2)
  if line1 > line2 or line1 == line2 and col1 > col2 then
    return line2, col2, line1, col1, true
  end
  return line1, col1, line2, col2, false
end

---Iterate selections of the active document. A range ending at the start of a
---later line ends at the preceding line's newline.
---@param sort? boolean Order the endpoints of each range.
---@return modal.selection_iterator
function modal_utils.doc_multiline_selections(sort)
  if get_dv() == nil or get_doc() == nil or get_doc().get_selections == nil then
    return function() return nil end
  end
  local iter, state, idx, line1, col1, line2, col2 =
    get_doc():get_selections(sort)
  return function()
    idx, line1, col1, line2, col2 = iter(state, idx)
    if idx and line2 > line1 and col2 == 1 then
      line2 = line2 - 1
      col2 = #get_doc().lines[line2]
    end
    return idx, line1, col1, line2, col2
  end
end

---Jump to column one of the line given by the current numeric prefix.
function modal_utils.go_to_line()
  if get_dv() ~= nil and get_dv().modal ~= nil
    and get_dv().modal.current_command
    and get_dv().modal.current_command.n_repeat ~= '' and get_doc() ~= nil then
    local N = get_dv().modal.current_command.num
    get_doc():set_selection(N, 1)
  end
end

---Indent each selected range of lines and adjust its selection columns.
function modal_utils.indent()
  local docview = core.active_view and core.active_view.doc
  if docview then
    for idx, line1, col1, line2, col2 in
      modal_utils.doc_multiline_selections(false) do
      local l1, c1, _, _ = docview:indent_text(false,
        math.min(line1, line2), 1, math.max(line1, line2), math.huge)
      if l1 then
        docview:set_selections(idx, line1, c1 - 1 + col1, line2, c1 - 1 + col2)
      end
    end
  end
end

---Unindent each selected range of lines and adjust its selection columns.
function modal_utils.unindent()
  local docview = core.active_view and core.active_view.doc
  if docview then
    for idx, line1, col1, line2, col2 in
      modal_utils.doc_multiline_selections(false) do
      local l1, c1, _, _ = docview:indent_text(true,
        math.min(line1, line2), 1, math.max(line1, line2), math.huge)
      if l1 then
        docview:set_selections(idx, line1, c1 - 1 + col1, line2, c1 - 1 + col2)
      end
    end
  end
end

---Collapse each selection at its later endpoint.
function modal_utils.unselect()
  for idx, _, _, line2, col2 in modal_utils.doc_multiline_selections(true) do
    get_doc():set_selections(idx, line2, col2, line2, col2)
  end
end

---Select the current line backwards or extend the selected lines upwards.
function modal_utils.select_LINE()
  for idx, line1, col1, line2, col2 in
    modal_utils.doc_multiline_selections(false) do
    local lobj = get_doc().highlighter:get_line(line2)
    if line1 == line2 and (math.abs(col2 - col1) ~= (#lobj.text - 1)) then
      get_doc():set_selections(idx, line1, 0, line1, math.huge)
    else
      get_doc():set_selections(
        idx, math.min(line1, line2) - 1, 0, math.max(line1, line2), math.huge)
    end
  end
end

---Select the current line forwards or extend the selected lines downwards.
function modal_utils.select_line()
  for idx, line1, col1, line2, col2 in
    modal_utils.doc_multiline_selections(false) do
    local lobj = get_doc().highlighter:get_line(line2)
    if line1 == line2 and (math.abs(col1 - col2) ~= (#lobj.text - 1)) then
      get_doc():set_selections(idx, line1, math.huge, line1, 0)
    else
      get_doc():set_selections(
        idx, math.max(line1, line2) + 1, math.huge, math.min(line1, line2), 0)
    end
  end
end

---Delete each selection, or the next character at an empty selection.
function modal_utils.delete()
  local doc = get_doc()
  for idx, line1, col1, line2, col2 in doc:get_selections(true, true) do
    if line1 == line2 and col1 == col2 then
      line2, col2 = translate.next_char(doc, line1, col1)
    end
    doc:remove(line1, col1, line2, col2)
    doc:set_selections(idx, line1, col1)
  end
end

---Collect matches wholly inside the supplied document range.
---@param document core.doc
---@param line1 integer
---@param col1 integer
---@param line2 integer
---@param col2 integer
---@param text string Search pattern.
---@param opt? core.doc.searchoptions
---@return modal.text_range[] matches
function modal_utils.select_in_blob(
  document, line1, col1, line2, col2, text, opt)
  local results = {}
  local ok, l1, c1, l2, c2 =
    pcall(search.find, document, line1, col1, text, opt)
  while ok and l1 and (l2 < line2 or (l2 == line2 and c2 <= col2)) do
    table.insert(results, { l1, c1, l2, c2 })
    ok, l1, c1, l2, c2 = pcall(search.find, document, l2, c2, text, opt)
  end
  return results
end

---Collect the ranges between matches inside the supplied document range.
---@param document core.doc
---@param line1 integer
---@param col1 integer
---@param line2 integer
---@param col2 integer
---@param text string Search pattern.
---@param opt? core.doc.searchoptions
---@return modal.text_range[] pieces
function modal_utils.split_in_blob(
  document, line1, col1, line2, col2, text, opt)
  local l0, c0 = line1, col1
  local results = {}
  local ok, l1, c1, l2, c2 =
    pcall(search.find, document, line1, col1, text, opt)
  while ok and l1 and (l2 < line2 or (l2 == line2 and c2 <= col2)) do
    table.insert(results, { l0, c0, l1, c1 })
    l0, c0 = l2, c2
    ok, l1, c1, l2, c2 = pcall(search.find, document, l2, c2, text, opt)
  end
  if l0 < line2 or (l0 == line2 and c0 < col2) then
    table.insert(results, { l0, c0, line2, col2 })
  end
  return results
end

---Restore the saved selections in order, starting with the primary range.
---@param document core.doc
---@param selections? modal.saved_selection[] Nonempty snapshot when supplied.
function modal_utils.reset_selections(document, selections)
  if selections then
    local _, l1, c1, l2, c2 = table.unpack(selections[1])
    document:set_selection(l1, c1, l2, c2)
    for i = 2, #selections do
      _, l1, c1, l2, c2 = table.unpack(selections[i])
      document:add_selection(l1, c1, l2, c2)
    end
    document.last_selection = selections.primary or 1
  end
end

---Apply a regex selection operation to each nonempty range. Restore the
---original selections if nothing matches.
---@param document core.doc
---@param text string
---@param fn modal.search_action
---@param selections modal.saved_selection[]
function modal_utils.blob_action(document, text, fn, selections)
  if not text or #text == 0 then
    return nil
  end
  local opt = { wrap = false, no_case = false, regex = true, reverse = false }
  local results = {}
  for _, sel in ipairs(selections) do
    local _, line1, col1, line2, col2 = table.unpack(sel)
    if line1 ~= line2 or col1 ~= col2 then
      line1, col1, line2, col2, _ =
        modal_utils.sort_positions(line1, col1, line2, col2)
      local ok, r = pcall(fn, document, line1, col1, line2, col2, text, opt)
      if ok and #r >= 1 then
        table.insert(results, r)
      end
    end
  end
  if #results == 0 then
    modal_utils.reset_selections(document, selections)
  else
    for i, res in ipairs(results) do
      for j, sel in ipairs(res) do
        if i == 1 and j == 1 then
          document:set_selection(sel[3], sel[4], sel[1], sel[2])
        else
          document:add_selection(sel[3], sel[4], sel[1], sel[2])
        end
      end
    end
    document.last_selection = 1
  end
end

---Move each caret to the earlier endpoint of its selection.
function modal_utils.go_to_selection_start()
  for idx, line1, col1, _, _ in modal_utils.doc_multiline_selections(true) do
    get_doc():set_selections(idx, line1, col1)
  end
end

---Move each caret to the later endpoint of its selection.
function modal_utils.go_to_selection_end()
  for idx, _, _, line1, col1 in modal_utils.doc_multiline_selections(true) do
    get_doc():set_selections(idx, line1, col1)
  end
end

---Fill missing keys in the destination table with entries from the source.
---@param t1 table Source.
---@param t2 table Destination. Its existing bindings take priority.
---@return table destination The same table passed as t2.
function modal_utils.concat(t1, t2)
  for k, v in pairs(t1) do
    if t2[k] == nil then
      t2[k] = v
    end
  end
  return t2
end

---Copy all selected ranges, preserving individual values for multiple carets.
function modal_utils.copy()
  local doc, values, whole = get_doc(), {}, {}
  for idx, l, c, a, b in doc:get_selections(true) do
    if l == a and c == b then a, b = translate.next_char(doc, l, c) end
    values[idx], whole[idx] = doc:get_text(l, c, a, b), false
  end
  values.full = table.concat(values, "\n")
  core.cursor_clipboard, core.cursor_clipboard_whole_line = values, whole
  system.set_clipboard(values.full)
end

---Insert each clipboard value at the chosen edge and select the pasted text.
---@param before boolean
local function paste(before)
  local doc, text = get_doc(), system.get_clipboard()
  if not text or text == "" then return end
  local values = core.cursor_clipboard
  local individual = values and values.full == text
    and #values == #doc.selections / 4
  for idx, l, c, a, b in doc:get_selections(true, true) do
    local value = individual and values[idx] or text
    if not before then l, c = a, b end
    doc:insert(l, c, value)
    local last, stop = doc:position_offset(l, c, #value)
    doc:set_selections(idx, last, stop, l, c)
  end
end

---Paste after each selection.
function modal_utils.paste_after() paste(false) end

---Paste before each selection.
function modal_utils.paste_before() paste(true) end

---Get the text-input event associated with the most recent modal stroke.
---@return string? text Character produced by Shift or the keyboard layout.
function modal_utils.get_last_key()
  local view = get_dv()
  ---@cast view core.view
  if view.modal then
    return view.modal.last_input
  end
  return nil
end

---Replace selected text with copies of the last input, retaining line breaks.
function modal_utils.replace()
  local doc, last = get_doc(), modal_utils.get_last_key()
  if not last then return end
  for idx, l, c, a, b, forward in doc:get_selections(true, true) do
    local empty = l == a and c == b
    if empty then a, b = translate.next_char(doc, l, c) end
    local parts = {}
    for char in common.utf8_graphemes(doc:get_text(l, c, a, b)) do
      parts[#parts + 1] = char == "\n" and char or last
    end
    local value = table.concat(parts)
    doc:remove(l, c, a, b)
    doc:insert(l, c, value)
    a, b = doc:position_offset(l, c, #value)
    if empty then a, b = l, c end
    doc:set_selections(idx, l, c, a, b, forward)
  end
end

---Extend each selection forward through the next occurrence of the typed
---character.
function modal_utils.select_next_char()
  local view = get_dv()
  ---@cast view modal.docview
  local last = modal_utils.get_last_key()
  if last then
    for idx, line1, col1, line2, col2 in
      modal_utils.doc_multiline_selections(false) do
      local l1, c1, l2, c2 =
        modal_utils.sort_positions(line1, col1, line2, col2)
      local ok, _, _, lnn, cnn = pcall(search.find, view.doc, l2, c2 + 1, last,
        { wrap = false, regex = false, no_case = false, reverse = false })
      if ok and lnn then
        view.doc:set_selections(idx, lnn, cnn - 1, l1, c1)
      end
    end
  end
end


---Extend each selection backward through the previous occurrence of the typed
---character.
function modal_utils.select_prev_char()
  local view = get_dv()
  ---@cast view modal.docview
  local last = modal_utils.get_last_key()
  if last then
    for idx, line1, col1, line2, col2 in
      modal_utils.doc_multiline_selections(false) do
      local l1, c1, l2, c2 =
        modal_utils.sort_positions(line1, col1, line2, col2)
      local ok, lnn, cnn, _, _ = pcall(search.find, view.doc, l1, c1, last,
        { wrap = false, regex = false, no_case = false, reverse = true })
      if ok and lnn then
        view.doc:set_selections(idx, lnn, cnn, l2, c2)
      end
    end
  end
end

---Extend each selection to just before the next occurrence of the typed
---character.
function modal_utils.select_till_next_char()
  local view = get_dv()
  ---@cast view modal.docview
  local last = modal_utils.get_last_key()
  if last then
    for idx, line1, col1, line2, col2 in
      modal_utils.doc_multiline_selections(false) do
      local l1, c1, l2, c2 =
        modal_utils.sort_positions(line1, col1, line2, col2)
      local ok, _, cnn, lnn, _ = pcall(search.find, view.doc, l2, c2 + 2, last,
        { wrap = false, regex = false, no_case = false, reverse = false })
      if ok and lnn then
        view.doc:set_selections(idx, lnn, cnn - 1, l1, c1)
      end
    end
  end
end

---Extend each selection to just after the previous occurrence of the typed
---character.
function modal_utils.select_till_prev_char()
  local view = get_dv()
  ---@cast view modal.docview
  local last = modal_utils.get_last_key()
  if last then
    for idx, line1, col1, line2, col2 in
      modal_utils.doc_multiline_selections(false) do
      local l1, c1, l2, c2 =
        modal_utils.sort_positions(line1, col1, line2, col2)
      local ok, lnn, _, _, cnn = pcall(search.find, view.doc, l1, c1, last,
        { wrap = false, regex = false, no_case = false, reverse = true })
      if ok and lnn then
        view.doc:set_selections(idx, lnn, cnn, l2, c2)
      end
    end
  end
end

---Test whether a character falls outside the ASCII letter ranges.
---@param char string? Nil denotes the start of the scan.
---@return boolean
local function is_non_letter(char)
  if char == nil then
    return false
  end
  return not ((char >= 'a' and char <= 'z') or (char >= 'A' and char <= 'Z'))
end

---Test for a separator in the preset's extended ASCII word-character set.
---@param char string? Nil denotes the start of the scan.
---@return boolean
local function is_non_LETTER(char)
  if char == nil then
    return false
  end
  return not ((char >= ',' and char <= '.') or (char >= '_' and char <= 'z')
    or (char >= '?' and char <= 'Z') or char == ';'
    or char == ':' or char == '!')
end

---Find the next transition from a separator to an ASCII letter.
---@param doc core.doc
---@param line integer
---@param col integer
---@return integer line
---@return integer col
function modal_utils.next_word_start(doc, line, col)
  local prev
  local end_line, end_col = translate.end_of_doc(doc, line, col)
  while line < end_line or col < end_col do
    local char = doc:get_char(line, col)
    if not is_non_letter(char) and is_non_letter(prev) then
      break
    end
    line, col = doc:position_offset(line, col, 1)
    prev = char
  end
  return line, col
end

---Skip spaces, tabs and line endings starting at the supplied position.
---@param doc core.doc
---@param line integer
---@param col integer
---@return integer line
---@return integer col
function modal_utils.next_non_ws(doc, line, col)
  local end_line, end_col = translate.end_of_doc(doc, line, col)
  while line < end_line or col < end_col do
    local char = doc:get_char(line, col)
    if char ~= ' ' and char ~='\t' and char ~='\r' and char ~='\n' then
      break
    end
    line, col = doc:position_offset(line, col, 1)
  end
  return line, col
end

---Find the next ASCII letter after an extended-word separator.
---@param doc core.doc
---@param line integer
---@param col integer
---@return integer line
---@return integer col
function modal_utils.next_WORD_start(doc, line, col)
  local prev
  local end_line, end_col = translate.end_of_doc(doc, line, col)
  while line < end_line or col < end_col do
    local char = doc:get_char(line, col)
    if not is_non_letter(char) and is_non_LETTER(prev) then
      break
    end
    line, col = doc:position_offset(line, col, 1)
    prev = char
  end
  return line, col
end

---Move the carets to the next word start.
function modal_utils.move_to_next_word_start()
  get_doc():move_to(modal_utils.next_word_start)
end

---Move the carets to the next extended-word start.
function modal_utils.move_to_next_WORD_start()
  get_doc():move_to(modal_utils.next_WORD_start)
end

---Move the carets forward over whitespace.
function modal_utils.move_to_next_non_ws()
  get_doc():move_to(modal_utils.next_non_ws)
end

---Locate the last non-whitespace character of a line, or column one on a blank
---line.
---@param doc core.doc
---@param line integer
---@return integer line
---@return integer col
local function last_non_ws(doc, line)
  local last = doc.lines[line]:match(".*()%S")
  if last then return translate.previous_char(doc, line, last + 1) end
  return line, 1
end

---Move each caret to the last non-whitespace character of its line.
function modal_utils.move_to_last_non_ws()
  get_doc():move_to(last_non_ws)
end

---Extend each selection to its line's last non-whitespace character.
function modal_utils.select_to_last_non_ws()
  get_doc():select_to(last_non_ws)
end

---Skip leading whitespace and advance past a run of non-whitespace characters.
---@param doc core.doc
---@param line integer
---@param col integer
---@return integer line
---@return integer col
local function next_WORD_end(doc, line, col)
  line, col = modal_utils.next_non_ws(doc, line, col)
  while not doc:get_char(line, col):match("%s") do
    line, col = doc:position_offset(line, col, 1)
  end
  return line, col
end

---Walk backwards over whitespace and the preceding run of non-whitespace
---characters.
---@param doc core.doc
---@param line integer
---@param col integer
---@return integer line
---@return integer col
local function previous_WORD_start(doc, line, col)
  local in_word = false
  while line > 1 or col > 1 do
    local l, c = doc:position_offset(line, col, -1)
    local space = doc:get_char(l, c):match("%s")
    if in_word and space then break end
    in_word = not space
    line, col = l, c
  end
  return line, col
end

---Extend each selection through the next non-whitespace run.
function modal_utils.select_to_next_WORD_end()
  get_doc():select_to(next_WORD_end)
end

---Extend each selection backwards to the start of the previous non-whitespace
---run.
function modal_utils.select_to_previous_WORD_start()
  get_doc():select_to(previous_WORD_start)
end

---Extend each selection to the next word start.
function modal_utils.select_to_next_word_start()
  local dv = get_dv()
  ---@cast dv core.docview
  dv.doc:select_to(modal_utils.next_word_start, dv)
end

---Extend each selection forward over whitespace.
function modal_utils.select_to_next_non_ws()
  local dv = get_dv()
  ---@cast dv core.docview
  dv.doc:select_to(modal_utils.next_non_ws, dv)
end

---Extend each selection to the next extended-word start.
function modal_utils.select_to_next_WORD_start()
  local dv = get_dv()
  ---@cast dv core.docview
  dv.doc:select_to(modal_utils.next_WORD_start, dv)
end

return modal_utils
