import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PC3
import org.kde.kirigami as Kirigami

ColumnLayout {
    id: vb
    property var brain
    spacing: Kirigami.Units.largeSpacing

    PC3.Switch {
        Layout.alignment: Qt.AlignHCenter
        text: "office-tunnel"
        font.pointSize: Kirigami.Theme.defaultFont.pointSize + 1
        checked: brain.svcActive
        onClicked: brain.pressPower()
    }

    Rectangle {
        Layout.fillWidth: true
        implicitHeight: term.implicitHeight + Kirigami.Units.largeSpacing * 2
        radius: Kirigami.Units.smallSpacing
        color: "#16181d"
        border.color: brain.state === "alert" ? Kirigami.Theme.negativeTextColor : "#3c3f46"
        border.width: brain.state === "alert" ? 2 : 1
        ColumnLayout {
            id: term
            anchors.fill: parent
            anchors.margins: Kirigami.Units.largeSpacing
            spacing: Kirigami.Units.smallSpacing
            PC3.Label {
                font.family: "monospace"
                color: brain.noAnswer ? "#8a8d98" : (brain.stale ? "#5c5f66" : "#74d69c")
                text: "gateway   " + (brain.noAnswer ? "-- no answer --" : (brain.gatewayIP || "…"))
            }
            PC3.Label {
                font.family: "monospace"
                color: "#8a8d98"
                text: "baseline  " + (brain.baseline || "—")
            }
            PC3.Label {
                font.family: "monospace"
                color: brain.stale ? "#bf8455" : "#8a8d98"
                text: "samples   " + "▮".repeat(Math.min(brain.ticksUsed, brain.tickCap))
                     + "▯".repeat(Math.max(0, brain.tickCap - brain.ticksUsed))
                     + "  " + brain.ticksUsed + "/" + brain.tickCap
                     + (brain.stale ? "  STALE" : "")
            }
            PC3.Label {
                visible: brain.state === "alert" || brain.state === "starting"
                font.family: "monospace"
                color: brain.state === "alert" ? "#fc8f78" : "#d6c26a"
                text: brain.state === "alert"
                    ? "! " + (brain.svcState === "failed" ? "service failed" : "revert — traffic bypassed tunnel")
                    : "… verifying (" + Math.max(0, Math.ceil(30 - brain.suspectSeconds)) + "s)"
            }
        }
    }

    PC3.Label {
        Layout.fillWidth: true
        wrapMode: Text.Wrap
        font.pointSize: Kirigami.Theme.defaultFont.pointSize - 2
        color: Kirigami.Theme.disabledTextColor
        text: brain.state === "on"
            ? "gateway differs from baseline — traffic is inside the tunnel"
            : (brain.state === "off" ? "tunnel stopped — sampling paused" : "sampling every 5 s while open, budget 12")
    }
}
