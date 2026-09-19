import QtQuick
import qs.Common
import qs.Widgets

// Token Consumption card: the period figures left-aligned, each a large value
// over its label and sub-line, then the all-time line at the foot.
//
// The columns are declared by the Source's descriptor rather than fixed here,
// because Sources report different periods in different units. Claude,
// ChatGPT and Z.ai show Today, Week and Month in tokens with a cost sub-line;
// ChatGPT keeps its session and message count beside them.
//
// A descriptor that carries a captionKey qualifies the card's figures with it,
// which is where the cost caveat (ADR 0006) lives: the figures are what the
// tokens would have cost at API rates, not what the subscription was paid.
//
// All-time session and message figures ride along here rather than in a card of
// their own, and hide until there is something to report. The widget zeroes them
// while a single Account is selected, since the figures are only tracked in
// aggregate.
StyledRect {
    id: root

    property var ctx: null
    property var section: null

    readonly property var source: ctx ? ctx.source : null
    readonly property var api: ctx ? ctx.api : null
    readonly property var columns: section && section.columns ? section.columns : []
    readonly property var alltime: source && source.alltime ? source.alltime : null
    readonly property bool hasAlltime: alltime !== null && (alltime.sessions > 0 || alltime.messages > 0)

    width: parent.width
    height: consumptionCol.implicitHeight + Theme.spacingS * 2
    color: Theme.surfaceContainerHigh

    function valueText(spec) {
        if (!spec || !root.source)
            return "";
        var raw = root.source[spec.key] || 0;
        if (spec.kind === "tokens")
            return api.formatTokens(raw);
        if (spec.kind === "cost")
            return raw > 0 ? api.formatCost(raw) : "";
        if (spec.kind === "count")
            return raw + " " + api.tr(spec.unitKey);
        return String(raw);
    }

    Column {
        id: consumptionCol
        anchors.fill: parent
        anchors.margins: Theme.spacingS
        spacing: Theme.spacingXS

        StyledText {
            text: api.tr("Token Consumption")
            font.pixelSize: Theme.fontSizeSmall
            font.weight: Font.Medium
            color: Theme.surfaceVariantText
        }

        // The notional-cost caveat a cost-bearing descriptor carries (ADR 0006).
        // A dollar figure on a subscription reads as an amount owed, so the
        // card says what the figure is before the figures themselves.
        StyledText {
            visible: root.section && root.section.captionKey !== undefined
            width: parent.width
            wrapMode: Text.WordWrap
            font.pixelSize: Theme.fontSizeSmall - 1
            color: Theme.surfaceVariantText
            text: root.section && root.section.captionKey ? root.api.tr(root.section.captionKey) : ""
        }

        // Left-aligned rather than centred columns: each figure is its value
        // over the label and sub-line that qualify it. The columns share the
        // card's width so a long token figure cannot push the row wider.
        Row {
            width: parent.width
            spacing: Theme.spacingS

            Repeater {
                model: root.columns
                delegate: Column {
                    required property var modelData
                    width: (parent.width - Math.max(root.columns.length - 1, 0) * Theme.spacingS) / Math.max(root.columns.length, 1)
                    spacing: 0

                    StyledText {
                        width: parent.width
                        text: root.valueText(modelData.value)
                        font.pixelSize: modelData.text ? Theme.fontSizeMedium : Theme.fontSizeLarge
                        font.weight: Font.Bold
                        color: modelData.accent ? Theme.primary : Theme.surfaceText
                        wrapMode: Text.NoWrap
                        elide: Text.ElideRight
                    }

                    StyledText {
                        width: parent.width
                        text: {
                            var sub = root.valueText(modelData.sub);
                            return root.api.tr(modelData.labelKey) + (sub ? "  " + sub : "");
                        }
                        font.pixelSize: Theme.fontSizeSmall - 1
                        color: Theme.surfaceVariantText
                        wrapMode: Text.WordWrap
                    }
                }
            }
        }

        StyledText {
            visible: root.hasAlltime
            width: parent.width
            wrapMode: Text.WordWrap
            font.pixelSize: Theme.fontSizeSmall - 1
            color: Theme.surfaceVariantText
            text: {
                if (!root.alltime)
                    return "";
                var parts = [];
                if (root.alltime.firstSession && root.alltime.firstSession !== "unknown")
                    parts.push(root.api.tr("Since") + " " + root.alltime.firstSession);
                parts.push(root.alltime.sessions + " " + root.api.tr("sessions"));
                parts.push(root.alltime.messages.toLocaleString() + " " + root.api.tr("msgs"));
                return parts.join(" · ");
            }
        }
    }
}
