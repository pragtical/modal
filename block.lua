-- Block edges use zero-based display cells. Pragtical selections use byte
-- positions, so resolve each edge separately on every document line.
local common = require "core.common"
---The start and end byte columns of one grapheme, followed by the two
---fractions of its rendered width that enclose the selection.
---@class modal.block_edge
---@field [1] integer First byte of the grapheme.
---@field [2] integer Byte column after the grapheme.
---@field [3] number Left fraction, from zero to one.
---@field [4] number Right fraction, from zero to one.

---The intersection of one document line with a display-cell rectangle.
---@class modal.block_row
---@field first integer First affected byte column.
---@field finish integer Exclusive byte column after the affected text.
---@field text string Selected text with partial graphemes expanded to spaces.
---@field width integer Selected display cells on this line.
---@field leading integer Cells preserved on the left of the first grapheme.
---@field trailing integer Cells preserved on the right of the last grapheme.
---@field short boolean The line ends before the rectangle's left edge.

---Translate between display cells and Pragtical's one-based byte columns.
---@class plugins.modal.block
local block = {}

local emoji_variant, joiner = "\239\184\143", "\226\128\141"
---Measure one grapheme in display cells at a zero-based screen column.
---@param char string Grapheme.
---@param cell integer
---@param tabstop integer Tab stop in cells.
---@return integer width
local function cell_width(char, cell, tabstop)
  if char == "\t" then return tabstop - cell % tabstop end
  local base = char:ucodepoint(1, 1)
  if char:find(emoji_variant, 1, true) or char:find(joiner, 1, true)
    or (base >= 0x1f1e6 and base <= 0x1f1ff and #char > 4) then return 2 end
  return math.max(1, utf8extra.width(base))
end

---Locate the grapheme containing a byte column or display cell on a document
---line.
---@param doc core.doc
---@param line integer
---@param target number
---@param by_byte boolean Interpret the target as a one-based byte column.
---@return integer byte
---@return integer start_cell
---@return integer end_cell
---@return integer next_byte
local function locate(doc, line, target, by_byte)
  local text = doc:get_utf8_line(line)
  local _, tabstop = doc:get_indent_info()
  local byte, cell = 1, 0
  for char in common.utf8_graphemes(text) do
    if byte >= #text then break end
    local width = cell_width(char, cell, tabstop)
    local after = byte + #char
    if target < (by_byte and after or cell + width) then
      return byte, cell, cell + width, after
    end
    byte, cell = after, cell + width
  end
  return byte, cell, cell, byte
end

---Locate the grapheme covering a zero-based display cell, clamping at end of
---line.
---@param doc core.doc
---@param line integer
---@param cell number May be infinite to select the end of the line.
---@return integer byte
---@return integer start_cell
---@return integer end_cell
---@return integer next_byte
function block.at(doc, line, cell)
  return locate(doc, line, cell, false)
end

---Get the half-open display-cell interval of the grapheme at a byte column.
---@param doc core.doc
---@param line integer
---@param col integer
---@return integer start_cell
---@return integer end_cell
function block.cells(doc, line, col)
  local _, start, stop = locate(doc, line, col, true)
  return start, stop
end

---Measure one row of a rectangle in the half-open display-cell interval [left,
---right).
---Projection mode returns native byte columns and fractional highlight edges
---instead of the row text.
---@param doc core.doc
---@param line integer
---@param left integer
---@param right number Exclusive right edge, possibly infinite.
---@param projection? false
---@return modal.block_row row
---@overload fun(doc: core.doc, line: integer, left: integer, right: number,
---projection: true): integer, integer, modal.block_edge[]?
function block.row(doc, line, left, right, projection)
  local first, start, first_end, first_after = block.at(doc, line, left)
  local last, last_start, last_end, last_after = block.at(doc, line, right)
  local leading = math.min(left - start, first_end - start)
  local trailing = right > last_start and math.max(0, last_end - right) or 0
  local finish = trailing > 0 and last_after or last
  if projection then
    local edges = {}
    if leading > 0 then
      edges[1] = { first, first_after, leading / (first_end - start),
        math.min(right - start, first_end - start) / (first_end - start) }
    end
    if trailing > 0 and (leading == 0 or first ~= last) then
      edges[#edges + 1] = {
        last, last_after, 0, (right - last_start) / (last_end - last_start)
      }
    end
    local from = leading > 0 and first_after or first
    return from, math.max(from, last), edges[1] and edges
  end
  local width = math.max(0, math.min(right, last_end) - left)
  local text = doc:get_text(line, first, line, finish)
  if leading > 0 or trailing > 0 then
    if first_after == finish and (leading > 0 or first == last) then
      text = (" "):rep(width)
    else
      if leading > 0 then
        text = (" "):rep(first_end - left) .. text:sub(first_after - first + 1)
      end
      if trailing > 0 then
        text = text:sub(1, #text - (last_after - last))
          .. (" "):rep(right - last_start)
      end
    end
  end
  return { first = first, finish = finish, text = text, width = width,
    leading = leading, trailing = trailing, short = start < left
      and first == first_after }
end

---Materialize a byte position at a display cell, padding a short line or
---replacing a partial grapheme with spaces.
---@param doc core.doc
---@param line integer
---@param cell integer
---@return integer col
function block.insertion_col(doc, line, cell)
  local col, start, stop, after = block.at(doc, line, cell)
  if cell > start then
    if col ~= after then doc:remove(line, col, line, after) end
    doc:insert(line, col, (" "):rep(math.max(cell, stop) - start))
    col = col + cell - start
  end
  return col
end

return block
