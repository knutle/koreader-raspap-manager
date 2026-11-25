local Button = require("raspap_button")
local Card = require("raspap_card")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local Font = require("ui/font")
local Geom = require("ui/geometry")
local Icons = require("raspap_icons")
local InputContainer = require("ui/widget/container/inputcontainer")
local ScrollTextWidget = require("ui/widget/scrolltextwidget")
local TextBoxWidget = require("ui/widget/textboxwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local _ = require("gettext")
local Screen = Device.screen

local Details = InputContainer:extend{ modal = true, stop_events_propagation = true }

function Details:init()
    local margin, padding, gap = Screen:scaleBySize(14), Screen:scaleBySize(8), Screen:scaleBySize(8)
    local border = Screen:scaleBySize(1)
    self.title = self.title or _("RaspAP manager")
    self.icon = self.icon or Icons.raspap
    local width = Screen:getWidth() - 2 * margin
    local body_width = width - 2 * (padding + border)
    self.close_button = Button:new{
        text = _("Close"), width = body_width,
        text_font_size = 16, padding = Screen:scaleBySize(4), radius = Screen:scaleBySize(4),
        callback = function() self:onClose() end,
    }
    local function panel(body)
        return Card:new{
            width = width, label = self.title, icon = self.icon, show_icon = true,
            icon_invert = self.icon ~= Icons.raspap,
            padding = padding, header_font_size = 18, icon_size = 24, body_widget = body,
        }
    end
    local header_probe = panel(VerticalSpan:new{ width = 0 })
    local header_height = header_probe.header:getSize().h
    header_probe:free()
    local face = Font:getFace("smallinfofont", 16)
    local text_probe = TextBoxWidget:new{
        text = self.text, face = face, width = body_width - Screen:scaleBySize(18),
    }
    local text_height = text_probe:getSize().h
    text_probe:free()
    local budget = Screen:getHeight() - 2 * margin - 2 * border - header_height
        - 2 * padding - gap - self.close_button:getSize().h
    self.scroll = ScrollTextWidget:new{
        text = self.text, face = face, width = body_width, height = math.min(text_height, budget),
        dialog = self, alignment = "left",
    }
    self.panel = panel(VerticalGroup:new{
        align = "left", self.scroll, VerticalSpan:new{ width = gap }, self.close_button,
    })
    self.dimen = Geom:new{ x = 0, y = 0, w = Screen:getWidth(), h = Screen:getHeight() }
    self[1] = CenterContainer:new{ dimen = self.dimen, self.panel }
    if Device:hasKeys() then self.key_events.Close = { { Device.input.group.Back } } end
end

function Details:onShow()
    UIManager:setDirty(self, "ui")
end

function Details:onClose()
    UIManager:close(self)
    return true
end

function Details:onCloseWidget()
    self:free()
    UIManager:setDirty(nil, "ui")
end

function Details:onScreenResize()
    self:free()
    self:init()
    UIManager:setDirty(self, "ui")
end

return Details
