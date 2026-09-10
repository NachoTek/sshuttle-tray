import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PC3
import org.kde.kirigami as Kirigami

Rectangle {
    id: va
    property var brain

    radius: Kirigami.Units.largeSpacing
    color: "#161B22"
    border.color: "#21262D"
    border.width: 1
    implicitHeight: content.implicitHeight + Kirigami.Units.largeSpacing * 2
    Layout.fillWidth: true

    readonly property color cText: "#F0F6FC"
    readonly property color cMuted: "#8B949E"
    readonly property color cCard: "#0D1117"
    readonly property color cBorder: "#21262D"
    readonly property color accent: {
        if (brain.state === "on") return "#00E5FF"
        if (brain.state === "starting") return "#DBAB0A"
        if (brain.state === "alert") return "#F85149"
        return "#484F58"
    }
    readonly property string glyph: {
        if (brain.state === "off") return "⏻"
        if (brain.state === "starting") return "…"
        if (brain.state === "on") return "✓"
        return "!"
    }
    readonly property string headline: {
        if (brain.state === "on") return "ON"
        if (brain.state === "starting") return "CONNECTING"
        if (brain.state === "alert") return "ALERT"
        return "OFF"
    }
    readonly property string caption: {
        if (brain.state === "on") return "Traffic routed through the tunnel"
        if (brain.state === "off") return "Tunnel is off — click the ring to start"
        return brain.stateCause
    }
    readonly property var pill: {
        if (brain.noAnswer) return { text: "NO ANSWER", fill: Qt.rgba(110/255,118/255,129/255,0.15), fg: "#8B949E" }
        if (brain.stale) return { text: "STALE", fill: Qt.rgba(219/255,171/255,10/255,0.15), fg: "#F2CC60" }
        if (brain.state === "on") return { text: "PROTECTED", fill: Qt.rgba(46/255,160/255,67/255,0.15), fg: "#3FB950" }
        if (brain.state === "starting") return { text: "ESTABLISHING", fill: Qt.rgba(219/255,171/255,10/255,0.15), fg: "#F2CC60" }
        if (brain.state === "alert") return { text: "DEGRADED", fill: Qt.rgba(248/255,81/255,73/255,0.15), fg: "#FF7B72" }
        return { text: "UNPROTECTED", fill: Qt.rgba(110/255,118/255,129/255,0.15), fg: "#8B949E" }
    }

    ColumnLayout {
        id: content
        anchors.fill: parent
        anchors.margins: Kirigami.Units.largeSpacing
        spacing: Kirigami.Units.largeSpacing

        RowLayout {
            Layout.fillWidth: true
            PC3.Label {
                text: "office tunnel"
                color: va.cMuted
                font.pointSize: Kirigami.Theme.defaultFont.pointSize - 2
                font.letterSpacing: 1
            }
            Item { Layout.fillWidth: true }
            PC3.ToolButton {
                implicitWidth: 20
                implicitHeight: 20
                icon.name: "configure"
                PC3.ToolTip.text: "settings — not in prototype"
                PC3.ToolTip.visible: hovered
            }
        }

        Item {
            Layout.alignment: Qt.AlignHCenter
            implicitWidth: 84
            implicitHeight: 84
            MouseArea {
                id: ringClick
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: brain.pressPower()
            }
            Rectangle {
                id: halo
                anchors.centerIn: parent
                width: 112
                height: 112
                radius: 56
                color: va.accent
                opacity: brain.state === "on" ? 0.18 : 0
                Behavior on opacity { NumberAnimation { duration: 300 } }
            }
            Rectangle {
                id: ring
                anchors.fill: parent
                radius: 42
                color: "transparent"
                border.color: va.accent
                border.width: 3
                SequentialAnimation on opacity {
                    running: brain.state === "starting"
                    loops: Animation.Infinite
                    NumberAnimation { from: 1; to: 0.35; duration: 550 }
                    NumberAnimation { from: 0.35; to: 1; duration: 550 }
                }
            }
            Text {
                anchors.centerIn: parent
                text: va.glyph
                color: va.accent
                font.pixelSize: 34
                font.bold: true
            }
        }

        PC3.Label {
            Layout.alignment: Qt.AlignHCenter
            text: va.headline
            color: va.accent
            font.pixelSize: 24
            font.bold: true
            font.letterSpacing: 1.2
        }

        PC3.Label {
            Layout.alignment: Qt.AlignHCenter
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            text: va.caption
            color: va.cMuted
            font.pixelSize: 13
        }

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: card.implicitHeight + Kirigami.Units.largeSpacing * 2
            radius: Kirigami.Units.smallSpacing + 2
            color: va.cCard
            border.color: va.cBorder
            border.width: 1
            ColumnLayout {
                id: card
                anchors.fill: parent
                anchors.margins: Kirigami.Units.largeSpacing
                spacing: Kirigami.Units.smallSpacing

                RowLayout {
                    Layout.fillWidth: true
                    PC3.Label {
                        text: "GATEWAY ROUTING"
                        color: va.cMuted
                        font.pixelSize: 12
                        font.bold: true
                        font.letterSpacing: 1
                    }
                    Item { Layout.fillWidth: true }
                    Rectangle {
                        radius: height / 2
                        implicitHeight: pillText.implicitHeight + 6
                        implicitWidth: pillText.implicitWidth + 12
                        color: va.pill.fill
                        PC3.Label {
                            id: pillText
                            anchors.centerIn: parent
                            text: va.pill.text
                            color: va.pill.fg
                            font.pixelSize: 10
                            font.bold: true
                            font.letterSpacing: 0.8
                        }
                    }
                }

                GridLayout {
                    Layout.fillWidth: true
                    columns: 2
                    columnSpacing: Kirigami.Units.smallSpacing
                    rowSpacing: 2
                    PC3.Label {
                        text: "VPN GATEWAY"
                        color: va.cMuted
                        font.pixelSize: 12
                    }
                    PC3.Label {
                        Layout.alignment: Qt.AlignRight
                        text: brain.state === "alert" ? "DOWN" : (brain.state === "starting" ? "CHECKING" : "REACHABLE")
                        color: brain.state === "alert" ? "#FF7B72" : (brain.state === "on" ? "#3FB950" : va.cMuted)
                        font.pixelSize: 10
                        font.bold: true
                    }
                    PC3.Label {
                        Layout.columnSpan: 2
                        text: brain.relayIP
                        color: va.cText
                        font.family: "monospace"
                        font.pixelSize: 13
                        font.bold: true
                    }
                    PC3.Label {
                        text: "ISP GATEWAY"
                        color: va.cMuted
                        font.pixelSize: 12
                        Layout.topMargin: Kirigami.Units.smallSpacing
                    }
                    PC3.Label {
                        Layout.alignment: Qt.AlignRight
                        Layout.topMargin: Kirigami.Units.smallSpacing
                        text: "DEFAULT"
                        color: va.cMuted
                        font.pixelSize: 10
                        font.bold: true
                    }
                    PC3.Label {
                        Layout.columnSpan: 2
                        text: brain.ispGateway
                        color: va.cText
                        font.family: "monospace"
                        font.pixelSize: 13
                        font.bold: true
                    }
                }
            }
        }
    }
}
