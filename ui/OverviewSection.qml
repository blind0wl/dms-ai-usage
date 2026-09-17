import QtQuick
import qs.Common
import qs.Widgets

// The Popout's first tab: one row per visible Source, ranked by Tightest Window
// so the scarcest budget is the top line (ADR 0003).
//
// It is a dumb repeater over `ctx.rows`. Every ranking rule and every degraded
// flag was already decided by `Sources.overviewRows`, and a row carries the
// label, Window, Utilisation and reset it draws, so nothing here reads the
// registry or compares one Source with another. A press on a row selects that
// Source's tab, where the Source's own Sections explain why it is there.
//
// The degraded rows mirror the rules the Source tab already follows. A Missing
// Source offers the sign-in its Login Section offers, in place of a bar it has
// no reading for, and the same Setup guide link, so a Source that needs an API
// key has its way out here and not only on its own tab. An Unavailable Source
// keeps its last known reading with the bar dimmed and marked stale, because a
// stale reading is still a reading.
Column {
    id: root

    // SourceTab supplies these two; everything else is derived, so the section
    // can be instantiated generically by type.
    property var ctx: null
    property var section: null

    readonly property var api: ctx ? ctx.api : null
    readonly property var rows: ctx && ctx.rows ? ctx.rows : []

    width: parent.width
    spacing: Theme.spacingXS

    // Which Window is tightest and when it resets. Both come from the row, and
    // neither exists before a reading arrives: an unranked row has no Tightest
    // Window to name.
    function windowLine(row) {
        if (!row.ranked)
            return "";
        var label = row.windowLabelKey
            ? root.api.tr(row.windowLabelKey)
            : root.api.windowLabelForLength(row.windowSeconds, row.window);
        var countdown = root.api.formatCountdown(row.resetMs);
        if (!countdown)
            return label;
        return label + " · " + root.api.tr("Resets in") + " " + countdown;
    }

    Repeater {
        model: root.rows

        delegate: StyledRect {
            id: row

            required property var modelData

            readonly property string sourceId: modelData.id
            readonly property bool missing: modelData.missing
            // The same sign-in the Login Section offers: a CLI Source gets its
            // button, a key-based one the Section's pointer to the settings.
            readonly property bool cliLogin: missing && modelData.loginKind === "cli"
            readonly property bool loggingIn: root.api.loginInProgress(sourceId)
            // Only a ranked row holds a reading it may show. A Missing row
            // never ranks, because the credential that produced its reading is
            // gone, while an Unavailable one still ranks on its last known value.
            readonly property bool showsReading: modelData.ranked
            // Clamped like the Ring's arc, so an over-quota reading cannot draw
            // a bar wider than its track.
            readonly property real fraction: Math.max(0, Math.min(modelData.util / 100, 1))

            width: root.width
            height: content.implicitHeight + Theme.spacingS * 2
            color: Theme.surfaceContainerHigh

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.api.selectTab(row.sourceId)
            }

            Column {
                id: content
                anchors.fill: parent
                anchors.margins: Theme.spacingS
                spacing: Theme.spacingXS

                Row {
                    width: parent.width
                    spacing: Theme.spacingXS

                    StyledText {
                        width: Math.max(0, parent.width - usage.width - parent.spacing)
                        text: root.api.tr(modelData.labelKey)
                        font.pixelSize: Theme.fontSizeSmall
                        font.weight: Font.Medium
                        color: Theme.surfaceText
                        wrapMode: Text.NoWrap
                        elide: Text.ElideRight
                    }

                    Row {
                        id: usage
                        spacing: Theme.spacingXXS

                        // "--" is the Pill's own word for a Source with no
                        // reading, rather than a zero the Source never reported.
                        StyledText {
                            text: row.showsReading ? Math.round(modelData.util) + "%" : "--"
                            font.pixelSize: Theme.fontSizeSmall
                            font.weight: Font.Medium
                            color: row.showsReading ? root.api.progressColor(modelData.util) : Theme.surfaceVariantText
                        }

                        StyledText {
                            visible: modelData.stale
                            text: root.api.tr("stale")
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.surfaceVariantText
                        }
                    }
                }

                // The bar, in the space a Missing row gives to its sign-in. An
                // Unavailable Source dims its whole bar, so a stale reading does
                // not read as a current one.
                Rectangle {
                    visible: !row.missing
                    width: parent.width
                    height: 4
                    radius: 2
                    color: Theme.surfaceVariant
                    opacity: modelData.stale ? 0.5 : 1

                    Rectangle {
                        width: parent.width * row.fraction
                        height: parent.height
                        radius: parent.radius
                        color: root.api.progressColor(modelData.util)
                    }
                }

                LoginButton {
                    visible: row.cliLogin
                    api: root.api
                    inProgress: row.loggingIn
                    // Runs the same login the Source tab's card runs, without
                    // sending the user to that tab first. The press is consumed
                    // here rather than selecting the row.
                    onClicked: root.api.startLogin(row.sourceId)
                }

                // A key-based Source has no flow to run, so it gets the Login
                // Section's explanation instead of a button.
                StyledText {
                    width: parent.width
                    visible: row.missing && !row.cliLogin
                    text: modelData.loginBodyKey ? root.api.tr(modelData.loginBodyKey) : ""
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceVariantText
                    wrapMode: Text.WordWrap
                }

                // The Login Section's way out, on the row that needs it. Only a
                // Missing row is being asked to go and set something up, so only
                // it asks the link to show.
                SetupGuideLink {
                    shown: row.missing
                    api: root.api
                    labelKey: modelData.labelKey
                }

                StyledText {
                    width: parent.width
                    visible: row.showsReading
                    text: root.windowLine(modelData)
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceVariantText
                    wrapMode: Text.WordWrap
                }
            }
        }
    }
}
