local Blitbuffer = require("ffi/blitbuffer")
local Device = require("device")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local IconWidget = require("ui/widget/iconwidget")
local InputContainer = require("ui/widget/container/inputcontainer")
local LeftContainer = require("ui/widget/container/leftcontainer")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TextWidget = require("ui/widget/textwidget")
local VerticalGroup = require("ui/widget/verticalgroup")
local Screen = Device.screen

local Card = InputContainer:extend{}
local CardFrame = FrameContainer:extend{}

function CardFrame:paintTo(bb, x, y)
    local size = self:getSize()
    local radius = self.radius + self.bordersize
    local header_height = self.header_height + self.bordersize
    bb:paintRoundedRect(x, y, size.w, size.h, Blitbuffer.COLOR_WHITE, radius)
    bb:paintRoundedRect(x, y, size.w, header_height, Blitbuffer.COLOR_BLACK, radius)
    -- Square the header's lower corners without painting over its rounded top corners.
    bb:paintRect(x, y + radius, size.w, header_height - radius, Blitbuffer.COLOR_BLACK)
    FrameContainer.paintTo(self, bb, x, y)
end

function Card:init()
    local border, padding = Screen:scaleBySize(1), self.padding or Screen:scaleBySize(5)
    local text_width = self.width - 2 * (border + padding)
    local icon_size, icon_gap = Screen:scaleBySize(self.icon_size or 20), Screen:scaleBySize(4)
    local has_icon = self.callback or self.show_icon
    local label_width = text_width - (has_icon and (icon_size + icon_gap) or 0)
    self.header_text = TextWidget:new{
        text = self.label,
        face = Font:getFace("smallinfofont", self.header_font_size or 14),
        fgcolor = Blitbuffer.COLOR_WHITE,
        bold = true,
        padding = 0,
        max_width = label_width,
    }
    local header_height = math.max(self.header_text:getSize().h, icon_size)
    local header_content = HorizontalGroup:new{
        allow_mirroring = false,
        LeftContainer:new{
            allow_mirroring = false,
            dimen = { w = label_width, h = header_height },
            self.header_text,
        },
    }
    if has_icon then
        self.info_icon = IconWidget:new{
            icon = not self.icon and "notice-info" or nil, file = self.icon,
            width = icon_size, height = icon_size, invert = self.icon_invert ~= false,
            alpha = self.icon_invert == false,
        }
        table.insert(header_content, HorizontalSpan:new{ width = icon_gap })
        table.insert(header_content, self.info_icon)
    end
    self.header = FrameContainer:new{
        bordersize = 0,
        padding = padding,
        header_content,
    }
    self.body_text = not self.body_widget and TextBoxWidget:new{
        text = self.body,
        face = Font:getFace("smallinfofont", 16),
        fgcolor = Blitbuffer.COLOR_BLACK,
        width = text_width,
        height = Screen:scaleBySize(60),
        height_adjust = true,
        height_overflow_show_ellipsis = true,
        line_height = 0.1,
        alignment = "left",
    } or nil
    self.frame = CardFrame:new{
        color = Blitbuffer.COLOR_BLACK,
        bordersize = border,
        radius = Screen:scaleBySize(6),
        padding = 0,
        header_height = self.header:getSize().h,
        VerticalGroup:new{
            align = "left",
            self.header,
            FrameContainer:new{ bordersize = 0, padding = padding, self.body_widget or self.body_text },
        },
    }
    self[1] = self.frame
    self.dimen = self.frame:getSize()
    if self.callback then
        self.ges_events.TapCard = {
            GestureRange:new{ ges = "tap", range = function() return self.dimen end },
        }
    end
end

function Card:onTapCard()
    if self.callback then self.callback(); return true end
    return false
end

return Card
