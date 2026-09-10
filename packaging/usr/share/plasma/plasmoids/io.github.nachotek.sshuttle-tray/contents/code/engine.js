// sshuttle-tray decision core — pure JS, no Qt.
//
// Event scripts in (service polls, echo answers, ping results, popup
// lifecycle, button presses, clock ticks), observables + planned commands
// out. Imported by the plasmoid QML and by the Node test runner.

var UNIT_DEFAULT = "sshuttle-tray-tunnel.service"

var DEFAULT_ENDPOINTS = [
    { host: "ifconfig.me", url: "https://ifconfig.me/ip" },
    { host: "ipv4.icanhazip.com", url: "https://ipv4.icanhazip.com" },
    { host: "api.ipify.org", url: "https://api.ipify.org" },
]

var DEFAULTS = {
    unit: UNIT_DEFAULT,
    endpoints: DEFAULT_ENDPOINTS,
    echoInterval: 5,
    sampleCap: 12,
    backgroundInterval: 60,
    pingInterval: 60,
    svcOpenInterval: 3,
    svcClosedInterval: 60,
    graceSeconds: 30,
    pingStrikes: 3,
    routeSetPath: "/etc/sshuttle-tray/route-set.env",
    tunnelEnvPath: "/etc/sshuttle-tray/tunnel.env",
}

function createEngine(options) {
    var opts = {}
    for (var k in DEFAULTS) opts[k] = DEFAULTS[k]
    for (var k2 in (options || {})) opts[k2] = options[k2]

    var st = {
        sec: 0,
        svc: "",                 // "", inactive, activating, active, failed
        popupOpen: false,
        ticksUsed: 0,
        rotation: 0,
        endpoints: {},           // host -> { baseline, lastIP, lastAnswerAt }
        lastAnswerAt: null,
        lastAnswerHost: "",
        lastRoundAnswer: null,   // true/false once a round completed
        lastEchoRoundAt: -1e9,
        lastSvcReqAt: -1e9,
        lastPingReqAt: -1e9,
        lastRouteSetReqAt: -1e9,
        round: null,             // { start, next } while an echo round is open
        routeSet: { subnets: ["0/0"], pingTarget: "" },
        remoteAlias: "",
        ping: { failStreak: 0, lastOk: false },
        run: { everEffective: false, everEchoDiverged: false, notEffSince: null },
        restartToApply: false,
    }
    for (var i = 0; i < opts.endpoints.length; i++) {
        st.endpoints[opts.endpoints[i].host] = { baseline: "", lastIP: "", lastAnswerAt: null }
    }
    var pending = {}             // tag -> true while a command is queued/in flight

    // -- helpers -------------------------------------------------------------

    function plan(list, tag, command) {
        if (pending[tag]) return
        pending[tag] = true
        list.push({ tag: tag, command: command })
    }

    function svcCmd() {
        return "systemctl show -p ActiveState -p SubState " + opts.unit
    }

    function curlCmd(ep) {
        return "curl -4 -fsS --connect-timeout 2 --max-time 3 " + ep.url
    }

    function pingCmd(target) {
        return "ping -4 -c1 -W2 " + target
    }

    function stoppedForBaselines() {
        return st.svc === "inactive" || st.svc === "failed"
    }

    function startEchoRound(list) {
        var idx = st.rotation % opts.endpoints.length
        st.round = { start: idx, next: idx }
        st.lastEchoRoundAt = st.sec
        plan(list, "echo:" + opts.endpoints[idx].host, curlCmd(opts.endpoints[idx]))
    }

    // -- effectivity ----------------------------------------------------------

    function endpointDiverged(ep) {
        return ep.baseline !== "" && ep.lastIP !== "" && ep.lastIP !== ep.baseline
    }

    function echoDivergedNow() {
        for (var h in st.endpoints) if (endpointDiverged(st.endpoints[h])) return true
        return false
    }

    // Echo evidence owns the verdict once any endpoint has diverged this run
    // (ADR 0004): a Ping Target that still answers cannot mask a Revert.
    function effectiveNow() {
        if (echoDivergedNow()) return true
        if (!st.run.everEchoDiverged && st.routeSet.pingTarget !== ""
            && st.ping.lastOk && st.ping.failStreak < opts.pingStrikes) return true
        return false
    }

    function fullTunnel() {
        return st.routeSet.subnets.indexOf("0/0") >= 0 || st.routeSet.subnets.indexOf("0.0.0.0/0") >= 0
    }

    function pingStriked() {
        return st.routeSet.pingTarget !== "" && st.ping.failStreak >= opts.pingStrikes
    }

    function suspectSeconds() {
        if (st.svc !== "active" || effectiveNow()) return 0
        return st.run.notEffSince === null ? 0 : st.sec - st.run.notEffSince
    }

    // -- view -----------------------------------------------------------------

    function computeView() {
        var icon, cause
        var unverified = false
        if (st.svc === "failed") {
            icon = "alert"; cause = "Service failed — check the journal"
        } else if (st.svc === "" || st.svc === "inactive") {
            icon = "off"; cause = "Tunnel is off"
        } else if (st.svc === "activating") {
            icon = "starting"; cause = "Starting…"
        } else {
            var eff = effectiveNow()
            var suspect = suspectSeconds()
            if (eff) {
                icon = "on"; cause = "Traffic routes through the Tunnel"
            } else if (suspect < opts.graceSeconds) {
                icon = "starting"
                cause = "Verifying traffic… " + Math.max(0, Math.ceil(opts.graceSeconds - suspect)) + "s"
            } else if (st.run.everEffective) {
                icon = "alert"; cause = "Traffic reverted to its Baseline — Tunnel dead or bypassed"
            } else if (fullTunnel() || st.routeSet.pingTarget !== "") {
                icon = "alert"; cause = "Tunnel never became effective"
            } else {
                icon = "on"; cause = "No in-scope evidence — Unverified"
                unverified = true
            }
            if (pingStriked()) {
                icon = "alert"; cause = "Ping Target unreachable"
            }
        }

        return {
            iconState: icon,
            stateWord: icon === "off" ? "Off" : icon === "starting" ? "Starting" : icon === "on" ? "On" : "Alert",
            causeText: cause,
            unverified: unverified,
            tunnelActive: st.svc === "active" || st.svc === "activating",
            localGateway: st.lastAnswerAt === null ? "" : st.endpoints[st.lastAnswerHost].lastIP,
            localGatewayHost: st.lastAnswerHost,
            freshness: freshness(),
            remoteAlias: st.remoteAlias,
            restartToApply: st.restartToApply,
        }
    }

    function freshness() {
        if (st.lastRoundAnswer === false) return "noans"
        if (st.lastAnswerAt === null) return "none"
        if (st.popupOpen && st.ticksUsed >= opts.sampleCap) return "stale"
        var cadence = st.popupOpen ? opts.echoInterval : opts.backgroundInterval
        if (st.sec - st.lastAnswerAt > cadence * 2.5) return "stale"
        return "live"
    }

    // -- scheduling -----------------------------------------------------------

    function scheduleDue(list) {
        var svcEvery = st.popupOpen ? opts.svcOpenInterval : opts.svcClosedInterval
        if (st.sec - st.lastSvcReqAt >= svcEvery) {
            st.lastSvcReqAt = st.sec
            plan(list, "svc", svcCmd())
        }
        if (st.svc === "active" && st.round === null) {
            var echoEvery = st.popupOpen ? opts.echoInterval : opts.backgroundInterval
            var budgetLeft = !st.popupOpen || st.ticksUsed < opts.sampleCap
            if (budgetLeft && st.sec - st.lastEchoRoundAt >= echoEvery) startEchoRound(list)
        }
        if (st.svc === "active" && st.routeSet.pingTarget !== "" && st.sec - st.lastPingReqAt >= opts.pingInterval) {
            st.lastPingReqAt = st.sec
            plan(list, "ping", pingCmd(st.routeSet.pingTarget))
        }
        // pick up apply-unit installs and hand edits (banner appears without a reopen)
        if (st.sec - st.lastRouteSetReqAt >= opts.backgroundInterval) {
            st.lastRouteSetReqAt = st.sec
            plan(list, "routeset", "cat " + opts.routeSetPath)
        }
    }

    // -- result parsing -------------------------------------------------------

    function parseEnv(text) {
        var map = {}
        var lines = ("" + text).split("\n")
        for (var i = 0; i < lines.length; i++) {
            var line = lines[i].trim()
            if (line === "" || line.charAt(0) === "#") continue
            var eq = line.indexOf("=")
            if (eq <= 0) continue
            var key = line.slice(0, eq).trim()
            var val = line.slice(eq + 1).trim()
            if (val.length >= 2 && ((val.charAt(0) === '"' && val.charAt(val.length - 1) === '"') ||
                                    (val.charAt(0) === "'" && val.charAt(val.length - 1) === "'"))) {
                val = val.slice(1, -1)
            }
            map[key] = val
        }
        return map
    }

    function applyServiceState(state) {
        var prev = st.svc
        st.svc = state
        if (state === "inactive" || state === "failed") {
            st.run = { everEffective: false, everEchoDiverged: false, notEffSince: null }
            st.ping = { failStreak: 0, lastOk: false }
            st.restartToApply = false
            if (prev !== "inactive" && prev !== "failed" && state === "inactive" && st.popupOpen && st.round === null) {
                var list = []
                startEchoRound(list)   // quiet Baseline re-capture on confirmed stop
                return list
            }
        } else if (state === "activating" && prev !== "activating") {
            st.run = { everEffective: false, everEchoDiverged: false, notEffSince: null }
            st.ping = { failStreak: 0, lastOk: false }
        }
        return []
    }

    function acceptEcho(host, ip) {
        var ep = st.endpoints[host]
        ep.lastIP = ip
        ep.lastAnswerAt = st.sec
        st.lastAnswerAt = st.sec
        st.lastAnswerHost = host
        st.lastRoundAnswer = true
        if (stoppedForBaselines()) ep.baseline = ip
        roundFinished()
    }

    function roundFinished() {
        if (!st.round) return
        var tried = (st.round.next - st.round.start + opts.endpoints.length) % opts.endpoints.length + 1
        st.rotation = (st.round.start + tried) % opts.endpoints.length
        st.round = null
        if (st.popupOpen) st.ticksUsed++
    }

    function handleEchoResult(list, host, exitCode, stdout) {
        if (!st.endpoints[host]) return
        var ip = ("" + stdout).trim()
        if (exitCode === 0 && validIPv4(ip)) {
            acceptEcho(host, ip)
            return
        }
        // advance to the next endpoint immediately within the same tick
        var nextIdx = st.round ? (st.round.next + 1) % opts.endpoints.length : -1
        var triedAny = false
        if (st.round) {
            triedAny = true
            var startIdx = st.round.start
            if (nextIdx === startIdx) {          // all endpoints tried
                st.lastRoundAnswer = false
                roundFinished()
                return
            }
        }
        if (!triedAny) return
        st.round.next = nextIdx
        plan(list, "echo:" + opts.endpoints[nextIdx].host, curlCmd(opts.endpoints[nextIdx]))
    }

    // -- events ---------------------------------------------------------------

    function handle(ev) {
        var cmds = []
        var t = ev.type

        if (t === "init") {
            plan(cmds, "tunnelenv", "cat " + opts.tunnelEnvPath)
            st.lastRouteSetReqAt = st.sec
            plan(cmds, "routeset", "cat " + opts.routeSetPath)
            plan(cmds, "svc", svcCmd())
            return cmds
        }

        if (t === "clock") {
            st.sec += ev.dt
            var eff = st.svc === "active" && effectiveNow()
            if (echoDivergedNow()) st.run.everEchoDiverged = true
            if (eff) {
                if (!st.run.everEffective) st.run.everEffective = true
                st.run.notEffSince = null
            } else if (st.svc === "active") {
                if (st.run.notEffSince === null) st.run.notEffSince = st.sec
            }
            scheduleDue(cmds)
            return cmds
        }

        if (t === "popupOpened") {
            st.popupOpen = true
            st.ticksUsed = 0
            st.lastSvcReqAt = st.sec
            plan(cmds, "svc", svcCmd())
            st.lastRouteSetReqAt = st.sec
            plan(cmds, "routeset", "cat " + opts.routeSetPath)
            if (st.round === null) startEchoRound(cmds)
            if (st.svc === "active" && st.routeSet.pingTarget !== "") {
                st.lastPingReqAt = st.sec
                plan(cmds, "ping", pingCmd(st.routeSet.pingTarget))
            }
            return cmds
        }

        if (t === "popupClosed") {
            st.popupOpen = false
            return cmds
        }

        if (t === "hoverEnter") {
            if (st.popupOpen) {
                st.ticksUsed = 0
                st.lastEchoRoundAt = -1e9
            }
            return cmds
        }

        if (t === "powerPressed") {
            if (st.svc === "active" || st.svc === "activating") {
                plan(cmds, "stop", "systemctl stop " + opts.unit)
            } else {
                if (st.round === null) startEchoRound(cmds)  // Baseline capture at start-click
                plan(cmds, "start", "systemctl start " + opts.unit)
            }
            return cmds
        }

        if (t === "restartPressed") {
            st.restartToApply = false
            plan(cmds, "stop", "systemctl stop " + opts.unit)
            plan(cmds, "start", "systemctl start " + opts.unit)
            return cmds
        }

        if (t === "config") {
            for (var key in ev.config) {
                if (key === "echoInterval" || key === "sampleCap" || key === "backgroundInterval") {
                    opts[key] = ev.config[key]
                }
            }
            return cmds
        }

        if (t === "result") {
            delete pending[ev.tag]
            if (ev.tag === "svc") {
                var map = parseEnv(ev.stdout)
                if (map["ActiveState"] === "deactivating") return cmds   // transient stop job — keep the last state
                var mapped = { active: "active", activating: "activating", failed: "failed",
                               inactive: "inactive", reloading: "active" }
                var state = mapped[map["ActiveState"]] || "inactive"
                return applyServiceState(state)
            }
            if (ev.tag === "routeset") {
                if (ev.exitCode === 0) {
                    var env = parseEnv(ev.stdout)
                    var parsed = parseSubnets(env["SSHUTTLE_SUBNETS"] || "0/0")
                    if (parsed.ok) {
                        var changed = JSON.stringify(parsed.subnets) !== JSON.stringify(st.routeSet.subnets) ||
                                      (env["SSHUTTLE_PING_TARGET"] || "") !== st.routeSet.pingTarget
                        st.routeSet = { subnets: parsed.subnets, pingTarget: env["SSHUTTLE_PING_TARGET"] || "" }
                        if (changed && (st.svc === "active" || st.svc === "activating")) st.restartToApply = true
                    }
                }
                return cmds
            }
            if (ev.tag === "tunnelenv") {
                if (ev.exitCode === 0) {
                    var tenv = parseEnv(ev.stdout)
                    st.remoteAlias = tenv["SSHUTTLE_REMOTE"] || ""
                }
                return cmds
            }
            if (ev.tag === "ping") {
                if (ev.exitCode === 0) st.ping = { failStreak: 0, lastOk: true }
                else st.ping = { failStreak: st.ping.failStreak + 1, lastOk: st.ping.failStreak + 1 >= opts.pingStrikes ? false : st.ping.lastOk }
                return cmds
            }
            if (ev.tag.indexOf("echo:") === 0) {
                handleEchoResult(cmds, ev.tag.slice(5), ev.exitCode, ev.stdout)
                return cmds
            }
            if (ev.tag === "start" || ev.tag === "stop") {
                st.lastSvcReqAt = -1e9   // poll service immediately after a control action
                plan(cmds, "svc", svcCmd())
                return cmds
            }
            return cmds
        }

        return cmds
    }

    return {
        handle: handle,
        view: computeView,
    }
}

// -- pure helpers (also used by the config dialog) ---------------------------

function validIPv4(s) {
    if (!/^(\d{1,3}\.){3}\d{1,3}$/.test(s)) return false
    var parts = s.split(".")
    for (var i = 0; i < parts.length; i++) if (parseInt(parts[i], 10) > 255) return false
    return true
}

function parseSubnets(text) {
    var result = { ok: true, subnets: [], errors: [] }
    if (text === undefined || text === null) text = ""
    var tokens = ("" + text).trim().split(/\s+/).filter(function (t) { return t !== "" })
    if (tokens.length === 0) {
        result.ok = false
        result.errors.push("Route Set is empty")
        return result
    }
    for (var i = 0; i < tokens.length; i++) {
        var tok = tokens[i]
        if (tok === "0/0") { result.subnets.push(tok); continue }
        var m = /^(\d{1,3}\.){3}\d{1,3}(\/\d{1,2})?$/.exec(tok)
        if (!m) { result.ok = false; result.errors.push("Not a CIDR: " + tok); continue }
        var octets = tok.split("/")[0].split(".")
        var bad = false
        for (var j = 0; j < octets.length; j++) if (parseInt(octets[j], 10) > 255) bad = true
        if (bad) { result.ok = false; result.errors.push("Bad octet in: " + tok); continue }
        if (m[2]) {
            var prefix = parseInt(tok.split("/")[1], 10)
            if (prefix > 32) { result.ok = false; result.errors.push("Prefix too large: " + tok); continue }
        }
        result.subnets.push(tok)
    }
    return result
}

function ipToInt(ip) {
    var p = ip.split(".")
    return ((parseInt(p[0], 10) << 24) | (parseInt(p[1], 10) << 16) |
            (parseInt(p[2], 10) << 8) | parseInt(p[3], 10)) >>> 0
}

function subnetContains(cidr, ip) {
    if (cidr === "0/0" || cidr === "0.0.0.0/0") return true
    var parts = cidr.split("/")
    var base = ipToInt(parts[0])
    var prefix = parts.length > 1 ? parseInt(parts[1], 10) : 32
    var mask = prefix === 0 ? 0 : (0xffffffff << (32 - prefix)) >>> 0
    return ((base & mask) >>> 0) === ((ipToInt(ip) & mask) >>> 0)
}

function subnetsContain(subnets, ip) {
    if (!validIPv4(ip)) return true   // hostname: cannot judge — assume in scope
    for (var i = 0; i < subnets.length; i++) if (subnetContains(subnets[i], ip)) return true
    return false
}

if (typeof module !== "undefined" && module.exports) {
    module.exports = {
        createEngine: createEngine,
        validIPv4: validIPv4,
        parseSubnets: parseSubnets,
        subnetContains: subnetContains,
        subnetsContain: subnetsContain,
    }
}
