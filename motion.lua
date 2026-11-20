local block = require "plugins.modal.block"
local translate = require "core.doc.translate"

---Grapheme and word boundaries used by modal presets.
---@class plugins.modal.motion
local motion = {}

---Return the grapheme at a document byte position, or nil at end of document.
---@param doc core.doc
---@param line integer
---@param col integer
---@return string?
function motion.char(doc, line, col)
  if col == #doc.lines[line] then
    if line < #doc.lines then return "\n" end
    return nil
  end
  local _, after = doc:get_grapheme_bounds(line, col)
  return doc.lines[line]:sub(col, after - 1)
end

---Classify a grapheme for short words or whitespace-delimited WORDs.
---@param ch string?
---@param big boolean
---@return string
function motion.class(ch, big)
  if not ch or ch == "\n" then return "newline" end
  if ch:umatch("^%s") then return "space" end
  if big or ch:umatch("^[%w_]") then return "word" end
  return "punct"
end

---A preferred display column survives consecutive vertical motions.
---@class modal.vertical_goal
---@field line integer
---@field col integer
---@field cell integer
---@field command? modal.command

---Move by document lines, retaining the desired column across short rows.
---@param view modal.docview
---@param idx integer
---@param l integer
---@param c integer
---@param delta integer
---@param character_only boolean Clamp to the last printable character.
---@return integer, integer
function motion.vertical(view, idx, l, c, delta, character_only)
  local doc, state = view.doc, view.modal
  state.vertical_goals = state.vertical_goals or {}
  local previous = state.vertical_goals[idx]
  local cell
  if previous and previous.line == l and previous.col == c
    and previous.command == state.last_command then
    cell = previous.cell
  else
    local first, after = block.cells(doc, l, c)
    cell = character_only and math.max(first, after - 1) or first
  end
  l = math.min(#doc.lines, math.max(1, l + delta))
  c = block.at(doc, l, cell)
  if character_only and c == #doc.lines[l] and c > 1 then
    l, c = translate.previous_char(doc, l, c)
  end
  state.vertical_goals[idx] = { line = l, col = c, cell = cell,
    command = state.current_command }
  return l, c
end

---Search by grapheme, optionally crossing lines, stopping before a till target.
---@param doc core.doc
---@param line integer
---@param col integer
---@param count integer
---@param key string f, F, t or T.
---@param char string?
---@param multiline? boolean
---@return integer? line
---@return integer? col
---@return boolean? forward
function motion.find(doc, line, col, count, key, char, multiline)
  if not char or char == "" then return end
  local forward = key == "f" or key == "t"
  local step = forward and translate.next_char or translate.previous_char
  while count > 0 do
    local l, c = step(doc, line, col)
    if l == line and c == col or not multiline and l ~= line then return end
    line, col = l, c
    if motion.char(doc, l, c) == char then count = count - 1 end
  end
  if key == "t" then line, col = translate.previous_char(doc, line, col) end
  if key == "T" then line, col = translate.next_char(doc, line, col) end
  return line, col, forward
end

return motion
