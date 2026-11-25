# KOReader RaspAP manager

A small, read-only KOReader plugin for viewing a RaspAP instance over its
official REST API. Intended for a Kindle Paperwhite 11th generation; physical
Kindle/Pi compatibility has **not yet been verified**.

## Features and limits

- Pi hostname/uptime and hotspot running/stopped state.
- Hotspot SSID, interface and channel (never its password).
- Compact two-column dashboard with reported client count and sorted client
  cards: hostname, connection type, IP and MAC. Separate **System / Hotspot**
  and **Clients** headings organize the cards. Black headers extend to the
  rounded edges with white text; data sits in the white body. Client headers
  read **[Wi-Fi] hostname** (or Ethernet/other type), using the IP when no
  hostname is available. Typical setups fit on one screen; larger lists paginate.
- Bordered buttons and cards with a right-aligned **info icon** are clickable.
  Custom server, Wi-Fi and device info icons identify System, Hotspot and Client
  details. Tap a marked card for a matching rounded dialog with a black header,
  labeled fields, scrollable full text and a **Close** button.
- Button press feedback fills the rounded background up to the border,
  including the favicon, dashboard controls and detail-dialog Close buttons.
- Network interface addresses.
- Status/client pages automatically refresh every 15 seconds after each fetch;
  pause/resume and manual refresh are available on the page.
- Saved API connection settings, connection test and a status-page launcher.
- Overall API status beside the last-attempt time; transient failures retain
  already loaded cards and clearly mark the page **Stale**, rather than
  replacing their contents with errors. The top-left **RaspAP favicon button**
  opens styled connection-status details and per-section last-success times.
  Connection tests, setup guidance and settings messages use the same dialog style.

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

1. Copy the entire [`raspapmanager.koplugin`](./raspapmanager.koplugin) folder,
   including its bundled [`icons`](./raspapmanager.koplugin/icons),
   into your KOReader installation's `plugins` directory. On many Kindles this
   is `/mnt/us/koreader/plugins/raspapmanager.koplugin`.
2. Restart KOReader and enable **RaspAP manager** in its plugin manager if needed.
3. Connect the Kindle's Wi-Fi to the Pi's hotspot, or another network that can
   reach the Pi.
4. Open **Tools → More tools → RaspAP manager → Connection settings** (menu
   placement may vary by KOReader version).
5. Enter the API URL and key, save, then select **Test connection**.
6. Open **Status**, **Connected clients** or **Network interfaces**.
   The status/client pages update automatically. Tap **Refresh now** to fetch
   immediately, or **Pause updates** / **Resume updates**. Swipe or use the page
   controls to browse clients; automatic updates preserve the page number
   unless the list shrinks. Network interfaces still uses manual **Refresh**.

Polling stops on close and suspend, and skips requests while another dialog
covers the dashboard. Polling does not repeatedly prompt to reconnect or turn
Wi-Fi on. Reconnect normally to resume updates. Pause or close the dashboard
to reduce battery use.

**Online** means all API requests succeeded, not that the Pi has internet.
**Stale** means some visible data was retained after a connection failure,
timeout, HTTP 408/429/5xx or Wi-Fi disconnection. Successful sections still
update, including a genuinely empty client list. **Partial** means only some
sections loaded without retaining failed data; **Unavailable** means none
loaded. Failed sections without cached data show **Not loaded**; error details
stay in the favicon button's details dialog. Authentication failures, invalid
responses and other non-transient errors clear the affected section. Changing the server
address or API key clears all cached data. Cached data is held only in memory.

Normal KOReader startup makes no requests. No browser session or extra Pi-side
software beyond RaspAP's API is required. Internet access is not required: the
plugin uses KOReader's LAN-connected helper, not its internet-online check.

### Launch directly into the status page

Configure the connection and enable the plugin first, then **fully exit
KOReader**. Copy [`scripts/koreader-raspap.sh`](./scripts/koreader-raspap.sh)
onto the Kindle, for example beside `koreader.sh`, and run:

```sh
sh /mnt/us/koreader/koreader-raspap.sh
```

For a KUAL custom launcher action, use:

```sh
sh /mnt/us/koreader/koreader-raspap.sh --kual
```

The script calls the normal Kindle `koreader.sh` (preserving its device setup,
logging and cleanup), forwarding all arguments. It defaults to
`/mnt/us/koreader`; override `KOREADER_DIR` for a different installation:

```sh
KOREADER_DIR='/mnt/us/other-koreader' sh /path/to/koreader-raspap.sh
```

The equivalent minimal shell scriptlet is:

```sh
RASPAP_STATUS_ON_START=1 /mnt/us/koreader/koreader.sh
```

The plugin consumes this environment flag once per KOReader process and opens
the status dashboard after initialization, not every time a book is opened.
KOReader restarts within the same launcher inherit the flag and open the
dashboard again. Launch KOReader normally to retain its usual startup behavior.
No persistent startup setting or upstream KOReader file is modified. This
launches a new process; it does not navigate an already-running instance.

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
  routes. The overall status indicates the failure; tap the top-left RaspAP favicon
  for details. Invalid responses clear the affected section, while other
  successful sections remain visible.
- **Missing client/IP fields:** optional or null values appear as unavailable.
  An empty client list is explicitly distinguished from a request error.
- **Slow screen:** requests are synchronous (including automatic refresh), with a
  3-second socket-block timeout, an 8-second transfer budget and a 256 KiB
  response limit per endpoint. Status loads three endpoints sequentially;
  the clients-only page loads one. The next 15-second delay starts after
  completion, so requests never overlap.
  DNS lookup and OS socket behavior can exceed these budgets; they are not a
  hard wall-clock guarantee. Prefer a numeric Pi address on unreliable DNS.

## Development and validation

Production uses only libraries bundled with KOReader. Local tests need Lua 5.1
or LuaJIT and `dkjson` (also bundled with KOReader); no live Pi is needed.
Launcher tests use a POSIX shell; ShellCheck is optional for shell linting.

From the repository root:

```sh
lua5.1 tests/run.lua
luac5.1 -p raspapmanager.koplugin/*.lua tests/run.lua
sh tests/launcher.sh
shellcheck scripts/koreader-raspap.sh tests/launcher.sh
```

Use your executable names (`lua`, `luajit`, `luac`) as appropriate. If `dkjson`
is not on the runtime's path, point `LUA_PATH` at a local copy, for example:

```sh
LUA_PATH='/path/to/koreader/common/?.lua;;' lua5.1 tests/run.lua
```

Tests use the real JSON decoder and mocked KOReader UI/network transports.
They check request safety, response parsing, timeout restoration, error
handling, settings save/reload/removal and LAN-only menu/refresh behavior.
Dashboard tests cover automatic refresh, measured card layout, contrasting
flush rounded headers, custom info icons, the bundled favicon, matching
scrollable detail dialogs, rounded button press feedback, section headings, pagination,
client formatting/sorting, stale-data retention, cache invalidation,
pause/resume, hidden/suspended/closed pages, failure recovery and one-shot
startup. Layout tests use Paperwhite-sized geometry with mocked font metrics;
physical appearance still needs device verification.
The shell test uses a fake KOReader launcher to verify prerequisites,
environment flags, argument quoting and exit-status forwarding.
They do not prove physical-device compatibility or perform a real TLS handshake.

### Manual Kindle/Pi smoke checklist

1. Enable the API, authorize `/system` in the API docs, and join the Pi network.
2. Install/restart KOReader. Check the menu from both file manager and reader.
3. Save settings, restart KOReader, and confirm the connection still works.
4. Compare status, clients and interface addresses with RaspAP. Check automatic
   refresh, pause/resume, client-card details and pagination, including long
   hostnames and an empty client list. Check that card headers are white on
   black without white insets, borders are rounded, section headings separate
   details from clients, and only buttons or cards with info icons respond to
   taps. Confirm the three card types open matching detail icons, long detail
   text scrolls, and Close returns to the dashboard. Tap the top-left RaspAP
   favicon for connection status. Check pressed button backgrounds meet their
   rounded borders without an inset or square-corner spill. Check suspend/resume
   and close the page to confirm polling stops.
5. Stop the API or disconnect Wi-Fi after loading: cards should retain their
   data, with **Stale** beside the last-attempt time. Tap the RaspAP favicon
   for useful errors. Restore access and verify recovery. Test a wrong key or
   changed API address: old data must disappear rather than remain cached.
6. Remove the Pi's upstream internet connection: LAN status should still work.
7. If using HTTPS, verify a trusted matching certificate works and an untrusted
   or mismatched certificate is rejected before the API key is sent.
8. Clear the saved key, restart, and confirm requests require configuration.
   Rotate the key in RaspAP if device backups may contain it.
9. After configuring the key again, exit KOReader and run the status launcher.
   Confirm it opens the dashboard once; opening a book afterwards must not
   reopen it. A normal launch should keep KOReader's usual startup behavior.

## Icon attribution

The bundled [RaspAP favicon](./raspapmanager.koplugin/icons/raspap.png) is copied
unchanged from
[RaspAP/raspap-webgui](https://github.com/RaspAP/raspap-webgui/blob/515025abcf2cbe8976b383f78ea0af549a9415c7/app/icons/favicon-96x96.png),
revision `515025a`, under its GNU GPL v3 license. The upstream
[license text](./raspapmanager.koplugin/icons/RaspAP-LICENSE) is included alongside
the image. The System, Hotspot and Client SVG info icons are custom artwork
for this plugin. All icons load locally; no runtime asset downloads are needed.
