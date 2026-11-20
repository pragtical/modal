local core = require "core"
local translate = require "core.doc.translate"
local block = require "plugins.modal.block"

---Clipboard fragments in caret order, or row order for a rectangular yank.
---@class modal.clipboard_parts
---@field [integer] string
---@field full? string System clipboard text that identifies these fragments.
---@field widths? integer[] Display widths of rectangular rows.
---@field block_width? integer Width of the yanked rectangle in display cells.

---Clipboard contents captured before replacing a visual selection.
---@class modal.paste
---@field text string
---@field parts? modal.clipboard_parts
---@field linewise? boolean

---Read and write Vi register data using Pragtical's native clipboard.
---@class plugins.modal.vi.register
local register = {}

---Publish text, per-caret fragments and whole-line flags to Pragtical's
---clipboard.
---@param text string
---@param parts modal.clipboard_parts
---@param whole_lines boolean[]
function register.write(text, parts, whole_lines)
  parts.full = text
  core.cursor_clipboard = parts
  core.cursor_clipboard_whole_line = whole_lines
  system.set_clipboard(text)
end

---Read the clipboard and recover its shape when the text still matches
---Pragtical's saved fragments.
---@return string? text
---@return modal.clipboard_parts? parts
---@return boolean[]? whole_lines
---@return boolean? linewise
function register.read()
  local text = system.get_clipboard()
  local parts = core.cursor_clipboard
  if text and parts and parts.full == text
    and (parts.block_width or text ~= "") then
    local whole = core.cursor_clipboard_whole_line
    local linewise = #parts > 0
    for i = 1, #parts do linewise = linewise and whole[i] end
    return text, parts, whole, linewise
  end
  if not text or text == "" then return end
  return text:gsub("\r\n", "\n"), nil, nil, text:sub(-1) == "\n"
end

---Insert rectangular fragments at a display cell, extending the document and
---repeating rows horizontally as needed.
---@param doc core.doc
---@param line integer
---@param cell integer
---@param parts modal.clipboard_parts
---@param count integer
---@return integer? first_col Byte column of the first inserted row.
function register.put_block(doc, line, cell, parts, count)
  local missing = line + #parts - 1 - #doc.lines
  if missing > 0 then
    doc:insert(#doc.lines, #doc.lines[#doc.lines], ("\n"):rep(missing))
  end
  local first_col
  for i, text in ipairs(parts) do
    local l = line + i - 1
    local col = block.insertion_col(doc, l, cell)
    first_col = first_col or col
    local gap = (" "):rep(math.max(0, parts.block_width - parts.widths[i]))
    local repeated = (text .. gap):rep(count - 1) .. text
    if col < #doc.lines[l] then repeated = repeated .. gap end
    doc:insert(l, col, repeated)
  end
  return first_col
end

---Put a counted register value at each caret, honoring characterwise, linewise
---and blockwise placement.
---@param before boolean Put before the caret or above its line.
---@param count integer
function register.put(before, count)
  local doc = core.active_view.doc
  local text, parts, whole, linewise = register.read()
  if not text then return end
  if parts and parts.block_width then
    doc.undo_stack.force_group = true
    for idx, line, col in doc:get_selections(false, true) do
      local left, right = block.cells(doc, line, col)
      col =
        register.put_block(doc, line, before and left or right, parts, count)
      doc:set_selections(idx, line, col)
    end
    doc:merge_cursors()
    return
  end
  for idx, line, col in doc:get_selections(false, true) do
    local value, lines = text, linewise
    if parts and #parts == #doc.selections / 4 then
      value, lines = parts[idx], whole[idx]
    elseif lines then
      value = value:sub(1, -2)
    end
    if lines then
      if before then
        doc:insert(line, 1, (value .. "\n"):rep(count))
      else
        doc:insert(line, #doc.lines[line], ("\n" .. value):rep(count))
        line = line + 1
      end
      col = doc.lines[line]:find("%S") or 1
    elseif value ~= "" then
      if not before and col < #doc.lines[line] then
        line, col = translate.next_char(doc, line, col)
      end
      value = value:rep(count)
      doc:insert(line, col, value)
      if not value:find("\n", 1, true) then
        line, col = translate.previous_char(doc, line, col + #value)
      end
    end
    doc:set_selections(idx, line, col)
  end
  doc:merge_cursors()
end

return register
