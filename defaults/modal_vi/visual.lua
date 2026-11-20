local core = require "core"
local modal = require "plugins.modal"
local translate = require "core.doc.translate"
local mu = require "plugins.modal.utils"
local register = require "plugins.modal.defaults.modal_vi.register"
local changes = require "plugins.modal.defaults.modal_vi.changes"
local operators = require "plugins.modal.defaults.modal_vi.operators"
local shapes = require "plugins.modal.defaults.modal_vi.shapes"

---Vi characterwise visual motions and inclusive selection operators.
---@class plugins.modal.vi.visual
local visual = {}
local next_char, prev_char = translate.next_char, translate.previous_char

---Convert between Vi's inclusive character endpoints and native half-open
---selections.
---@param doc core.doc
---@param expand boolean Expand to a native range or contract to its carets.
local function endpoints(doc, expand)
  for idx, l, c, a, b in doc:get_selections() do
    if expand then
      modal.selection.set_characters(doc, idx, l, c, a, b)
    else
      doc:set_selections(idx, modal.selection.characters(doc, idx))
    end
  end
end

---Create a counted binding that enters or leaves a character, line or block
---selection.
---@param mode string Mode ID.
---@return modal.counted_action
function visual.switch(mode)
  ---Switch selection shape at the current anchor, or leave Visual mode on a
  ---repeated shape key.
  ---@param count integer
  local function switch(count)
    local view = core.active_view
    local doc, current = view.doc, view.modal.mode
    if current == shapes.line or current == shapes.block then
      modal.selection.release(view)
    elseif current == "VIS" then
      endpoints(doc, false)
    else
      for idx, l, c in doc:get_selections() do doc:set_selections(idx, l, c) end
    end
    if mode == current or mode == "NOR" then
      for idx, l, c in doc:get_selections() do doc:set_selections(idx, l, c) end
      modal.set_mode("NOR")
    elseif mode == "VIS" then
      endpoints(doc, true)
      modal.set_mode(mode)
    else
      shapes.enter(view, mode, count)
    end
  end
  modal.fns[switch] = "Switch to " .. modal.mode_labels[mode]
  return modal.with_count(switch)
end

---Wrap a motion so its inclusive endpoints remain highlighted between
---keystrokes.
---@param action modal.action
---@param key string Original binding used in the help caption.
---@return modal.counted_action
function visual.motion(action, key)
  ---Run the motion on caret positions, then restore the inclusive selection.
  ---@param count integer
  local function move(count)
    local doc = core.active_view.doc
    endpoints(doc, false)
    modal.eval_cmd(action, count)
    endpoints(doc, true)
  end
  modal.fns[move] = modal.fns[action] or (type(action) == "string" and action)
    or ("Select with " .. key)
  return modal.with_count(move)
end

---Count graphemes in a half-open byte range on one line.
---@param doc core.doc
---@param line integer
---@param start integer
---@param finish integer
---@return integer
local function width(doc, line, start, finish)
  local n = 0
  while start < finish do
    local _, c = next_char(doc, line, start)
    start, n = c, n + 1
  end
  return n
end

---Yank, delete or change all characterwise selections and capture edit
---dimensions for dot repeat.
---@param op modal.operator
local function apply(op)
  local view = core.active_view
  local doc, ranges, sizes = view.doc, {}, {}
  for idx, l, c, a, b in doc:get_selections(true) do
    if l == a and c == b then a, b = next_char(doc, l, c) end
    ranges[idx] = { l, c, a, b }
    sizes[idx] = { rows = a - l, chars = width(doc, a, a == l and c or 1, b) }
  end
  ---Apply the captured ranges and leave Visual mode.
  local function edit()
    for idx, r in ipairs(ranges) do doc:set_selections(idx, r[1], r[2]) end
    operators.apply_ranges(view, op, ranges)
    if op ~= "c" then modal.set_mode("NOR") end
  end
  if op == "y" then return edit() end
  ---Rebuild equivalent ranges at the current carets before repeating the
  ---operator.
  local function replay()
    local target = core.active_view
    local d, repeated = target.doc, {}
    for idx, l, c in d:get_selections() do
      local shape = sizes[idx] or sizes[1]
      local a = math.min(#d.lines, l + shape.rows)
      local b = shape.rows == 0 and c or 1
      for _ = 1, shape.chars do
        local previous = a
        a, b = next_char(d, a, b)
        if a ~= previous or (a == #d.lines and b == #d.lines[a]) then break end
      end
      -- At EOF a multiline repeat can end on the starting row, to the
      -- left of the caret. Both characters still belong to the selection.
      if shape.rows > 0 and a == l and b <= c then
        local start = b > 1 and select(2, prev_char(d, a, b)) or 1
        a, b = next_char(d, l, c)
        c = start
      end
      repeated[idx] = { l, c, a, b }
    end
    operators.apply_ranges(target, op, repeated)
  end
  changes.perform(edit, 1, nil, modal.with_count(replay))
end

---Replace each selected grapheme and return to the start of the changed text.
---In Normal mode the count is limited to the remainder of the current line.
---@param count integer
function visual.replace(count)
  local view = core.active_view
  local doc, normal = view.doc, view.modal.mode == "NOR"
  if normal then
    local spans = {}
    for idx, l, c in doc:get_selections() do
      local stop = c
      for _ = 1, count do
        if stop >= #doc.lines[l] then return end
        stop = select(2, next_char(doc, l, stop))
      end
      spans[idx] = { l, stop, l, c }
    end
    for idx, span in ipairs(spans) do
      doc:set_selections(idx, table.unpack(span))
    end
  end
  doc.undo_stack.force_group = true
  mu.replace()
  for idx, l, c, a, b in doc:get_selections(true) do
    if normal then l, c = prev_char(doc, a, b) end
    doc:set_selections(idx, l, c)
  end
  modal.set_mode("NOR")
end

---Put the unnamed register over the selected text.
---@param preserve boolean Keep the register when using uppercase P.
---@param count integer
function visual.put(preserve, count)
  local doc = core.active_view.doc
  local text, parts, _, linewise = register.read()
  if not text then return end
  local removed, whole = {}, {}
  doc.undo_stack.force_group = true
  for idx, l, c, a, b in doc:get_selections(true, true) do
    removed[idx], whole[idx] = doc:get_text(l, c, a, b), false
    local fragment = parts and #parts == #doc.selections / 4 and parts[idx]
    local value = fragment or text
    if linewise then
      if not fragment then value = value:gsub("\n$", "") end
      value = "\n" .. (value .. "\n"):rep(count)
    else
      value = value:rep(count)
    end
    doc:set_selections(idx, l, c)
    doc:remove(l, c, a, b)
    doc:insert(l, c, value)
    if linewise then
      l = l + 1
      c = doc.lines[l]:find("%S") or 1
    elseif not value:find("\n", 1, true) then
      l, c = prev_char(doc, l, c + #value)
    end
    doc:set_selections(idx, l, c)
  end
  if not preserve then register.write(table.concat(removed, "\n"), removed,
    whole) end
  modal.set_mode("NOR")
end

---Delete the inclusive selections and remember their dimensions for repeat.
function visual.delete() apply("d") end
---Change the selected text and capture the insertion for dot repeat.
visual.change = modal.with_count(function() apply("c") end)
---Copy the inclusive selections to the register and return to Normal mode.
function visual.yank() apply("y") end
modal.fns[visual.change] = "Change selection"

return visual
