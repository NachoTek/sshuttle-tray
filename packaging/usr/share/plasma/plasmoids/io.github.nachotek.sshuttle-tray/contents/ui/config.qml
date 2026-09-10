pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.plasma.plasma5support as Plasma5Support
import org.kde.kirigami as Kirigami
import "../code/engine.js" as EngineLib

// Standard Plasma config page. Cadence/cap entries are ordinary preferences.
// The Route Set editor and Ping Target stage the desired env-file content and
// install it through the root apply unit — one password prompt per change.
ColumnLayout {
    id: page

    property alias cfg_echoIntervalSeconds: echoSpin.value
    property alias cfg_sampleCap: capSpin.value
    property alias cfg_backgroundIntervalSeconds: bgSpin.value
    property alias cfg_routeSetDesired: routeEdit.text
    property alias cfg_pingTargetDesired: pingField.text

    property string applyStatus: ""

    function parsedSubnets() {
        return EngineLib.parseSubnets(routeEdit.text.replace(/[\n,]+/g, " "))
    }

    function shQuote(s) {
        return "'" + ("" + s).replace(/'/g, "'\\''") + "'"
    }

    function applyRouteSet() {
        const parsed = parsedSubnets()
        if (!parsed.ok) {
            applyStatus = "✗ " + parsed.errors[0]
            return
        }
        const target = pingField.text.trim()
        if (target !== "" && !/^[A-Za-z0-9._:-]+$/.test(target)) {
            applyStatus = "✗ Ping Target must be a hostname or IPv4"
            return
        }
        let content = "SSHUTTLE_SUBNETS=" + parsed.subnets.join(" ") + "\n"
        if (target !== "") content += "SSHUTTLE_PING_TARGET=" + target + "\n"
        const inner = "mkdir -p -- \"$XDG_RUNTIME_DIR/sshuttle-tray\""
            + " && printf %s " + shQuote(content)
            + " > \"$XDG_RUNTIME_DIR/sshuttle-tray/route-set.env\""
            + " && systemctl start sshuttle-tray-apply@$(id -u).service"
        applyStatus = "Applying… (enter your password when prompted)"
        runner.connectSource("sh -c " + shQuote(inner))
    }

    Plasma5Support.DataSource {
        id: runner
        engine: "executable"
        connectedSources: []
        onNewData: function(source, data) {
            runner.disconnectSource(source)
            if (data["exit code"] === 0) {
                page.applyStatus = "✓ Applied — restart the Tunnel from the popup to use the new Route Set"
            } else {
                page.applyStatus = "✗ Apply failed (exit " + data["exit code"] + ") — see journalctl -u sshuttle-tray-apply@<uid>"
            }
        }
    }

    QQC2.Label {
        Layout.fillWidth: true
        wrapMode: Text.Wrap
        text: "Sampling"
        font.bold: true
    }

    QQC2.SpinBox {
        id: echoSpin
        from: 1
        to: 60
        editable: true
    }
    QQC2.Label { text: "Echo sample interval while the popup is open (seconds)" }

    QQC2.SpinBox {
        id: capSpin
        from: 1
        to: 60
        editable: true
    }
    QQC2.Label { text: "Echo sample cap per popup-open window (budget resets on hover)" }

    QQC2.SpinBox {
        id: bgSpin
        from: 10
        to: 600
        editable: true
    }
    QQC2.Label { text: "Background echo interval while the popup is closed (seconds)" }

    QQC2.Label {
        Layout.topMargin: Kirigami.Units.largeSpacing
        Layout.fillWidth: true
        wrapMode: Text.Wrap
        text: "Route Set (IPv4 CIDRs, one or space-separated, 0/0 for everything)"
        font.bold: true
    }

    QQC2.TextField {
        id: routeEdit
        Layout.fillWidth: true
        placeholderText: "192.0.2.0/24 198.51.100.0/24"
        font.family: "monospace"
    }

    QQC2.Label {
        visible: routeEdit.text.length > 0 && !page.parsedSubnets().ok
        Layout.fillWidth: true
        wrapMode: Text.Wrap
        color: "#F85149"
        text: page.parsedSubnets().ok ? "" : "✗ " + page.parsedSubnets().errors.join("; ")
    }

    QQC2.Label {
        Layout.topMargin: Kirigami.Units.smallSpacing
        Layout.fillWidth: true
        wrapMode: Text.Wrap
        text: "Ping Target — a host inside the Route Set that must answer pings while the Tunnel is active (optional)"
    }

    QQC2.TextField {
        id: pingField
        Layout.fillWidth: true
        placeholderText: "192.0.2.55"
        font.family: "monospace"
    }

    QQC2.Label {
        visible: pingTargetWarningText.text !== ""
        id: pingTargetWarningText
        Layout.fillWidth: true
        wrapMode: Text.Wrap
        color: "#F2CC60"
        text: {
            const target = pingField.text.trim()
            if (target === "" || !page.parsedSubnets().ok) return ""
            return EngineLib.subnetsContain(page.parsedSubnets().subnets, target)
                ? "" : "⚠ " + target + " looks outside the Route Set — the Tool cannot verify through it"
        }
    }

    RowLayout {
        Layout.topMargin: Kirigami.Units.largeSpacing
        QQC2.Button {
            text: "Apply Route Set"
            enabled: page.parsedSubnets().ok
            onClicked: page.applyRouteSet()
        }
        QQC2.Label {
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            text: page.applyStatus
        }
    }

    QQC2.Label {
        Layout.topMargin: Kirigami.Units.smallSpacing
        Layout.fillWidth: true
        wrapMode: Text.Wrap
        color: Kirigami.Theme.disabledTextColor
        font.pointSize: Kirigami.Theme.smallFont.pointSize
        text: "Applying stages the file under /run/user/<uid>/sshuttle-tray/ and runs the root apply unit (one password prompt). Hand-editing /etc/sshuttle-tray/route-set.env still works; changes take effect on the next Tunnel start."
    }

    Item { Layout.fillHeight: true }
}
