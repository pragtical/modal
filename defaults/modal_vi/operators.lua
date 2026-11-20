local core = require "core"
local modal = require "plugins.modal"
local mu = require "plugins.modal.utils"
local translate = require "core.doc.translate"
local register = require "plugins.modal.defaults.modal_vi.register"
local changes = require "plugins.modal.defaults.modal_vi.changes"
---@alias modal.operator "d"|"c"|"y"
---@alias modal.window_motion fun(view: modal.docview, key: string,
---count: integer): integer, number?

---Two line/byte-column pairs with the motion's operator semantics.
---@class modal.vi_range
---@field [integer] integer
---@field inclusive? boolean Include the character at the final byte position.
---@field linewise? boolean Operate on whole lines.
---@field yank_col? integer Byte column to restore after a linewise yank.

---Resolve Vi operator-motion pairs and apply their ranges to the document.
---@class plugins.modal.vi.operators
local operators = {}
local motions_api = require "plugins.modal.motion"

local next_char, prev_char = translate.next_char, translate.previous_char

---Classify the character under the caret for word or WORD motions.
---@param doc core.doc
---@param line integer
---@param col integer
---@param big boolean
---@return string kind Space, punctuation or word.
local function word_class(doc, line, col, big)
  local kind = motions_api.class(motions_api.char(doc, line, col), big)
  return kind == "newline" and "space" or kind
end

---Find the insertion column after the current character class on one line.
---@param doc core.doc
---@param line integer
---@param col integer
---@param big boolean
---@return integer col
local function after_run(doc, line, col, big)
  local kind = word_class(doc, line, col, big)
  while col < #doc.lines[line] and word_class(doc, line, col, big) == kind do
    line, col = next_char(doc, line, col)
  end
  return col
end

---Find the next word start, optionally stopping at the current line's newline.
---@param doc core.doc
---@param line integer
---@param col integer
---@param big boolean
---@param stop_at_eol boolean?
---@return integer line
---@return integer col
local function next_start(doc, line, col, big, stop_at_eol)
  local eol = #doc.lines[line]
  if stop_at_eol and col == eol and line < #doc.lines then
    return line + 1, 1
  end
  if col < eol then
    col = after_run(doc, line, col, big)
    if col < eol and word_class(doc, line, col, big) == "space" then
      col = after_run(doc, line, col, big)
    end
    if col < eol or stop_at_eol then return line, col end
  end
  while line < #doc.lines do
    line, col = line + 1, 1
    if #doc.lines[line] == 1 then break end
    if word_class(doc, line, col, big) == "space" then
      col = after_run(doc, line, col, big)
    end
    if col < #doc.lines[line] then break end
  end
  return line, col
end

---Walk backwards to the start of the previous word or WORD.
---@param doc core.doc
---@param line integer
---@param col integer
---@param big boolean
---@return integer line
---@return integer col
local function previous_start(doc, line, col, big)
  line, col = prev_char(doc, line, col)
  while word_class(doc, line, col, big) == "space" do
    if #doc.lines[line] == 1 or (line == 1 and col == 1) then
      return line, col
    end
    line, col = prev_char(doc, line, col)
  end
  local kind = word_class(doc, line, col, big)
  while col > 1 do
    local _, prev = prev_char(doc, line, col)
    if word_class(doc, line, prev, big) ~= kind then break end
    col = prev
  end
  return line, col
end

---Find the end of a word or WORD, optionally including the current character in
---the search.
---@param doc core.doc
---@param line integer
---@param col integer
---@param big boolean
---@param include_current boolean?
---@return integer line
---@return integer col
local function word_end(doc, line, col, big, include_current)
  if not include_current then line, col = next_char(doc, line, col) end
  while word_class(doc, line, col, big) == "space" do
    local l, c = next_char(doc, line, col)
    if l == line and c == col then return line, col end
    line, col = l, c
  end
  return prev_char(doc, line, after_run(doc, line, col, big))
end

---Resolve a counted word motion, including Vi's change-word behavior.
---@param doc core.doc
---@param line integer
---@param col integer
---@param count integer
---@param motion string
---@overload fun(doc: core.doc, line: integer, col: integer, count: integer,
---motion: string): integer, integer, boolean
---@param op modal.operator
---@return integer? line
---@return integer? col
---@return boolean? inclusive
local function word_target(doc, line, col, count, motion, op)
  local big = motion:upper() == motion
  motion = motion:lower()
  local change_word = op == "c" and motion == "w"
    and word_class(doc, line, col, big) ~= "space"
  for i = 1, count do
    local l, c = line, col
    if motion == "b" then
      line, col = previous_start(doc, line, col, big)
      if op and l == line and c == col and #doc.lines[1] == 1 then return end
    elseif motion == "e" or change_word then
      line, col = word_end(doc, line, col, big, change_word and i == 1)
    else
      line, col = next_start(doc, line, col, big, op and i == count)
    end
    if l == line and c == col and not (change_word and i == 1) then break end
  end
  return line, col, motion == "e" or change_word
end

local names = { d = "Delete", c = "Change", y = "Yank" }
---Compare two document positions in reading order.
---@param l1 integer
---@param c1 integer
---@param l2 integer
---@param c2 integer
---@return boolean
local function before(l1, c1, l2, c2)
  return l1 < l2 or (l1 == l2 and c1 < c2)
end

---Find the first non-whitespace byte column or the last character on a blank
---line.
---@param doc core.doc
---@param line integer
---@return integer col
local function first_nonblank(doc, line)
  local text = doc.lines[line]
  return text:find("%S") or math.max(1, #text - 1)
end

---Build a linewise operator range from a vertical motion or doubled operator.
---@param view modal.docview
---@param op modal.operator
---@param motion string
---@param count integer
---@param line integer
---@param col integer
---@param window_line modal.window_motion
---@return modal.vi_range?
local function line_range(view, op, motion, count, line, col, window_line)
  local doc = view.doc
  local target
  if motion == "line" then
    target = line + count - 1
    if target > #doc.lines then return end
  elseif motion == "j" then target = line + count
  elseif motion == "k" then target = line - count
  elseif motion == "gg" then target = count
  elseif motion == "G" then
    target = view.modal.current_command.n_repeat == "" and #doc.lines or count
  else
    target = window_line(view, motion, count)
  end
  target = math.max(1, math.min(#doc.lines, target))
  if target == line and (motion == "j" or motion == "k") then return end
  local first, last = math.min(line, target), math.max(line, target)
  local yank_col = col
  if op == "y" and motion == "k" then
    yank_col = view:get_x_offset_col(target, view:get_col_x_offset(line, col))
    if yank_col >= #doc.lines[target] and yank_col > 1 then
      yank_col = select(2, prev_char(doc, target, #doc.lines[target]))
    end
  elseif motion ~= "line" and target <= line then
    yank_col = first_nonblank(doc, target)
    if target == line then yank_col = math.min(col, yank_col) end
  end
  return {
    first, 1, last, #doc.lines[last], linewise = true, yank_col = yank_col }
end

---Find the half-open range of an inner word or a word with adjacent spaces.
---@param doc core.doc
---@param line integer
---@param col integer
---@param key string
---@param count integer
---@return modal.vi_range?
local function word_object(doc, line, col, key, count)
  local big, around = key:sub(-1) == "W", key:sub(1, 1) == "a"
  local eol = #doc.lines[line]
  if col >= eol then return end
  local kind = word_class(doc, line, col, big)
  local first, finish = col, after_run(doc, line, col, big)
  while first > 1 do
    local _, prev = prev_char(doc, line, first)
    if word_class(doc, line, prev, big) ~= kind then break end
    first = prev
  end
  if around and kind == "space" and finish < eol then
    finish = after_run(doc, line, finish, big)
  end
  local last = line
  for _ = 2, count do
    if finish >= eol then
      if last == #doc.lines then return end
      last, finish = last + 1, 1
      eol = #doc.lines[last]
    end
    if around and word_class(doc, last, finish, big) == "space" then
      finish = after_run(doc, last, finish, big)
    end
    if finish < eol then finish = after_run(doc, last, finish, big) end
  end
  if around and kind ~= "space" then
    if finish < eol and word_class(doc, last, finish, big) == "space" then
      finish = after_run(doc, last, finish, big)
    else
      while first > 1 do
        local _, prev = prev_char(doc, line, first)
        if word_class(doc, line, prev, big) ~= "space" then break end
        first = prev
      end
    end
  end
  return { line, first, last, finish }
end

---Translate an operator and counted motion into a half-open document range.
---@param view modal.docview
---@param op modal.operator
---@param motion string
---@param count integer
---@param line integer
---@param col integer
---@param window_line modal.window_motion
---@return modal.vi_range?
local function range_for(view, op, motion, count, line, col, window_line)
  local doc = view.doc
  local target, finish, inclusive
  if motion:match("^[ia][wW]$") then
    return word_object(doc, line, col, motion, count)
  elseif motion:match("^[wWebBE]$") then
    if motion:lower() == "b" and line == 1 and col == 1 then return end
    target, finish, inclusive = word_target(doc, line, col, count, motion, op)
  elseif motion:match("^[fFtT]$") then
    target, finish, inclusive = motions_api.find(doc, line, col, count, motion,
      view.modal.current_command.input)
  elseif motion == "h" or motion == "l" then
    local step = motion == "h" and prev_char or next_char
    target, finish = line, col
    for _ = 1, count do
      local l, c = step(doc, line, finish)
      if l ~= line or c == finish then break end
      finish = c
    end
  elseif motion == "0" or motion == "^" then
    target = line
    finish = motion == "0" and 1 or first_nonblank(doc, line)
  elseif motion == "$" or motion == "g_" then
    if count > 1 and line == #doc.lines then return end
    target = math.min(#doc.lines, line + count - 1)
    finish = #doc.lines[target]
    if motion == "g_" then
      local last = doc.lines[target]:match("^.*()%S")
      finish = last and select(2, prev_char(doc, target, last + 1)) or 1
      inclusive = true
    end
  else
    return line_range(view, op, motion, count, line, col, window_line)
  end
  if not target then return end
  local l1, c1, l2, c2 = mu.sort_positions(line, col, target, finish)
  if inclusive and c2 < #doc.lines[l2] then l2, c2 = next_char(doc, l2, c2) end
  if l1 < l2 then
    local starts_in_indent = not doc.lines[l1]:sub(1, c1 - 1):find("%S")
    -- An exclusive motion ending at column one stops on the preceding line.
    if c2 == 1 and not inclusive and motion ~= "$" and motion ~= "g_" then
      l2 = l2 - 1
      c2 = #doc.lines[l2]
      if starts_in_indent then return { l1, 1, l2, c2, linewise = true } end
    elseif op == "d" and starts_in_indent
      and not doc.lines[l2]:find("%S", c2) then
      return { l1, 1, l2, #doc.lines[l2], linewise = true }
    end
  end
  return { l1, c1, l2, c2, inclusive = inclusive or motion == "$" }
end

---Merge overlapping ranges, write the register and apply edits from the end of
---the document. Change enters Insert mode.
---@param view modal.docview
---@param op modal.operator
---@param ranges modal.vi_range[] Nonempty ranges in pre-edit coordinates.
function operators.apply_ranges(view, op, ranges)
  local doc = view.doc
  if op == "y" then
    for idx, r in ipairs(ranges) do
      doc:set_selections(idx, r[1], r.yank_col or r[2])
    end
    doc:merge_cursors()
  end
  table.sort(ranges, function(a, b) return before(a[1], a[2], b[1], b[2]) end)
  local merged, parts = {}, {}
  for _, r in ipairs(ranges) do
    local last = merged[#merged]
    if last and (before(r[1], r[2], last[3], last[4])
      or (r[1] == last[1] and r[2] == last[2])) then
      if before(last[3], last[4], r[3], r[4]) then
        last[3], last[4], last.linewise = r[3], r[4], r.linewise
      elseif last[3] == r[3] and last[4] == r[4] and r.linewise then
        last.linewise = true
      end
    else
      merged[#merged + 1] = r
    end
  end
  local values, whole = {}, {}
  for i, r in ipairs(merged) do
    local text = doc:get_text(r[1], r[2], r[3], r[4])
    values[i], whole[i] = text, r.linewise or false
    if r.linewise or i < #merged then text = text .. "\n" end
    parts[i] = text
  end
  local clipboard = table.concat(parts)
  if clipboard ~= "" or op == "y" or (op == "c" and merged[1].inclusive) then
    register.write(clipboard, values, whole)
  end
  if op == "y" then return end

  doc.undo_stack.force_group = true
  for i = #merged, 1, -1 do
    local r = merged[i]
    local l1, c1, l2, c2 = r[1], r[2], r[3], r[4]
    if r.linewise and op == "d" then
      if l2 < #doc.lines then
        l2, c2 = l2 + 1, 1
      elseif l1 > 1 and c1 == 1 then
        l1, c1 = l1 - 1, #doc.lines[l1 - 1]
      end
    end
    doc:remove(l1, c1, l2, c2)
    if r.linewise and r[2] == 1 and op == "d" then
      c1 = first_nonblank(doc, l1)
    elseif op == "d" and c1 == #doc.lines[l1] and c1 > 1 then
      l1, c1 = prev_char(doc, l1, c1)
    end
    -- The host moves these carets as earlier ranges are removed. The first
    -- removal captures the original selections for undo.
    if i == #merged then
      doc:set_selection(l1, c1)
    else
      doc:add_selection(l1, c1)
    end
  end
  doc:merge_cursors()
  if op == "c" then modal.set_mode("INS") end
end

local motions = {
  h = "h", left = "h", l = "l", right = "l", j = "j", down = "j",
    k = "k", up = "k",
  w = "w", ["S+w"] = "W", e = "e", ["S+e"] = "E", b = "b", ["S+b"] = "B",
  ["0"] = "0", ["S+6"] = "^", ["S+4"] = "$", ["g S+-"] = "g_",
  ["g g"] = "gg", ["S+g"] = "G", ["S+h"] = "H", ["S+m"] = "M", ["S+l"] = "L",
  ["f $"] = "f", ["S+f $"] = "F", ["t $"] = "t", ["S+t $"] = "T",
}

local motion_labels = {
  h = "left", l = "right", j = "through line below", k = "through line above",
  w = "word", W = "WORD", e = "to word end", E = "to WORD end",
  b = "back to word start", B = "back to WORD start",
  ["0"] = "to line start", ["^"] = "to first nonblank", ["$"] = "to line end",
  g_ = "to last nonblank", gg = "to first line", G = "to last line",
  H = "to top of window", M = "to middle of window", L = "to bottom of window",
  f = "through next character", F = "through previous character",
  t = "up to next character", T = "up to previous character", line = "line",
}

---Install Vi's word motions and operator-motion bindings, then return the
---prefixes that accept inner counts.
---@param keymaps table<string,modal.keymap>
---@param window_line modal.window_motion
---@return modal.operator_modes
function operators.bind(keymaps, window_line)
  for key, motion in pairs(motions) do
    if motion:match("^[wWebBEfFtT]$") then
      for _, mode in ipairs({ "NOR", "VIS", "VLINE", "VBLOCK" }) do
        ---Move the cursor or extend the active Visual shape.
        ---@param count integer
        local function move(count)
          local view = core.active_view
          local doc = view.doc
          local shape = modal.selection.current(view)
          for idx, l, c in doc:get_selections() do
            local a, b
            if shape then
              l, c = shape.line, shape.col
            elseif mode == "VIS" then
              l, c, a, b = modal.selection.characters(doc, idx)
            end
            local line, col
            if motion:match("^[fFtT]$") then
              line, col = motions_api.find(doc, l, c, count, motion,
                view.modal.current_command.input)
            else
              line, col = word_target(doc, l, c, count, motion)
            end
            if not line then return end
            if col == #doc.lines[line] and col > 1 then
              line, col = prev_char(doc, line, col)
            end
            if shape then
              shape.line, shape.col, shape.goal, shape.to_eol = line, col
              modal.selection.set(view, shape.kind, shape)
              break
            elseif mode == "VIS" then
              modal.selection.set_characters(doc, idx, line, col, a, b)
            else
              doc:set_selections(idx, line, col)
            end
          end
        end
        modal.fns[move] = "Move by " .. motion
        keymaps[mode][key] = modal.with_count(move)
      end
    end
  end
  for _, object in ipairs({ "iw", "aw", "iW", "aW" }) do
    local first, word = object:sub(1, 1), object:sub(2)
    local key = first .. (word == "W" and " S+w" or " w")
    motions[key] = object
    motion_labels[object] = (first == "a" and "a " or "inner ")
      .. (word == "W" and "WORD" or "word")
    ---Apply the word object at the active Visual head.
    ---@param count integer
    local function select_object(count)
      local view = core.active_view
      local doc, shape = view.doc, modal.selection.current(view)
      for idx in doc:get_selections() do
        local l, c, a, b = modal.selection.characters(doc, idx)
        if shape then l, c = shape.line, shape.col end
        local r = word_object(doc, l, c, object, count)
        if not r then return end
        local last, stop = prev_char(doc, r[3], r[4])
        if shape and shape.kind == "block" then
          shape.line, shape.col = last, stop
          shape.anchor_line, shape.anchor_col = r[1], r[2]
          modal.selection.set(view, "block", shape)
          return
        elseif shape then
          modal.selection.release(view)
          modal.set_mode("VIS")
        elseif l ~= a or c ~= b then
          if l < a or l == a and c < b then
            modal.selection.set_characters(doc, idx, r[1], r[2], a, b)
            return
          end
          r[1], r[2] = a, b
        end
        modal.selection.set_characters(doc, idx, last, stop, r[1], r[2])
      end
    end
    modal.fns[select_object] = "Select " .. motion_labels[object]
    for _, mode in ipairs({ "VIS", "VLINE", "VBLOCK" }) do
      keymaps[mode][key] = modal.with_count(select_object)
    end
  end
  for op, name in pairs(names) do
    ---Install one operator and motion pair with its repeat and help behavior.
    ---@param key string
    ---@param motion string
    local function bind(key, motion)
      ---Compute the ranges for every caret before applying the operator.
      ---@param count integer
      local function action(count)
        local view, ranges = mu.get_dv(), {}
        ---@cast view modal.docview
        for _, line, col in view.doc:get_selections() do
          local range =
            range_for(view, op, motion, count, line, col, window_line)
          if not range then return end
          ranges[#ranges + 1] = range
        end
        operators.apply_ranges(view, op, ranges)
      end
      modal.fns[action] = name .. " " .. motion_labels[motion]
      modal.with_count(action)
      keymaps.NOR[op .. " " .. key] = op == "y" and action
        or changes.track(action)
    end
    bind(op, "line")
    for key, motion in pairs(motions) do bind(key, motion) end
  end
  return { NOR = names }
end

return operators
