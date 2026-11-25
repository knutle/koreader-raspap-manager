local http = require("socket.http")
local https = require("ssl.https")
local JSON = require("dkjson")
local socket = require("socket")
local socketutil = require("socketutil")
local ssl = require("ssl")
local _ = require("gettext")

local Client = {}
local MAX_BYTES = 256 * 1024
local BLOCK_TIMEOUT = 3
local TOTAL_TIMEOUT = 8
local endpoints = { ["/system"] = true, ["/ap"] = true, ["/clients"] = true, ["/networking"] = true }

function Client.validate(url, key)
    if type(url) ~= "string" or url:find("[%c%s@?#\\]") then
        return nil, _("Use an HTTP(S) API URL without credentials, spaces, query or fragment.")
    end
    local scheme, authority, path = url:match("^(https?)://([^/]+)(.*)$")
    if not scheme then
        return nil, _("The API URL must start with http:// or https://.")
    end
    local host, port = authority:match("^([%w%.%-]+):(%d+)$")
    host = host or authority:match("^([%w%.%-]+)$")
    if not host or #host > 253 or host:find("%.%.") or host:match("^%.") or host:match("%.$") then
        return nil, _("Use a valid IPv4 address or DNS hostname, with an optional port.")
    end
    for label in host:gmatch("[^.]+") do
        if #label > 63 or label:find("[^%w%-]") or label:match("^%-") or label:match("%-$") then
            return nil, _("Invalid API hostname.")
        end
    end
    if port and (tonumber(port) < 1 or tonumber(port) > 65535) then
        return nil, _("The API port must be between 1 and 65535.")
    end
    if path:find("[^/%w%._~%-]") then
        return nil, _("The API URL path may only contain letters, numbers, /, ., _, ~ and -.")
    end
    if type(key) ~= "string" or key == "" or key:find("[%c%s]") then
        return nil, _("Enter an API key without spaces or control characters.")
    end
    local normalized = url:gsub("/+$", "")
    return normalized
end

local function object(value)
    return type(value) == "table" and getmetatable(value)
        and getmetatable(value).__jsontype == "object"
end

local function scalar(value)
    if type(value) == "string" or type(value) == "number" then
        return value
    end
end

local function count(value)
    return type(value) == "number" and value >= 0 and value < math.huge and value % 1 == 0
end

-- Only keep displayable fields: /ap also returns the hotspot password.
local function normalize(endpoint, data)
    if not object(data) then return nil end
    if endpoint == "/system" then
        if type(data.hostname) ~= "string" or data.hostname == "" then return nil end
        return {
            hostname = data.hostname,
            uptime = scalar(data.uptime),
            hostapdStatus = (data.hostapdStatus == 0 or data.hostapdStatus == 1) and data.hostapdStatus or nil,
        }
    elseif endpoint == "/ap" then
        if type(data.ssid) ~= "string" or type(data.interface) ~= "string" then return nil end
        return { ssid = data.ssid, interface = data.interface, channel = scalar(data.channel) }
    elseif endpoint == "/clients" then
        local clients = data.active_clients
        if type(clients) ~= "table" or not getmetatable(clients)
            or getmetatable(clients).__jsontype ~= "array" then return nil end
        local result = {
            active_clients_amount = count(data.active_clients_amount) and data.active_clients_amount or nil,
            active_clients = {},
        }
        for _, entry in ipairs(clients) do
            if not object(entry) or type(entry.mac_address) ~= "string" then return nil end
            table.insert(result.active_clients, {
                hostname = scalar(entry.hostname),
                ip_address = scalar(entry.ip_address),
                mac_address = entry.mac_address,
                connection_type = scalar(entry.connection_type),
            })
        end
        return result
    elseif endpoint == "/networking" then
        if not object(data.interfaces) then return nil end
        local interfaces = {}
        for name, entry in pairs(data.interfaces) do
            if not object(entry) then return nil end
            interfaces[name] = {
                IP_address = scalar(entry.IP_address),
                Netmask = scalar(entry.Netmask),
                MAC_address = scalar(entry.MAC_address),
            }
        end
        return { interfaces = interfaces }
    end
end

function Client.get(url, key, endpoint)
    local base, validation_error = Client.validate(url, key)
    if not base then return nil, validation_error end
    if not endpoints[endpoint] then return nil, _("Unsupported RaspAP endpoint.") end
    if http.PROXY then
        return nil, _("Disable the HTTP proxy before sending a RaspAP API key.")
    end
    local request = {
        url = base .. endpoint,
        method = "GET",
        headers = { access_token = key, accept = "application/json" },
        redirect = false,
    }
    local transport = http
    if base:match("^https://") then
        -- These functions identify KOReader's CA-discovery and hostname-verification patches.
        if type(ssl.checkhostname) ~= "function" or type(ssl.get_system_ca) ~= "function" then
            return nil, _("Verified HTTPS requires a newer KOReader build. Update KOReader or use HTTP only on a trusted LAN.")
        end
        local ca = ssl.get_system_ca()
        if not ca then return nil, _("No trusted CA bundle is available. Update KOReader before using HTTPS.") end
        request.verify = "peer"
        request.cafile = ca
        transport = https
    end

    local chunks, bytes = {}, 0
    local started = socket.gettime()
    local sink_error
    local timed_sink = socketutil.table_sink(chunks)
    request.sink = function(chunk, err)
        if socket.gettime() - started > TOTAL_TIMEOUT then
            sink_error = _("The RaspAP response timed out.")
            return nil, "timeout"
        end
        if chunk then
            bytes = bytes + #chunk
            if bytes > MAX_BYTES then
                sink_error = _("The RaspAP response exceeds the 256 KiB limit.")
                return nil, "response too large"
            end
        end
        return timed_sink(chunk, err)
    end

    local old_block, old_total = socketutil.block_timeout, socketutil.total_timeout
    local old_http, old_https = http.TIMEOUT, https.TIMEOUT
    socketutil:set_timeout(BLOCK_TIMEOUT, TOTAL_TIMEOUT)
    local ok, result, code = pcall(transport.request, request)
    socketutil:set_timeout(old_block, old_total)
    http.TIMEOUT, https.TIMEOUT = old_http, old_https

    if sink_error then return nil, sink_error, bytes > MAX_BYTES and "response" or "transient" end
    if not ok or not result then
        if code == "timeout" or code == socketutil.SINK_TIMEOUT_CODE then
            return nil, _("Connection timed out. Check the Pi address, Wi-Fi and REST API service."), "transient"
        end
        return nil, _("Cannot reach RaspAP. Check the address, Wi-Fi, REST API service and HTTPS certificate if applicable."), "transient"
    end
    code = tonumber(code)
    if code == 401 or code == 403 then
        return nil, _("Authentication failed. Check the API key in RaspAP's RestAPI settings.")
    elseif code ~= 200 then
        local transient = code and ((code >= 500 and code <= 599) or code == 408 or code == 429)
        return nil, string.format(_("RaspAP returned HTTP %s. Check the API address and version; redirects are not followed."), code or "?"),
            transient and "transient" or nil
    end
    local body = table.concat(chunks)
    local decoded_ok, data, position, decode_error = pcall(JSON.decode, body, 1, JSON.null)
    if not decoded_ok or decode_error or not position or body:sub(position):find("%S") then
        return nil, _("RaspAP returned invalid JSON.")
    end
    local normalized = normalize(endpoint, data)
    if not normalized then
        return nil, _("Unexpected RaspAP response format. Check the REST API version.")
    end
    return normalized
end

return Client
