import QtQuick
import qs.Common
import qs.Widgets

// The Source tab's header: the Source's Brand Colour as a dot, its name, and the
// plan as an outlined chip on the right. The plan reads as a subscription type
// with its rate-limit tier, or as a single plan name, and the chip is dropped
// when the Source reports neither.
Item {
    id: root

    property var ctx: null
    property var section: null

    readonly property var api: ctx ? ctx.api : null
    readonly property var source: ctx ? ctx.source : null
    readonly property color brandColor: ctx && ctx.brandColor ? ctx.brandColor : Theme.primary
    readonly property string planText: {
        if (!source)
            return "";
        var style = ctx && ctx.descriptor ? ctx.descriptor.planStyle : "plan";
        if (style === "subscription")
            return api.formatSubscription(source.plan, source.planTier);
        if (!source.plan || source.plan === "unknown")
            return "";
        return source.plan.replace(/\b\w/g, function (c) {
            return c.toUpperCase();
        });
    }

    width: parent.width
    height: 28

    Rectangle {
        id: brandDot
        width: 10
        height: 10
        radius: 5
        color: root.brandColor
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
    }

    StyledText {
        anchors.left: brandDot.right
        anchors.leftMargin: Theme.spacingS
        anchors.verticalCenter: parent.verticalCenter
        text: root.ctx ? root.ctx.label : ""
        font.pixelSize: Theme.fontSizeMedium
        font.weight: Font.Bold
        color: Theme.surfaceText
    }

    Rectangle {
        id: planChip
        visible: root.planText !== ""
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        width: Math.min(planLabel.implicitWidth, root.width * 0.55) + Theme.spacingS * 2
        height: 22
        radius: 11
        color: "transparent"
        border.width: 1
        border.color: root.brandColor

        StyledText {
            id: planLabel
            anchors.centerIn: parent
            width: Math.min(implicitWidth, root.width * 0.55)
            elide: Text.ElideRight
            wrapMode: Text.NoWrap
            text: root.planText
            font.pixelSize: Theme.fontSizeSmall - 1
            color: root.brandColor
        }
    }
}
