-- mod-version:3
local modal = require "plugins.modal"
local kb_modal = require "plugins.modal.kb_modal"

local core = require "core"
local search = require "core.doc.search"
local config = require "core.config"
local command = require "core.command"

require "plugins.modal-hx.interface"


local modal_hx = {}
modal_hx.last_select = ""
-- TODO implement registers
modal_hx.target_register = nil
modal_hx.registers = {}

local mode = { NOR = "NOR", INS = "INS", SEL = "SEL" }

local function dv()
  return core.active_view
end

local function doc()
  return dv().doc
end

-- local function explore(node, label, spaces)
--     local tab = string.rep(' ', spaces)
-- 	  if node.type == "leaf" then
--       return tab .. label .. ': '.. tostring(node.active_view:get_name()) ..'['.. tostring(node.active_view) ..']\n'
--     else
--       local string = tab .. label.. ': '..node.type ..'\n'
--       string = string .. explore(node.a, "A", spaces + 2)
--       string = string .. explore(node.b, "B", spaces + 2)
--       return string
--     end
-- end


local function sort_positions(line1, col1, line2, col2)
  if line1 > line2 or line1 == line2 and col1 > col2 then
    return line2, col2, line1, col1, true
  end
  return line1, col1, line2, col2, false
end

local function doc_multiline_selections(sort)
  if dv() == nil or doc() == nil or doc().get_selections == nil then return function() return nil end end
  local iter, state, idx, line1, col1, line2, col2 = doc():get_selections(sort)
  return function()
    idx, line1, col1, line2, col2 = iter(state, idx)
    if idx and line2 > line1 and col2 == 1 then
      line2 = line2 - 1
      col2 = #doc().lines[line2]
    end
    return idx, line1, col1, line2, col2
  end
end


local function go_to_line()
  if dv() ~= nil and dv().modal ~= nil and dv().modal.current_command and dv().modal.current_command.n_repeat ~= '' and doc() ~= nil then
    local N = dv().modal.current_command.num
    doc():set_selection(N, 1)
  end
end

local function indent()
  local docview = core.active_view and core.active_view.doc
  if docview then
    for idx, line1, col1, line2, col2 in doc_multiline_selections(false) do
      local l1, c1, _, _ = docview:indent_text(false, math.min(line1, line2), 1, math.max(line1, line2), math.huge)
      if l1 then
        docview:set_selections(idx, line1, c1 - 1 + col1, line2, c1 - 1 + col2)
      end
    end
  end
end

local function unindent()
  local docview = core.active_view and core.active_view.doc
  if docview then
    for idx, line1, col1, line2, col2 in doc_multiline_selections(false) do
      local l1, c1, _, _ = docview:indent_text(true, math.min(line1, line2), 1, math.max(line1, line2), math.huge)
      if l1 then
        docview:set_selections(idx, line1, c1 - 1 + col1, line2, c1 - 1 + col2)
      end
    end
  end
end

local function unselect()
  if modal.get_mode() ~= mode.SEL then
    for idx, _, _, line2, col2 in doc_multiline_selections(true) do
      doc():set_selections(idx, line2, col2, line2, col2)
    end
  end
end

local function select_LINE()
  for idx, line1, col1, line2, col2 in doc_multiline_selections(false) do
    local lobj = doc().highlighter:get_line(line2)
    if line1 == line2 and (col1 - col2 ~= #lobj.text - 1) then
      doc():set_selections(idx, line1 - 1, math.huge, line1, math.huge)
    end
  end
end


local function select_line()
  for idx, line1, col1, line2, col2 in doc_multiline_selections(false) do
    local lobj = doc().highlighter:get_line(line2)
    if line1 == line2 and (col1 - col2 ~= #lobj.text - 1) then
      doc():set_selections(idx, line1, math.huge, line1 - 1, math.huge)
    else
      doc():set_selections(idx, math.max(line1, line2) + 1, math.huge, math.min(line1, line2), math.huge)
    end
  end
end

local function delete()
  for idx, line1, col1, line2, col2 in doc_multiline_selections(true) do
    if line1 == line2 and col1 == col2 then
      local text = doc():get_text(line1, 1, line1, math.huge)
      col2 = col2 + 1
      if #text + 1 < col2 then
        col2 = 1
        line2 = line2 + 1
      end
    end
    doc():raw_remove(line1, col1, line2, col2, doc().undo_stack, system.get_time())
    doc():set_selections(idx, line1, col1)
  end
end

local function select_in_blob(document, line1, col1, line2, col2, text, opt)
  local results = {}
  local ok, l1, c1, l2, c2 = pcall(search.find, document, line1, col1, text, opt)
  while ok and l1 and (l2 < line2 or (l2 == line2 and c2 <= col2)) do
    table.insert(results, { l1, c1, l2, c2 })
    ok, l1, c1, l2, c2 = pcall(search.find, document, l2, c2, text, opt)
  end
  return results
end

local function split_in_blob(document, line1, col1, line2, col2, text, opt)
  local l0, c0 = line1, col1
  local results = {}
  local ok, l1, c1, l2, c2 = pcall(search.find, document, line1, col1, text, opt)
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

local function reset_selections(document, selections)
  if selections then
    local _, l1, c1, l2, c2 = table.unpack(selections[1])
    document:set_selection(l1, c1, l2, c2)
    for i = 2, #selections do
      _, l1, c1, l2, c2 = table.unpack(selections[i])
      document:add_selection(l1, c1, l2, c2)
    end
  end
end

local function blob_action(document, text, fn, selections)
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
      line1, col1, line2, col2, _ = sort_positions(line1, col1, line2, col2)
      local ok, r = pcall(fn, document, line1, col1, line2, col2, text, opt)
      if ok and #r >= 1 then
        table.insert(results, r)
      end
    end
  end
  if #results == 0 then
    reset_selections(document, selections)
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


local function search_select()
  local selections = {}
  for idx, line1, col1, line2, col2 in doc_multiline_selections(false) do
    table.insert(selections, { idx, line1, col1, line2, col2 })
  end
  local last_doc = doc()
  core.command_view:enter("select", {
    text = modal_hx.last_select,
    select_text = true,
    show_suggestions = false,
    submit = function(text, _)
      modal_hx.last_select = text
      blob_action(last_doc, text, select_in_blob, selections)
    end,
    cancel = function(_)
      core.status_view:remove_tooltip()
      reset_selections(last_doc, selections)
    end,
    suggest = function(text)
      if text and #text > 0 then
        blob_action(last_doc, text, select_in_blob, selections)
      else
        reset_selections(last_doc, selections)
      end
    end
  })
end

local function search_split()
  local selections = {}
  for idx, line1, col1, line2, col2 in doc_multiline_selections(false) do
    table.insert(selections, { idx, line1, col1, line2, col2 })
  end
  local last_doc = doc()
  core.command_view:enter("split", {
    text = modal_hx.last_select,
    select_text = true,
    show_suggestions = false,
    submit = function(text, _)
      modal_hx.last_select = text
      blob_action(last_doc, text, split_in_blob, selections)
    end,
    cancel = function(_)
      core.status_view:remove_tooltip()
      reset_selections(last_doc, selections)
    end,
    suggest = function(text)
      if text and #text > 0 then
        core.log("Split %s", text)
        blob_action(last_doc, text, split_in_blob, selections)
      else
        reset_selections(last_doc, selections)
      end
    end
  })
end

local function go_to_selection_start()
  for idx, line1, col1, _, _ in doc_multiline_selections(true) do
    doc():set_selections(idx, line1, col1)
  end
end

local function go_to_selection_end()
  for idx, _, _, line1, col1 in doc_multiline_selections(true) do
    doc():set_selections(idx, line1, col1)
  end
end

local function concat(t1, t2)
  for k, v in pairs(t1) do
    if t2[k] == nil then
      t2[k] = v
    end
  end
  return t2
end


local function copy()
  if doc() and doc().get_selection then
    local l1, c1, l2, c2 = doc():get_selection()
    if l1 == l2 and c2 == c1 then
      c2 = c1 + 1
    end
    local text = doc():get_text(l1, c1, l2, c2)
    system.set_clipboard(text)
  end
end

local function paste_after()
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
    for idx, line1, col1, line2, col2 in doc_multiline_selections(false) do
      local line = math.max(line1, line2)
      local col = (line1 == line2 and math.max(col1, col2)) or (line1 > line2 and col1 or col2)
      doc():insert(line, col, text)
      doc():set_selections(idx, line + delta_line, col + delta_col, line, col)
    end
  end
end

local function paste_before()
  -- TODO improve
  local text = system.get_clipboard()
  if text and #text > 0 then
    local _, delta_line = text:gsub("\n", "")
    local delta_col = 0
    if delta_line == 0 then
      delta_col = #text
    end
    for idx, line1, col1, line2, col2 in doc_multiline_selections(false) do
      local line = math.min(line1, line2)
      local col = (line1 == line2 and math.min(col1, col2)) or (line1 < line2 and col1 or col2)
      doc():insert(line, col, text)
      doc():set_selections(idx, line1 + delta_line, col1 + delta_col, line2 + delta_line, col2 + delta_col)
    end
  end
end


local function get_last_key()
  local view = dv()
  if view.modal then
    local seq = modal.split_command(view.modal.current_command.seq)
    local last = seq[#seq]
    if #last > 1 then
      last = modal.reverse_key_mapping[last]
    end
    if last then
      return last
    end
  end
  return nil
end

local function replace()
  local view = dv()
  local last = get_last_key()
  if last then
    for idx, line1, col1, line2, col2 in doc_multiline_selections(false) do
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

local function move_next_char()
  local view = dv()
  local last = get_last_key()
  if last then
    for idx, line1, col1, line2, col2 in doc_multiline_selections(false) do
      local _, _, l2, c2 = sort_positions(line1, col1, line2, col2)
      local ok, _, _, lnn, cnn = pcall(search.find, view.doc, l2, c2 + 1, last,
        { wrap = false, regex = false, no_case = false, reverse = false })
      if ok and lnn then
        view.doc:set_selections(idx, lnn, cnn, l2, c2)
      end
    end
  end
end

local function select_next_char()
  local view = dv()
  local last = get_last_key()
  if last then
    for idx, line1, col1, line2, col2 in doc_multiline_selections(false) do
      local l1, c1, l2, c2 = sort_positions(line1, col1, line2, col2)
      local ok, _, _, lnn, cnn = pcall(search.find, view.doc, l2, c2 + 1, last,
        { wrap = false, regex = false, no_case = false, reverse = false })
      if ok and lnn then
        view.doc:set_selections(idx, lnn, cnn, l1, c1)
      end
    end
  end
end

local function move_prev_char()
  local view = dv()
  local last = get_last_key()
  if last then
    for idx, line1, col1, line2, col2 in doc_multiline_selections(false) do
      local l1, c1, _, _ = sort_positions(line1, col1, line2, col2)
      local ok, lnn, cnn, _, _ = pcall(search.find, view.doc, l1, c1, last,
        { wrap = false, regex = false, no_case = false, reverse = true })
      if ok and lnn then
        view.doc:set_selections(idx, lnn, cnn, l1, c1)
      end
    end
  end
end

local function select_prev_char()
  local view = dv()
  local last = get_last_key()
  if last then
    for idx, line1, col1, line2, col2 in doc_multiline_selections(false) do
      local l1, c1, l2, c2 = sort_positions(line1, col1, line2, col2)
      local ok, lnn, cnn, _, _ = pcall(search.find, view.doc, l1, c1, last,
        { wrap = false, regex = false, no_case = false, reverse = true })
      if ok and lnn then
        view.doc:set_selections(idx, lnn, cnn, l2, c2)
      end
    end
  end
end

local function move_till_next_char()
  local view = dv()
  local last = get_last_key()
  if last then
    for idx, line1, col1, line2, col2 in doc_multiline_selections(false) do
      local _, _, l2, c2 = sort_positions(line1, col1, line2, col2)
      local ok, _, cnn, lnn, _ = pcall(search.find, view.doc, l2, c2 + 1, last,
        { wrap = false, regex = false, no_case = false, reverse = false })
      if ok and lnn then
        view.doc:set_selections(idx, lnn, cnn, l2, c2)
      end
    end
  end
end

local function select_till_next_char()
  local view = dv()
  local last = get_last_key()
  if last then
    for idx, line1, col1, line2, col2 in doc_multiline_selections(false) do
      local l1, c1, l2, c2 = sort_positions(line1, col1, line2, col2)
      local ok, _, cnn, lnn, _ = pcall(search.find, view.doc, l2, c2 + 1, last,
        { wrap = false, regex = false, no_case = false, reverse = false })
      if ok and lnn then
        view.doc:set_selections(idx, lnn, cnn, l1, c1)
      end
    end
  end
end

local function move_till_prev_char()
  local view = dv()
  local last = get_last_key()
  if last then
    for idx, line1, col1, line2, col2 in doc_multiline_selections(false) do
      local l1, c1, _, _ = sort_positions(line1, col1, line2, col2)
      local ok, lnn, _, _, cnn = pcall(search.find, view.doc, l1, c1, last,
        { wrap = false, regex = false, no_case = false, reverse = true })
      if ok and lnn then
        view.doc:set_selections(idx, lnn, cnn, l1, c1)
      end
    end
  end
end

local function select_till_prev_char()
  local view = dv()
  local last = get_last_key()
  if last then
    for idx, line1, col1, line2, col2 in doc_multiline_selections(false) do
      local l1, c1, l2, c2 = sort_positions(line1, col1, line2, col2)
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

modal.fns[unselect] = "hx:unselect"
modal.fns[copy] = "hx:copy"
modal.fns[paste_after] = "hx:paste-after"
modal.fns[paste_before] = "hx:paste-before"
modal.fns[indent] = "hx:indent"
modal.fns[unindent] = "hx:unindent"
modal.fns[replace] = "hx:replace"
modal.fns[go_to_line] = "hx:go-to-line"
modal.fns[delete] = "hx:delete"
modal.fns[select_LINE] = "hx:select-LINE"
modal.fns[select_line] = "hx:select-line"
modal.fns[select_next_char] = "hx:select-next-character"
modal.fns[select_prev_char] = "hx:select-previous-character"
modal.fns[select_till_next_char] = "hx:select-till-next-character"
modal.fns[select_till_prev_char] = "hx:select-till-previous-character"
modal.fns[move_next_char] = "hx:move-next-character"
modal.fns[move_prev_char] = "hx:move-previous-character"
modal.fns[move_till_next_char] = "hx:move-till-next-character"
modal.fns[move_till_prev_char] = "hx:move-till-previous-character"
modal.fns[search_select] = "hx:search"
modal.fns[search_split] = "hx:split"
modal.fns[go_to_selection_start] = "hx:go-to-selection-start"
modal.fns[go_to_selection_end] = "hx:go-to-selection-end"

config.plugins.modal.base_mode = mode.NOR
config.plugins.modal.modes = { mode.NOR, mode.INS, mode.SEL }
config.plugins.modal.keymaps = {
  NOR = {
    [":"] = "core:find-command",
    ["<return>"] = { "command:submit", "dialog:select" },
    ["."] = "modal:redo",
    -- mode change
    ["i"] = { go_to_selection_start, modal.go_to_mode(mode.INS) },
    ["I"] = { "doc:move-to-start-of-line", modal.go_to_mode(mode.INS) },
    ["v"] = modal.go_to_mode(mode.SEL),
    ["O"] = { "doc:newline-above", go_to_selection_start, modal.go_to_mode(mode.INS) },
    ["o"] = { "doc:newline-below", go_to_selection_start, modal.go_to_mode(mode.INS) },
    ["a"] = { go_to_selection_end, modal.go_to_mode(mode.INS) },
    ["A"] = { "doc:move-to-end-of-line", go_to_selection_start, modal.go_to_mode(mode.INS) },
    -- actions
    ["u"] = "doc:undo",
    ["U"] = "doc:redo",
    ["p"] = paste_after,
    ["P"] = paste_before,
    ["y"] = copy,
    ["d"] = { copy, delete },
    ["J"] = "doc:join-lines",
    ["\\<"] = unindent,
    [">"] = indent,
    ["r<.>"] = replace,
    ["R"] = "doc:paste",
    -- search
    ["<space>/"] = "project-search:find",
    ["/"] = "find-replace:find",
    ["n"] = "find-replace:repeat-find",
    ["N"] = "find-replace:previous-find",

    -- movements
    ["<left>"] = { unselect, "doc:move-to-previous-char", "dialog:previous-entry" },
    ["<right>"] = { unselect, "doc:move-to-next-char", "dialog:next-entry" },
    ["<up>"] = { unselect, "command:select-previous", "doc:move-to-previous-line" },
    ["<down>"] = { unselect, "command:select-next", "doc:move-to-next-line" },
    ["h"] = { unselect, "doc:move-to-previous-char" },
    ["l"] = { unselect, "doc:move-to-next-char" },
    ["k"] = { unselect, "doc:move-to-previous-line" },
    ["j"] = { unselect, "doc:move-to-next-line" },
    ["<pageup>"] = { unselect, "doc:move-to-previous-page" },
    ["<pagedown>"] = { unselect, "doc:move-to-next-page" },
    ["C-<left>"] = {unselect, "movestory:prev"},
    ["C-h"] = {unselect, "movestory:prev"},
    ["C-<right>"] = {unselect, "movestory:next"},
    ["C-l"] = {unselect, "movestory:next"},

    -- movement + selection
    ["x"] = select_line,
    ["X"] = select_LINE,
    ["w"] = { unselect, "doc:select-to-next-word-end" },
    ["W"] = { unselect, "doc:select-to-next-WORD-end" },
    ["e"] = { unselect, "doc:select-to-next-word-end" },
    ["E"] = { unselect, "doc:select-to-next-WORD-end" },
    ["b"] = { unselect, "doc:select-to-previous-word-start" },
    ["B"] = { unselect, "doc:select-to-previous-WORD-start" },
    ["f<.>"] = { move_next_char },
    ["F<.>"] = { move_prev_char },
    ["t<.>"] = { move_till_next_char },
    ["T<.>"] = { move_till_prev_char },
    ["G"] = { go_to_line },
    ["%"] = "doc:select-all",

    -- multi cursors and selections
    ["C"] = "doc:create-cursor-next-line",
    [","] = "doc:select-none", -- slighty different then hx
    ["s"] = search_select,
    ["S"] = search_split,
    -- Go To
    ["gh"] = { unselect, "doc:move-to-start-of-line" },
    ["g_"] = { unselect, "doc:move-to-fisrt-line-character" },
    ["gl"] = { unselect, "doc:move-to-end-of-line" },
    ["gg"] = { unselect, "doc:move-to-start-of-doc" },
    ["ge"] = { unselect, "doc:move-to-end-of-doc" },
    ["g:"] = { unselect, "doc:go-to-line" },

    -- match
    ["mm"] = { unselect, "bracket-match:move-to-matching" },
    ["ms"] = { unselect, "bracket-match:select-to-matching" },

    -- macro
    -- TODO implement macro
    -- ["q"] = { function() modal.notify("macro:play") end, "macro:play" },
    -- ["Q"] = { function()
    --   modal.notify("macro:toggle-record")
    -- end, "macro:toggle-record" },
    -- search
    -- FILE operations
    ["<space>f"] = "core:find-project-file",
    ["<space>F"] = "core:open-file",
    ["<space>p"] = "core:change-project-folder",
    ["<space>P"] = "core:open-project-folder",
    ["<space>b"] = "buffer:picker", -- need plugin tab-switcher
    ["<space>c"] = "doc:toggle-line-comments",
    ["C-c"] = "doc:toggle-line-comments",

    -- WINDOWS operations
    ["<f11>"] = "core:toogle-full-screen",
    ["<space>wv"] = { "root:split-right", "root:switch-to-right" },
    ["<space>ws"] = { "root:split-down", "root:switch-to-down" },
    ["<space>wq"] = "root:close-node",
    ["<space>wQ"] = "core:quit",
    ["<space>w<left>"] = "root:switch-to-left",
    ["<space>w<right>"] = "root:switch-to-right",
    ["<space>w<up>"] = "root:switch-to-up",
    ["<space>w<down>"] = "root:switch-to-down",
    ["<space>w+"] = "root:grow",
    ["<space>w-"] = "root:shrink",

    -- LITE
    ["<space>\\"] = "treeview:toggle",
    ["<space>ll"] = "core:open-log",
    ["<space>lL"] = "log:open-as-doc",
    ["<space>lu"] = "core:open-user-module",
    ["<space>lr"] = "core:reload-module",
    ["<space>lR"] = "core:restart",
    ["<space>ls"] = "ui:settings",

    -- HX
    ["<space>?"] = "modal:help",

    -- LSP (Require lintplus and LSP plugins)
    ["<space>k"] = "lsp:show-symbol-info",
    ["<space>r"] = "lsp:rename-symbol",
    ["<space>D"] = "lsp:view-all-diagnostics",
    ["<space>d"] = "lsp:view-document-diagnostics",
    ["<space>S"] = "lsp:find-workspace-symbol",
    ["<space>s"] = "lsp:view-document-symbols",
    -- Go To(LSP)
    ["gd"] = "lsp:goto-definition",
    ["gi"] = "lsp:goto-implementation",
    ["gr"] = "lsp:find-references",
  },
  INS = {
    ["<ESC>"] = modal.go_to_mode(mode.NOR),
  },
  SEL = {
    ["i"] = { go_to_selection_start, modal.go_to_mode(mode.INS) },
    ["v"] = modal.go_to_mode(mode.NOR),
    ["<ESC>"] = modal.go_to_mode(mode.NOR),
  },
}

local sel_movements = {
  ["<left>"] = { "doc:select-to-previous-char", "dialog:previous-entry" },
  ["<right>"] = { "doc:select-to-next-char", "dialog:next-entry" },
  ["<up>"] = { "command:select-previous", "doc:select-to-previous-line" },
  ["<down>"] = { "command:select-next", "doc:select-to-next-line" },
  ["h"] = { "doc:select-to-previous-char" },
  ["l"] = { "doc:select-to-next-char" },
  ["k"] = { "doc:select-to-previous-line" },
  ["j"] = { "doc:select-to-next-line" },
  ["<pageup>"] = { "doc:select-to-previous-page" },
  ["<pagedown>"] = { "doc:select-to-next-page" },

  -- movement + selection
  ["w"] = { "doc:select-to-next-word-end" },
  ["W"] = { "doc:select-to-next-WORD-end" },
  ["e"] = { "doc:select-to-next-word-end" },
  ["E"] = { "doc:select-to-next-WORD-end" },
  ["b"] = { "doc:select-to-previous-word-start" },
  ["B"] = { "doc:select-to-previous-WORD-start" },
  ["f<.>"] = select_next_char,
  ["F<.>"] = select_prev_char,
  ["t<.>"] = select_till_next_char,
  ["T<.>"] = select_till_prev_char,
  [","] = nil
}

config.plugins.modal.keymaps.SEL = concat(config.plugins.modal.keymaps.NOR,
  config.plugins.modal.keymaps.SEL)
config.plugins.modal.keymaps.SEL = concat(config.plugins.modal.keymaps.SEL, sel_movements)

config.plugins.modal.carets.NOR = modal.caret_style.BAR
config.plugins.modal.carets.INS = modal.caret_style.NORMAL
config.plugins.modal.carets.SEL = modal.caret_style.BAR

config.plugins.modal.on_key_callbacks.NOR = modal.on_key_command_only
config.plugins.modal.on_key_callbacks.SEL = modal.on_key_command_only
config.plugins.modal.on_key_callbacks.INS = modal.on_key_passtrought


local helpers = {
  ["<space>"] = {
    { "f",  "open project file picker" },
    { "F",  "open file picker" },
    { "p",  "change project folder" },
    { "P",  "open project folder" },
    { "b",  "open buffer picker" },
    { "s",  "show symbol picker" },
    { "S",  "show project symbol picer" },
    { "d",  "show document diagnostic picker" },
    { "D",  "show project diagnostic picker" },
    { "w",  "window mode" },
    { "k",  "show symbol information" },
    { "r",  "rename symbol" },
    { "c",  "comment line" },
    { "\\", "toggle project tree" },
    { "l",  "lite-xl mode" },
    { "?",  "show keymap" },
  },
  ["<space>w"] = {
    { "q",     "close view" },
    { "Q",     "quit Lite XL" },
    { "v",     "vertical right split" },
    { "s",     "horizontal down split" },
    { "left",  "jump to left split" },
    { "right", "jump to right split" },
    { "up",    "jump to split above" },
    { "down",  "jump to split below" },
    { "+",     "grow view" },
    { "-",     "shrink view" }
  },
  ["<space>l"] = {

    { "l", "open log" },
    { "L", "open log as doc" },
    { "u", "open user module" },
    { "s", "open UI settings" },
    { "r", "reload a module" },
    { "R", "restart lite-xl" },
  },
  ["g"] = {
    { "g", "Goto file start" },
    { "e", "Goto file end" },
    { "h", "Goto line start" },
    { "l", "Goto line end" },
    { "_", "Goto first character of line" },
    { "d", "Goto definition" },
    { "i", "Goto implementation" },
    { "r", "Goto references" },
    { ":", "Goto line" },
  },
  ["m"] = {
    { "m", "Goto matching braket" },
    { "s", "Select to matching brakets" },
  }
}

config.plugins.modal.helpers.NOR = helpers
config.plugins.modal.helpers.SEL = helpers

command.add(nil, {
  ["w"] = function() command.perform "doc:save" end,
  ["wq"] = function()
    command.perform "doc:save"
    command.perform "core:quit"
  end,
  ["q"] = function() command.perform "core:quit" end

})

modal.load_bindings(kb_modal)

return modal_hx
