local Client = require("raspap_client")
local DataStorage = require("datastorage")
local InfoMessage = require("ui/widget/infomessage")
local KeyValuePage = require("ui/widget/keyvaluepage")
local LuaSettings = require("luasettings")
local MultiInputDialog = require("ui/widget/multiinputdialog")
local NetworkMgr = require("ui/network/manager")
local StatusPage = require("raspap_status")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = require("gettext")

local DEFAULT_URL = "http://10.3.141.1:8081"
local WARNING = _("The API key is saved unencrypted in KOReader settings. HTTP also sends it in plaintext. Use only a trusted LAN, or verified HTTPS. Do not expose port 8081 to the internet.")
local startup_requested = os.getenv("RASPAP_STATUS_ON_START") == "1"

local Manager = WidgetContainer:extend{
    name = "raspapmanager",
    is_doc_only = false,
}

local function display(value)
    if value == nil or value == "" then return _("Unavailable") end
    return tostring(value)
end

function Manager:init()
    self.settings = LuaSettings:open(DataStorage:getSettingsDir() .. "/raspapmanager.lua")
    self.ui.menu:registerToMainMenu(self)
    if startup_requested then
        startup_requested = false
        self.startup_task = function()
            self.startup_task = nil
            self:showStatus("summary")
        end
        UIManager:nextTick(self.startup_task)
    end
end

function Manager:onCloseWidget()
    if self.startup_task then UIManager:unschedule(self.startup_task) end
    if self.status_page and UIManager:isWidgetShown(self.status_page) then
        UIManager:close(self.status_page)
    end
end

function Manager:message(text)
    UIManager:show(InfoMessage:new{ text = text })
end

function Manager:persistSettings()
    local ok = pcall(self.settings.flush, self.settings)
    local readable, saved = pcall(dofile, self.settings.file)
    if not ok or not readable or type(saved) ~= "table"
        or saved.url ~= self.settings:readSetting("url")
        or saved.api_key ~= self.settings:readSetting("api_key") then
        self:message(_("Could not save RaspAP settings. Check the device's free space and settings directory permissions."))
        return false
    end
    return true
end

function Manager:addToMainMenu(menu_items)
    menu_items.raspapmanager = {
        text = _("RaspAP manager"),
        sorting_hint = "more_tools",
        sub_item_table = {
            { text = _("Status"), callback = function() self:showStatus("summary") end },
            { text = _("Connected clients"), callback = function() self:showStatus("clients") end },
            { text = _("Network interfaces"), callback = function() self:showStatus("networking") end },
            { text = _("Test connection"), callback = function() self:testConnection() end },
            { text = _("Connection settings"), callback = function() self:configure() end },
            { text = _("Clear saved API key"), callback = function() self:clearKey() end },
            { text = _("Setup and limitations"), callback = function() self:showHelp() end },
        },
    }
end

function Manager:configure()
    local dialog
    dialog = MultiInputDialog:new{
        title = _("RaspAP connection"),
        fields = {
            {
                description = _("API URL (10.3.141.1:8081 is a common default, not auto-detected)"),
                text = self.settings:readSetting("url") or DEFAULT_URL,
            },
            {
                description = _("API key (saved unencrypted)"),
                text = self.settings:readSetting("api_key") or "",
                text_type = "password",
            },
        },
        buttons = { {
            { text = _("Cancel"), id = "close", callback = function() UIManager:close(dialog) end },
            { text = _("Save"), callback = function()
                local fields = dialog:getFields()
                local url, err = Client.validate(fields[1], fields[2])
                if not url then self:message(err); return end
                self.settings:saveSetting("url", url)
                self.settings:saveSetting("api_key", fields[2])
                if not self:persistSettings() then return end
                UIManager:close(dialog)
                self:message(_("Connection settings saved.") .. "\n\n" .. WARNING)
            end },
        } },
    }
    UIManager:show(dialog)
    dialog:onShowKeyboard()
    self:message(WARNING)
end

function Manager:clearKey()
    self.settings:delSetting("api_key")
    if not self:persistSettings() then return end
    -- LuaSettings may retain a previous key in its .old backup.
    local backup = self.settings.file .. ".old"
    local removed, _remove_error, code = os.remove(backup)
    if not removed and code ~= 2 then
        self:message(_("The active key was cleared, but its settings backup could not be removed. Remove raspapmanager.lua.old manually and rotate the key in RaspAP."))
        return
    end
    self:message(_("Saved API key cleared. Copies may remain in device backups; rotate the key in RaspAP to revoke them."))
end

function Manager:withConnection(callback)
    local url = self.settings:readSetting("url") or DEFAULT_URL
    local key = self.settings:readSetting("api_key")
    local valid, err = Client.validate(url, key)
    if not valid then
        self:message(_("Configure the RaspAP connection first.") .. "\n\n" .. err)
        return
    end
    NetworkMgr:runWhenConnected(function() callback(valid, key) end)
end

function Manager:testConnection()
    self:withConnection(function(url, key)
        local data, err = Client.get(url, key, "/system")
        self:message(data and (_("API reachable: ") .. data.hostname
            .. "\n" .. _("This does not test the Pi's internet connection.")) or err)
    end)
end

function Manager:showStatus(kind, previous_page)
    if kind ~= "networking" then
        self:withConnection(function()
            if self.status_page and UIManager:isWidgetShown(self.status_page) then
                UIManager:close(self.status_page)
            end
            self.status_page = StatusPage:new{
                settings = self.settings,
                default_url = DEFAULT_URL,
                clients_only = kind == "clients",
            }
            UIManager:show(self.status_page)
        end)
        return
    end
    self:withConnection(function(url, key)
        local rows = {}
        local function row(label, value) table.insert(rows, { label, display(value) }) end
        local function fetch(endpoint, label)
            local data, err = Client.get(url, key, endpoint)
            if not data then row(label, _("Unavailable: ") .. err) end
            return data
        end
        local network = fetch("/networking", _("Network interfaces"))
        if network then
            local names = {}
            for name in pairs(network.interfaces) do table.insert(names, name) end
            table.sort(names)
            if #names == 0 then row(_("Interfaces"), _("No interfaces returned")) end
            for i = 1, #names do
                local name = names[i]
                local interface = network.interfaces[name]
                row(_("Interface"), name)
                row(_("IP address"), interface.IP_address)
                row(_("Netmask"), interface.Netmask)
                row(_("MAC address"), interface.MAC_address)
            end
        end
        table.insert(rows, 1, { _("Refresh"), _("Tap to fetch again"), callback = function(page)
            self:showStatus(kind, page)
        end })
        if previous_page then UIManager:close(previous_page) end
        UIManager:show(KeyValuePage:new{ title = _("RaspAP interfaces"), kv_pairs = rows })
    end)
end

function Manager:showHelp()
    self:message(_("Enable the official REST API using RaspAP's documented installer option, then generate and save an API key on its RestAPI page. Test /system in the API docs. Connect the Kindle to the Pi's network and enter the API URL and key here.")
        .. "\n\n" .. WARNING .. "\n\n"
        .. _("This plugin is read-only. The official API has no hotspot start/stop, SSID/password updates, upstream Wi-Fi configuration or Pi internet-connectivity test. See the README for setup and troubleshooting."))
end

return Manager
