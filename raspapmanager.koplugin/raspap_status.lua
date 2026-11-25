local Client = require("raspap_client")
local Card = require("raspap_card")
local Blitbuffer = require("ffi/blitbuffer")
local Button = require("raspap_button")
local Details = require("raspap_details")
local Device = require("device")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local Icons = require("raspap_icons")
local InputContainer = require("ui/widget/container/inputcontainer")
local NetworkMgr = require("ui/network/manager")
local TextWidget = require("ui/widget/textwidget")
local TitleBar = require("ui/widget/titlebar")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local _ = require("gettext")
local Screen = Device.screen

local REFRESH_SECONDS = 15
local Status = InputContainer:extend{ stop_events_propagation = true }

local function display(value)
    if value == nil or value == "" then return _("Unavailable") end
    return (tostring(value):gsub("[%c]", " "))
end

local function clientName(client)
    if client.hostname and client.hostname ~= "" and client.hostname ~= "*" then
        return display(client.hostname)
    end
    return display(client.ip_address or client.mac_address)
end

function Status:init()
    self.title = self.clients_only and _("RaspAP clients") or _("RaspAP status")
    self.subtitle = self.subtitle or _("Waiting for first update")
    if self.auto_refresh == nil then self.auto_refresh = true end
    self.refresh_task = self.refresh_task or function() self:refresh() end
    self.page = self.page or 1
    self.snapshot = self.snapshot or {}
    self.last_success = self.last_success or {}
    self.section_titles = self.section_titles or { details = _("System / Hotspot"), clients = _("Clients") }
    self.cards = self.cards or { {
        section = self.clients_only and "clients" or "details",
        label = _("Status"), body = _("Loading RaspAP status..."),
    } }
    self:buildLayout()
    self.ges_events.Swipe = {
        GestureRange:new{ ges = "swipe", range = function() return self.dimen end },
    }
    if Device:hasKeys() then
        self.key_events.Close = { { Device.input.group.Back } }
        self.key_events.NextPage = { { Device.input.group.PgFwd } }
        self.key_events.PrevPage = { { Device.input.group.PgBack } }
    end
end

function Status:buildLayout()
    local width, height = Screen:getWidth(), Screen:getHeight()
    local margin, gap = Screen:scaleBySize(8), Screen:scaleBySize(5)
    local content_width = width - 2 * margin
    local columns = content_width >= Screen:scaleBySize(360) and 2 or 1
    self.columns = columns
    local card_width = math.floor((content_width - (columns - 1) * gap) / columns)
    local status_button = Button:new{
        icon = "notice-info", icon_file = Icons.raspap,
        icon_width = Screen:scaleBySize(24), icon_height = Screen:scaleBySize(24),
        width = Screen:scaleBySize(36), padding = Screen:scaleBySize(4),
        radius = Screen:scaleBySize(4),
        callback = function() self:showRefreshStatus() end,
    }
    self.titlebar = TitleBar:new{
        title = self.title,
        subtitle = self.subtitle,
        subtitle_fullwidth = true,
        width = content_width - status_button:getSize().w - gap,
        title_top_padding = 0,
        button_padding = Screen:scaleBySize(4),
        close_callback = function() self:onClose() end,
    }
    local title = HorizontalGroup:new{
        align = "center", allow_mirroring = false,
        status_button, HorizontalSpan:new{ width = gap }, self.titlebar,
    }
    local button_width = math.floor((content_width - gap) / 2)
    local function button(text, callback, size, enabled)
        return Button:new{
            text = text, callback = callback, width = size,
            enabled = enabled ~= false, text_font_size = 16,
            padding = Screen:scaleBySize(4), radius = Screen:scaleBySize(4),
        }
    end
    self.controls = {
        status = status_button,
        refresh = button(_("Refresh now"), function() self:refresh() end, button_width),
        pause = button(self.auto_refresh and _("Pause updates") or _("Resume updates"), function()
            self.auto_refresh = not self.auto_refresh
            self:buildLayout()
            self:scheduleRefresh()
        end, button_width),
    }
    local toolbar = HorizontalGroup:new{
        self.controls.refresh, HorizontalSpan:new{ width = gap }, self.controls.pause,
    }
    local function note(text, bold)
        return TextWidget:new{
            text = text, face = Font:getFace("smallinfofont", bold and 14 or 13),
            bold = bold,
            max_width = content_width, padding = 0,
        }
    end
    local legend = note(_("Info icons open details. Buttons perform actions."))
    local internet = not self.clients_only and note(_("Pi internet connectivity: not exposed by the API"))
    local probe = Card:new{ width = card_width, label = "", body = "" }
    local card_height = probe:getSize().h
    probe:free()
    local heading_probe = note("", true)
    local heading_height = heading_probe:getSize().h
    heading_probe:free()
    local content = VerticalGroup:new{
        align = "left",
        title, VerticalSpan:new{ width = gap },
        toolbar, VerticalSpan:new{ width = gap },
    }
    local footer = VerticalGroup:new{ align = "left", legend }
    if internet then
        table.insert(footer, VerticalSpan:new{ width = gap })
        table.insert(footer, internet)
    end
    local available = height - 2 * margin - title:getSize().h - toolbar:getSize().h
        - 2 * gap - footer:getSize().h
    local rows = {}
    for index, data in ipairs(self.cards) do
        local row = rows[#rows]
        if not row or row.section ~= data.section or #row.indices == columns then
            row = { section = data.section, indices = {} }
            table.insert(rows, row)
        end
        table.insert(row.indices, index)
    end
    local function paginate(budget)
        local pages = { { rows = {}, height = 0 } }
        for _, row in ipairs(rows) do
            local page = pages[#pages]
            local previous = page.rows[#page.rows]
            local heading = not previous or previous.section ~= row.section
            local cost = card_height + gap + (heading and (heading_height + gap) or 0)
            if #page.rows > 0 and page.height + cost > budget then
                page = { rows = {}, height = 0 }
                table.insert(pages, page)
                cost = card_height + heading_height + 2 * gap
            end
            table.insert(page.rows, row)
            page.height = page.height + cost
        end
        return pages
    end
    local pages = paginate(available)
    local navigation
    self.page_label = nil
    if #pages > 1 then
        local nav_width = math.floor((content_width - 2 * gap) / 3)
        self.controls.previous = button(_("Previous"), function() self:onPrevPage() end, nav_width)
        self.controls.next = button(_("Next"), function() self:onNextPage() end, nav_width)
        self.page_label = button("", nil, nav_width, false)
        navigation = HorizontalGroup:new{
            self.controls.previous, HorizontalSpan:new{ width = gap },
            self.page_label, HorizontalSpan:new{ width = gap }, self.controls.next,
        }
        pages = paginate(available - navigation:getSize().h - gap)
    end
    self.page_count = #pages
    self.page = math.max(1, math.min(self.page, self.page_count))
    if navigation then
        self.page_label:setText(string.format(_("%d / %d"), self.page, self.page_count))
        if self.page == 1 then self.controls.previous:disable() end
        if self.page == self.page_count then self.controls.next:disable() end
    end
    self.card_widgets = {}
    self.section_headings = {}
    local previous_section
    for _, data_row in ipairs(pages[self.page].rows) do
        if previous_section ~= data_row.section then
            local heading = note(self.section_titles[data_row.section], true)
            table.insert(self.section_headings, heading)
            table.insert(content, heading)
            table.insert(content, VerticalSpan:new{ width = gap })
            previous_section = data_row.section
        end
        local row = HorizontalGroup:new{ align = "top" }
        for column, index in ipairs(data_row.indices) do
            if column > 1 then table.insert(row, HorizontalSpan:new{ width = gap }) end
            local data = self.cards[index]
            local card = Card:new{
                width = card_width, label = data.label, body = data.body, callback = data.callback,
                icon = data.icon,
            }
            table.insert(self.card_widgets, card)
            table.insert(row, card)
        end
        table.insert(content, row)
        table.insert(content, VerticalSpan:new{ width = gap })
    end
    table.insert(content, footer)
    if navigation then
        table.insert(content, VerticalSpan:new{ width = gap })
        table.insert(content, navigation)
    end
    self.layout_height = content:getSize().h + 2 * margin
    local old = self[1]
    self[1] = FrameContainer:new{
        background = Blitbuffer.COLOR_WHITE, bordersize = 0,
        padding = margin, width = width, height = height, content,
    }
    self.dimen = Geom:new{ x = 0, y = 0, w = width, h = height }
    if old then old:free(true) end
    UIManager:setDirty(self, "ui")
end

function Status:onNextPage()
    self.page = math.min(self.page + 1, self.page_count)
    self:buildLayout()
    return true
end

function Status:onPrevPage()
    self.page = math.max(1, self.page - 1)
    self:buildLayout()
    return true
end

function Status:onSwipe(_arg, gesture)
    if gesture.direction == "west" then return self:onNextPage() end
    if gesture.direction == "east" then return self:onPrevPage() end
end

function Status:onScreenResize()
    self:buildLayout()
end

function Status:onClose()
    UIManager:close(self)
    return true
end

function Status:scheduleRefresh(delay)
    UIManager:unschedule(self.refresh_task)
    if not self.closed and not self.suspended and self.auto_refresh then
        UIManager:scheduleIn(delay or REFRESH_SECONDS, self.refresh_task)
    end
end

function Status:onShow()
    self:scheduleRefresh(0)
end

function Status:onSuspend()
    self.suspended = true
    UIManager:unschedule(self.refresh_task)
end

function Status:onResume()
    self.suspended = false
    self:scheduleRefresh(1)
end

function Status:onCloseWidget()
    self.closed = true
    UIManager:unschedule(self.refresh_task)
    self:free()
    UIManager:setDirty(nil, "ui")
end

function Status:render()
    self.cards = {}
    self.client_summary = _("Clients: unavailable")
    local function info(section, label, body, loaded, icon, details)
        table.insert(self.cards, {
            section = section,
            label = label,
            body = body,
            icon = icon,
            callback = loaded and function()
                UIManager:show(Details:new{
                    title = label, icon = icon, text = details or body,
                })
            end or nil,
        })
    end
    if not self.clients_only then
        local system, ap = self.snapshot.system, self.snapshot.ap
        if system then
            local state = _("Unavailable")
            if system.hostapdStatus == 1 then state = _("Running")
            elseif system.hostapdStatus == 0 then state = _("Stopped") end
            info("details", _("System"), display(system.hostname) .. "\n" .. display(system.uptime)
                .. "\n" .. _("Hotspot: ") .. state, true, Icons.system,
                _("Hostname: ") .. display(system.hostname) .. "\n\n"
                .. _("Uptime: ") .. display(system.uptime) .. "\n\n" .. _("Hotspot: ") .. state)
        else
            info("details", _("System"), _("Not loaded"))
        end
        if ap then
            info("details", _("Hotspot"), _("SSID: ") .. display(ap.ssid) .. "\n"
                .. display(ap.interface) .. "  |  " .. _("Channel: ") .. display(ap.channel), true, Icons.hotspot,
                _("SSID: ") .. display(ap.ssid) .. "\n\n" .. _("Interface: ") .. display(ap.interface)
                .. "\n\n" .. _("Channel: ") .. display(ap.channel))
        else
            info("details", _("Hotspot"), _("Not loaded"))
        end
    end
    local clients = self.snapshot.clients
    if not clients then
        info("clients", _("Clients"), _("Not loaded"))
    else
        self.client_summary = _("Clients") .. "  |  " .. _("Reported: ") .. display(clients.active_clients_amount)
            .. "  |  " .. _("Listed: ") .. #clients.active_clients
        local sorted = {}
        for i, client in ipairs(clients.active_clients) do sorted[i] = client end
        table.sort(sorted, function(a, b)
            local a_name, b_name = clientName(a):lower(), clientName(b):lower()
            if a_name ~= b_name then return a_name < b_name end
            return a.mac_address < b.mac_address
        end)
        if #sorted == 0 then info("clients", _("Clients"), _("No clients returned")) end
        for i = 1, #sorted do
            local client = sorted[i]
            local connection = display(client.connection_type)
            if client.connection_type == "wireless" then connection = _("Wi-Fi")
            elseif client.connection_type == "ethernet" then connection = _("Ethernet") end
            local label = "[" .. connection .. "] " .. clientName(client)
            local details = _("IP: ") .. display(client.ip_address) .. "\n"
                .. _("MAC: ") .. display(client.mac_address)
            info("clients", label, details, true, Icons.client,
                _("Hostname: ") .. display(client.hostname) .. "\n\n"
                .. _("Connection: ") .. connection .. "\n\n"
                .. _("IP: ") .. display(client.ip_address) .. "\n\n"
                .. _("MAC: ") .. display(client.mac_address))
        end
    end
    self.section_titles = { details = _("System / Hotspot"), clients = self.client_summary }
    if self.checked_at then
        self.subtitle = self.health .. " | " .. _("Last attempt: ") .. self.checked_at
    end
    self:buildLayout()
end

function Status:showRefreshStatus()
    local details = { self.subtitle }
    if self.errors and #self.errors > 0 then
        for _, err in ipairs(self.errors) do table.insert(details, err) end
    elseif self.checked_at then
        table.insert(details, _("All API requests succeeded."))
    end
    for i, section in ipairs({ { "system", _("System") }, { "ap", _("Hotspot") }, { "clients", _("Clients") } }) do
        local updated = self.last_success[section[1]]
        if updated then
            table.insert(details, section[2] .. " - " .. _("Last success: ") .. updated)
        end
    end
    UIManager:show(Details:new{
        title = _("RaspAP connection status"), icon = Icons.raspap,
        text = table.concat(details, "\n\n"),
    })
end

function Status:refresh()
    UIManager:unschedule(self.refresh_task)
    if self.closed or self.suspended then return end
    if UIManager:getTopmostVisibleWidget() ~= self then
        self:scheduleRefresh()
        return
    end
    local url = self.settings:readSetting("url") or self.default_url
    local key = self.settings:readSetting("api_key")
    local valid, err = Client.validate(url, key)
    if valid ~= self.cache_url or key ~= self.cache_key then
        self.snapshot, self.last_success = {}, {}
    end
    self.cache_url, self.cache_key = valid, key
    self.errors, self.stale_sections = {}, {}
    local function connectionError(message, transient)
        table.insert(self.errors, message)
        for name in pairs(self.snapshot) do
            if transient then self.stale_sections[name] = true
            else self.snapshot[name] = nil end
        end
    end
    if not valid then
        connectionError(_("Configure the RaspAP connection first.") .. "\n" .. err, false)
    elseif not NetworkMgr:isConnected() then
        connectionError(_("Wi-Fi is disconnected. Reconnect to the Pi's network to resume updates."), true)
    else
        local function fetch(name, endpoint, label)
            local data, request_error, kind = Client.get(valid, key, endpoint)
            if data then
                self.snapshot[name] = data
                self.last_success[name] = os.date("%H:%M:%S")
            else
                table.insert(self.errors, label .. ": " .. request_error)
                if kind == "transient" and self.snapshot[name] then self.stale_sections[name] = true
                else self.snapshot[name] = nil end
            end
        end
        if not self.clients_only then
            fetch("system", "/system", _("System"))
            fetch("ap", "/ap", _("Hotspot"))
        end
        fetch("clients", "/clients", _("Clients"))
    end
    self.health = #self.errors == 0 and _("Online")
        or next(self.stale_sections) and _("Stale")
        or next(self.snapshot) and _("Partial") or _("Unavailable")
    self.checked_at = os.date("%H:%M:%S")
    self:render()
    self:scheduleRefresh()
end

return Status
