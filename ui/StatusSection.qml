import QtQuick
import qs.Common
import qs.Widgets
import "../sources.js" as Sources

// Endpoint-failure card, shown when a Source's credentials are fine but its
// usage endpoint failed: a 404, a timeout, a 5xx or a body that does not carry
// the expected payload.
//
// It is deliberately not a login card. The user cannot fix a failed endpoint in
// settings, so this card must not send them there. It only explains that the
// values below, if any, are the last known ones and not current.
StyledRect {
    id: root

    property var ctx: null
    property var section: null

    readonly property var source: ctx ? ctx.source : null
    readonly property var api: ctx ? ctx.api : null
    readonly property var status: ctx && ctx.descriptor ? ctx.descriptor.status : null

    // A Source that has never had a good reading has nothing to fall back on,
    // so it says so rather than claiming to show last known values. The rule is
    // the registry's (Sources.hasReading), the same one the Window card and the
    // Overview ask.
    readonly property bool hasData: Sources.hasReading(source)
    readonly property bool unavailable: source && source.credsStatus === "unavailable"
    // The Section's own intent to show. The renderer reads this rather than
    // `visible`, which QML reports as false while an ancestor is hidden.
    readonly property bool shown: unavailable

    readonly property string title: {
        if (status && status.titleKey)
            return api.tr(status.titleKey);
        return api.tr("Usage endpoint unavailable");
    }
    readonly property string body: {
        if (!status)
            return "";
        if (!hasData && status.emptyBodyKey)
            return api.tr(status.emptyBodyKey);
        return api.tr(status.bodyKey);
    }

    width: parent.width
    visible: shown
    height: content.implicitHeight + Theme.spacingS * 2
    color: Theme.surfaceContainerHigh
    border.width: 1
    border.color: Theme.error || Theme.primary

    Column {
        id: content
        width: parent.width - Theme.spacingS * 2
        anchors.centerIn: parent
        spacing: Theme.spacingXXS

        StyledText {
            width: parent.width
            text: root.title
            font.pixelSize: Theme.fontSizeSmall
            font.weight: Font.Medium
            color: Theme.surfaceText
            wrapMode: Text.WordWrap
        }

        StyledText {
            width: parent.width
            text: root.body
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.surfaceVariantText
            wrapMode: Text.WordWrap
        }
    }
}
