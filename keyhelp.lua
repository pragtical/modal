local core = require "core"
local style = require "core.style"
local notation = require "plugins.modal.bindings_models.modal"

---Compare an input prefix with a compiled binding and return its strokes.
---@alias modal.matcher fun(prefix: string[], binding: string, full: boolean):
---boolean, string[]?

---A possible next key below the current prefix.
---@class modal.choice
---@field stroke string Compiled stroke.
---@field key string Display name.
---@field count integer Number of bindings with this next stroke.
---@field caption? string Explicit preset caption.
---@field example modal.action One binding below this prefix.
---@field action? modal.action Action that executes on this key.
---@field group boolean The key introduces a longer sequence.
---@field text string Caption displayed in the overlay.

---Suggestions for a pending sequence, with hit bounds set by the renderer.
---@class modal.overlay
---@field entries modal.choice[] Sorted display rows.
---@field bound table<string, modal.choice> Choices indexed by native stroke.
---@field title string Display form of the pending sequence.
---@field page integer One-based current page.
---@field pages? integer Page count after layout.
---@field waiting? boolean Waiting for the configured display delay.
---@field x? number
---@field y? number
---@field w? number
---@field h? number

---Collect, lay out and display next-key suggestions for a document view.
---@class plugins.modal.keyhelp
local keyhelp = {}

---Format a native stroke for display, including shifted punctuation and
---wildcard arguments.
---@param stroke string
---@return string
local function display_key(stroke)
  if stroke == "$" then return "<char>" end
  local key = stroke:match("^shift%+(.+)$")
  if key then
    if key:match("^%l$") then return key:upper() end
    if notation.shifted_symbols[key] then
      return notation.shifted_symbols[key]
    end
  end
  if #stroke == 1 then return stroke end
  return (stroke:gsub("%a+", function(word)
    return #word > 1 and word:sub(1, 1):upper() .. word:sub(2) or word
  end))
end

---Index explicit captions by full sequence, accepting both preset notation and
---native key names.
---@param helpers modal.helpers
---@param model modal.model
---@return table<string,string> captions
function keyhelp.labels(helpers, model)
  local labels = {}
  for prefix, entries in pairs(helpers) do
    for _, entry in ipairs(entries) do
      labels[prefix .. " " .. entry[1]] = entry[2]
      labels[prefix .. " " .. model.convert(entry[1])] = entry[2]
    end
  end
  return labels
end

---Collect the possible next strokes of a prefix in the active view's compiled
---keymap.
---@param state modal.state
---@param prefix string[]
---@param match modal.matcher
---@param labels table<string,string>
---@param modal plugins.modal
---@return modal.overlay? suggestions
function keyhelp.collect(state, prefix, match, labels, modal)
  local choices, by_key = {}, {}
  for binding, action in pairs(state.keymap) do
    local matches, keys = match(prefix, binding, false)
    local next_key = matches and keys[#prefix + 1]
    if next_key then
      ---@cast keys string[]
      local item = by_key[next_key]
      if not item then
        item = { stroke = next_key, key = display_key(next_key), count = 0 }
        by_key[next_key] = item
        choices[#choices + 1] = item
      end
      item.count = item.count + 1
      local path = table.concat(keys, " ", 1, #prefix + 1)
      item.caption = labels[path] or item.caption
      item.example = action
      if #keys == #prefix + 1 then item.action = action end
    end
  end
  if #choices == 0 then return end
  local path = table.concat(prefix, " ") .. " "
  for _, item in ipairs(choices) do
    -- A wildcard can execute immediately even if a longer literal binding
    -- shares the same next stroke.
    if item.action or by_key["$"] then
      item.action = modal.get_command(path .. item.stroke)
    end
    item.group = item.action == nil
    item.text = item.caption
      or (item.action and modal.describe_action(item.action, true))
      or (item.count == 1 and modal.describe_action(item.example, true)
        or item.count .. " bindings")
    if item.group then item.text = "+" .. item.text end
  end
  table.sort(choices, function(a, b)
    if a.group ~= b.group then return a.group end
    if a.key:lower() ~= b.key:lower() then
      return a.key:lower() < b.key:lower()
    end
    return a.stroke < b.stroke
  end)
  local title = state.keyhelper:gsub("%S+", display_key)
  return { entries = choices, bound = by_key, title = title, page = 1 }
end

---Move a paginated overlay by the given number of pages, clamped to its
---available range.
---@param help modal.overlay?
---@param delta integer
---@return boolean handled
local function turn(help, delta)
  if not help or not help.pages or help.pages <= 1 then return false end
  help.page = math.max(1, math.min(help.pages, help.page + delta))
  core.redraw = true
  return true
end

---Handle Page Up or Page Down when the prefix leaves the paging key unbound.
---@param help modal.overlay?
---@param stroke string
---@return boolean handled
function keyhelp.page_key(help, stroke)
  if not help or help.bound[stroke] or help.bound["$"] then return false end
  if stroke == "pageup" then return turn(help, -1) end
  if stroke == "pagedown" then return turn(help, 1) end
  return false
end

---Page a visible overlay when the pointer is inside its screen rectangle.
---@param help modal.overlay?
---@param x number
---@param y number
---@param delta number Vertical wheel delta.
---@return boolean handled
function keyhelp.wheel(help, x, y, delta)
  if not help or not help.x or delta == 0 then return false end
  if x >= help.x and x < help.x + help.w and y >= help.y
    and y < help.y + help.h then
    return turn(help, delta > 0 and -1 or 1)
  end
  return false
end

---Lay out, paginate and draw the next-key overlay within the document pane.
---@param view core.docview
---@param help modal.overlay
---@param align modal.alignment
function keyhelp.draw(view, help, align)
  local panel, font, code = style.helper, style.font, style.code_font
  local margin, pad = panel.margin, panel.padding
  local width, height = view.size.x - 2 * margin, view.size.y - 2 * margin
  local line = math.max(font:get_height(), code:get_height())
  local row = line + math.ceil(style.padding.y / 2)
  if width <= 2 * pad or height < row + 2 * pad then
    help.x, help.pages = nil, nil
    return
  end

  local key_width, label_width = 0, 0
  for _, item in ipairs(help.entries) do
    key_width = math.max(key_width, code:get_width(item.key))
    label_width = math.max(label_width, font:get_width(item.text))
  end
  local arrow_width = code:get_width(" → ")
  local gap = style.padding.x
  local cell = math.min(width - 2 * pad, key_width + arrow_width + label_width)
  local columns = math.max(1, math.min(#help.entries,
    math.floor((width - 2 * pad + gap) / (cell + gap))))
  local rows = math.ceil(#help.entries / columns)
  local header = height >= 2 * row + 2 * pad and row or 0
  local max_rows = math.max(1,
    math.floor((height * 0.5 - header - 2 * pad) / row))
  rows = math.min(rows, max_rows)
  local capacity = rows * columns
  help.pages = math.ceil(#help.entries / capacity)
  help.page = math.min(help.page, help.pages)
  local first = 1 + (help.page - 1) * capacity
  local page_label = ""
  if help.pages > 1 then
    local keys = (help.bound.pageup or help.bound.pagedown or help.bound["$"])
      and "Scroll" or "PgUp/PgDn"
    page_label = string.format("%s  %d/%d", keys, help.page, help.pages)
  end
  local w = math.min(width, 2 * pad + math.max(
    columns * cell + (columns - 1) * gap,
    code:get_width(help.title) + gap + font:get_width(page_label)))
  local h = 2 * pad + header + rows * row
  local x, y = view.position.x + margin,
    view.position.y + view.size.y - margin - h
  if panel.alignement == align.RIGHT then x = x + width - w end
  if panel.alignement == align.CENTER then x = x + (width - w) / 2 end
  help.x, help.y, help.w, help.h = x, y, w, h

  core.push_clip_rect(x, y, w, h)
  renderer.draw_rect(x, y, w, h, panel.background)
  renderer.draw_rect(x, y, w, style.divider_size, style.divider)
  x, y = x + pad, y + pad
  if header > 0 then
    local label_width = font:get_width(page_label)
    core.push_clip_rect(
      x, y, math.max(0, w - 2 * pad - label_width - gap), header)
    renderer.draw_text(code, help.title, x, y, style.accent)
    core.pop_clip_rect()
    if page_label ~= "" then
      renderer.draw_text(
        font, page_label, x + w - 2 * pad - label_width, y, style.dim)
    end
    y = y + header
  end
  for i = first, math.min(#help.entries, first + capacity - 1) do
    local item = help.entries[i]
    local cx = x + math.floor((i - first) / rows) * (cell + gap)
    local cy = y + (i - first) % rows * row
    core.push_clip_rect(cx, cy, cell, row)
    renderer.draw_text(
      code, item.key, cx + key_width - code:get_width(item.key), cy,
      style.syntax.number or style.accent)
    renderer.draw_text(code, " → ", cx + key_width, cy, style.dim)
    renderer.draw_text(font, item.text, cx + key_width + arrow_width, cy,
      item.group and (style.syntax["function"] or style.accent) or panel.text)
    core.pop_clip_rect()
  end
  core.pop_clip_rect()
end

return keyhelp
