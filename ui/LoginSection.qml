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
// prose that explains a fix is not the same as being able to reach it. The link
// goes to the README section for this Source rather than the README root, so a
// missing Z.ai key lands on the Z.ai instructions.
StyledRect {
    id: root

    property var ctx: null
    property var section: null

    readonly property var source: ctx ? ctx.source : null
    readonly property var api: ctx ? ctx.api : null
    readonly property var login: ctx && ctx.descriptor ? ctx.descriptor.login : null
    readonly property bool inProgress: ctx ? ctx.loginInProgress === true : false

    // The README section for this Source. A Source's section is headed by its
    // name and the link's anchor is that heading's slug (pinned by
    // tests/test-setup-links.sh), so no Source is named here.
    //
    // Qt.openUrlExternally is the plugin's first and only URL-opening path, so
    // it was verified under the Quickshell runtime DMS loads this in before the
    // link came to rely on it.
    readonly property string readmeUrl: "https://github.com/blind0wl/dms-ai-usage"
    readonly property string docsUrl: ctx && ctx.descriptor
        ? readmeUrl + "#" + anchorFor(ctx.descriptor.labelKey)
        : ""

    // GitHub's heading slug: lowercase, keep word characters, hyphens and
    // spaces, then spaces to hyphens. `labelKey` rather than the Source's
    // translated label, because the README those headings live in is English,
    // so the anchor is the same in every locale.
    function anchorFor(name) {
        return name.toLowerCase().replace(/[^\w\- ]+/g, "").replace(/ /g, "-");
    }

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

            // Shown whenever the Source has a README section, which is every
            // Source: it supplements a cli login button rather than replacing
            // it, and it is the only way out for an API-key Source.
            Item {
                id: setupLinkRow
                // The label's own size, so the click area is the link and not
                // the whole column width.
                width: setupLink.implicitWidth
                height: setupLink.implicitHeight
                visible: root.docsUrl !== ""

                StyledText {
                    id: setupLink
                    text: api.tr("Setup guide")
                    font.pixelSize: Theme.fontSizeSmall
                    font.weight: Font.Medium
                    color: Theme.primary
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Qt.openUrlExternally(root.docsUrl)
                }
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
                onClicked: root.api.startLogin(root.ctx.source.id)
            }
        }
    }
}
