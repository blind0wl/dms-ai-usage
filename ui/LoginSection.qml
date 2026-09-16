import QtQuick
import qs.Common
import qs.Widgets

// Credentials card, shown in place of silently sitting at 0% whenever a Source's
// credentials are missing or expired.
//
// "cli" Sources offer a button that runs the CLI's own login flow.
// "text" Sources only explain the fix, because there is no CLI to shell out to
// and the fix is an API key in the plugin settings.
StyledRect {
    id: root

    property var ctx: null
    property var section: null

    readonly property var source: ctx ? ctx.source : null
    readonly property var api: ctx ? ctx.api : null
    readonly property var login: ctx && ctx.descriptor ? ctx.descriptor.login : null
    readonly property bool inProgress: ctx ? ctx.loginInProgress === true : false

    readonly property bool missing: source && source.credsStatus === "missing"
    readonly property bool expired: source && source.credsStatus === "expired"
    readonly property bool isCli: login && login.kind === "cli"
    // The Section's own intent to show. The renderer reads this rather than
    // `visible`, which QML reports as false while an ancestor is hidden.
    readonly property bool shown: missing || expired
    readonly property string title: {
        if (isCli)
            return missing ? api.tr("Not logged in") : api.tr("Session expired");
        return missing ? api.tr(login.titleKey) : api.tr("Session expired");
    }
    readonly property string body: {
        if (isCli)
            return api.tr("Usage data unavailable until you log in.");
        return missing ? api.tr(login.bodyKey) : api.tr("Usage data unavailable until you log in.");
    }

    width: parent.width
    visible: shown
    height: content.implicitHeight + Theme.spacingM * 2
    color: Theme.surfaceContainerHigh
    border.width: 1
    border.color: Theme.error || Theme.primary

    Row {
        id: content
        anchors.fill: parent
        anchors.margins: Theme.spacingM
        spacing: Theme.spacingM

        Column {
            width: root.isCli ? parent.width - loginButton.width - parent.spacing : parent.width
            anchors.verticalCenter: parent.verticalCenter
            spacing: Theme.spacingXS

            StyledText {
                width: parent.width
                text: root.title
                font.pixelSize: Theme.fontSizeMedium
                font.weight: Font.Medium
                color: Theme.surfaceText
                wrapMode: Text.WordWrap
            }

            StyledText {
                width: parent.width
                text: root.body
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceVariantText
                wrapMode: Text.WordWrap
            }
        }

        Rectangle {
            id: loginButton
            visible: root.isCli
            width: loginButtonLabel.implicitWidth + Theme.spacingM * 2
            height: 32
            radius: 16
            anchors.verticalCenter: parent.verticalCenter
            color: Theme.primary
            opacity: root.inProgress ? 0.6 : 1

            StyledText {
                id: loginButtonLabel
                anchors.centerIn: parent
                text: root.inProgress ? api.tr("Logging in…") : api.tr("Log in")
                font.pixelSize: Theme.fontSizeSmall
                font.weight: Font.Medium
                color: Theme.primaryText
            }

            MouseArea {
                anchors.fill: parent
                enabled: !root.inProgress
                cursorShape: Qt.PointingHandCursor
                onClicked: root.api.startLogin(root.login.action)
            }
        }
    }
}
