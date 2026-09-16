import QtQuick
import qs.Common
import qs.Widgets

// Source name plus its plan line. `planStyle` picks how the plan reads:
// "subscription" pairs a subscription type with a rate-limit tier, "plan"
// shows a single plan name.
Column {
    id: root

    property var ctx: null
    property var section: null

    readonly property string label: ctx ? ctx.label : ""
    readonly property var api: ctx ? ctx.api : null
    readonly property var source: ctx ? ctx.source : null
    readonly property string plan: source ? source.plan : ""
    readonly property string planTier: source ? source.planTier : ""
    readonly property string planStyle: ctx && ctx.descriptor ? ctx.descriptor.planStyle : "plan"

    readonly property string planText: {
        if (planStyle === "subscription") {
            var sub = api.formatSubscription(plan, planTier);
            return sub ? api.tr("Subscription") + ": " + sub : "";
        }
        if (!plan || plan === "unknown")
            return "";
        return api.tr("Plan") + ": " + plan.replace(/\b\w/g, function (c) {
            return c.toUpperCase();
        });
    }

    width: parent.width
    spacing: 2

    StyledText {
        text: root.label
        font.pixelSize: Theme.fontSizeLarge
        font.weight: Font.Bold
        color: Theme.surfaceText
    }

    StyledText {
        width: parent.width
        text: root.planText
        visible: text !== ""
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
        wrapMode: Text.WordWrap
    }
}
