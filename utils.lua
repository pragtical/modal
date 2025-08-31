local core = require "core"
local search = require "core.doc.search"
local config = require "core.config"
local translate = require "core.doc.translate"

local modal = require "plugins.modal"

local modal_utils = {}

local function get_dv()
  return core.active_view
end

local function get_doc()
  return get_dv().doc
end

function modal_utils.sort_positions(line1, col1, line2, col2)
  if line1 > line2 or line1 == line2 and col1 > col2 then
    return line2, col2, line1, col1, true
  end
  return line1, col1, line2, col2, false
end

function modal_utils.doc_multiline_selections(sort)
  if get_dv() == nil or get_doc() == nil or get_doc().get_selections == nil then return function() return nil end end
  local iter, state, idx, line1, col1, line2, col2 = get_doc():get_selections(sort)
  return function()
    idx, line1, col1, line2, col2 = iter(state, idx)
    if idx and line2 > line1 and col2 == 1 then
      line2 = line2 - 1
      col2 = #get_doc().lines[line2]
    end
    return idx, line1, col1, line2, col2
  end
end

function modal_utils.go_to_line()
  if get_dv() ~= nil and get_dv().modal ~= nil and get_dv().modal.current_command and get_dv().modal.current_command.n_repeat ~= '' and get_doc() ~= nil then
    local N = get_dv().modal.current_command.num
    get_doc():set_selection(N, 1)
  end
end

function modal_utils.indent()
  local docview = core.active_view and core.active_view.doc
  if docview then
    for idx, line1, col1, line2, col2 in modal_utils.doc_multiline_selections(false) do
      local l1, c1, _, _ = docview:indent_text(false, math.min(line1, line2), 1, math.max(line1, line2), math.huge)
      if l1 then
        docview:set_selections(idx, line1, c1 - 1 + col1, line2, c1 - 1 + col2)
      end
    end
  end
end

function modal_utils.unindent()
  local docview = core.active_view and core.active_view.doc
  if docview then
    for idx, line1, col1, line2, col2 in modal_utils.doc_multiline_selections(false) do
      local l1, c1, _, _ = docview:indent_text(true, math.min(line1, line2), 1, math.max(line1, line2), math.huge)
      if l1 then
        docview:set_selections(idx, line1, c1 - 1 + col1, line2, c1 - 1 + col2)
      end
    end
  end
end

function modal_utils.unselect()
  for idx, _, _, line2, col2 in modal_utils.doc_multiline_selections(true) do
    get_doc():set_selections(idx, line2, col2, line2, col2)
  end
end

function modal_utils.select_LINE()
  for idx, line1, col1, line2, col2 in modal_utils.doc_multiline_selections(false) do
    local lobj = get_doc().highlighter:get_line(line2)
    if line1 == line2 and (col1 - col2 ~= #lobj.text - 1) then
      get_doc():set_selections(idx, line1 - 1, math.huge, line1, math.huge)
    end
  end
end

function modal_utils.select_line()
  for idx, line1, col1, line2, col2 in modal_utils.doc_multiline_selections(false) do
    local lobj = get_doc().highlighter:get_line(line2)
    if line1 == line2 and (col1 - col2 ~= #lobj.text - 1) then
      get_doc():set_selections(idx, line1, math.huge, line1 - 1, math.huge)
    else
      get_doc():set_selections(idx, math.max(line1, line2) + 1, math.huge, math.min(line1, line2), math.huge)
    end
  end
end

function modal_utils.delete()
  for idx, line1, col1, line2, col2 in modal_utils.doc_multiline_selections(true) do
    if line1 == line2 and col1 == col2 then
      local text = get_doc():get_text(line1, 1, line1, math.huge)
      col2 = col2 + 1
      if #text + 1 < col2 then
        col2 = 1
        line2 = line2 + 1
      end
    end
    get_doc():raw_remove(line1, col1, line2, col2, get_doc().undo_stack, system.get_time())
    get_doc():set_selections(idx, line1, col1)
  end
end

function modal_utils.select_in_blob(document, line1, col1, line2, col2, text, opt)
  local results = {}
  local ok, l1, c1, l2, c2 = pcall(modal_utils.search.find, document, line1, col1, text, opt)
  while ok and l1 and (l2 < line2 or (l2 == line2 and c2 <= col2)) do
    table.insert(results, { l1, c1, l2, c2 })
    ok, l1, c1, l2, c2 = pcall(modal_utils.search.find, document, l2, c2, text, opt)
  end
  return results
end

function modal_utils.split_in_blob(document, line1, col1, line2, col2, text, opt)
  local l0, c0 = line1, col1
  local results = {}
  local ok, l1, c1, l2, c2 = pcall(modal_utils.search.find, document, line1, col1, text, opt)
  while ok and l1 and (l2 < line2 or (l2 == line2 and c2 <= col2)) do
    table.insert(results, { l0, c0, l1, c1 })
    l0, c0 = l2, c2
    ok, l1, c1, l2, c2 = pcall(modal_utils.search.find, document, l2, c2, text, opt)
  end
  if l0 < line2 or (l0 == line2 and c0 < col2) then
    table.insert(results, { l0, c0, line2, col2 })
  end
  return results
end

function modal_utils.reset_selections(document, selections)
  if selections then
    local _, l1, c1, l2, c2 = table.unpack(selections[1])
    document:set_selection(l1, c1, l2, c2)
    for i = 2, #selections do
      _, l1, c1, l2, c2 = table.unpack(selections[i])
      document:add_selection(l1, c1, l2, c2)
    end
  end
end

function modal_utils.blob_action(document, text, fn, selections)
  if not text or #text == 0 then
    return nil
  end
  local opt = { wrap = false, no_case = false, regex = true, reverse = false }
  local results = {}
  local initials = {}
  for _, sel in ipairs(selections) do
    table.insert(initials, sel)
    local _, line1, col1, line2, col2 = table.unpack(sel)
    if line1 ~= line2 or col1 ~= col2 then
      line1, col1, line2, col2, _ = modal_utils.sort_positions(line1, col1, line2, col2)
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
  end
end

function modal_utils.go_to_selection_start()
  for idx, line1, col1, _, _ in modal_utils.doc_multiline_selections(true) do
    get_doc():set_selections(idx, line1, col1)
  end
end

function modal_utils.go_to_selection_end()
  for idx, _, _, line1, col1 in modal_utils.doc_multiline_selections(true) do
    get_doc():set_selections(idx, line1, col1)
  end
end

function modal_utils.concat(t1, t2)
  for k, v in pairs(t1) do
    if t2[k] == nil then
      t2[k] = v
    end
  end
  return t2
end

function modal_utils.copy()
  if get_doc() and get_doc().get_selection then
    local l1, c1, l2, c2 = get_doc():get_selection()
    if l1 == l2 and c2 == c1 then
      c2 = c1 + 1
    end
    local text = get_doc():get_text(l1, c1, l2, c2)
    system.set_clipboard(text)
  end
end

function modal_utils.paste_after()
  -- TODO improve
  local text = system.get_clipboard()
  if text and #text > 0 then
    local _, delta_line = text:gsub("\n", "")
    local delta_col = 1
    if delta_line == 0 then
      delta_col = #text
    else
      delta_col = math.huge
    end
    for idx, line1, col1, line2, col2 in modal_utils.doc_multiline_selections(false) do
      local line = math.max(line1, line2)
      local col = (line1 == line2 and math.max(col1, col2)) or (line1 > line2 and col1 or col2)
      get_doc():insert(line, col, text)
      get_doc():set_selections(idx, line + delta_line, col + delta_col, line, col)
    end
  end
end

function modal_utils.paste_before()
  -- TODO improve
  local text = system.get_clipboard()
  if text and #text > 0 then
    local _, delta_line = text:gsub("\n", "")
    local delta_col = 0
    if delta_line == 0 then
      delta_col = #text
    end
    for idx, line1, col1, line2, col2 in modal_utils.doc_multiline_selections(false) do
      local line = math.min(line1, line2)
      local col = (line1 == line2 and math.min(col1, col2)) or (line1 < line2 and col1 or col2)
      get_doc():insert(line, col, text)
      get_doc():set_selections(idx, line1 + delta_line, col1 + delta_col, line2 + delta_line, col2 + delta_col)
    end
  end
end

function modal_utils.get_last_key()
  local view = get_dv()
  if view.modal then
    return view.modal.last_input
  end
  return nil
end

function modal_utils.replace()
  local view = get_dv()
  local last = modal_utils.get_last_key()
  if last then
    for idx, line1, col1, line2, col2 in modal_utils.doc_multiline_selections(false) do
      local c1, c2 = col1, col2
      if line1 == line2 and col1 == col2 then
        c2 = c1 + 1
      end
      local text = view.doc:get_text(line1, c1, line2, c2)
      local repl = ''
      for line in text:gmatch("[^\r\n]*") do
        if #repl > 0 then
          repl = repl .. '\n'
        end
        repl = repl .. string.rep(last, #line)
      end
      if line1 == line2 then
        view.doc:insert(line1, math.max(c1, c2), repl)
        view.doc:remove(line1, math.min(c1, c2), line1, math.max(c1, c2))
      elseif line1 < line2 then
        view.doc:insert(line2, c2, repl)
        view.doc:remove(line1, c1, line2, c2)
      else
        view.doc:insert(line1, c1, repl)
        view.doc:remove(line2, c2, line1, c1)
      end
      view.doc:set_selections(idx, line1, col1, line2, col2)
    end
  end
end

function modal_utils.select_next_char()
  local view = get_dv()
  local last = modal_utils.get_last_key()
  if last then
    for idx, line1, col1, line2, col2 in modal_utils.doc_multiline_selections(false) do
      local _, _, l2, c2 = modal_utils.sort_positions(line1, col1, line2, col2)
      local ok, _, _, lnn, cnn = pcall(search.find, view.doc, l2, c2 + 1, last,
        { wrap = false, regex = false, no_case = false, reverse = false })
      if ok and lnn then
        view.doc:set_selections(idx, lnn, cnn - 1, l2, c2)
      end
    end
  end
end

function modal_utils.move_next_char()
  local view = get_dv()
  local last = modal_utils.get_last_key()
  if last then
    for idx, line1, col1, line2, col2 in modal_utils.doc_multiline_selections(false) do
      local _, _, l2, c2 = modal_utils.sort_positions(line1, col1, line2, col2)
      local ok, _, _, lnn, cnn = pcall(search.find, view.doc, l2, c2 + 1, last,
        { wrap = false, regex = false, no_case = false, reverse = false })
      if ok and lnn then
        view.doc:set_selections(idx, lnn, cnn - 1, lnn, cnn - 1)
      end
    end
  end
end

function modal_utils.extend_next_char()
  local view = get_dv()
  local last = modal_utils.get_last_key()
  if last then
    for idx, line1, col1, line2, col2 in modal_utils.doc_multiline_selections(false) do
      local l1, c1, l2, c2 = modal_utils.sort_positions(line1, col1, line2, col2)
      local ok, _, _, lnn, cnn = pcall(search.find, view.doc, l2, c2 + 1, last,
        { wrap = false, regex = false, no_case = false, reverse = false })
      if ok and lnn then
        view.doc:set_selections(idx, lnn, cnn, l1, c1)
      end
    end
  end
end

function modal_utils.select_prev_char()
  local view = get_dv()
  local last = modal_utils.get_last_key()
  if last then
    for idx, line1, col1, line2, col2 in modal_utils.doc_multiline_selections(false) do
      local l1, c1, _, _ = modal_utils.sort_positions(line1, col1, line2, col2)
      local ok, lnn, cnn, _, _ = pcall(search.find, view.doc, l1, c1, last,
        { wrap = false, regex = false, no_case = false, reverse = true })
      if ok and lnn then
        view.doc:set_selections(idx, lnn, cnn, l1, c1)
      end
    end
  end
end

function modal_utils.move_prev_char()
  local view = get_dv()
  local last = modal_utils.get_last_key()
  if last then
    for idx, line1, col1, line2, col2 in modal_utils.doc_multiline_selections(false) do
      local l1, c1, _, _ = modal_utils.sort_positions(line1, col1, line2, col2)
      local ok, lnn, cnn, _, _ = pcall(search.find, view.doc, l1, c1, last,
        { wrap = false, regex = false, no_case = false, reverse = true })
      if ok and lnn then
        view.doc:set_selections(idx, lnn, cnn, lnn, cnn)
      end
    end
  end
end

function modal_utils.extend_prev_char()
  local view = get_dv()
  local last = modal_utils.get_last_key()
  if last then
    for idx, line1, col1, line2, col2 in modal_utils.doc_multiline_selections(false) do
      local l1, c1, l2, c2 = modal_utils.sort_positions(line1, col1, line2, col2)
      local ok, lnn, cnn, _, _ = pcall(search.find, view.doc, l1, c1, last,
        { wrap = false, regex = false, no_case = false, reverse = true })
      if ok and lnn then
        view.doc:set_selections(idx, lnn, cnn, l2, c2)
      end
    end
  end
end

function modal_utils.select_till_next_char()
  local view = get_dv()
  local last = modal_utils.get_last_key()
  if last then
    for idx, line1, col1, line2, col2 in modal_utils.doc_multiline_selections(false) do
      local _, _, l2, c2 = modal_utils.sort_positions(line1, col1, line2, col2)
      local ok, _, cnn, lnn, _ = pcall(search.find, view.doc, l2, c2 + 2, last,
        { wrap = false, regex = false, no_case = false, reverse = false })
      if ok and lnn then
        view.doc:set_selections(idx, lnn, cnn - 1, l2, c2)
      end
    end
  end
end

function modal_utils.move_till_next_char()
  local view = get_dv()
  local last = modal_utils.get_last_key()
  if last then
    for idx, line1, col1, line2, col2 in modal_utils.doc_multiline_selections(false) do
      local _, _, l2, c2 = modal_utils.sort_positions(line1, col1, line2, col2)
      local ok, _, cnn, lnn, _ = pcall(search.find, view.doc, l2, c2 + 2, last,
        { wrap = false, regex = false, no_case = false, reverse = false })
      if ok and lnn then
        view.doc:set_selections(idx, lnn, cnn - 1, lnn, cnn - 1)
      end
    end
  end
end

function modal_utils.extend_till_next_char()
  local view = get_dv()
  local last = modal_utils.get_last_key()
  if last then
    for idx, line1, col1, line2, col2 in modal_utils.doc_multiline_selections(false) do
      local l1, c1, l2, c2 = modal_utils.sort_positions(line1, col1, line2, col2)
      local ok, _, cnn, lnn, _ = pcall(search.find, view.doc, l2, c2 + 2, last,
        { wrap = false, regex = false, no_case = false, reverse = false })
      if ok and lnn then
        view.doc:set_selections(idx, lnn, cnn - 1, l1, c1)
      end
    end
  end
end

function modal_utils.select_till_prev_char()
  local view = get_dv()
  local last = modal_utils.get_last_key()
  if last then
    for idx, line1, col1, line2, col2 in modal_utils.doc_multiline_selections(false) do
      local l1, c1, _, _ = modal_utils.sort_positions(line1, col1, line2, col2)
      local ok, lnn, _, _, cnn = pcall(search.find, view.doc, l1, c1, last,
        { wrap = false, regex = false, no_case = false, reverse = true })
      if ok and lnn then
        view.doc:set_selections(idx, lnn, cnn, l1, c1)
      end
    end
  end
end

function modal_utils.move_till_prev_char()
  local view = get_dv()
  local last = modal_utils.get_last_key()
  if last then
    for idx, line1, col1, line2, col2 in modal_utils.doc_multiline_selections(false) do
      local l1, c1, _, _ = modal_utils.sort_positions(line1, col1, line2, col2)
      local ok, lnn, _, _, cnn = pcall(search.find, view.doc, l1, c1, last,
        { wrap = false, regex = false, no_case = false, reverse = true })
      if ok and lnn then
        view.doc:set_selections(idx, lnn, cnn, lnn, cnn)
      end
    end
  end
end

function modal_utils.extend_till_prev_char()
  local view = get_dv()
  local last = modal_utils.get_last_key()
  if last then
    for idx, line1, col1, line2, col2 in modal_utils.doc_multiline_selections(false) do
      local l1, c1, l2, c2 = modal_utils.sort_positions(line1, col1, line2, col2)
      local ok, lnn, _, _, cnn = pcall(search.find, view.doc, l1, c1, last,
        { wrap = false, regex = false, no_case = false, reverse = true })
      if ok and lnn then
        view.doc:set_selections(idx, lnn, cnn, l2, c2)
      end
    end
  end
end

local set_mode__orig = modal.set_mode
function modal.set_mode(mode_id)
  if mode_id then
    set_mode__orig(mode_id)
    modal.notify(mode_id, false)
  end
end

local function is_non_word(char)
  if char == nil then
    return false
  end
  return not ((char >= 'a' and char <= 'z') or (char >= 'A' and char <= 'Z'))
end

local function is_non_WORD(char)
  if char == nil then
    return false
  end
  return not ((char >= ',' and char <= '.') or (char >= '_' and char <= 'z') or (char >= '?' and char <= 'Z') or char == ';' or char == ':' or char == '!')
end

function modal_utils.next_word_start(doc, line, col)
  local prev
  local end_line, end_col = translate.end_of_doc(doc, line, col)
  while line < end_line or col < end_col do
    local char = doc:get_char(line, col)
    if not is_non_word(char) and is_non_word(prev) then
      break
    end
    line, col = doc:position_offset(line, col, 1)
    prev = char
  end
  return line, col
end

function modal_utils.next_WORD_start(doc, line, col)
  local prev
  local end_line, end_col = translate.end_of_doc(doc, line, col)
  while line < end_line or col < end_col do
    local char = doc:get_char(line, col)
    if not is_non_word(char) and is_non_WORD(prev) then
      break
    end
    line, col = doc:position_offset(line, col, 1)
    prev = char
  end
  return line, col
end

function modal_utils.move_to_next_word_start()
  local dv = get_dv()
  dv.doc:move_to(modal_utils.next_word_start, dv)
end

function modal_utils.move_to_next_WORD_start()
  local dv = get_dv()
  dv.doc:move_to(modal_utils.next_WORD_start, dv)
end

return modal_utils
