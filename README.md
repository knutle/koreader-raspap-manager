# KOReader RaspAP manager

A small, read-only KOReader plugin for viewing a RaspAP instance over its
official REST API. Intended for a Kindle Paperwhite 11th generation; physical
Kindle/Pi compatibility has **not yet been verified**.

## Features and limits

- Pi hostname/uptime and hotspot running/stopped state.
- Hotspot SSID, interface and channel (never its password).
- Reported client count and client hostname, IP, MAC and connection type.
- Network interface addresses.
- Saved API connection settings, connection test and manual refresh.
- Section-specific errors instead of substituting empty or stale results.

The [official API](https://docs.raspap.com/features-experimental/restapi/) is
experimental and read-only in the verified upstream revision
[`515025a`](https://github.com/RaspAP/raspap-webgui/blob/515025abcf2cbe8976b383f78ea0af549a9415c7/api/main.py).
Hotspot start/stop, SSID/password changes and upstream Wi-Fi configuration are
**deferred**, not implemented through undocumented routes or SSH. The API does
not expose a Pi-side internet-connectivity test; an API connection or an IP
address does not prove internet connectivity. Client counts/list entries are
reported by RaspAP, not independently verified associations.

## 1. Enable the RaspAP API

The plugin cannot enable the Pi's API itself.

1. Follow RaspAP's [REST API installation guide](https://docs.raspap.com/features-experimental/restapi/).
   The official Quick installer offers **Install and enable RestAPI?**. If your
   existing installation lacks the RestAPI page/service, consult that guide
   for your release before updating or rerunning the installer; back up your
   Pi configuration first. Do not blindly rerun an installer on a working Pi.
2. In RaspAP's **RestAPI** administration page, confirm the service is running.
   Generate an API key and choose **Save settings**.
3. Open its interactive API docs (normally `http://<pi-address>:8081/docs`).
   Select **Authorize**, enter the key, then try **GET /system**.
   Authentication uses the `access_token` header, not `Authorization: Bearer`.
4. Ensure the Kindle can reach the Pi on the configured API port, normally
   8081. Restrict access to your trusted LAN. Do not forward this port from
   your router or expose it on a public/WAN interface.

The default address `http://10.3.141.1:8081` is only a common RaspAP default.
Use your Pi's actual address and port. A numeric IPv4 address avoids local
hostname/mDNS-resolution problems on a Kindle.

To test from a computer on the same trusted LAN, replace `YOUR_API_KEY` and
the Pi address as needed:

```sh
curl --fail --show-error --connect-timeout 3 --max-time 8 \
  --header 'accept: application/json' \
  --header 'access_token: YOUR_API_KEY' \
  'http://10.3.141.1:8081/system'
```

A successful request returns JSON containing fields such as `hostname`,
`uptime` and `hostapdStatus`. HTTP 403 usually means the API key is missing or
incorrect. Avoid saving your real key in shell history or shared scripts;
HTTP transmits it in plaintext.

## 2. Install in KOReader

1. Copy the entire [`raspapmanager.koplugin`](./raspapmanager.koplugin) folder
   into your KOReader installation's `plugins` directory. On many Kindles this
   is `/mnt/us/koreader/plugins/raspapmanager.koplugin`.
2. Restart KOReader and enable **RaspAP manager** in its plugin manager if needed.
3. Connect the Kindle's Wi-Fi to the Pi's hotspot, or another network that can
   reach the Pi.
4. Open **Tools → More tools → RaspAP manager → Connection settings** (menu
   placement may vary by KOReader version).
5. Enter the API URL and key, save, then select **Test connection**.
6. Open **Status**, **Connected clients** or **Network interfaces**.
   Tap the first **Refresh** row to fetch new data.

No background polling, startup requests, browser session, or extra Pi-side
software beyond RaspAP's API is required. Internet access is not required:
the plugin uses KOReader's LAN-connected helper, not its internet-online check.

### Credentials and HTTPS

- The API key is masked in the dialog but stored **unencrypted** in
  `raspapmanager.lua` in KOReader's settings directory. KOReader may retain a
  `.old` backup. Protect device access and backups.
- HTTP sends the key in plaintext. Use it **only on a trusted LAN**.
- HTTPS requires a trusted certificate chain and KOReader's bundled LuaSec
  CA-discovery/hostname-verification support. Update KOReader if the plugin
  reports missing support. Untrusted/self-signed certificates or hostname
  mismatches fail; the plugin never turns verification off or downgrades.
  Use the DNS name in your certificate, not an unrelated IP.
- API URLs support IPv4/DNS hostnames, optional ports and simple reverse-proxy
  path prefixes. IPv6 literals, embedded credentials, query strings, fragments
  and percent-encoded paths are intentionally unsupported.
- Redirects and HTTP proxies are not used to send the API key. Enter the final
  API address directly.
- **Clear saved API key** removes the active setting and the local `.old`
  backup. To revoke any other copies (including device backups), generate a
  new key in RaspAP. Removing the plugin folder alone does not remove settings.
- Response bodies, keys and hotspot passwords are not logged or persisted.

### Troubleshooting

- **Authentication failed:** regenerate/save the key in RaspAP, then update it
  in the plugin. Web-interface login credentials are not an API key.
- **Cannot reach / timeout:** check Wi-Fi, actual Pi address, port, firewall
  and the RestAPI status page. On the Pi, `systemctl status restapi.service`
  and `journalctl -u restapi.service` can help diagnose service failures.
- **Unexpected response / HTTP 404:** confirm this is the API URL, not the
  RaspAP web-interface URL. Check your API version against the linked upstream
  routes. Failed sections are labeled unavailable while others remain visible.
- **Missing client/IP fields:** optional or null values appear as unavailable.
  An empty client list is explicitly distinguished from a request error.
- **Slow screen:** requests are synchronous and user-initiated, with a
  3-second socket-block timeout, an 8-second transfer budget and a 256 KiB
  response limit per endpoint. Summary loads three endpoints sequentially.
  DNS lookup and OS socket behavior can exceed these budgets; they are not a
  hard wall-clock guarantee. Prefer a numeric Pi address on unreliable DNS.

## Development and validation

Production uses only libraries bundled with KOReader. Local tests need Lua 5.1
or LuaJIT and `dkjson` (also bundled with KOReader); no live Pi is needed.

From the repository root:

```sh
lua5.1 tests/run.lua
luac5.1 -p raspapmanager.koplugin/*.lua tests/run.lua
```

Use your executable names (`lua`, `luajit`, `luac`) as appropriate. If `dkjson`
is not on the runtime's path, point `LUA_PATH` at a local copy, for example:

```sh
LUA_PATH='/path/to/koreader/common/?.lua;;' lua5.1 tests/run.lua
```

Tests use the real JSON decoder and mocked KOReader UI/network transports.
They check request safety, response parsing, timeout restoration, error
handling, settings save/reload/removal and LAN-only menu/refresh behavior.
They do not prove physical-device compatibility or perform a real TLS handshake.

### Manual Kindle/Pi smoke checklist

1. Enable the API, authorize `/system` in the API docs, and join the Pi network.
2. Install/restart KOReader. Check the menu from both file manager and reader.
3. Save settings, restart KOReader, and confirm the connection still works.
4. Compare status, clients and interface addresses with RaspAP. Check refresh
   and pagination, including long hostnames and an empty client list.
5. Test a wrong key, stopped API and unreachable address; verify useful errors.
6. Remove the Pi's upstream internet connection: LAN status should still work.
7. If using HTTPS, verify a trusted matching certificate works and an untrusted
   or mismatched certificate is rejected before the API key is sent.
8. Clear the saved key, restart, and confirm requests require configuration.
   Rotate the key in RaspAP if device backups may contain it.
