import QtQuick
import qs.Common
import qs.Widgets

// The way out for a Source that needs setting up: a link into this plugin's
// README, at the section for that Source rather than at the README root, so a
// Missing Z.ai key lands on the Z.ai instructions.
//
// It goes to the README section for the Source rather than the README root, and
// a Source's section is headed by its name, so the link's anchor is that
// heading's slug (pinned by tests/test-setup-links.sh). No Source is named here.
//
// Qt.openUrlExternally is the plugin's first and only URL-opening path, so it was
// verified under the Quickshell runtime DMS loads this in before the link came to
// rely on it.
Item {
    id: root

    property var api: null
    // The descriptor's `labelKey`, so the anchor is built from the Source's own
    // name and a new Source needs nothing added here.
    property string labelKey: ""

    readonly property string readmeUrl: "https://github.com/blind0wl/dms-ai-usage"
    readonly property string docsUrl: root.labelKey !== "" ? root.readmeUrl + "#" + anchorFor(root.labelKey) : ""

    // GitHub's heading slug: lowercase, keep word characters, hyphens and
    // spaces, then spaces to hyphens. `labelKey` rather than the Source's
    // translated label, because the README those headings live in is English,
    // so the anchor is the same in every locale.
    function anchorFor(name) {
        return name.toLowerCase().replace(/[^\w\- ]+/g, "").replace(/ /g, "-");
    }

    // The label's own size, so the click area is the link and not the whole
    // column width.
    width: setupLink.implicitWidth
    height: setupLink.implicitHeight
    // Shown whenever the Source has a README section, which is every Source.
    // The Sections that render it narrow that further: only a Missing Source
    // needs the way out, so only its card and its Overview row show the link.
    visible: root.docsUrl !== ""

    StyledText {
        id: setupLink
        text: root.api.tr("Setup guide")
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
