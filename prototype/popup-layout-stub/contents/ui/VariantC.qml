import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PC3
import org.kde.kirigami as Kirigami

ColumnLayout {
    id: vc
    property var brain
    spacing: Kirigami.Units.smallSpacing

    readonly property color dotColor: {
        if (brain.state === "off") return Kirigami.Theme.disabledTextColor
        if (brain.state === "starting") return Kirigami.Theme.neutralTextColor
        if (brain.state === "on") return Kirigami.Theme.positiveTextColor
        return Kirigami.Theme.negativeTextColor
    }

    Rectangle {
        visible: brain.state === "alert"
        Layout.fillWidth: true
        implicitHeight: banner.implicitHeight + Kirigami.Units.smallSpacing * 2
        radius: Kirigami.Units.smallSpacing
        color: Kirigami.Theme.negativeTextColor
        opacity: 0.2
        PC3.Label {
            id: banner
            anchors.centerIn: parent
            width: parent.width - Kirigami.Units.largeSpacing
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            color: Kirigami.Theme.textColor
            font.bold: true
            text: "! " + brain.stateCause
        }
    }

    GridLayout {
        columns: 2
        columnSpacing: Kirigami.Units.largeSpacing
        rowSpacing: Kirigami.Units.smallSpacing
        Layout.fillWidth: true

        Repeater {
            model: [
                { label: "State", value: brain.stateWord, mono: false },
                { label: "Gateway", value: brain.noAnswer ? "no answer" : (brain.gatewayIP || "…"), mono: true },
                { label: "Baseline", value: brain.baseline || "—", mono: true },
                { label: "Samples", value: brain.ticksUsed + "/" + brain.tickCap + (brain.stale ? " · stale" : ""), mono: false }
            ]
            RowLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.largeSpacing
                required property var modelData
                PC3.Label {
                    text: modelData.label
                    color: Kirigami.Theme.disabledTextColor
                }
                Item { Layout.fillWidth: true }
                PC3.Label {
                    text: modelData.value
                    font.family: modelData.mono ? "monospace" : Kirigami.Theme.defaultFont.family
                    opacity: brain.stale && modelData.label === "Gateway" ? 0.45 : 1
                    color: modelData.label === "State" ? vc.dotColor : Kirigami.Theme.textColor
                }
            }
        }
    }

    RowLayout {
        Layout.fillWidth: true
        PC3.Label {
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            font.pointSize: Kirigami.Theme.defaultFont.pointSize - 2
            color: Kirigami.Theme.disabledTextColor
            text: "cause text lives in the tooltip — hover the tray icon"
        }
        PC3.Button {
            flat: true
            text: brain.svcActive ? "Stop" : "Start"
            onClicked: brain.pressPower()
        }
    }
}
