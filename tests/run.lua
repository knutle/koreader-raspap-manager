package.path = "./raspapmanager.koplugin/?.lua;" .. package.path

local JSON = require("dkjson")
local passed, failed = 0, 0
local temp = os.tmpname()
local state, settings, shown, closed, now, request_handler
local http, https = { TIMEOUT = 41 }, { TIMEOUT = 42 }
local ssl = {}
local socketutil = { block_timeout = 41, total_timeout = 99, SINK_TIMEOUT_CODE = "sink timeout" }
function socketutil:set_timeout(block, total)
    self.block_timeout, self.total_timeout = block, total
    http.TIMEOUT, https.TIMEOUT = block, block
end
function socketutil.table_sink(chunks)
    return function(chunk)
        if chunk then table.insert(chunks, chunk) end
        return 1
    end
end
http.request = function(request) return request_handler(request) end
https.request = http.request
package.loaded["socket.http"] = http
package.loaded["ssl.https"] = https
package.loaded.ssl = ssl
package.loaded.socketutil = socketutil
package.loaded.socket = { gettime = function() return now end }
package.loaded.gettext = function(text) return text end

local function equal(actual, expected)
    assert(actual == expected, string.format("expected %s, got %s", tostring(expected), tostring(actual)))
end
local function contains(text, fragment)
    assert(type(text) == "string" and text:find(fragment, 1, true), "missing text: " .. fragment)
end
local function missing(text, fragment)
    assert(not text:find(fragment, 1, true), "sensitive/unexpected text was exposed")
end
local responses = {
    ["/system"] = '{"hostname":"test-pi","uptime":"up 1 hour","hostapdStatus":1}',
    ["/ap"] = '{"ssid":"Test AP","interface":"wlan0","channel":"6","wpa_passphrase":"fixture-hotspot-secret"}',
    ["/clients"] = '{"active_clients_amount":1,"active_clients":[{"hostname":"kindle","ip_address":"10.3.141.2","mac_address":"00:00:00:00:00:01","connection_type":"wireless"}]}',
    ["/networking"] = '{"interfaces":{"wlan0":{"IP_address":"10.3.141.1","Netmask":null,"MAC_address":"00:00:00:00:00:02"}}}',
}
local key = "fixture-api-key"
local base = "http://10.3.141.1:8081"
local function respond(body, code)
    return function(request)
        local ok, err = request.sink(body)
        if not ok then return nil, err end
        request.sink(nil)
        return 1, code or 200
    end
end

local widget = {}
function widget:new(options) return options end
local container = {}
function container:extend(options)
    options.__index = options
    return setmetatable(options, { __index = self })
end
function container:new(options)
    local instance = setmetatable(options or {}, self)
    if instance._init then instance:_init() end
    if instance.init then instance:init() end
    return instance
end
function container:free()
    self.freed = true
    for _, child in ipairs(self) do
        if child.free then child:free() end
    end
end
function container:getSize()
    return self.dimen or self[1]:getSize()
end
local dialog = {}
function dialog:new(options)
    function options:getFields() return state.fields end
    function options:onShowKeyboard() state.keyboard = true end
    state.dialog = options
    return options
end
package.loaded["ui/widget/container/widgetcontainer"] = container
package.loaded["ui/widget/infomessage"] = widget
package.loaded["ui/widget/keyvaluepage"] = widget
package.loaded["ui/widget/multiinputdialog"] = dialog
local screen = {}
function screen:getWidth() return state.screen_width end
function screen:getHeight() return state.screen_height end
function screen:scaleBySize(value) return math.floor(value * state.screen_scale + 0.5) end
package.loaded.device = { screen = screen, hasKeys = function() return false end }
package.loaded["ui/font"] = {
    getFace = function(_, _name, size) return { size = size * state.screen_scale } end,
}
package.loaded["ffi/blitbuffer"] = { COLOR_BLACK = "black", COLOR_WHITE = "white", COLOR_DARK_GRAY = "gray" }
package.loaded["ui/geometry"] = { new = function(_, value) return value end }
package.loaded["ui/gesturerange"] = widget
local input = container:extend{}
function input:_init() self.ges_events, self.key_events = {}, {} end
package.loaded["ui/widget/container/inputcontainer"] = input
local function visual(kind)
    local class = container:extend{ kind = kind }
    function class:getSize()
        if kind == "text" then
            return {
                w = math.min(self.max_width or math.huge, #self.text * self.face.size * 0.55),
                h = self.face.size * 1.25,
            }
        elseif kind == "textbox" then
            local line = self.face.size * (1 + (self.line_height or 0.3))
            if self.height then return { w = self.width, h = math.floor(self.height / line) * line } end
            local lines = 0
            for text in (self.text .. "\n"):gmatch("(.-)\n") do
                lines = lines + math.max(1, math.ceil(#text * self.face.size * 0.55 / self.width))
            end
            return { w = self.width, h = lines * line }
        elseif kind == "scrolltext" then
            return { w = self.width, h = self.height }
        elseif kind == "button" then
            return self.frame:getSize()
        elseif kind == "title" then
            return { w = self.width, h = (20 + 13) * state.screen_scale * 1.25 + 2 * self.button_padding }
        elseif kind == "horizontal-span" then
            return { w = self.width, h = 0 }
        elseif kind == "vertical-span" then
            return { w = 0, h = self.width }
        elseif kind == "left" or kind == "center" then
            return self.dimen
        elseif kind == "icon" then
            return { w = self.width, h = self.height }
        elseif kind == "frame" then
            local size = self[1]:getSize()
            local pad = 2 * (self.padding or 0) + 2 * (self.bordersize or 0)
            return { w = size.w + pad, h = size.h + pad }
        end
        if self._size then return self._size end
        local width, height = 0, 0
        for _, child in ipairs(self) do
            local size = child:getSize()
            if kind == "horizontal" then
                width, height = width + size.w, math.max(height, size.h)
            else
                width, height = math.max(width, size.w), height + size.h
            end
        end
        self._size = { w = width, h = height }
        return self._size
    end
    function class:setText(text) self.text = text end
    function class:disable() self.enabled = false end
    function class:paintTo(bb, x, y)
        self.painted_at = { x = x, y = y }
        local size = self:getSize()
        self.dimen = { x = x, y = y, w = size.w, h = size.h }
        if kind == "frame" and self.background and bb.paintRoundedRect then
            bb:paintRoundedRect(x, y, size.w, size.h, self.background,
                self.radius and self.radius + (self.bordersize or 0) or nil)
        end
    end
    return class
end
for name, kind in pairs({
    ["ui/widget/textwidget"] = "text",
    ["ui/widget/textboxwidget"] = "textbox",
    ["ui/widget/scrolltextwidget"] = "scrolltext",
    ["ui/widget/button"] = "button",
    ["ui/widget/titlebar"] = "title",
    ["ui/widget/iconwidget"] = "icon",
    ["ui/widget/horizontalspan"] = "horizontal-span",
    ["ui/widget/verticalspan"] = "vertical-span",
    ["ui/widget/horizontalgroup"] = "horizontal",
    ["ui/widget/verticalgroup"] = "vertical",
    ["ui/widget/container/framecontainer"] = "frame",
    ["ui/widget/container/leftcontainer"] = "left",
    ["ui/widget/container/centercontainer"] = "center",
}) do
    package.loaded[name] = visual(kind)
end
local NativeButton = package.loaded["ui/widget/button"]
function NativeButton:init()
    if self.enabled == nil then self.enabled = true end
    self.bordersize = self.bordersize or screen:scaleBySize(1)
    if self.text then
        self.label_widget = package.loaded["ui/widget/textwidget"]:new{
            text = self.text, face = package.loaded["ui/font"]:getFace("cfont", self.text_font_size),
            fgcolor = self.enabled and "black" or "gray",
        }
    else
        self.label_widget = package.loaded["ui/widget/iconwidget"]:new{
            icon = self.icon, width = self.icon_width, height = self.icon_height,
        }
    end
    local pad = 2 * ((self.padding or 0) + self.bordersize)
    self.label_container = package.loaded["ui/widget/container/centercontainer"]:new{
        dimen = { w = self.width - pad, h = self.label_widget:getSize().h }, self.label_widget,
    }
    self.frame = package.loaded["ui/widget/container/framecontainer"]:new{
        padding = self.padding, bordersize = self.bordersize, radius = self.radius,
        background = "white", color = "black", self.label_container,
    }
    self[1] = self.frame
end
package.loaded["ui/uimanager"] = {
    show = function(_, value)
        table.insert(shown, value)
        table.insert(state.stack, value)
        if value.onShow then value:onShow() end
    end,
    close = function(_, value)
        table.insert(closed, value)
        if value.onCloseWidget then value:onCloseWidget() end
        for i = #state.stack, 1, -1 do
            if state.stack[i] == value then table.remove(state.stack, i) end
        end
    end,
    scheduleIn = function(_, delay, callback) state.jobs[callback] = delay end,
    nextTick = function(_, callback) state.jobs[callback] = 0 end,
    unschedule = function(_, callback) state.jobs[callback] = nil end,
    getTopmostVisibleWidget = function() return state.stack[#state.stack] end,
    isWidgetShown = function(_, value)
        for i = 1, #state.stack do
            if state.stack[i] == value then return true end
        end
        return false
    end,
    setDirty = function() end,
    widgetRepaint = function(_, value, x, y)
        state.repainted = value
        if state.canvas then value:paintTo(state.canvas, x, y) end
    end,
}
package.loaded["ui/network/manager"] = {
    runWhenConnected = function(_, callback) state.connected = state.connected + 1; callback() end,
    runWhenOnline = function() error("Internet connectivity must not be required") end,
    isConnected = function() return state.is_connected end,
}
package.loaded.datastorage = { getSettingsDir = function() return "." end }
package.loaded.luasettings = {
    open = function()
        return settings
    end,
}

local Client = require("raspap_client")
local function loadManager(startup)
    local original_getenv = os.getenv
    os.getenv = function(name)
        if name == "RASPAP_STATUS_ON_START" then return startup end
        return original_getenv(name)
    end
    local ok, class = pcall(dofile, "raspapmanager.koplugin/main.lua")
    os.getenv = original_getenv
    assert(ok, class)
    return class
end
local Manager = loadManager()
local function reset()
    os.remove(temp)
    os.remove(temp .. ".old")
    state, shown, closed, now = {
        connected = 0, calls = 0, jobs = {}, stack = {}, is_connected = true,
        screen_width = 1072, screen_height = 1448, screen_scale = 300 / 167,
    }, {}, {}, 0
    http.PROXY = nil
    http.TIMEOUT, https.TIMEOUT = 41, 42
    socketutil.block_timeout, socketutil.total_timeout = 41, 99
    ssl.checkhostname = function() end
    ssl.get_system_ca = function() return "fixture-ca.pem" end
    request_handler = function(request)
        state.calls = state.calls + 1
        state.last_request = request
        local endpoint = request.url:match("(/[^/]+)$")
        return respond(assert(responses[endpoint]))(request)
    end
    settings = { file = temp, data = { url = base, api_key = key } }
    function settings:readSetting(name) return self.data[name] end
    function settings:saveSetting(name, value) self.data[name] = value end
    function settings:delSetting(name) self.data[name] = nil end
    function settings:flush()
        if state.flush_throws then error(key) end
        if state.flush_fails then return end
        local file = assert(io.open(self.file, "w"))
        file:write("return {")
        for name, value in pairs(self.data) do
            file:write(string.format("[%q]=%q,", name, value))
        end
        file:write("}")
        file:close()
    end
end
local function test(name, callback)
    reset()
    local ok, err = pcall(callback)
    if ok then
        passed = passed + 1
        print("PASS " .. name)
    else
        failed = failed + 1
        print("FAIL " .. name .. ": " .. tostring(err))
    end
end
local function manager(class)
    return (class or Manager):new{ ui = { menu = { registerToMainMenu = function() state.registered = true end } } }
end
local function rows(page)
    local text = {}
    if page.cards then
        table.insert(text, page.client_summary or "")
        for _, card in ipairs(page.cards) do table.insert(text, card.label .. ": " .. card.body) end
        if not page.clients_only then table.insert(text, "Pi internet connectivity: not exposed by the API") end
    else
        for _, row in ipairs(page.kv_pairs) do table.insert(text, row[1] .. ": " .. row[2]) end
    end
    return table.concat(text, "\n")
end
local function runScheduled(callback)
    assert(state.jobs[callback] ~= nil, "callback is not scheduled")
    state.jobs[callback] = nil
    callback()
end
local function openStatus(plugin, kind)
    plugin:showStatus(kind or "summary")
    local page = plugin.status_page
    equal(state.jobs[page.refresh_task], 0)
    runScheduled(page.refresh_task)
    return page
end
local function getError(endpoint)
    local data, err = Client.get(base, key, endpoint or "/system")
    equal(data, nil)
    assert(err)
    missing(err, key)
    missing(err, "fixture-hotspot-secret")
    return err
end
local function restored()
    equal(socketutil.block_timeout, 41)
    equal(socketutil.total_timeout, 99)
    equal(http.TIMEOUT, 41)
    equal(https.TIMEOUT, 42)
end

test("validates and normalizes connection settings", function()
    equal(Client.validate(base .. "///", key), base)
    equal(Client.validate("https://pi.example:443/api/", key), "https://pi.example:443/api")
    for _, url in ipairs({
        "ftp://pi", "http://user:pass@pi", "http://pi?key=x", "http://pi#x",
        "http://pi:0", "http://pi:65536", "http://pi:abc", "http://pi\r\nx",
        "http://pi\\evil", "http://pi/%0a", "http://-pi", "http://pi..local",
        "http://pi_name", "http://[::1]", "http://",
    }) do
        local valid, err = Client.validate(url, key)
        equal(valid, nil)
        assert(err)
    end
    for _, invalid in ipairs({ "", "a\r\nb", "a b", "a\0b", "a\tb" }) do
        equal(Client.validate(base, invalid), nil)
    end
    equal(Client.validate(base, nil), nil)
end)

test("uses GET, access_token, final URL and no redirects", function()
    local data = assert(Client.get(base .. "/", key, "/system"))
    equal(data.hostname, "test-pi")
    equal(state.last_request.url, base .. "/system")
    equal(state.last_request.method, "GET")
    equal(state.last_request.headers.access_token, key)
    equal(state.last_request.redirect, false)
    restored()
end)

test("restricts endpoints and rejects proxies before sending credentials", function()
    contains(getError("/system?x"), "Unsupported")
    equal(state.calls, 0)
    http.PROXY = "http://proxy"
    contains(getError(), "proxy")
    equal(state.calls, 0)
end)

test("requires HTTPS verification support and a CA bundle", function()
    ssl.checkhostname = nil
    local data, err = Client.get("https://pi.example", key, "/system")
    equal(data, nil)
    contains(err, "newer KOReader")
    equal(state.calls, 0)
    ssl.checkhostname = function() end
    ssl.get_system_ca = function() return nil end
    data, err = Client.get("https://pi.example", key, "/system")
    equal(data, nil)
    contains(err, "CA bundle")
    equal(state.calls, 0)
end)

test("explicitly verifies HTTPS peers without weakening hostname checks", function()
    assert(Client.get("https://pi.example/api", key, "/system"))
    equal(state.last_request.verify, "peer")
    equal(state.last_request.cafile, "fixture-ca.pem")
    equal(state.last_request.url, "https://pi.example/api/system")
    equal(state.last_request.redirect, false)
    restored()
end)

test("strips hotspot credentials and handles null optional fields", function()
    local ap = assert(Client.get(base, key, "/ap"))
    equal(ap.wpa_passphrase, nil)
    local network = assert(Client.get(base, key, "/networking"))
    equal(network.interfaces.wlan0.Netmask, nil)
    request_handler = respond('{"hostname":"pi","uptime":null,"hostapdStatus":null}')
    local system = assert(Client.get(base, key, "/system"))
    equal(system.uptime, nil)
    equal(system.hostapdStatus, nil)
end)

test("preserves stopped status and a genuine empty client list", function()
    request_handler = respond('{"hostname":"pi","hostapdStatus":0}')
    equal(assert(Client.get(base, key, "/system")).hostapdStatus, 0)
    request_handler = respond('{"active_clients_amount":0,"active_clients":[]}')
    local clients = assert(Client.get(base, key, "/clients"))
    equal(clients.active_clients_amount, 0)
    equal(#clients.active_clients, 0)
end)

test("rejects malformed, trailing and incompatible payloads", function()
    for _, body in ipairs({ "", "{bad", responses["/system"] .. " trailing" }) do
        request_handler = respond(body)
        contains(getError(), "JSON")
    end
    for _, body in ipairs({ "null", "[]", "{}", '{"hostname":false}' }) do
        request_handler = respond(body)
        contains(getError(), "format")
    end
    for endpoint, body in pairs({
        ["/ap"] = '{"ssid":"a"}',
        ["/clients"] = '{"active_clients":{}}',
        ["/networking"] = '{"interfaces":[]}',
    }) do
        request_handler = respond(body)
        contains(getError(endpoint), "format")
    end
    request_handler = respond('{"active_clients":[null]}')
    contains(getError("/clients"), "format")
end)

test("does not substitute zero for an absent or invalid count", function()
    for _, count_json in ipairs({ "null", "-1", "1.5", '"3"' }) do
        request_handler = respond('{"active_clients_amount":' .. count_json .. ',"active_clients":[]}')
        equal(assert(Client.get(base, key, "/clients")).active_clients_amount, nil)
    end
end)

test("classifies transient HTTP errors without revealing response bodies", function()
    for _, code in ipairs({ 401, 403, 404, 408, 429, 500, 503, 599, 302 }) do
        request_handler = respond(key .. " fixture-hotspot-secret", code)
        local err = getError()
        contains(err, (code == 401 or code == 403) and "Authentication" or tostring(code))
        local _, _, kind = Client.get(base, key, "/system")
        equal(kind, (code == 408 or code == 429 or code >= 500) and "transient" or nil)
        restored()
    end
end)

test("restores shared timeouts after transport failures and exceptions", function()
    for _, mode in ipairs({ "timeout", "closed", "exception" }) do
        request_handler = function()
            equal(http.TIMEOUT, 3)
            equal(socketutil.total_timeout, 8)
            if mode == "exception" then error(key) end
            return nil, mode
        end
        local err = getError()
        contains(err, mode == "timeout" and "timed out" or "Cannot reach")
        restored()
    end
end)

test("enforces exact response-size and elapsed transfer limits", function()
    local minimal = '{"hostname":"pi"}'
    request_handler = respond(minimal .. string.rep(" ", 256 * 1024 - #minimal))
    assert(Client.get(base, key, "/system"))
    request_handler = respond(minimal .. string.rep(" ", 256 * 1024 + 1 - #minimal))
    contains(getError(), "256 KiB")
    restored()
    request_handler = function(request)
        now = 8
        assert(request.sink(minimal))
        return 1, 200
    end
    assert(Client.get(base, key, "/system"))
    request_handler = function(request)
        assert(request.sink(minimal))
        now = now + 9
        local ok, err = request.sink(" ")
        equal(ok, nil)
        return nil, err
    end
    contains(getError(), "timed out")
    restored()
    request_handler = function(request)
        now = now + 9
        local ok, err = request.sink(minimal)
        equal(ok, nil)
        return nil, err
    end
    contains(getError(), "timed out")
    restored()
end)

test("registers tools menu without making startup requests", function()
    local plugin = manager()
    equal(state.registered, true)
    equal(state.calls, 0)
    local menu = {}
    plugin:addToMainMenu(menu)
    equal(menu.raspapmanager.sorting_hint, "more_tools")
    equal(#menu.raspapmanager.sub_item_table, 7)
    menu.raspapmanager.sub_item_table[4].callback()
    contains(shown[#shown].text, "API reachable: test-pi")
    equal(shown[#shown].icon, require("raspap_icons").system)
    equal(shown[#shown].title, "Connection test")
    assert(shown[#shown].panel)
    equal(state.connected, 1)
end)

test("saves settings, masks key and warns about plaintext storage", function()
    local plugin = manager()
    plugin:configure()
    equal(state.dialog.fields[2].text_type, "password")
    contains(shown[#shown].text, "unencrypted")
    state.fields = { "http://new-pi:8081/", "fixture-new-key" }
    state.dialog.buttons[1][2].callback()
    local saved = assert(dofile(temp))
    equal(saved.url, "http://new-pi:8081")
    equal(saved.api_key, "fixture-new-key")
    settings.data = saved
    manager():testConnection()
    equal(state.last_request.headers.access_token, "fixture-new-key")
end)

test("rejects invalid dialog settings and reports failed persistence", function()
    local plugin = manager()
    plugin:configure()
    state.fields = { base, "bad\nkey" }
    state.dialog.buttons[1][2].callback()
    equal(settings:readSetting("api_key"), key)
    equal(#closed, 0)
    state.fields = { base, key }
    for _, mode in ipairs({ "flush_fails", "flush_throws" }) do
        state[mode] = true
        state.dialog.buttons[1][2].callback()
        contains(shown[#shown].text, "Could not save")
        missing(shown[#shown].text, key)
        equal(#closed, 0)
        state[mode] = nil
    end
end)

test("clears active key and backup and blocks unconfigured requests", function()
    settings:flush()
    local backup = assert(io.open(temp .. ".old", "w"))
    backup:write("fixture old credential")
    backup:close()
    local plugin = manager()
    plugin:clearKey()
    equal(assert(dofile(temp)).api_key, nil)
    equal(io.open(temp .. ".old"), nil)
    plugin:testConnection()
    equal(state.calls, 0)
    contains(shown[#shown].text, "Configure")
end)

test("warns when a settings backup cannot be removed", function()
    local original_remove = os.remove
    os.remove = function(path)
        equal(path, temp .. ".old")
        return nil, "fixture permission failure", 13
    end
    local ok, err = pcall(function() manager():clearKey() end)
    os.remove = original_remove
    assert(ok, err)
    equal(assert(dofile(temp)).api_key, nil)
    contains(shown[#shown].text, "backup could not be removed")
    missing(shown[#shown].text, "Saved API key cleared.")
end)

test("shows live LAN status, omits passwords and refreshes the same page", function()
    local plugin = manager()
    local page = openStatus(plugin)
    local text = rows(page)
    contains(text, "Hotspot: Running")
    contains(text, "SSID: Test AP")
    contains(text, "Reported: 1")
    contains(text, "not exposed by the API")
    contains(text, "[Wi-Fi] kindle: IP: 10.3.141.2\nMAC: 00:00:00:00:00:01")
    missing(text, "fixture-hotspot-secret")
    equal(state.connected, 1)
    equal(page.columns, 2)
    equal(page.page_count, 1)
    equal(state.jobs[page.refresh_task], 15)
    local old_layout = page[1]
    page.controls.refresh.callback()
    equal(#closed, 0)
    equal(#shown, 1)
    equal(page.page, 1)
    equal(old_layout.freed, true)
    equal(state.calls, 6)
    contains(page.subtitle, "Last attempt:")
end)

test("reports initial partial errors in overall status, not in cards", function()
    local normal = request_handler
    request_handler = function(request)
        if request.url:match("/system$") then return nil, "closed" end
        return normal(request)
    end
    local page = openStatus(manager())
    local text = rows(page)
    contains(text, "System: Not loaded")
    contains(text, "SSID: Test AP")
    missing(text, "Stopped")
    missing(text, "Reported: 0")
    contains(page.subtitle, "Partial | Last attempt:")
    page:showRefreshStatus()
    contains(shown[#shown].text, "System: Cannot reach")
    missing(text, "Cannot reach")
end)

test("renders clients and interfaces and distinguishes empty from failed", function()
    local plugin = manager()
    local page = openStatus(plugin, "clients")
    contains(rows(page), "IP: 10.3.141.2")
    plugin:showStatus("networking")
    local text = rows(shown[#shown])
    contains(text, "Interface: wlan0")
    contains(text, "Netmask: Unavailable")
    request_handler = respond('{"active_clients_amount":0,"active_clients":[]}')
    page = openStatus(plugin, "clients")
    contains(rows(page), "No clients returned")
    request_handler = function() return nil, "closed" end
    runScheduled(page.refresh_task)
    text = rows(page)
    contains(text, "No clients returned")
    contains(page.subtitle, "Stale | Last attempt:")
    missing(text, "Cannot reach")
end)

test("sorts client cards and uses an address when hostname is missing", function()
    request_handler = respond(JSON.encode{
        active_clients_amount = 3,
        active_clients = {
            { hostname = "Zulu", mac_address = "03", ip_address = "10.0.0.3", connection_type = "ethernet" },
            { hostname = "*", mac_address = "01", ip_address = "10.0.0.1" },
            { hostname = "alpha\nname", mac_address = "02", ip_address = "10.0.0.2", connection_type = "wireless" },
        },
    })
    local page = openStatus(manager(), "clients")
    contains(page.cards[1].body, "10.0.0.1")
    equal(page.cards[1].label, "[Unavailable] 10.0.0.1")
    equal(page.cards[2].label, "[Wi-Fi] alpha name")
    equal(page.cards[3].label, "[Ethernet] Zulu")
    equal(select(2, page.cards[2].body:gsub("\n", "")), 1)
    page.card_widgets[3]:onTapCard()
    contains(shown[#shown].text, "MAC: 03")
end)

test("timer retains stale clients on transient errors and clears the indicator on recovery", function()
    local page = openStatus(manager())
    local normal = request_handler
    request_handler = function(request)
        if request.url:match("/clients$") then return nil, "closed" end
        return normal(request)
    end
    local previous_clients = page.snapshot.clients
    local previous_success = page.last_success.clients
    runScheduled(page.refresh_task)
    equal(page.snapshot.clients, previous_clients)
    equal(page.last_success.clients, previous_success)
    contains(rows(page), "kindle")
    contains(page.subtitle, "Stale | Last attempt:")
    equal(page.stale_sections.clients, true)
    equal(state.jobs[page.refresh_task], 15)
    request_handler = normal
    runScheduled(page.refresh_task)
    contains(rows(page), "kindle")
    contains(page.subtitle, "Online | Last attempt:")
    equal(next(page.stale_sections), nil)
    equal(#shown, 1)
end)

test("retains each successful endpoint independently during transient server errors", function()
    local page = openStatus(manager())
    local previous_system, previous_ap = page.snapshot.system, page.snapshot.ap
    local normal = request_handler
    request_handler = function(request)
        if request.url:match("/system$") then return respond("", 503)(request) end
        if request.url:match("/ap$") then return nil, "timeout" end
        return respond('{"active_clients_amount":0,"active_clients":[]}')(request)
    end
    runScheduled(page.refresh_task)
    equal(page.snapshot.system, previous_system)
    equal(page.snapshot.ap, previous_ap)
    equal(#page.snapshot.clients.active_clients, 0)
    contains(rows(page), "No clients returned")
    missing(rows(page), "kindle")
    equal(page.health, "Stale")
    equal(page.stale_sections.system, true)
    equal(page.stale_sections.ap, true)
    equal(page.stale_sections.clients, nil)
    page:showRefreshStatus()
    contains(shown[#shown].text, "System: RaspAP returned HTTP 503")
    contains(shown[#shown].text, "Last success:")
    missing(shown[#shown].text, key)
    package.loaded["ui/uimanager"]:close(shown[#shown])
    request_handler = normal
    runScheduled(page.refresh_task)
    equal(page.health, "Online")
    contains(rows(page), "kindle")
end)

test("does not display errors as cards when there is no previous successful data", function()
    request_handler = function() return nil, "closed" end
    local page = openStatus(manager())
    equal(page.health, "Unavailable")
    equal(page.snapshot.clients, nil)
    equal(page.client_summary, "Clients: unavailable")
    contains(rows(page), "Not loaded")
    missing(rows(page), "No clients returned")
    missing(rows(page), "Cannot reach")
    for _, card in ipairs(page.card_widgets) do equal(card.info_icon, nil) end
    contains(page.subtitle, "Unavailable | Last attempt:")
    page:showRefreshStatus()
    contains(shown[#shown].text, "Cannot reach")
end)

test("clears retained endpoint data for authentication or invalid response failures", function()
    local page = openStatus(manager(), "clients")
    for _, failure in ipairs({ respond("", 403), respond("{invalid"), respond('{"active_clients":{}}') }) do
        request_handler = respond(responses["/clients"])
        runScheduled(page.refresh_task)
        contains(rows(page), "kindle")
        request_handler = failure
        runScheduled(page.refresh_task)
        equal(page.snapshot.clients, nil)
        equal(page.health, "Unavailable")
        missing(rows(page), "kindle")
        contains(rows(page), "Not loaded")
    end
end)

test("does not reuse cached information for a changed server or API key", function()
    local page = openStatus(manager())
    request_handler = function() return nil, "closed" end
    settings:saveSetting("url", "http://different-pi:8081")
    runScheduled(page.refresh_task)
    equal(next(page.snapshot), nil)
    equal(next(page.last_success), nil)
    equal(page.health, "Unavailable")
    missing(rows(page), "test-pi")
    request_handler = respond(responses["/clients"])
    settings:saveSetting("url", base)
    local clients_page = openStatus(manager(), "clients")
    contains(rows(clients_page), "kindle")
    settings:saveSetting("api_key", "fixture-rotated-key")
    request_handler = function() return nil, "closed" end
    runScheduled(clients_page.refresh_task)
    equal(next(clients_page.snapshot), nil)
    missing(rows(clients_page), "kindle")
end)

test("does not fetch behind a dialog or while suspended, and cleans up on close", function()
    local ui = package.loaded["ui/uimanager"]
    local page = openStatus(manager(), "clients")
    local cover = { text = "fixture dialog" }
    ui:show(cover)
    runScheduled(page.refresh_task)
    equal(state.calls, 1)
    equal(state.jobs[page.refresh_task], 15)
    ui:close(cover)
    runScheduled(page.refresh_task)
    equal(state.calls, 2)
    page:onSuspend()
    equal(state.jobs[page.refresh_task], nil)
    page.refresh_task()
    equal(state.calls, 2)
    page:onResume()
    equal(state.jobs[page.refresh_task], 1)
    runScheduled(page.refresh_task)
    equal(state.calls, 3)
    page:onClose()
    equal(state.jobs[page.refresh_task], nil)
    page.refresh_task()
    page:onResume()
    equal(state.calls, 3)
    equal(state.jobs[page.refresh_task], nil)
end)

test("supports paused auto-refresh with a working manual refresh", function()
    local page = openStatus(manager(), "clients")
    page.controls.pause.callback()
    equal(state.jobs[page.refresh_task], nil)
    equal(page.controls.pause.text, "Resume updates")
    page.controls.refresh.callback()
    equal(state.calls, 2)
    equal(state.jobs[page.refresh_task], nil)
    page.controls.pause.callback()
    equal(state.jobs[page.refresh_task], 15)
    runScheduled(page.refresh_task)
    equal(state.calls, 3)
end)

test("does not prompt for Wi-Fi or send requests when disconnected", function()
    local page = openStatus(manager(), "clients")
    state.is_connected = false
    runScheduled(page.refresh_task)
    equal(state.calls, 1)
    equal(state.connected, 1)
    contains(page.subtitle, "Stale | Last attempt:")
    contains(page.errors[1], "Wi-Fi is disconnected")
    contains(rows(page), "kindle")
    missing(rows(page), "Wi-Fi is disconnected")
    state.is_connected = true
    runScheduled(page.refresh_task)
    equal(state.calls, 2)
    contains(rows(page), "kindle")
    settings:delSetting("api_key")
    runScheduled(page.refresh_task)
    equal(state.calls, 2)
    contains(page.subtitle, "Unavailable | Last attempt:")
    contains(page.errors[1], "Configure")
    missing(rows(page), "kindle")
    missing(rows(page), key)
end)

test("closing or replacing a dashboard cancels its polling", function()
    local plugin = manager()
    local first = openStatus(plugin)
    local second = openStatus(plugin, "clients")
    equal(first.closed, true)
    equal(state.jobs[first.refresh_task], nil)
    equal(state.jobs[second.refresh_task], 15)
    plugin:onCloseWidget()
    equal(second.closed, true)
    equal(state.jobs[second.refresh_task], nil)
end)

test("reinitializing the menu does not replace the scheduled task or unpause it", function()
    local page = openStatus(manager(), "clients")
    local task = page.refresh_task
    page.controls.pause.callback()
    page:init()
    equal(page.refresh_task, task)
    equal(page.auto_refresh, false)
    equal(state.jobs[task], nil)
    contains(page.subtitle, "Last attempt:")
end)

local function clientPayload(count)
    local clients = {}
    for i = 1, count do
        clients[i] = {
            hostname = string.format("Client %02d", i),
            ip_address = "10.0.0." .. i,
            mac_address = string.format("00:00:00:00:00:%02x", i),
            connection_type = "wireless",
        }
    end
    return JSON.encode{ active_clients_amount = count, active_clients = clients }
end

test("fits system, hotspot and eight clients on one Paperwhite-sized page", function()
    local normal = request_handler
    request_handler = function(request)
        if request.url:match("/clients$") then return respond(clientPayload(8))(request) end
        return normal(request)
    end
    local page = openStatus(manager())
    equal(#page.cards, 10)
    equal(page.page_count, 1)
    equal(#page.card_widgets, 10)
    assert(page.layout_height <= state.screen_height, "dashboard exceeds screen height")
    assert(page[1]:getSize().w <= state.screen_width, "dashboard exceeds screen width")
end)

test("renders flush rounded headers with a reserved right-aligned white info icon", function()
    local page = openStatus(manager())
    local icons = require("raspap_icons")
    local expected_icons = { icons.system, icons.hotspot, icons.client }
    for index, card in ipairs(page.card_widgets) do
        equal(card.header_text.fgcolor, "white")
        equal(card.frame.background, nil)
        equal(card.frame.padding, 0)
        equal(card.frame.color, "black")
        assert(card.frame.radius > 0)
        assert(card.frame.bordersize > 0)
        missing(card.header_text.text, "[Tap]")
        equal(card.info_icon.file, expected_icons[index])
        equal(card.info_icon.invert, true)
        equal(card.header[1][3], card.info_icon)
        equal(card.header[1].allow_mirroring, false)
        local header_content_width = card.header[1]:getSize().w
        equal(header_content_width + 2 * card.header.padding + 2 * card.frame.bordersize, card.width)
        assert(card.ges_events.TapCard)
    end
    request_handler = respond('{"active_clients_amount":0,"active_clients":[]}')
    page = openStatus(manager(), "clients")
    local empty = page.card_widgets[1]
    equal(empty.header_text.text, "Clients")
    equal(empty.ges_events.TapCard, nil)
    equal(empty.info_icon, nil)
    equal(empty:onTapCard(), false)
    contains(empty.body_text.text, "No clients returned")
end)

test("opens matching styled details for each card and pauses polling behind the dialog", function()
    local page = openStatus(manager())
    local expected = {
        { icon = "system", field = "Hostname: test-pi" },
        { icon = "hotspot", field = "Interface: wlan0" },
        { icon = "client", field = "Connection: Wi-Fi" },
    }
    for index, spec in ipairs(expected) do
        local card = page.card_widgets[index]
        card:onTapCard()
        local details = shown[#shown]
        equal(details.title, card.label)
        equal(details.panel.info_icon.file, require("raspap_icons")[spec.icon])
        equal(details.panel.info_icon.invert, true)
        equal(details.panel.header_text.fgcolor, "white")
        contains(details.scroll.text, spec.field)
        assert(details.panel:getSize().h <= state.screen_height)
        assert(details.panel:getSize().w <= state.screen_width)
        equal(details.panel.ges_events.TapCard, nil)
        local calls = state.calls
        runScheduled(page.refresh_task)
        equal(state.calls, calls)
        details.close_button.callback()
        equal(details.panel.freed, true)
        equal(state.stack[#state.stack], page)
        runScheduled(page.refresh_task)
        equal(state.calls, calls + 3)
    end
end)

test("loads the bundled official favicon in the status button and status details", function()
    local icons = require("raspap_icons")
    for kind, path in pairs(icons) do
        local asset = assert(io.open(path, "rb"))
        local prefix = asset:read(64)
        asset:close()
        if kind == "raspap" then equal(prefix:sub(1, 8), "\137PNG\r\n\26\n")
        else contains(prefix, "<svg") end
    end
    local page = openStatus(manager())
    equal(page.controls.status.label_widget.file, icons.raspap)
    equal(page.controls.status.label_container[1], page.controls.status.label_widget)
    equal(page.titlebar.left_icon, nil)
    page.controls.status.callback()
    local details = shown[#shown]
    equal(details.icon, icons.raspap)
    equal(details.panel.info_icon.file, icons.raspap)
    equal(details.panel.info_icon.invert, false)
    equal(details.panel.info_icon.alpha, true)
    contains(details.text, "Last attempt:")
    contains(details.text, "All API requests succeeded")
    contains(details.text, "Last success:")
end)

test("bounds styled details and preserves full text through scrolling and resizing", function()
    local Details = require("raspap_details")
    state.screen_width, state.screen_height, state.screen_scale = 320, 800, 1
    local content = string.rep("A very long hostname and status description ", 600)
    local details = Details:new{ title = "Client details", icon = require("raspap_icons").client, text = content }
    package.loaded["ui/uimanager"]:show(details)
    equal(details.scroll.text, content)
    assert(details.scroll.height < #content)
    assert(details.panel:getSize().h <= state.screen_height)
    assert(details.panel:getSize().w <= state.screen_width)
    assert(details.close_button:getSize().h > 0)
    local old_panel = details.panel
    state.screen_width, state.screen_height = 800, 320
    details:onScreenResize()
    equal(old_panel.freed, true)
    equal(details.scroll.text, content)
    assert(details.scroll.height > 0)
    assert(details.panel:getSize().h <= state.screen_height)
    assert(details.panel:getSize().w <= state.screen_width)
    details:onClose()
    equal(#state.stack, 0)
end)

test("paints button press feedback flush to the border with unchanged rounded corners", function()
    request_handler = function(request) return respond(clientPayload(30))(request) end
    local page = openStatus(manager(), "clients")
    local buttons = {}
    for _, button in pairs(page.controls) do
        if button.callback and button.enabled then table.insert(buttons, button) end
    end
    page.card_widgets[1]:onTapCard()
    table.insert(buttons, shown[#shown].close_button)
    local canvas = {}
    function canvas:paintRoundedRect(x, y, width, height, color, radius)
        self.last = { x = x, y = y, width = width, height = height, color = color, radius = radius }
    end
    state.canvas = canvas
    local calls = state.calls
    for _, button in ipairs(buttons) do
        local radius = button.frame.radius
        local size = button.frame:getSize()
        button.frame:paintTo(canvas, 10, 20)
        button:_doFeedbackHighlight()
        equal(canvas.last.color, "black")
        equal(canvas.last.x, 10)
        equal(canvas.last.y, 20)
        equal(canvas.last.width, size.w)
        equal(canvas.last.height, size.h)
        equal(canvas.last.radius, radius + button.frame.bordersize)
        equal(button.frame.invert, false)
        if button.text then equal(button.label_widget.fgcolor, "white")
        else equal(button.label_widget.invert, true) end
        button:_undoFeedbackHighlight()
        equal(canvas.last.color, "white")
        equal(button.frame.radius, radius)
        if button.text then equal(button.label_widget.fgcolor, "black")
        else equal(button.label_widget.invert, false) end
        button:onFocus()
        button:_undoFeedbackHighlight()
        equal(button.frame.background, "black")
        button:onUnfocus()
        equal(button.frame.background, "white")
    end
    equal(state.calls, calls)
end)

test("paints edge-to-edge black headers without overwriting rounded outside corners", function()
    local page = openStatus(manager())
    local frame = page.card_widgets[1].frame
    local size = frame:getSize()
    local radius = frame.radius + frame.bordersize
    local header_height = frame.header_height + frame.bordersize
    local samples = {
        corner = { x = 0, y = 0 },
        top = { x = math.floor(size.w / 2), y = 0 },
        edge = { x = 1, y = radius },
        body = { x = math.floor(size.w / 2), y = header_height + 1 },
    }
    local canvas = {}
    local function fill(x, y, width, height, color, curve)
        for _, pixel in pairs(samples) do
            local px, py = pixel.x - x, pixel.y - y
            if px >= 0 and py >= 0 and px < width and py < height then
                local dx = math.max(curve - px, px - (width - curve), 0)
                local dy = math.max(curve - py, py - (height - curve), 0)
                if curve == 0 or dx * dx + dy * dy <= curve * curve then pixel.color = color end
            end
        end
    end
    function canvas:paintRoundedRect(x, y, width, height, color, curve)
        fill(x, y, width, height, color, curve)
    end
    function canvas:paintRect(x, y, width, height, color)
        fill(x, y, width, height, color, 0)
    end
    frame:paintTo(canvas, 0, 0)
    equal(samples.corner.color, nil)
    equal(samples.top.color, "black")
    equal(samples.edge.color, "black")
    equal(samples.body.color, "white")
    equal(frame.painted_at.x, 0)
end)

test("separates system and client rows with section headings, repeated on later pages", function()
    local normal = request_handler
    request_handler = function(request)
        if request.url:match("/clients$") then return respond(clientPayload(30))(request) end
        return normal(request)
    end
    local page = openStatus(manager())
    equal(page.section_headings[1].text, "System / Hotspot")
    contains(page.section_headings[2].text, "Clients  |  Reported: 30")
    equal(page.cards[1].section, "details")
    equal(page.cards[2].section, "details")
    equal(page.cards[3].section, "clients")
    page:onNextPage()
    equal(#page.section_headings, 1)
    contains(page.section_headings[1].text, "Clients")
    assert(page.layout_height <= state.screen_height)
    local measured_height = 2 * page[1].padding
    for _, child in ipairs(page[1][1]) do measured_height = measured_height + child:getSize().h end
    equal(page.layout_height, measured_height)
end)

test("paginates overflow, retains the page on refresh and clamps after shrink", function()
    local count = 30
    request_handler = function(request) return respond(clientPayload(count))(request) end
    local page = openStatus(manager(), "clients")
    assert(page.page_count > 1)
    assert(page.layout_height <= state.screen_height)
    equal(page.controls.previous.enabled, false)
    page.controls.next.callback()
    equal(page.page, 2)
    contains(page.page_label.text, "2 /")
    assert(page.layout_height <= state.screen_height)
    runScheduled(page.refresh_task)
    equal(page.page, 2)
    page:onSwipe(nil, { direction = "east" })
    equal(page.page, 1)
    count = 1
    page:onNextPage()
    runScheduled(page.refresh_task)
    equal(page.page, 1)
    equal(page.page_count, 1)
    equal(page.controls.next, nil)
end)

test("adapts to narrow screens and bounds long card text", function()
    request_handler = respond(JSON.encode{
        active_clients_amount = 1,
        active_clients = { {
            hostname = string.rep("Long hostname ", 40),
            mac_address = "00:00:00:00:00:01",
            ip_address = "10.0.0.1",
        } },
    })
    local page = openStatus(manager(), "clients")
    state.screen_width, state.screen_height, state.screen_scale = 320, 800, 1
    page:onScreenResize()
    equal(page.columns, 1)
    assert(page.layout_height <= state.screen_height)
    assert(page[1]:getSize().w <= state.screen_width)
    equal(page.card_widgets[1].body_text.height_overflow_show_ellipsis, true)
    page.card_widgets[1]:onTapCard()
    contains(shown[#shown].text, string.rep("Long hostname ", 40))
    equal(state.jobs[page.refresh_task], 15)
end)

test("launcher flag opens status only once after initialization", function()
    local class = loadManager("1")
    local plugin = manager(class)
    equal(#shown, 0)
    equal(state.calls, 0)
    equal(state.jobs[plugin.startup_task], 0)
    runScheduled(plugin.startup_task)
    local page = plugin.status_page
    assert(page)
    equal(state.calls, 0)
    runScheduled(page.refresh_task)
    equal(state.calls, 3)
    local second = manager(class)
    equal(second.startup_task, nil)
    equal(second.status_page, nil)
    plugin:onCloseWidget()
    equal(next(state.jobs), nil)
end)

test("normal startup is unchanged and teardown cancels a pending startup task", function()
    local plugin = manager()
    equal(plugin.startup_task, nil)
    equal(next(state.jobs), nil)
    plugin = manager(loadManager("1"))
    local task = plugin.startup_task
    plugin:onCloseWidget()
    equal(state.jobs[task], nil)
    equal(state.calls, 0)
    equal(#shown, 0)
end)

os.remove(temp)
os.remove(temp .. ".old")
print(string.format("\n%d passed, %d failed", passed, failed))
if failed > 0 then os.exit(1) end
