import QtQuick
import qs.Common
import qs.Widgets
import "../sources.js" as Sources

// Reported spend retains its billing currency. It is independent of the
// local transcript Cost and carries no invented reset time or pace tick.
StyledRect {
    id: root
    property var ctx: null
    property var section: null
    readonly property var source: ctx ? ctx.source : null
    readonly property var api: ctx ? ctx.api : null
    readonly property var spend: source ? source.spend : null
    readonly property var util: Sources.spendUtilisation(spend)
    readonly property bool shown: !!(source && spend && Sources.hasReading(source))

    width: parent.width
    height: content.implicitHeight + Theme.spacingS * 2
    visible: shown
    color: Theme.surfaceContainerHigh

    function money(minor) {
        return spend && api ? api.formatMoney(minor, spend.currency, spend.exponent) : "";
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
                width: Math.max(0, parent.width - percentage.width - parent.spacing)
                text: root.api ? root.api.tr("Monthly budget") : ""
                font.pixelSize: Theme.fontSizeSmall
                font.weight: Font.Medium
                color: Theme.surfaceText
                elide: Text.ElideRight
            }
            StyledText {
                id: percentage
                text: root.util !== null ? Math.round(root.util) + "%" : ""
                font.pixelSize: Theme.fontSizeSmall
                font.weight: Font.Medium
                color: root.api && root.source ? root.api.utilisationColor(root.source.id, root.util || 0) : Theme.surfaceText
            }
        }

        StyledText {
            width: parent.width
            wrapMode: Text.WordWrap
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.surfaceText
            text: {
                if (!root.spend || !root.api)
                    return "";
                var used = root.money(root.spend.usedMinor);
                if (root.spend.limitKind === "finite")
                    return used + " / " + root.money(root.spend.limitMinor);
                return used + " · " + root.api.tr(root.spend.limitKind === "unlimited" ? "Unlimited" : "Allowance unavailable");
            }
        }

        Rectangle {
            visible: root.util !== null
            width: parent.width
            height: 6
            radius: height / 2
            color: Theme.surfaceVariant
            Rectangle {
                width: parent.width * Math.max(0, Math.min((root.util || 0) / 100, 1))
                height: parent.height
                radius: parent.radius
                color: root.api && root.source ? root.api.utilisationColor(root.source.id, root.util || 0) : Theme.surfaceText
            }
        }

        StyledText {
            width: parent.width
            wrapMode: Text.WordWrap
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.surfaceVariantText
            text: {
                if (!root.spend || !root.api)
                    return "";
                if (!root.spend.enabled || root.spend.limitMinor === 0)
                    return root.api.tr("Usage credits disabled");
                if (root.util !== null)
                    return root.money(Math.max(0, root.spend.limitMinor - root.spend.usedMinor)) + " " + root.api.tr("remaining");
                return "";
            }
        }

        StyledText {
            width: parent.width
            wrapMode: Text.WordWrap
            font.pixelSize: Theme.fontSizeSmall - 1
            color: Theme.surfaceVariantText
            text: root.api ? root.api.tr("Spend reported by Claude; reset time unavailable") : ""
        }
    }
}
