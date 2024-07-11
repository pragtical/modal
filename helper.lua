-- DISPLAY COMMANDS HELPER

local core = require "core"
local style = require "core.style"
local RootView = require "core.rootview"
local padding = 10
local margin = 10

style["helper"] = {
  ["background"] = { 0, 0, 0, 200 },
  ["text"] = { 255, 255, 255, 220 },
}

local function pos(win_size, width, height)
  local y = win_size.y - margin - padding * 2 - height
  if core.modal.config.helper.alignement == core.modal.align.RIGHT then
    return margin, y
  elseif core.modal.config.helper.alignement == core.modal.align.CENTER then
    return win_size.x / 2 - width / 2 - padding, y
  else
    return win_size.x - margin - padding * 2 - width, y
  end
end

local function spaces(key_len, spacing)
  local res = ''
  for _ = 1, spacing - key_len do
    res = res .. ' '
  end
  return res
end

local rvDraw = RootView.draw
function RootView:draw(...)
  rvDraw(self, ...)
  if core.modal.active_help ~= nil then
    local font = style.code_font
    local lines = {}
    local box_h = 0
    local box_w = 0
    for _, kv in ipairs(core.modal.active_help) do
      local line = kv[1] .. spaces(#kv[1], 8) .. kv[2]
      local line_w = font:get_width(line)
      lines[#lines + 1] = line
      box_h = box_h + font:get_height()

      if line_w > box_w then
        box_w = line_w
      end
    end

    local x, y = pos(self.size, box_w, box_h)
    local w = box_w + padding * 2
    local h = box_h + padding * 2
    core.redraw = true
    local bg = style.helper.background
    local fg = style.helper.text
    renderer.draw_rect(x, y, w, h, bg)
    x = x + padding
    y = y + padding
    for _, line in ipairs(lines) do
      renderer.draw_text(font, line, x, y, fg)
      y = y + font:get_height()
    end
  end
end
