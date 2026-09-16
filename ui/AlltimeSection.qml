import QtQuick
import qs.Common
import qs.Widgets

// All-time footer: when the record starts, and the running session and message
// counts. Hidden until there is something to report.
//
// The parent zeroes these counts while a single Account is selected, since the
// figures are only tracked in aggregate.
StyledRect {
    id: root

    property var ctx: null
    property var section: null

    readonly property var source: ctx ? ctx.source : null
    readonly property var api: ctx ? ctx.api : null

    readonly property var alltime: source && source.alltime ? source.alltime : ({
        sessions: 0,
        messages: 0,
        firstSession: ""
    })
    // The Section's own intent to show. The renderer reads this rather than
    // `visible`, which QML reports as false while an ancestor is hidden.
    readonly property bool shown: alltime.sessions > 0 || alltime.messages > 0

    width: parent.width
    height: allTimeRow.implicitHeight + Theme.spacingM * 2
    color: Theme.surfaceContainerHigh
    visible: shown

    Row {
        id: allTimeRow
        anchors.fill: parent
        anchors.margins: Theme.spacingM
        spacing: Theme.spacingS

        DankIcon {
            id: allTimeIcon
            name: "calendar_today"
            size: 14
            color: Theme.surfaceVariantText
            anchors.verticalCenter: parent.verticalCenter
        }

        StyledText {
            width: Math.max(0, parent.width - allTimeIcon.width - parent.spacing)
            text: {
                var parts = [];
                if (root.alltime.firstSession && root.alltime.firstSession !== "unknown")
                    parts.push(root.api.tr("Since") + " " + root.alltime.firstSession);
                parts.push(root.alltime.sessions + " " + root.api.tr("sessions"));
                parts.push(root.alltime.messages.toLocaleString() + " " + root.api.tr("msgs"));
                return parts.join("  ·  ");
            }
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.surfaceVariantText
            wrapMode: Text.WordWrap
            anchors.verticalCenter: parent.verticalCenter
        }
    }
}
