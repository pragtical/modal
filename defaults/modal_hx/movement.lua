local core = require "core"
local translate = require "core.doc.translate"
local modal = require "plugins.modal"
local motion = require "plugins.modal.motion"
local selection = modal.selection
local next_char, prev_char = translate.next_char, translate.previous_char

---Return a counted word selection in native, directed half-open coordinates.
---@param doc core.doc
---@param idx integer
---@param key string
---@param count integer
---@return integer, integer, integer, integer
local function word(doc, idx, key, count)
  local reverse, big = key:lower() == "b", key == key:upper()
  local start = key:lower() == "w"
  local raw_l, raw_c = doc:get_selection_idx(idx)
  if reverse and raw_l == 1 and raw_c == 1
    or not reverse and not motion.char(doc, raw_l, raw_c) then
    return doc:get_selection_idx(idx)
  end
  local l, c = selection.characters(doc, idx)
  local a, b = next_char(doc, l, c)
  if not reverse then l, c, a, b = a, b, l, c end
  local step = reverse and prev_char or next_char

  ---Get the grapheme on the scanning side of a boundary.
  ---@param line integer
  ---@param col integer
  ---@param back boolean
  ---@return string?
  local function adjacent(line, col, back)
    if back then
      if line == 1 and col == 1 then return nil end
      line, col = prev_char(doc, line, col)
    end
    return motion.char(doc, line, col)
  end

  for _ = 1, count do
    local prior, char = adjacent(l, c, not reverse), adjacent(l, c, reverse)
    while char == "\n" do
      l, c = step(doc, l, c)
      prior, char = char, adjacent(l, c, reverse)
    end
    if prior == "\n" then a, b = l, c end
    local first = true
    while char do
      local old, new = motion.class(prior, big), motion.class(char, big)
      if not prior or old ~= new and (new == "newline"
        or start and new ~= "space"
        or not start and old ~= "space" and old ~= "newline") then
        if not first then break end
        a, b = l, c
      end
      l, c = step(doc, l, c)
      prior, char, first = char, adjacent(l, c, reverse), false
    end
    if not char then break end
  end
  return l, c, a, b
end

local aliases = {
  ["<left>"] = "h", ["<right>"] = "l", ["<up>"] = "k", ["<down>"] = "j",
}
---Create a Normal or Select motion over inclusive grapheme cursors.
---@param key string
---@param extend boolean
---@return modal.counted_action
local function movement(key, extend)
  key = aliases[key] or key
  ---Apply the motion to each directed selection.
  ---@param count integer
  local function move(count)
    local view = core.active_view
    local doc = view.doc
    for idx in doc:get_selections() do
      local l, c, a, b = selection.characters(doc, idx)
      if key:match("^[wWebBE]$") then
        doc:set_selections(idx, word(doc, idx, key, count))
        if extend then
          l, c = selection.characters(doc, idx)
          selection.set_characters(doc, idx, l, c, a, b)
        end
      elseif key == "x" or key == "X" then
        local first = math.min(l, a)
        local last = math.max(l, a)
        local endline, stop = doc:sanitize_position(last + 1, 1)
        local _, col, to, after = doc:get_selection_idx(idx, true)
        local full = col == 1 and to == endline and after == stop
        if key == "x" then
          last = last + count - (full and 0 or 1)
          endline, stop = doc:sanitize_position(last + 1, 1)
        end
        local backwards = key == "X" and (l < a or l == a and c < b)
        doc:set_selections(idx, endline, stop, first, 1, backwards)
      else
        local find = key:match("^[fFtT]")
        if not extend then a, b = l, c end
        if find then
          l, c = motion.find(doc, l, c, count, key:sub(1, 1),
            view.modal.current_command.input, true)
        elseif key == "h" or key == "l" then
          local step = key == "l" and next_char or prev_char
          for _ = 1, count do
            local row, col = step(doc, l, c)
            if row == l and col == c then break end
            l, c = row, col
          end
        elseif key == "j" or key == "k" then
          local rows = key == "j" and count or -count
          l, c = motion.vertical(view, idx, l, c, rows, false)
        elseif key == "gl" then
          c = #doc.lines[l]
          if c > 1 then l, c = prev_char(doc, l, c) end
        elseif key == "g_" then
          c = doc.lines[l]:find("%S") or 1
        elseif key == "gh" then
          c = 1
        elseif key ~= "G" or view.modal.current_command.n_repeat ~= "" then
          l = key == "ge" and #doc.lines or math.min(count, #doc.lines)
          if key == "ge" and l > 1 and #doc.lines[l] == 1 then l = l - 1 end
          c = 1
        else
          return
        end
        if l then
          if not extend and not find then a, b = l, c end
          selection.set_characters(doc, idx, l, c, a, b)
        end
      end
    end
    doc:merge_cursors()
  end
  modal.fns[move] = (extend and "Extend with " or "Move with ") .. key
  return modal.with_count(move)
end

return movement
