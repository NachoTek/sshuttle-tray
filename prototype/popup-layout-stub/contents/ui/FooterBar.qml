import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PC3
import org.kde.kirigami as Kirigami

Rectangle {
    id: footer
    property var brain

    radius: Kirigami.Units.smallSpacing
    color: Kirigami.Theme.alternateBackgroundColor
    border.color: Kirigami.Theme.disabledTextColor
    border.width: 1
    implicitHeight: col.implicitHeight + Kirigami.Units.smallSpacing * 2
    opacity: 0.95

    ColumnLayout {
        id: col
        anchors.fill: parent
        anchors.margins: Kirigami.Units.smallSpacing
        spacing: Kirigami.Units.smallSpacing

        RowLayout {
            spacing: Kirigami.Units.smallSpacing

            PC3.ToolButton { text: "◀"; onClicked: brain.cycleVariant(-1) }
            PC3.Label {
                text: "Variant " + brain.variant + " — " + brain.variantNames[brain.variants.indexOf(brain.variant)]
                font.bold: true
            }
            PC3.ToolButton { text: "▶"; onClicked: brain.cycleVariant(1) }

            Item { Layout.fillWidth: true }

            PC3.ToolButton {
                visible: brain.sim
                text: brain.simPaused ? "▶" : "⏸"
                onClicked: brain.simPaused = !brain.simPaused
            }
            PC3.ToolButton {
                visible: brain.sim
                text: brain.simSpeed === 1 ? "1x" : "4x"
                onClicked: brain.simSpeed = brain.simSpeed === 1 ? 4 : 1
            }
            PC3.ToolButton {
                visible: brain.sim
                text: "⏭"
                onClicked: brain.simStep()
            }
            PC3.Button {
                text: brain.sim ? "SIM" : "LIVE"
                onClicked: brain.toggleMode()
            }
            PC3.CheckBox {
                visible: !brain.sim
                text: "live control"
                checked: brain.liveControl
                onToggled: brain.liveControl = checked
            }
        }

        PC3.Label {
            Layout.fillWidth: true
            font.pointSize: Kirigami.Theme.defaultFont.pointSize - 3
            color: Kirigami.Theme.disabledTextColor
            elide: Text.ElideMiddle
            text: brain.lastCmd.length > 0
                ? "PROTOTYPE · " + brain.lastCmd + " · " + brain.lastLatency + " · exit " + brain.lastExit
                  + (brain.lastStderr ? " · err: " + brain.lastStderr : "")
                : "PROTOTYPE"
        }

        PC3.Label {
            Layout.fillWidth: true
            font.pointSize: Kirigami.Theme.defaultFont.pointSize - 3
            color: Kirigami.Theme.disabledTextColor
            elide: Text.ElideRight
            text: "state " + brain.state + " · suspect " + Math.round(brain.suspectSeconds) + "s"
                  + " · ticks " + brain.ticksUsed + "/" + brain.tickCap
                  + " · noans " + brain.noAnswerCount
                  + " · baseline " + (brain.baselineIP || "—")
                  + " · " + brain.lastAction
        }
    }
}
