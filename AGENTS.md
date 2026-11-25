# Contributor lessons

## Scope and structure

- This is a native Lua KOReader plugin, targeting a Kindle Paperwhite 11th
  generation. Keep Lua 5.1/LuaJIT compatibility and use KOReader-bundled libraries.
- The verified official RaspAP API is read-only. Do not invent write endpoints,
  add SSH workarounds, or imply that API reachability proves Pi internet access.
  See the upstream reference and limitations in [README.md](README.md).
- Keep API validation/normalization in
  [raspap_client.lua](raspapmanager.koplugin/raspap_client.lua), dashboard state
  and pagination in [raspap_status.lua](raspapmanager.koplugin/raspap_status.lua),
  card rendering in [raspap_card.lua](raspapmanager.koplugin/raspap_card.lua),
  and settings/menu/startup integration in
  [main.lua](raspapmanager.koplugin/main.lua).
- Reuse [raspap_details.lua](raspapmanager.koplugin/raspap_details.lua) for styled
  information dialogs and [raspap_button.lua](raspapmanager.koplugin/raspap_button.lua)
  for rounded button feedback. Shared dialogs reuse the card header renderer.

## Lua and KOReader pitfalls

- `_` is the gettext function. A local variable or loop index named `_` shadows
  it; use another name wherever the scope also calls `_()`. This caused actual
  runtime failures in error and status-details paths.
- Verify native widget behavior rather than inferring it from mock behavior.
  `VerticalGroup` caches its size and child offsets after `getSize()`. Finish
  adding children before measuring, or call `resetLayout()` after mutation.
  Keep the layout mocks faithful to this caching behavior.
- `FrameContainer:getSize()` measures its child plus padding, margin and border;
  explicit `width`/`height` affect painting, not the measured size. Measure real
  widgets when calculating page capacity.
- Paint flush black card headers at the outer frame level, not inside white
  frame padding. Preserve rounded top corners and let the native frame paint
  its border and children. Keep text padding separate from background coverage.
- Reserve header width for the info icon so long labels cannot overlap it.
  Load bundled icons through `IconWidget.file`, not `icon` (which searches
  KOReader's theme directories). Use
  [raspap_icons.lua](raspapmanager.koplugin/raspap_icons.lua) for plugin-relative
  asset paths. Flatten monochrome icons before inversion
  for white-on-black headers; retain alpha for the non-inverted favicon.
  Disable header mirroring to keep the icon physically right-aligned.
- Native Button feedback with an explicit radius uses rectangular frame
  inversion. Repaint background/foreground colors with the original radius
  instead, so feedback meets the border without spilling into rounded corners.
- Free replaced widget trees during recurring layout rebuilds. Include section
  headings, gaps, footers and navigation in pagination measurements; never
  orphan a heading from its first card row.

## Networking, data and credentials

- Use `NetworkMgr:runWhenConnected`, not `runWhenOnline`: the Pi's local network
  must work without upstream internet. Automatic refresh checks connectivity
  without repeatedly prompting or enabling Wi-Fi.
- Authenticate with the `access_token` header, not bearer authentication.
  Preserve the endpoint allowlist, URL validation, redirect prohibition and
  HTTP proxy rejection so credentials are not forwarded unexpectedly.
- HTTPS requires KOReader's hostname-verification and CA-discovery support.
  Never disable peer verification or silently fall back to HTTP.
- Preserve request-size/time limits and restore all shared socket/HTTP timeout
  settings even after transport exceptions. Synchronous requests and DNS/OS
  behavior mean these limits are not a hard UI wall-clock guarantee.
- Decode with real `dkjson` semantics: JSON null, an empty object and an empty
  array are distinct. Do not turn missing/invalid counts into zero or failed
  requests into empty client lists. Whitelist displayable fields: `/ap` also
  returns a hotspot password that must not reach UI state, logs or storage.
- Show sanitized, actionable errors, never raw response bodies, API keys or
  exception strings. Preserve plaintext-key-storage and trusted-LAN warnings.
- `LuaSettings:flush()` alone does not establish successful persistence. Read
  back and compare the saved settings before claiming success. Clearing the
  key must also remove the `.old` backup, with explicit failure reporting.

## Dashboard and lifecycle invariants

- Schedule the next poll after a fetch completes, not on a fixed overlapping
  cadence. Preserve pause/manual refresh behavior; skip covered pages and
  cancel callbacks on suspend, close or replacement.
- Retain successful endpoint data independently on transient failures,
  including disconnection, timeouts and HTTP 408/429/5xx. Keep errors outside
  the data cards and mark the overall page Stale beside the last-attempt time.
- Successful empty lists replace old clients. Authentication failures, invalid
  responses and other non-transient errors clear the affected section. Changing
  the normalized API URL or key clears the entire in-memory cache.
- Keep last-attempt and per-endpoint last-success times distinct. Preserve the
  current page during refresh and clamp it when the list shrinks.
- Keep section headings and client labels in the form `[connection type] name`,
  falling back to IP when no usable hostname exists. Info icons indicate cards
  that open details; placeholders must not look actionable.
- The [launcher](scripts/koreader-raspap.sh) must invoke the standard
  `koreader.sh`, forwarding arguments and exit status. Consume
  `RASPAP_STATUS_ON_START` once per process and open via `UIManager:nextTick`;
  ordinary startup must make no requests or reopen the dashboard for each book.

## Validation

Run the relevant checks from the repository root:

```sh
lua5.1 tests/run.lua
luac5.1 -p raspapmanager.koplugin/*.lua tests/run.lua
sh tests/launcher.sh
shellcheck scripts/koreader-raspap.sh tests/launcher.sh
git diff --check
```

Use the available Lua 5.1/LuaJIT executable names. If `dkjson` is not on the
module path, set `LUA_PATH='/path/to/dkjson/?.lua;;'`; do not commit local runtime
builds or machine-specific paths.

Extend [the existing tests](tests/run.lua) for changed behavior, especially
error paths, cache invalidation, timer cleanup and measured layout. Layout
mocks use approximate fonts: passing tests do not establish native rendering,
physical Kindle/Pi compatibility or a real TLS handshake. Report these limits
and use the manual smoke checklist in [README.md](README.md).
