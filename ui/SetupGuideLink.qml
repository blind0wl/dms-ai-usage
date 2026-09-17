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
    // The caller's own intent to show, the way a Section declares its `shown`:
    // only a Source that needs setting up gets the way out. The component's own
    // half of that decision is the URL below.
    property bool shown: false

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
    // Both halves of the decision: the caller asked for it, and this Source has
    // a README section to point at. A name that produced no anchor draws no
    // link rather than one that opens "".
    visible: root.shown && root.docsUrl !== ""

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
