# Research: ifconfig.me behavior, rate limits, and fallback IP-echo endpoints

Ticket: [NachoTek/sshuttle-tray#3](https://github.com/NachoTek/sshuttle-tray/issues/3)
Date: 2026-09-09. Method: primary-source docs + live probes from the dev machine (which was **not** behind the sshuttle tunnel at measurement time; no IPv6 default route on this box, so v6 paths are reasoned from DNS records + sshuttle docs, not measured).

## TL;DR

- `https://ifconfig.me/ip` (note the **`/ip` path**) is a fine primary: plain-text single-line IPv4, HTTPS, ~130 ms untunneled, no published rate limit. The bare `/` path returns a 10.8 KB **HTML page** when the User-Agent looks like a browser — `/ip` is UA-proof (verified).
- Best fallbacks, in order: `https://ipv4.icanhazip.com` (Cloudflare-owned since 2021, 30–35 B req/day capacity) and `https://api.ipify.org` (IPv4-only by DNS, "without limit" per project page, open source, no logging). All three return `text/plain`, single line, IP + `\n` — format-compatible.
- **Pin IPv4.** sshuttle `0/0` tunnels IPv4 TCP only; ifconfig.me and icanhazip.com are dual-stack, so a v6-capable client can leak around the tunnel and report the wrong (home) IP. `/ip` path does not pin v4 by itself — the client must force A-record resolution (or use the IPv4-only hostnames).
- Recommended client posture: HTTPS, no cookies, curl-like UA (or `/ip` + strict regex validation), 2 s connect / 3 s total timeout, rotate across the three endpoints, never retry the same host within a tick.

## Endpoint facts

All facts below verified live on 2026-09-09 (curl, IPv4-forced, from the dev machine) or taken from the linked primary source.

### ifconfig.me — primary

| Property | Finding |
|---|---|
| Format | `text/plain`, `<IPv4>\n` (13 bytes) — verified |
| Endpoints | `/` (=`/ip`), `/ip`, `/ua`, `/all`, `/all.json` etc. — [homepage](https://ifconfig.me/) self-documents the CLI |
| Transport | HTTP/2 + HTTP/3 (`alt-svc: h3`) over TLS; cleartext `http://` also answers 200 (no forced redirect) — verified |
| Infrastructure | Google Front End (`via: 1.1 google`, A/AAAA records inside Google Front End ranges — address literals elided per the no-leak policy, ADR 0005) — verified via headers/DNS |
| Latency (untunneled, 3 samples) | total 127–128 ms; connect 28–31 ms; TLS 67–70 ms — measured |
| Rate limit | **None published.** Site carries no ToS/rate-limit page; no rate-limit headers observed. Treat as a goodwill service; homepage now advertises an IPinfo.io partnership |
| Caching | No `Cache-Control` sent — effectively uncacheable per-request; nothing to work around |
| Quirks | **User-Agent content negotiation on `/`**: browser UA → `text/html; charset=utf-8` 10,793 B even with `Accept: */*`; curl UA → `text/plain` even with `Accept: text/html`. Negotiation keys on UA, not Accept. **`/ip` returns `text/plain` regardless of UA** (verified with a Chrome UA). Dual-stack DNS (AAAA present) |

### icanhazip.com — fallback #1

| Property | Finding |
|---|---|
| Format | `text/plain`, `<IP>\n` — verified |
| Transport | HTTPS (HTTP/2/3), cleartext HTTP 200 no-redirect — verified |
| Infrastructure | Cloudflare edge (`server: cloudflare`); owned & operated by **Cloudflare since June 2021** ([FAQ](https://major.io/icanhazip-com-faq/), [handover post](https://major.io/p/a-new-future-for-icanhazip/)) |
| Capacity | Served **30–35 B requests/day** at handover without response-time impact ([handover post](https://major.io/p/a-new-future-for-icanhazip/)); no per-client rate limit documented |
| Latency (untunneled, 3 samples) | total 82–94 ms; connect 19–23 ms; TLS 49–58 ms — measured (fastest of the four) |
| Quirks | Dual-stack; `ipv4.icanhazip.com` / `ipv6.icanhazip.com` pin the family (verified by DNS + request). Sets a Cloudflare `__cf_bm` bot-management cookie — **use a cookie-less client** so requests stay stateless and bot-scored as fresh GETs. Historical jokes-in-headers per the handover post; body is just the IP |

### api.ipify.org — fallback #2

| Property | Finding |
|---|---|
| Format | `text/plain`, `<IP>\n` (also `?format=json`) — [project page](https://www.ipify.org/) |
| Transport | HTTPS; cleartext HTTP 200 no-redirect — verified |
| Rate limit | **"You can use it without limit (even if you're doing millions of requests per minute)"** — [project page](https://www.ipify.org/) |
| Privacy/stance | "No visitor information is ever logged. Period."; fully open source ([repo](https://github.com/rdegges/ipify-api)) — project page |
| DNS | **No AAAA on `api.ipify.org`** → naturally IPv4-only (`api6.`/`api64.` exist for v6; verified AAAA on api64) |
| Latency (untunneled, 3 samples) | total 91–97 ms; connect 24–28 ms; TLS 55–63 ms — measured |

### ipinfo.io/ip — fallback #3 (optional)

| Property | Finding |
|---|---|
| Format | `text/plain; charset=utf-8`, `<IPv4>\n` — verified |
| Infrastructure | Google Front End (`via: 1.1 google`); no AAAA → IPv4-only — verified |
| Rate limit | Token-less `/ip` answered fine today (no rate-limit headers), but it is a **legacy, undocumented surface**; IPinfo's documented free path is the Lite API with a (free) token, which is unlimited — [developer docs](https://ipinfo.io/developers). Expect `429` behavior to be opaque without a token; rank it last |
| Latency (untunneled, 3 samples) | total 132–140 ms — measured (slowest of the four) |

## Behavior under sshuttle `0/0` with `--dns`

From the [sshuttle 1.3.2 manpage](https://sshuttle.readthedocs.io/en/stable/manpage.html):

1. **`0/0` matches IPv4 only.** IPv6 requires an explicit `::/0` subnet. With the default `nat` method, sshuttle *disables IPv6 locally* ("IPv6 disabled since it isn't supported by method nat" in its own startup log), which forces v6-capable clients onto the tunneled v4 path. With `nft`/`tproxy`/`pf`, IPv6 **leaks** unless `::/0` is passed or `--disable-ipv6` is set.
2. **TCP sessions, not packets.** sshuttle intercepts outgoing TCP and re-originates it from the SSH server. So an HTTPS echo query whose TCP connection is captured returns the **server's public (exit) IP** — exactly the signal the tray wants. There is no TCP-over-TCP penalty for a single small GET.
3. **`--dns` captures only plain DNS on port 53** to the local resolvers from `/etc/resolv.conf` (and systemd-resolved's resolv.conf if present). DNS-over-HTTPS/DoT is *not* captured — but that doesn't matter for the echo result, since the TCP connection is captured either way; only the resolver location differs.
4. **Practical consequences for the tray's queries:**
   - **IPv6 leak = wrong answer, silently.** On a dual-stack LAN with a non-`nat` method, a getaddrinfo-preferred-v6 client hitting `ifconfig.me` or `icanhazip.com` goes direct over v6 and echoes the **home** IPv6 — a false "tunnel down". Mitigation: force IPv4 resolution (A-records only / equivalent of `curl -4`), or prefer the IPv4-only hostnames (`api.ipify.org`, `ipinfo.io`, `ipv4.icanhazip.com`).
   - **The sshuttle server's own IP is auto-excluded** from routing, and the SSH control connection goes direct — never use the gateway hostname itself as an echo probe via v4; it will answer from... itself, direct (the exclusion keeps that traffic off the tunnel).
   - Expected tunneled latency = client→gateway SSH RTT + gateway→echo-endpoint time. Measured untunneled totals are 82–140 ms, so a typical intra-continental tunnel lands around 150–500 ms; an intercontinental one can exceed 1 s occasionally.

## Recommended client posture

- **URLs:** `https://ifconfig.me/ip` → `https://ipv4.icanhazip.com` → `https://api.ipify.org` (optionally `https://ipinfo.io/ip` last). All format-compatible: one line, trimmed, IPv4.
- **Force IPv4** at the resolver level (see leak above). Validate the body against a strict IPv4 regex (`^\d{1,3}(\.\d{1,3}){3}$`) — this also neutralizes any HTML/captive-portal/error-page response, making the UA question moot (belt and suspenders: still set a curl-like UA or use `/ip`).
- **Timeouts:** connect 2 s, total 3 s per attempt. That's ~25× the measured untunneled worst case (140 ms) and covers slow tunnels; it also leaves slack inside a 5 s UI tick for one same-tick fallback to the next endpoint.
- **Hygiene:** HTTPS only (all four support it; cleartext works but invites MITM'd answers); no cookie jar (icanhazip's `__cf_bm`); no HTTP caching in between (none of them send cache headers; treat every response as fresh); send `Cache-Control: no-cache` if a caching stack might sit in front.
- **Failure handling:** on timeout/non-200/regex-miss, advance to the next endpoint immediately; do not retry the same host within the same tick.

## Recommended sampling design for the tray cadence

Planned cadence (from the ticket): 1 query on popup open, then every 5 s up to 12 times, plus a ~60 s background poll.

- **Rotation, not fan-out:** each query goes to the *next* endpoint in the 3-host rotation. Popup burst worst case = 12 queries/60 s → **4 queries/min/host**; background = 1 query/60 s → **1 query/3 min/host**. Peak client rate is 0.2 req/s. This is invisible against ipify's "without limit", trivial against icanhazip's 30–35 B/day, and polite against ifconfig.me's unpublished limit.
- **Consensus on open:** the *first* popup-open query hits all three endpoints once (staggered ~250 ms) and requires 2-of-3 agreement to set the baseline "current public IP"; disagreement ⇒ mark state "unknown" rather than guessing. Later ticks rotate single-endpoint.
- **State semantics:** the tray shows "tunneled" when the consensus/rotating answer is stable and differs from the remembered untunneled baseline (or equals the configured gateway exit IP when known); "direct" when it matches the baseline; "unknown" on disagreement or consecutive failures.
- **Timeout budget inside a tick:** 3 s total per attempt leaves ≥ 1 headroom attempt within the 5 s tick; a fully failed tick defers to the next tick (no doubling up).
- **Stop conditions:** popup burst hard-stops at 12 ticks (60 s) even if the popup stays open; background poll pauses while a burst is active (don't double-poll); after 5 consecutive full failures the background poll backs off to 5 min until the next popup open.

## Sources

- ifconfig.me homepage (self-documented CLI endpoints; observed live behavior): https://ifconfig.me/
- ipify project page (unlimited use, no logging, open source): https://www.ipify.org/ ; repo: https://github.com/rdegges/ipify-api
- icanhazip FAQ (Cloudflare ownership since June 2021): https://major.io/icanhazip-com-faq/ ; handover post incl. 30–35 B req/day: https://major.io/p/a-new-future-for-icanhazip/
- IPinfo developer docs (token/Lite unlimited; 429 semantics): https://ipinfo.io/developers
- sshuttle 1.3.2 manpage (`0/0` vs `::/0`, `--dns` scope, method/IPv6 matrix): https://sshuttle.readthedocs.io/en/stable/manpage.html
- Live probes 2026-09-09: `dig`, `curl -4` header/body/content-negotiation/latency runs from the dev machine (not behind tunnel), 3 samples per endpoint.
