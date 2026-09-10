import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PC3
import org.kde.kirigami as Kirigami

Rectangle {
    id: va
    property var brain

    radius: 16
    color: "#161B22"
    border.color: "#21262D"
    border.width: 1
    implicitHeight: content.implicitHeight + 40
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
        if (brain.state === "starting") return "STARTING"
        if (brain.state === "alert") return "ALERT"
        return "OFF"
    }
    readonly property string caption: {
        if (brain.state === "on") return "Routed traffic travels through the tunnel"
        if (brain.state === "off") return "Tunnel is off — use the power button above"
        return brain.stateCause
    }
    readonly property var pill: {
        if (brain.noAnswer) return { text: "NO ANSWER", fill: Qt.rgba(110/255,118/255,129/255,0.15), fg: "#8B949E" }
        if (brain.stale) return { text: "STALE", fill: Qt.rgba(219/255,171/255,10/255,0.15), fg: "#F2CC60" }
        if (brain.state === "on") return { text: "ENCRYPTED", fill: Qt.rgba(46/255,160/255,67/255,0.15), fg: "#3FB950" }
        if (brain.state === "starting") return { text: "ESTABLISHING", fill: Qt.rgba(219/255,171/255,10/255,0.15), fg: "#F2CC60" }
        if (brain.state === "alert") return { text: "DEGRADED", fill: Qt.rgba(248/255,81/255,73/255,0.15), fg: "#FF7B72" }
        return { text: "UNENCRYPTED", fill: Qt.rgba(110/255,118/255,129/255,0.15), fg: "#8B949E" }
    }

    ColumnLayout {
        id: content
        anchors.fill: parent
        anchors.margins: 20
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
                implicitWidth: 22
                implicitHeight: 22
                icon.name: "system-shutdown"
                icon.color: brain.svcActive ? "#F85149" : "#3FB950"
                PC3.ToolTip.text: brain.svcActive ? "Stop the tunnel" : "Start the tunnel"
                PC3.ToolTip.visible: hovered
                onClicked: brain.pressPower()
            }
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
            Layout.topMargin: 4
            implicitWidth: 80
            implicitHeight: 80
            Rectangle {
                id: halo
                anchors.centerIn: parent
                width: 108
                height: 108
                radius: 54
                color: va.accent
                opacity: brain.state === "on" ? 0.15 : 0
                Behavior on opacity { NumberAnimation { duration: 300 } }
            }
            Rectangle {
                id: ring
                anchors.fill: parent
                radius: 40
                color: Qt.rgba(0, 229/255, 1, brain.state === "on" ? 0.06 : 0)
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
            Layout.topMargin: 8
            text: va.headline
            color: va.accent
            font.pixelSize: 24
            font.weight: Font.Black
            font.letterSpacing: 1.4
        }

        PC3.Label {
            Layout.alignment: Qt.AlignHCenter
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            text: va.caption
            color: va.cMuted
            font.pixelSize: 12
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.topMargin: 8
            implicitHeight: card.implicitHeight + 28
            radius: 12
            color: va.cCard
            border.color: va.cBorder
            border.width: 1
            ColumnLayout {
                id: card
                anchors.fill: parent
                anchors.margins: 14
                spacing: 10

                RowLayout {
                    Layout.fillWidth: true
                    PC3.Label {
                        text: "CURRENT NETWORK"
                        color: va.cMuted
                        font.pixelSize: 11
                        font.bold: true
                        font.letterSpacing: 1
                    }
                    Item { Layout.fillWidth: true }
                    RowLayout {
                        spacing: 5
                        Rectangle {
                            implicitWidth: 6
                            implicitHeight: 6
                            radius: 3
                            color: va.pill.fg
                        }
                        PC3.Label {
                            text: va.pill.text
                            color: va.pill.fg
                            font.pixelSize: 10
                            font.bold: true
                            font.letterSpacing: 0.8
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 1
                    color: va.cBorder
                }

                RowLayout {
                    Layout.fillWidth: true
                    PC3.Label {
                        text: "LOCAL GATEWAY"
                        color: va.cMuted
                        font.pixelSize: 11
                    }
                    Item { Layout.fillWidth: true }
                    RowLayout {
                        spacing: 6
                        PC3.Label {
                            text: brain.noAnswer ? "no answer" : (brain.gatewayIP || "…")
                            color: brain.noAnswer || brain.stale ? va.cMuted : va.cText
                            opacity: brain.stale ? 0.55 : 1
                            font.family: "monospace"
                            font.pixelSize: 12
                            font.bold: true
                        }
                        Rectangle {
                            radius: 4
                            implicitHeight: localChip.implicitHeight + 4
                            implicitWidth: localChip.implicitWidth + 8
                            color: {
                                if (brain.noAnswer) return "#21262D"
                                if (brain.stale) return Qt.rgba(219/255,171/255,10/255,0.15)
                                return brain.haveSample ? Qt.rgba(0, 229/255, 1, 0.12) : "#21262D"
                            }
                            PC3.Label {
                                id: localChip
                                anchors.centerIn: parent
                                text: brain.noAnswer ? "NO ANS" : (brain.haveSample ? (brain.stale ? "STALE" : "LIVE") : "…")
                                color: brain.noAnswer ? va.cMuted : (brain.stale ? "#F2CC60" : "#00E5FF")
                                font.pixelSize: 9
                                font.bold: true
                            }
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    PC3.Label {
                        text: "REMOTE GATEWAY"
                        color: va.cMuted
                        font.pixelSize: 11
                    }
                    Item { Layout.fillWidth: true }
                    RowLayout {
                        spacing: 6
                        PC3.Label {
                            text: brain.relayIP
                            color: va.cText
                            font.family: "monospace"
                            font.pixelSize: 12
                            font.bold: true
                        }
                        Rectangle {
                            radius: 4
                            implicitHeight: remoteChip.implicitHeight + 4
                            implicitWidth: remoteChip.implicitWidth + 8
                            color: {
                                if (brain.state === "on") return Qt.rgba(0, 229/255, 1, 0.12)
                                if (brain.state === "alert") return Qt.rgba(248/255,81/255,73/255,0.15)
                                return "#21262D"
                            }
                            PC3.Label {
                                id: remoteChip
                                anchors.centerIn: parent
                                text: brain.state === "on" ? "ACTIVE" : (brain.state === "alert" ? "DOWN" : "OFF")
                                color: brain.state === "on" ? "#00E5FF" : (brain.state === "alert" ? "#FF7B72" : va.cMuted)
                                font.pixelSize: 9
                                font.bold: true
                            }
                        }
                    }
                }
            }
        }
    }
}
