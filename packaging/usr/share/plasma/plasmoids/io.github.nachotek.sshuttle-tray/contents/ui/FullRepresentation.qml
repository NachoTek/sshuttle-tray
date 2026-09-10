pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PC3
import org.kde.kirigami as Kirigami

// The locked prototype design (Variant A): dark status hero. The header
// power icon is the sole tunnel toggle; the ring is display-only.
Rectangle {
    id: full
    property var brain

    readonly property color cText: "#F0F6FC"
    readonly property color cMuted: "#8B949E"
    readonly property color cCard: "#0D1117"
    readonly property color cBorder: "#21262D"

    readonly property color accent: {
        if (full.brain.iconState === "on") return "#00E5FF"
        if (full.brain.iconState === "starting") return "#DBAB0A"
        if (full.brain.iconState === "alert") return "#F85149"
        return "#484F58"
    }
    readonly property string glyph: {
        if (full.brain.iconState === "off") return "⏻"
        if (full.brain.iconState === "starting") return "…"
        if (full.brain.iconState === "on") return "✓"
        return "!"
    }
    readonly property string headline: {
        if (full.brain.iconState === "on") return "ON"
        if (full.brain.iconState === "starting") return "STARTING"
        if (full.brain.iconState === "alert") return "ALERT"
        return "OFF"
    }

    implicitWidth: 340
    implicitHeight: content.implicitHeight + 40
    radius: 16
    color: "#161B22"
    border.color: full.cBorder
    border.width: 1

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        onEntered: full.brain.hoverEntered()
        propagateComposedEvents: true
    }

    ColumnLayout {
        id: content
        anchors.fill: parent
        anchors.margins: 20
        spacing: Kirigami.Units.largeSpacing

        RowLayout {
            Layout.fillWidth: true
            PC3.Label {
                text: "sshuttle tunnel"
                color: full.cMuted
                font.pointSize: Kirigami.Theme.defaultFont.pointSize - 2
                font.letterSpacing: 1
            }
            Item { Layout.fillWidth: true }
            PC3.ToolButton {
                implicitWidth: 22
                implicitHeight: 22
                icon.name: "system-shutdown"
                icon.color: full.brain.tunnelActive ? "#F85149" : "#3FB950"
                PC3.ToolTip.text: full.brain.tunnelActive ? "Stop the Tunnel" : "Start the Tunnel"
                PC3.ToolTip.visible: hovered
                onClicked: full.brain.pressPower()
            }
            PC3.ToolButton {
                implicitWidth: 20
                implicitHeight: 20
                icon.name: "configure"
                PC3.ToolTip.text: "Settings"
                PC3.ToolTip.visible: hovered
                onClicked: {
                    const action = Plasmoid.internalAction("configure")
                    if (action) action.trigger()
                }
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
                color: full.accent
                opacity: full.brain.iconState === "on" ? 0.15 : 0
                Behavior on opacity { NumberAnimation { duration: 300 } }
            }
            Rectangle {
                id: ring
                anchors.fill: parent
                radius: 40
                color: Qt.rgba(0, 229/255, 1, full.brain.iconState === "on" ? 0.06 : 0)
                border.color: full.accent
                border.width: 3
                SequentialAnimation on opacity {
                    running: full.brain.iconState === "starting"
                    loops: Animation.Infinite
                    NumberAnimation { from: 1; to: 0.35; duration: 550 }
                    NumberAnimation { from: 0.35; to: 1; duration: 550 }
                }
            }
            Text {
                anchors.centerIn: parent
                text: full.glyph
                color: full.accent
                font.pixelSize: 34
                font.bold: true
            }
        }

        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            Layout.topMargin: 8
            spacing: 8
            PC3.Label {
                text: full.headline
                color: full.accent
                font.pixelSize: 24
                font.weight: Font.Black
                font.letterSpacing: 1.4
            }
            Rectangle {
                visible: full.brain.unverified
                radius: 4
                implicitHeight: unverifiedLabel.implicitHeight + 4
                implicitWidth: unverifiedLabel.implicitWidth + 8
                color: Qt.rgba(110/255, 118/255, 129/255, 0.15)
                PC3.Label {
                    id: unverifiedLabel
                    anchors.centerIn: parent
                    text: "UNVERIFIED"
                    color: full.cMuted
                    font.pixelSize: 9
                    font.bold: true
                    font.letterSpacing: 0.8
                }
            }
        }

        PC3.Label {
            Layout.alignment: Qt.AlignHCenter
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            text: full.brain.causeText
            color: full.cMuted
            font.pixelSize: 12
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.topMargin: 8
            visible: full.brain.restartToApply
            implicitHeight: restartRow.implicitHeight + 12
            radius: 8
            color: Qt.rgba(219/255, 171/255, 10/255, 0.12)
            border.color: "#DBAB0A"
            border.width: 1
            RowLayout {
                id: restartRow
                anchors.fill: parent
                anchors.margins: 6
                spacing: 8
                PC3.Label {
                    Layout.fillWidth: true
                    wrapMode: Text.Wrap
                    text: "Route Set changed — restart the Tunnel to apply it"
                    color: "#F2CC60"
                    font.pixelSize: 11
                }
                PC3.Button {
                    text: "Restart"
                    onClicked: full.brain.pressRestart()
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.topMargin: 8
            implicitHeight: card.implicitHeight + 28
            radius: 12
            color: full.cCard
            border.color: full.cBorder
            border.width: 1
            ColumnLayout {
                id: card
                anchors.fill: parent
                anchors.margins: 14
                spacing: 10

                RowLayout {
                    Layout.fillWidth: true
                    PC3.Label {
                        text: "GATEWAYS"
                        color: full.cMuted
                        font.pixelSize: 11
                        font.bold: true
                        font.letterSpacing: 1
                    }
                    Item { Layout.fillWidth: true }
                }

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 1
                    color: full.cBorder
                }

                RowLayout {
                    Layout.fillWidth: true
                    PC3.Label {
                        text: "LOCAL"
                        color: full.cMuted
                        font.pixelSize: 11
                    }
                    Item { Layout.fillWidth: true }
                    ColumnLayout {
                        spacing: 1
                        PC3.Label {
                            Layout.alignment: Qt.AlignRight
                            text: full.brain.freshness === "noans" ? "no answer"
                                : (full.brain.localGateway !== "" ? full.brain.localGateway : "…")
                            color: full.brain.freshness === "noans" || full.brain.freshness === "stale" ? full.cMuted : full.cText
                            opacity: full.brain.freshness === "stale" ? 0.55 : 1
                            font.family: "monospace"
                            font.pixelSize: 12
                            font.bold: true
                        }
                        PC3.Label {
                            Layout.alignment: Qt.AlignRight
                            visible: full.brain.localGatewayHost !== ""
                            text: full.brain.localGatewayHost
                            color: full.cMuted
                            font.pixelSize: 9
                        }
                    }
                    Rectangle {
                        radius: 4
                        implicitHeight: localChip.implicitHeight + 4
                        implicitWidth: localChip.implicitWidth + 8
                        color: {
                            if (full.brain.freshness === "noans" || full.brain.freshness === "none") return "#21262D"
                            if (full.brain.freshness === "stale") return Qt.rgba(219/255, 171/255, 10/255, 0.15)
                            return Qt.rgba(0, 229/255, 1, 0.12)
                        }
                        PC3.Label {
                            id: localChip
                            anchors.centerIn: parent
                            text: full.brain.freshness === "noans" ? "NO ANS"
                                : full.brain.freshness === "none" ? "…"
                                : full.brain.freshness === "stale" ? "STALE" : "LIVE"
                            color: full.brain.freshness === "stale" ? "#F2CC60"
                                : full.brain.freshness === "live" ? "#00E5FF" : full.cMuted
                            font.pixelSize: 9
                            font.bold: true
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 1
                    color: full.cBorder
                }

                RowLayout {
                    Layout.fillWidth: true
                    PC3.Label {
                        text: "REMOTE"
                        color: full.cMuted
                        font.pixelSize: 11
                    }
                    Item { Layout.fillWidth: true }
                    PC3.Label {
                        text: full.brain.remoteAlias !== "" ? full.brain.remoteAlias : "—"
                        color: full.cText
                        font.family: "monospace"
                        font.pixelSize: 12
                        font.bold: true
                    }
                }
            }
        }
    }
}
