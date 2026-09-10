import QtQuick
import org.kde.plasma.plasmoid
import org.kde.plasma.plasma5support as Plasma5Support

PlasmoidItem {
    id: root

    Plasmoid.icon: "network-vpn"
    toolTipMainText: {
        if (state === "off") return "office-tunnel: off"
        if (state === "starting") return "office-tunnel: starting"
        if (state === "alert") return "office-tunnel: alert"
        return "office-tunnel: on"
    }
    toolTipSubText: {
        if (!haveSample) return "Gateway IP not sampled yet"
        if (noAnswer) return "Echo endpoints not answering"
        return "Gateway " + gatewayIP + (stale ? " (stale)" : "")
    }

    compactRepresentation: CompactRepresentation { brain: root }
    fullRepresentation: Popup { brain: root }

    property bool sim: true
    property bool simPaused: false
    property int simSpeed: 4
    property double simClock: 0

    property string svcState: "inactive"
    property string gatewayIP: ""
    property string baselineIP: ""
    property bool haveSample: false
    property bool noAnswer: false
    property string evidence: "none"
    property double suspectSeconds: 0

    property int ticksUsed: 0
    readonly property int tickCap: 12
    readonly property bool stale: ticksUsed >= tickCap
    property int noAnswerCount: 0

    property string lastCmd: ""
    property string lastTag: ""
    property string lastLatency: ""
    property string lastExit: ""
    property string lastStderr: ""
    property string lastAction: "demo mode — actions are no-ops until live control is enabled"

    property string variant: "A"
    readonly property var variants: ["A", "B", "C"]
    readonly property var variantNames: ["Status hero", "Switch-first terminal", "Dense rows"]
    property bool liveControl: false

    property string relayIP: "office-tunnel"
    property string ispGateway: "192.0.2.254"

    readonly property string simHomeIP: "192.0.2.10"
    readonly property string simTunnelIP: "198.51.100.20"
    readonly property var simPhases: [
        { name: "off",          dur: 6,  svc: "inactive",   ip: simHomeIP,   noAns: false },
        { name: "activating",   dur: 4,  svc: "activating", ip: simHomeIP,   noAns: false },
        { name: "verifying",    dur: 26, svc: "active",     ip: simHomeIP,   noAns: false },
        { name: "on",           dur: 20, svc: "active",     ip: simTunnelIP, noAns: false },
        { name: "on-noanswer",  dur: 8,  svc: "active",     ip: "",          noAns: true  },
        { name: "revert-grace", dur: 30, svc: "active",     ip: simHomeIP,   noAns: false },
        { name: "alert",        dur: 12, svc: "active",     ip: simHomeIP,   noAns: false },
        { name: "off2",         dur: 5,  svc: "inactive",   ip: simHomeIP,   noAns: false }
    ]
    readonly property double simTotal: {
        let t = 0
        for (const p of simPhases) t += p.dur
        return t
    }

    readonly property bool svcActive: svcState === "active" || svcState === "activating"
    readonly property string state: {
        if (svcState === "failed") return "alert"
        if (svcState === "inactive" || svcState === "") return "off"
        if (svcState === "activating") return "starting"
        if (evidence === "routed") return "on"
        return suspectSeconds >= 30 ? "alert" : "starting"
    }
    readonly property string stateWord: {
        if (state === "off") return "Off"
        if (state === "starting") return "Starting"
        if (state === "on") return "On"
        return "Alert"
    }
    readonly property string stateCause: {
        if (svcState === "failed") return "Service failed — check the journal"
        if (state === "off") return "Tunnel is off"
        if (svcState === "activating") return "Starting…"
        if (state === "on") return "Traffic routed through the tunnel"
        if (baselineIP === "") return "Verifying — no baseline captured"
        if (suspectSeconds >= 30) return evidence === "baselineIP"
            ? "Traffic reverted to baseline — tunnel dead or bypassed"
            : "Tunnel never became effective"
        return "Verifying traffic… " + Math.max(0, Math.ceil(30 - suspectSeconds)) + "s"
    }

    Plasma5Support.DataSource {
        id: executable
        engine: "executable"
        connectedSources: []
        onNewData: function(source, data) {
            executable.disconnectSource(source)
            lastLatency = (Date.now() - pendingT0) + "ms"
            lastExit = "" + data["exit code"]
            lastStderr = ("" + (data["stderr"] || "")).trim().slice(0, 90)
            const out = "" + (data["stdout"] || "")
            if (lastTag === "svc") handleService(out)
            else if (lastTag === "ip1") handleIp(out, true)
            else if (lastTag === "ip2") handleIp(out, false)
            else if (lastTag === "relay") {
                const m = out.match(/^hostname (\S+)$/m)
                if (m) relayIP = "office-tunnel · " + m[1]
            }
            else if (lastTag === "ispgw") {
                const g = out.match(/default via (\S+)/)
                if (g) ispGateway = g[1]
            }
            else if (lastTag === "ctl") refreshService()
            lastTag = ""
            lastCmd = source
        }
    }
    property double pendingT0: 0

    function runCommand(cmd, tag) {
        if (lastTag !== "") return
        lastCmd = cmd
        lastTag = tag
        pendingT0 = Date.now()
        executable.connectSource(cmd)
    }

    function refreshService() {
        runCommand("systemctl show -p ActiveState -p SubState office-tunnel", "svc")
    }

    function sampleRound() {
        runCommand("curl -m2 -4 -s https://ifconfig.me/ip", "ip1")
    }

    function handleService(out) {
        const map = {}
        for (const line of out.split("\n")) {
            const i = line.indexOf("=")
            if (i > 0) map[line.slice(0, i)] = line.slice(i + 1)
        }
        svcState = map["ActiveState"] || "inactive"
        if (svcState === "inactive" && haveSample && !noAnswer && baselineIP !== gatewayIP) baselineIP = gatewayIP
    }

    function validIPv4(s) {
        return /^(\d{1,3}\.){3}\d{1,3}$/.test(s) && s.split(".").every(n => +n <= 255)
    }

    function acceptIp(ip) {
        gatewayIP = ip
        haveSample = true
        noAnswer = false
        if (baselineIP !== "") evidence = ip === baselineIP ? "baselineIP" : "routed"
        else evidence = "none"
    }

    function handleIp(out, isPrimary) {
        const ip = out.trim()
        if (validIPv4(ip)) {
            acceptIp(ip)
            ticksUsed = Math.min(tickCap, ticksUsed + 1)
        } else if (isPrimary) {
            runCommand("curl -m3 -4 -s https://ipv4.icanhazip.com", "ip2")
        } else {
            noAnswer = true
            noAnswerCount++
            ticksUsed = Math.min(tickCap, ticksUsed + 1)
        }
    }

    function applySim() {
        const t = simClock % simTotal
        let acc = 0, phase = simPhases[0], phaseStart = 0
        for (const p of simPhases) {
            if (t < acc + p.dur) { phase = p; phaseStart = acc; break }
            acc += p.dur
        }
        const local = t - phaseStart
        baselineIP = simHomeIP
        svcState = phase.svc
        if (phase.noAns) {
            noAnswer = true
        } else {
            noAnswer = false
            gatewayIP = phase.ip
            haveSample = true
            evidence = phase.ip === baselineIP ? "baselineIP" : "routed"
        }
        if (phase.name === "verifying" || phase.name === "revert-grace" || phase.name === "alert") suspectSeconds = local
        else suspectSeconds = 0
        ticksUsed = Math.min(tickCap, Math.floor(simClock / 5) % 13)
        noAnswerCount = phase.name === "on-noanswer" ? 1 : 0
    }

    function tick() {
        if (sim) {
            if (!simPaused) simClock += simSpeed
        } else {
            if (svcState === "active" && evidence !== "routed") suspectSeconds += 1
            else suspectSeconds = 0
        }
    }

    function openedPopup() {
        ticksUsed = 0
        if (!sim && lastTag === "") {
            refreshService()
            sampleRound()
        }
    }

    function pressPower() {
        if (sim) {
            jumpSimToNextServiceChange()
            return
        }
        const cmd = svcActive ? "systemctl stop office-tunnel" : "systemctl start office-tunnel"
        if (!liveControl) {
            lastAction = "demo: would run “" + cmd + "” — enable live control in the footer"
            return
        }
        lastAction = "live: " + cmd
        runCommand(cmd, "ctl")
    }

    function jumpSimToNextServiceChange() {
        const target = simPhases[phaseIndex(simClock % simTotal)].svc === "inactive" ? "active" : "inactive"
        let t = simClock + 0.001
        for (let i = 0; i < simPhases.length * 2; i++) {
            const idx = phaseIndex(t % simTotal)
            if (simPhases[idx].svc === target && simPhases[idx].name !== "activating") {
                simClock = t
                applySim()
                return
            }
            t = Math.floor(t) + 1
        }
    }

    function phaseIndex(t) {
        let acc = 0
        for (let i = 0; i < simPhases.length; i++) {
            if (t < acc + simPhases[i].dur) return i
            acc += simPhases[i].dur
        }
        return 0
    }

    function simStep() {
        simClock += 5
        applySim()
    }

    function toggleMode() {
        sim = !sim
        if (sim) {
            simClock = 0
            applySim()
        } else {
            svcState = ""
            gatewayIP = ""
            baselineIP = ""
            haveSample = false
            noAnswer = false
            evidence = "none"
            suspectSeconds = 0
            ticksUsed = 0
            noAnswerCount = 0
            refreshService()
            sampleRound()
            metaStagger.restart()
        }
    }

    Timer {
        id: metaStagger
        interval: 600
        onTriggered: {
            root.runCommand("ssh -G office-tunnel", "relay")
            ispgwStagger.restart()
        }
    }
    Timer {
        id: ispgwStagger
        interval: 600
        onTriggered: root.runCommand("ip route show default", "ispgw")
    }

    function cycleVariant(dir) {
        const i = variants.indexOf(variant)
        variant = variants[(i + dir + variants.length) % variants.length]
    }

    Timer {
        interval: 1000
        running: true
        repeat: true
        onTriggered: root.tick()
    }
    Timer {
        interval: 3000
        running: !root.sim
        repeat: true
        onTriggered: root.refreshService()
    }
    Timer {
        interval: 5000
        running: !root.sim && root.expanded && !root.stale
        repeat: true
        onTriggered: root.sampleRound()
    }
}
