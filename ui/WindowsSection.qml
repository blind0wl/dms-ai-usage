import QtQuick
import qs.Common
import qs.Widgets

// One rate Window card: ring, utilisation, pacing line and countdown.
// `compact` is the smaller secondary-Window card: a 56px ring, a title carrying
// the percentage, and small type throughout.
//
// The ring is what the card's height is made of, so the compaction carries a
// smaller one rather than only a smaller inset around it.
StyledRect {
    id: root

    // SourceTab supplies these two; everything else is derived, so the section
    // can be instantiated generically by type.
    property var ctx: null
    property var section: null

    readonly property var source: ctx ? ctx.source : null
    readonly property var api: ctx ? ctx.api : null
    readonly property bool showPacing: ctx ? ctx.showPacing : true
    readonly property string which: section && section.which ? section.which : "primary"
    readonly property bool compact: which === "secondary"
    readonly property bool showCounts: section && section.counts === true
    readonly property string label: section && section.labelKey ? api.tr(section.labelKey) : api.windowLabel(source, which)

    readonly property var win: source && source[which] ? source[which] : null
    readonly property real util: win && win.util !== undefined ? win.util : 0
    readonly property var pace: api.pace(source, which)
    readonly property string countdown: api.countdown(source, which)
    readonly property string title: compact ? label + " · " + Math.round(util) + "%" : label

    // An endpoint failure with no last good reading has nothing to fall back
    // on, so the card is dropped rather than drawing a fabricated zero. With a
    // reading to fall back on the card stays, flagged stale by the status card
    // that sits above it.
    readonly property bool noFallback: source && source.credsStatus === "unavailable" && source.hasData !== true
    // The Section's own intent to show. The renderer reads this rather than
    // `visible`, which QML reports as false while an ancestor is hidden.
    readonly property bool shown: !noFallback

    width: parent.width
    visible: shown
    height: content.implicitHeight + Theme.spacingS * 2
    color: Theme.surfaceContainerHigh

    Row {
        id: content
        anchors.fill: parent
        anchors.margins: Theme.spacingS
        spacing: Theme.spacingS

        Ring {
            id: winRing
            width: root.compact ? 56 : 84
            height: width
            anchors.verticalCenter: parent.verticalCenter
            percent: root.util
            pace: root.pace
            showPaceTick: root.showPacing
            ringRadius: root.compact ? 21 : 32
            ringWidth: root.compact ? 5 : 7

            StyledText {
                anchors.centerIn: parent
                text: Math.round(root.util) + "%"
                font.pixelSize: root.compact ? Theme.fontSizeSmall : Theme.fontSizeLarge
                font.weight: Font.DemiBold
                color: Theme.surfaceText
            }
        }

        Column {
            width: Math.max(0, parent.width - winRing.width - parent.spacing)
            anchors.verticalCenter: parent.verticalCenter
            spacing: root.compact ? Theme.spacingXXS : Theme.spacingXS

            StyledText {
                width: parent.width
                text: root.title
                font.pixelSize: Theme.fontSizeSmall
                font.weight: Font.Medium
                color: Theme.surfaceText
                wrapMode: Text.WordWrap
            }

            // The secondary card shows the percentage in its title instead.
            StyledText {
                width: parent.width
                visible: !root.compact
                text: Math.round(root.util) + "% " + api.tr("used")
                font.pixelSize: Theme.fontSizeSmall
                color: api.progressColor(root.util)
                wrapMode: Text.WordWrap
            }

            StyledText {
                width: parent.width
                text: api.paceLabel(root.pace)
                visible: root.showPacing && text !== ""
                font.pixelSize: Theme.fontSizeSmall
                color: api.paceColor(root.pace ? root.pace.status : "")
                wrapMode: Text.WordWrap
            }

            StyledText {
                width: parent.width
                visible: root.showCounts && text !== ""
                text: {
                    var parts = [];
                    if (root.source && root.source.weekSessions > 0)
                        parts.push(root.source.weekSessions + " " + api.tr("sessions"));
                    if (root.source && root.source.weekMessages > 0)
                        parts.push(root.source.weekMessages + " " + api.tr("msgs"));
                    return parts.join(" · ");
                }
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceVariantText
                wrapMode: Text.WordWrap
            }

            StyledText {
                width: parent.width
                text: root.countdown ? api.tr("Resets in") + " " + root.countdown : ""
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceVariantText
                visible: root.countdown !== ""
                wrapMode: Text.WordWrap
            }
        }
    }
}
