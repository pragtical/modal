local core = require "core"
local command = require "core.command"
local common = require "core.common"
local config = require "core.config"
local keymap = require "core.keymap"
local style = require "core.style"
local View = require "core.view"


---Measure one help row in screen pixels.
---@return number
local function row_height()
  return style.code_font:get_height() + style.padding.y
end


---Yield the formatted row followed by its screen rectangle in pixels.
---@alias modal.help_iterator fun():string?, number, number, number, number

---Scrollable tab displaying the active mode's compiled bindings.
---@class modal.keymapview : core.view
---@overload fun(mode?: string, helpers?: modal.help_row[]): modal.keymapview
---@field super core.view
---@field mode string Display name of the mode shown in this tab.
---@field helpers modal.help_row[] Ordered binding and description pairs.
---@field padding integer Width of the key column in bytes.
local KeyMapView = View:extend()



---Create the help tab and measure the width of its key column.
---@param mode? string Display name.
---@param helpers? modal.help_row[]
function KeyMapView:new(mode, helpers)
  KeyMapView.super.new(self)
  self.helpers = helpers
  self.padding = 1
  if self.helpers == nil then
    self.helpers = {}
  end
  for _, k in ipairs(self.helpers) do
    if #k[1] + 1 > self.padding then
      self.padding = #k[1] + 1
    end
  end
  self.mode = mode
  if self.mode == nil then
    self.mode = ""
  end
  self.scrollable = true
end

---Get the tab title for the displayed mode.
---@return string
function KeyMapView:get_name()
  return "Keymap " .. self.mode
end

---Right-pad a key sequence to the common key-column width.
---@param str string
---@param pad integer
---@return string
local function spaced(str, pad)
  local res = str
  if #str < pad then
    for _ = 1, pad - #str do
      res = res .. ' '
    end
  end
  return res
end

---Iterate formatted help rows and their on-screen rectangles.
---@return modal.help_iterator
function KeyMapView:each_item()
  local x, y = self:get_content_offset()
  y = y + style.padding.y
  local h = row_height()
  return coroutine.wrap(function()
    for _, v in ipairs(self.helpers) do
      local item = spaced(v[1], self.padding) .. ": " .. v[2]
      coroutine.yield(item, x, y, self.size.x, h)
      y = y + h
    end
  end)
end

---Get the scrollable content height, honoring the host's scroll-past-end
---setting.
---@return number pixels
function KeyMapView:get_scrollable_size()
  local count = #self.helpers
  if count == 0 then return 0 end
  if config.scroll_past_end then
    return style.padding.y + (count - 1) * row_height() + self.size.y
  end
  return 2 * style.padding.y + count * row_height()
end

---Handle scrollbar clicks and Ctrl-click to copy a binding to the clipboard.
---@param button string
---@param px number
---@param py number
---@param clicks integer
---@return boolean handled
function KeyMapView:on_mouse_pressed(button, px, py, clicks)
  if KeyMapView.super.on_mouse_pressed(self, button, px, py, clicks) then
    return true
  end

  local selected
  for item, x, y, w, h in self:each_item() do
    if px >= x and py >= y and px < x + w and py < y + h then
      selected = item
      break
    end
  end

  if selected then
    if keymap.modkeys["ctrl"] then
      system.set_clipboard(selected)
      core.status_view:show_message(
        "i", style.text, "Copied binding to clipboard.")
    end
  end

  return true
end

---Draw visible keymap rows and the native scrollbar.
function KeyMapView:draw()
  self:draw_background(style.background)

  for item, x, y, w, h in self:each_item() do
    if y + h >= self.position.y and y <= self.position.y + self.size.y then
      core.push_clip_rect(x, y, w, h)
      x = x + style.padding.x


      w = w - (x - self:get_content_offset())

      common.draw_text(style.code_font, style.text, item, "left", x, y, w, h)
      core.pop_clip_rect()
    end
  end
  KeyMapView.super.draw_scrollbar(self)
end

---Scroll the help tab vertically by a signed number of rows.
---@param view modal.keymapview
---@param rows integer
local function scroll_rows(view, rows)
  view.scroll.to.y = view.scroll.to.y + rows * row_height()
  view:clamp_scroll_position()
end

command.add(KeyMapView, {
  ["modal:scroll-help-up"] = function(view) scroll_rows(view, -1) end,
  ["modal:scroll-help-down"] = function(view) scroll_rows(view, 1) end,
})

keymap.add {
  ["up"] = "modal:scroll-help-up",
  ["down"] = "modal:scroll-help-down",
}

return KeyMapView
