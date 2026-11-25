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
    instance:init()
    return instance
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
package.loaded["ui/uimanager"] = {
    show = function(_, value) table.insert(shown, value) end,
    close = function(_, value) table.insert(closed, value) end,
}
package.loaded["ui/network/manager"] = {
    runWhenConnected = function(_, callback) state.connected = state.connected + 1; callback() end,
    runWhenOnline = function() error("Internet connectivity must not be required") end,
}
package.loaded.datastorage = { getSettingsDir = function() return "." end }
package.loaded.luasettings = {
    open = function()
        return settings
    end,
}

local Client = require("raspap_client")
local Manager = dofile("raspapmanager.koplugin/main.lua")
local function reset()
    os.remove(temp)
    os.remove(temp .. ".old")
    state, shown, closed, now = { connected = 0, calls = 0 }, {}, {}, 0
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
local function manager()
    return Manager:new{ ui = { menu = { registerToMainMenu = function() state.registered = true end } } }
end
local function rows(page)
    local text = {}
    for _, row in ipairs(page.kv_pairs) do table.insert(text, row[1] .. ": " .. row[2]) end
    return table.concat(text, "\n")
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

test("reports HTTP errors without revealing response bodies", function()
    for _, code in ipairs({ 401, 403, 404, 500, 302 }) do
        request_handler = respond(key .. " fixture-hotspot-secret", code)
        local err = getError()
        contains(err, (code == 401 or code == 403) and "Authentication" or tostring(code))
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

test("shows LAN-only status, omits passwords and refreshes instead of appending", function()
    local plugin = manager()
    plugin:showStatus("summary")
    local page = shown[#shown]
    local text = rows(page)
    contains(text, "Hotspot: Running")
    contains(text, "SSID: Test AP")
    contains(text, "Reported clients: 1")
    contains(text, "Not exposed by the API")
    missing(text, "fixture-hotspot-secret")
    equal(state.connected, 1)
    page.kv_pairs[1].callback(page)
    equal(closed[1], page)
    equal(#shown[#shown].kv_pairs, #page.kv_pairs)
    equal(state.calls, 6)
end)

test("labels partial errors without inventing offline or empty data", function()
    local normal = request_handler
    request_handler = function(request)
        if request.url:match("/system$") then return nil, "closed" end
        return normal(request)
    end
    manager():showStatus("summary")
    local text = rows(shown[#shown])
    contains(text, "System: Unavailable:")
    contains(text, "SSID: Test AP")
    missing(text, "Stopped")
    missing(text, "Reported clients: 0")
end)

test("renders clients and interfaces and distinguishes empty from failed", function()
    local plugin = manager()
    plugin:showStatus("clients")
    contains(rows(shown[#shown]), "IP address: 10.3.141.2")
    plugin:showStatus("networking")
    local text = rows(shown[#shown])
    contains(text, "Interface: wlan0")
    contains(text, "Netmask: Unavailable")
    request_handler = respond('{"active_clients_amount":0,"active_clients":[]}')
    plugin:showStatus("clients")
    contains(rows(shown[#shown]), "No clients returned")
    request_handler = function() return nil, "closed" end
    plugin:showStatus("clients")
    text = rows(shown[#shown])
    contains(text, "Unavailable:")
    missing(text, "No clients returned")
end)

os.remove(temp)
os.remove(temp .. ".old")
print(string.format("\n%d passed, %d failed", passed, failed))
if failed > 0 then os.exit(1) end
