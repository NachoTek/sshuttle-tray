pragma ComponentBehavior: Bound
import QtQuick
import org.kde.kirigami as Kirigami

MouseArea {
    id: compact
    property var brain

    hoverEnabled: true
    onClicked: compact.brain.expanded = !compact.brain.expanded

    readonly property color stateColor: {
        if (compact.brain.iconState === "off") return Kirigami.Theme.disabledTextColor
        if (compact.brain.iconState === "starting") return Kirigami.Theme.neutralTextColor
        if (compact.brain.iconState === "on") return Kirigami.Theme.positiveTextColor
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
            width: compact.brain.iconState === "off" ? parent.width * 0.25 : parent.width * 0.45
            height: width
            radius: width / 2
            color: compact.stateColor
            visible: compact.brain.iconState !== "alert"
        }
        Text {
            anchors.centerIn: parent
            visible: compact.brain.iconState === "alert"
            text: "!"
            color: compact.stateColor
            font.bold: true
            font.pixelSize: parent.height * 0.6
        }
        SequentialAnimation on opacity {
            running: compact.brain.iconState === "starting"
            loops: Animation.Infinite
            NumberAnimation { from: 1; to: 0.3; duration: 600 }
            NumberAnimation { from: 0.3; to: 1; duration: 600 }
        }
    }
}
