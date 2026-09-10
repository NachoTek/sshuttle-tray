pragma ComponentBehavior: Bound
import QtQuick
import org.kde.plasma.plasmoid
import org.kde.plasma.plasma5support as Plasma5Support
import "../code/engine.js" as EngineLib

PlasmoidItem {
    id: root

    // --- decision core + command queue ----------------------------------------

    property var engine: EngineLib.createEngine()
    property var cmdQueue: []
    property string inFlightTag: ""

    // mirrored engine view (what the representations and tooltip bind to)
    property string iconState: "off"
    property string stateWord: "Off"
    property string causeText: "Tunnel is off"
    property bool unverified: false
    property bool tunnelActive: false
    property string localGateway: ""
    property string localGatewayHost: ""
    property string freshness: "none"
    property string remoteAlias: ""
    property bool restartToApply: false

    function dispatch(ev) {
        const cmds = engine.handle(ev)
        if (cmds.length > 0) cmdQueue = cmdQueue.concat(cmds)
        syncView()
        pump()
    }

    // one command in flight at a time; the engine serializes decisions,
    // the queue serializes execution (connect -> onNewData -> disconnect)
    function pump() {
        if (inFlightTag !== "" || cmdQueue.length === 0) return
        const item = cmdQueue[0]
        cmdQueue = cmdQueue.slice(1)
        inFlightTag = item.tag
        executable.connectSource(item.command)
    }

    function syncView() {
        const v = engine.view()
        iconState = v.iconState
        stateWord = v.stateWord
        causeText = v.causeText
        unverified = v.unverified
        tunnelActive = v.tunnelActive
        localGateway = v.localGateway
        localGatewayHost = v.localGatewayHost
        freshness = v.freshness
        remoteAlias = v.remoteAlias
        restartToApply = v.restartToApply
    }

    function pressPower() { dispatch({ type: "powerPressed" }) }
    function pressRestart() { dispatch({ type: "restartPressed" }) }
    function hoverEntered() { dispatch({ type: "hoverEnter" }) }

    Plasma5Support.DataSource {
        id: executable
        engine: "executable"
        connectedSources: []
        onNewData: function(source, data) {
            executable.disconnectSource(source)
            const ev = {
                type: "result",
                tag: root.inFlightTag,
                exitCode: data["exit code"],
                stdout: "" + (data["stdout"] || ""),
                stderr: "" + (data["stderr"] || ""),
            }
            root.inFlightTag = ""
            root.dispatch(ev)
        }
    }

    Timer {
        interval: 1000
        running: true
        repeat: true
        onTriggered: root.dispatch({ type: "clock", dt: 1 })
    }

    Component.onCompleted: {
        pushConfig()
        dispatch({ type: "init" })
    }

    function pushConfig() {
        dispatch({
            type: "config",
            config: {
                echoInterval: Plasmoid.configuration.echoIntervalSeconds,
                sampleCap: Plasmoid.configuration.sampleCap,
                backgroundInterval: Plasmoid.configuration.backgroundIntervalSeconds,
            }
        })
    }

    Connections {
        target: Plasmoid.configuration
        function onValueChanged(key) {
            if (key === "echoIntervalSeconds" || key === "sampleCap" || key === "backgroundIntervalSeconds")
                root.pushConfig()
        }
    }

    // --- tray surface -----------------------------------------------------------

    Plasmoid.icon: "network-vpn"

    toolTipMainText: "sshuttle tunnel: " + root.stateWord + (root.unverified ? " (Unverified)" : "")
    toolTipSubText: {
        if (root.freshness === "none") return "Local Gateway not sampled yet"
        if (root.freshness === "noans") return "Echo endpoints not answering"
        const stale = root.freshness === "stale" ? " (stale)" : ""
        return "Local Gateway " + root.localGateway + stale
            + (root.remoteAlias !== "" ? "\nRemote Gateway " + root.remoteAlias : "")
    }

    compactRepresentation: CompactRepresentation { brain: root }
    fullRepresentation: FullRepresentation {
        brain: root
        onVisibleChanged: root.dispatch(visible ? { type: "popupOpened" } : { type: "popupClosed" })
    }
}
