local directory = assert(debug.getinfo(1, "S").source:match("^@(.*/)"),
    "Cannot locate RaspAP plugin icons") .. "icons/"

return {
    system = directory .. "system-info.svg",
    hotspot = directory .. "hotspot-info.svg",
    client = directory .. "client-info.svg",
    raspap = directory .. "raspap.png",
}
