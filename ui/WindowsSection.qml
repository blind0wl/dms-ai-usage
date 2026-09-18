import QtQuick
import qs.Common
import qs.Widgets

// One rate Window card holding both of a Source's Windows as bar rows in the
// Overview's style: the Window's label, its Utilisation as a percentage, a bar
// with a pace tick at the linear-burn position, and a line naming its pacing and
// reset countdown. `counts` also carries the week's session and message counts
// on the secondary row.
//
// The popout has no Ring: the Ring is the Pill's, and a Window here is a bar.
StyledRect {
    id: root

    // SourceTab supplies these two; everything else is derived, so the section
    // can be instantiated generically by type.
    property var ctx: null
    property var section: null

    readonly property var source: ctx ? ctx.source : null
    readonly property string sourceId: ctx ? ctx.sourceId : ""
    readonly property var api: ctx ? ctx.api : null
    readonly property bool showPacing: ctx ? ctx.showPacing : true
    readonly property bool showCounts: section ? section.counts === true : false

    // An endpoint failure with no last good reading has nothing to fall back
    // on, so the card is dropped rather than drawing a fabricated zero. With a
    // reading to fall back on the card stays, flagged stale by the status card
    // that sits above it. Before the first reading there is no Source state to
    // draw from, so the card waits rather than showing an empty shell.
    readonly property bool noFallback: source && source.credsStatus === "unavailable" && source.hasData !== true
    // The Section's own intent to show. The renderer reads this rather than
    // `visible`, which QML reports as false while an ancestor is hidden.
    readonly property bool shown: source !== null && !noFallback

    width: parent.width
    visible: shown
    height: card.implicitHeight + Theme.spacingS * 2
    color: Theme.surfaceContainerHigh

    Column {
        id: card
        anchors.fill: parent
        anchors.margins: Theme.spacingS
        spacing: Theme.spacingXS

        Repeater {
            model: ["primary", "secondary"]

            delegate: Column {
                id: row
                required property string modelData

                readonly property var win: root.source && root.source[modelData] ? root.source[modelData] : null
                readonly property real util: win && win.util !== undefined ? win.util : 0
                readonly property var pace: root.api.pace(root.source, modelData)
                readonly property string countdown: root.api.countdown(root.source, modelData)
                readonly property string pacing: root.showPacing ? root.api.paceLabel(pace) : ""
                readonly property string counts: {
                    if (modelData !== "secondary" || !root.showCounts || !root.source)
                        return "";
                    var parts = [];
                    if (root.source.weekSessions > 0)
                        parts.push(root.source.weekSessions + " " + root.api.tr("sessions"));
                    if (root.source.weekMessages > 0)
                        parts.push(root.source.weekMessages + " " + root.api.tr("msgs"));
                    return parts.join(" · ");
                }

                visible: win !== null
                width: card.width
                spacing: Theme.spacingXS

                Row {
                    width: parent.width
                    spacing: Theme.spacingXS

                    StyledText {
                        width: Math.max(0, parent.width - pct.width - parent.spacing)
                        text: root.api.windowLabel(root.source, row.modelData)
                        font.pixelSize: Theme.fontSizeSmall
                        font.weight: Font.Medium
                        color: Theme.surfaceText
                        wrapMode: Text.NoWrap
                        elide: Text.ElideRight
                    }

                    StyledText {
                        id: pct
                        text: Math.round(row.util) + "%"
                        font.pixelSize: Theme.fontSizeSmall
                        font.weight: Font.Medium
                        color: root.api.utilisationColor(root.sourceId, row.util)
                    }
                }

                // The bar, with a pace tick at the linear-burn position. The
                // fill is clamped like the Ring's arc, so an over-quota reading
                // cannot draw a bar wider than its track.
                Item {
                    width: parent.width
                    height: 6

                    Rectangle {
                        anchors.fill: parent
                        radius: height / 2
                        color: Theme.surfaceVariant
                    }

                    Rectangle {
                        width: parent.width * Math.max(0, Math.min(row.util / 100, 1))
                        height: parent.height
                        radius: height / 2
                        color: root.api.utilisationColor(root.sourceId, row.util)
                    }

                    Rectangle {
                        visible: root.showPacing && row.pace && row.pace.status !== "unknown"
                        x: parent.width * Math.max(0, Math.min(row.pace ? row.pace.timeFrac : 0, 1)) - 1
                        y: -3
                        width: 2
                        height: parent.height + 6
                        color: Theme.surfaceText
                    }
                }

                StyledText {
                    width: parent.width
                    wrapMode: Text.WordWrap
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceVariantText
                    text: {
                        var parts = [];
                        if (row.pacing)
                            parts.push(row.pacing);
                        if (row.counts)
                            parts.push(row.counts);
                        if (row.countdown)
                            parts.push(root.api.tr("Resets in") + " " + row.countdown);
                        return parts.join(" · ");
                    }
                }
            }
        }
    }
}
