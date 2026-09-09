import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PC3
import org.kde.kirigami as Kirigami

ColumnLayout {
    id: va
    property var brain
    spacing: Kirigami.Units.largeSpacing

    readonly property color stateColor: {
        if (brain.state === "off") return Kirigami.Theme.disabledTextColor
        if (brain.state === "starting") return Kirigami.Theme.neutralTextColor
        if (brain.state === "on") return Kirigami.Theme.positiveTextColor
        return Kirigami.Theme.negativeTextColor
    }
    readonly property string glyph: {
        if (brain.state === "off") return "⏻"
        if (brain.state === "starting") return "…"
        if (brain.state === "on") return "✓"
        return "!"
    }

    Rectangle {
        Layout.alignment: Qt.AlignHCenter
        implicitWidth: Kirigami.Units.gridUnit * 4
        implicitHeight: implicitWidth
        radius: width / 2
        color: "transparent"
        border.color: va.stateColor
        border.width: 3
        Text {
            anchors.centerIn: parent
            text: va.glyph
            color: va.stateColor
            font.pixelSize: parent.width * 0.45
            font.bold: true
        }
    }

    PC3.Label {
        Layout.alignment: Qt.AlignHCenter
        text: brain.state === "alert" ? "ALERT" : brain.stateWord
        font.pointSize: Kirigami.Theme.defaultFont.pointSize + 6
        font.bold: true
        color: va.stateColor
    }

    PC3.Label {
        Layout.fillWidth: true
        Layout.alignment: Qt.AlignHCenter
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.Wrap
        text: brain.stateCause
        color: Kirigami.Theme.disabledTextColor
    }

    ColumnLayout {
        spacing: 0
        Layout.alignment: Qt.AlignHCenter
        PC3.Label {
            Layout.alignment: Qt.AlignHCenter
            text: "GATEWAY IP"
            font.pointSize: Kirigami.Theme.defaultFont.pointSize - 2
            color: Kirigami.Theme.disabledTextColor
        }
        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: Kirigami.Units.smallSpacing
            PC3.Label {
                text: brain.noAnswer ? "no answer" : (brain.gatewayIP || "…")
                font.family: "monospace"
                font.pointSize: Kirigami.Theme.defaultFont.pointSize + 3
                color: brain.noAnswer ? Kirigami.Theme.disabledTextColor : Kirigami.Theme.textColor
                opacity: brain.stale ? 0.45 : 1
            }
            Rectangle {
                visible: brain.haveSample
                radius: height / 2
                implicitHeight: pillText.implicitHeight + Kirigami.Units.smallSpacing
                implicitWidth: pillText.implicitWidth + Kirigami.Units.largeSpacing
                color: brain.stale ? Kirigami.Theme.disabledTextColor : Kirigami.Theme.positiveTextColor
                opacity: 0.25
                PC3.Label {
                    id: pillText
                    anchors.centerIn: parent
                    text: brain.stale ? "STALE" : "LIVE"
                    font.pointSize: Kirigami.Theme.defaultFont.pointSize - 3
                    color: brain.stale ? Kirigami.Theme.textColor : Kirigami.Theme.positiveTextColor
                }
            }
        }
    }

    PC3.Button {
        Layout.fillWidth: true
        text: brain.svcActive ? "Stop tunnel" : "Start tunnel"
        font.pointSize: Kirigami.Theme.defaultFont.pointSize + 1
        onClicked: brain.pressPower()
    }
}
