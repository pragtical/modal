---Accept the native key sequence syntax used by Pragtical.
---@class plugins.modal.model.pragtical : modal.model
local kb_pragtical = {}

---Use a native Pragtical stroke sequence verbatim.
---@param str string
---@return string strokes
function kb_pragtical.convert(str)
  -- no conversion necessary for the moment
  return str
end

return kb_pragtical
