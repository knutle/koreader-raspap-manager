local Blitbuffer = require("ffi/blitbuffer")
local Button = require("ui/widget/button")
local IconWidget = require("ui/widget/iconwidget")
local UIManager = require("ui/uimanager")

local RaspAPButton = Button:extend{}

function RaspAPButton:init()
    Button.init(self)
    if self.icon_file then
        -- Native Button accepts theme icon names, not plugin file paths.
        self.label_widget:free()
        self.label_widget = IconWidget:new{
            file = self.icon_file, width = self.icon_width, height = self.icon_height,
        }
        self.label_container[1] = self.label_widget
    end
end

function RaspAPButton:setHighlighted(highlighted)
    self.frame.invert = false
    self.frame.background = highlighted and Blitbuffer.COLOR_BLACK or Blitbuffer.COLOR_WHITE
    if self.text then
        self.label_widget.fgcolor = highlighted and Blitbuffer.COLOR_WHITE
            or (self.enabled and Blitbuffer.COLOR_BLACK or Blitbuffer.COLOR_DARK_GRAY)
        if self.label_widget.update then
            self.label_widget.bgcolor = self.frame.background
            self.label_widget:update()
        end
    else
        self.label_widget.invert = highlighted
    end
end

function RaspAPButton:onFocus()
    if self.no_focus then return end
    self.focused = true
    self:setHighlighted(true)
    return true
end

function RaspAPButton:onUnfocus()
    if self.no_focus then return end
    self.focused = false
    self:setHighlighted(false)
    return true
end

function RaspAPButton:_doFeedbackHighlight()
    if not self.frame.dimen then return Button._doFeedbackHighlight(self) end
    self:setHighlighted(true)
    UIManager:widgetRepaint(self.frame, self.frame.dimen.x, self.frame.dimen.y)
    UIManager:setDirty(nil, "fast", self.frame.dimen)
end

function RaspAPButton:_undoFeedbackHighlight(is_translucent)
    if not self.frame.dimen then return Button._undoFeedbackHighlight(self, is_translucent) end
    self:setHighlighted(self.focused == true)
    UIManager:widgetRepaint(self.frame, self.frame.dimen.x, self.frame.dimen.y)
    UIManager:setDirty(is_translucent and self.show_parent or nil,
        (is_translucent or not self.enabled) and "ui" or "fast", self.frame.dimen)
end

return RaspAPButton
