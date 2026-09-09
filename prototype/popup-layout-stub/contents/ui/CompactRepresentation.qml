import QtQuick
import org.kde.plasma.plasmoid
import org.kde.kirigami as Kirigami

MouseArea {
    id: compact
    property var brain

    hoverEnabled: true
    onClicked: Plasmoid.expanded = !Plasmoid.expanded

    readonly property color stateColor: {
        if (brain.state === "off") return Kirigami.Theme.disabledTextColor
        if (brain.state === "starting") return Kirigami.Theme.neutralTextColor
        if (brain.state === "on") return Kirigami.Theme.positiveTextColor
        return Kirigami.Theme.negativeTextColor
    }

    Rectangle {
        anchors.centerIn: parent
        width: Math.min(parent.width, parent.height) * 0.75
        height: width
        radius: width / 2
        color: "transparent"
        border.color: compact.stateColor
        border.width: 2
        Rectangle {
            anchors.centerIn: parent
            width: brain.state === "off" ? parent.width * 0.25 : parent.width * 0.45
            height: width
            radius: width / 2
            color: compact.stateColor
            visible: brain.state !== "alert"
        }
        Text {
            anchors.centerIn: parent
            visible: brain.state === "alert"
            text: "!"
            color: compact.stateColor
            font.bold: true
            font.pixelSize: parent.height * 0.6
        }
        SequentialAnimation on opacity {
            running: brain.state === "starting"
            loops: Animation.Infinite
            NumberAnimation { from: 1; to: 0.3; duration: 600 }
            NumberAnimation { from: 0.3; to: 1; duration: 600 }
        }
    }
}
