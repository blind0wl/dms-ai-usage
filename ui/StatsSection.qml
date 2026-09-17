import QtQuick
import qs.Common
import qs.Widgets

// Token Consumption card: one column per period, each with an optional sub-line.
//
// The columns are declared by the Source's descriptor rather than fixed here,
// because Sources report different periods in different units. Claude shows
// Today, Week and Month in tokens with a cost sub-line, while ChatGPT and Z.ai
// show Week and Month in tokens with a call or session count beside them.
StyledRect {
    id: root

    property var ctx: null
    property var section: null

    readonly property var source: ctx ? ctx.source : null
    readonly property var api: ctx ? ctx.api : null
    readonly property var columns: section && section.columns ? section.columns : []

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
            return api.formatCost(raw);
        if (spec.kind === "count")
            return raw + " " + api.tr(spec.unitKey);
        return String(raw);
    }

    // Cost sub-lines stay hidden at zero so an unpriced Source does not read as
    // a real $0.00; count sub-lines always show, because zero msgs is a fact.
    function subVisible(spec) {
        if (!spec || !root.source)
            return false;
        if (spec.kind === "cost")
            return (root.source[spec.key] || 0) > 0;
        return true;
    }

    Column {
        id: consumptionCol
        anchors.fill: parent
        anchors.margins: Theme.spacingS
        spacing: Theme.spacingS

        StyledText {
            text: api.tr("Token Consumption")
            font.pixelSize: Theme.fontSizeSmall
            font.weight: Font.Medium
            color: Theme.surfaceText
        }

        Row {
            width: parent.width

            Repeater {
                model: root.columns
                delegate: Column {
                    required property var modelData
                    width: parent.width / 3
                    spacing: Theme.spacingXXS

                    StyledText {
                        text: root.api.tr(modelData.labelKey)
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.surfaceVariantText
                        anchors.horizontalCenter: parent.horizontalCenter
                    }

                    StyledText {
                        text: root.valueText(modelData.value)
                        font.pixelSize: modelData.text ? Theme.fontSizeSmall : Theme.fontSizeMedium
                        font.weight: Font.DemiBold
                        color: modelData.accent ? Theme.primary : Theme.surfaceText
                        anchors.horizontalCenter: parent.horizontalCenter
                    }

                    StyledText {
                        text: root.valueText(modelData.sub)
                        visible: root.subVisible(modelData.sub)
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.surfaceVariantText
                        anchors.horizontalCenter: parent.horizontalCenter
                    }
                }
            }
        }
    }
}
