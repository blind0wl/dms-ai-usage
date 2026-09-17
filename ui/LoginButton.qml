import QtQuick
import qs.Common
import qs.Widgets

// The sign-in a Missing Source offers, wherever it is offered.
//
// A Source without credentials is met in two places: its own tab's Login
// Section, and its Overview row. Both draw this button rather than each drawing
// their own, so its geometry, its progress copy and its MouseArea exist once.
// What a press runs is the call site's business: each Section knows which Source
// it is drawing, so each connects `clicked` to that Source's login.
Rectangle {
    id: root

    property var api: null
    property bool inProgress: false

    signal clicked

    width: loginButtonLabel.implicitWidth + Theme.spacingS * 2
    height: 32
    radius: 16
    color: Theme.primary
    opacity: root.inProgress ? 0.6 : 1

    StyledText {
        id: loginButtonLabel
        anchors.centerIn: parent
        text: root.inProgress ? root.api.tr("Logging in…") : root.api.tr("Log in")
        font.pixelSize: Theme.fontSizeSmall
        font.weight: Font.Medium
        color: Theme.primaryText
    }

    MouseArea {
        anchors.fill: parent
        enabled: !root.inProgress
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
