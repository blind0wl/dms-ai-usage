import QtQuick
import qs.Common
import qs.Widgets

// Credentials card, shown in place of silently sitting at 0% whenever a Source's
// credentials are missing or expired.
//
// "cli" Sources offer a button that runs the CLI's own login flow. "text"
// Sources can only explain the fix, because there is no CLI to shell out to and
// the fix is an API key in the plugin settings.
//
// Both kinds also offer a Setup guide link into the plugin's README, because
// prose that explains a fix is not the same as being able to reach it.
//
// The button and the link are shared components, not this card's own: a Missing
// Source is met on its own tab and on the Overview, and both places draw the
// same sign-in (ui/LoginButton.qml) and the same way out (ui/SetupGuideLink.qml).
StyledRect {
    id: root

    property var ctx: null
    property var section: null

    readonly property var source: ctx ? ctx.source : null
    readonly property var api: ctx ? ctx.api : null
    readonly property var login: ctx && ctx.descriptor ? ctx.descriptor.login : null
    readonly property bool inProgress: ctx ? ctx.loginInProgress === true : false

    // The README section this Source's Setup guide link opens is the slug of its
    // name, which is the descriptor's labelKey.
    readonly property string labelKey: ctx && ctx.descriptor ? ctx.descriptor.labelKey : ""

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
    height: content.implicitHeight + Theme.spacingS * 2
    color: Theme.surfaceContainerHigh
    border.width: 1
    border.color: Theme.error || Theme.primary

    Row {
        id: content
        anchors.fill: parent
        anchors.margins: Theme.spacingS
        spacing: Theme.spacingS

        Column {
            width: root.isCli ? parent.width - loginButton.width - parent.spacing : parent.width
            anchors.verticalCenter: parent.verticalCenter
            spacing: Theme.spacingXXS

            StyledText {
                width: parent.width
                text: root.title
                font.pixelSize: Theme.fontSizeSmall
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

            // Supplements a cli login button rather than replacing it, and is the
            // only way out for an API-key Source.
            SetupGuideLink {
                api: root.api
                labelKey: root.labelKey
            }
        }

        LoginButton {
            id: loginButton
            visible: root.isCli
            anchors.verticalCenter: parent.verticalCenter
            api: root.api
            inProgress: root.inProgress
            onClicked: root.api.startLogin(root.ctx.source.id)
        }
    }
}
