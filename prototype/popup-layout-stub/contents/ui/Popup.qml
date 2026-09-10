import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PC3
import org.kde.kirigami as Kirigami

ColumnLayout {
    id: popup
    property var brain

    Layout.preferredWidth: brain.variant === "A" ? 340 : Kirigami.Units.gridUnit * 19
    Layout.preferredHeight: implicitHeight + Kirigami.Units.largeSpacing
    spacing: Kirigami.Units.smallSpacing

    VariantA { brain: popup.brain; visible: brain.variant === "A"; Layout.fillWidth: true }
    VariantB { brain: popup.brain; visible: brain.variant === "B"; Layout.fillWidth: true }
    VariantC { brain: popup.brain; visible: brain.variant === "C"; Layout.fillWidth: true }

    FooterBar { brain: popup.brain; Layout.fillWidth: true }

    onVisibleChanged: if (visible) brain.openedPopup()
}
