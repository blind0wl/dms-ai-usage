import QtQuick
import qs.Common
import qs.Widgets
import "../sources.js" as Sources

// Status card for the two states a Source reaches without a credential problem:
// a Blocked Source whose Script could not read past a missing or failing
// Requirement, and an Unavailable Source whose credentials are fine but whose
// usage endpoint failed.
//
// Blocked is deliberately not a login card. No credential was read, the fix is
// to install or repair the named command, and no plugin setting supplies one, so
// this card must not send the user to settings.
//
// Unavailable is likewise not a login card: the user cannot fix a failed
// endpoint, so it only explains that the values below, if any, are the last
// known ones and not current.
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
    // Blocked and Unavailable are the two states this card explains. Blocked is a
    // missing or failing Requirement, which the Script named in its report;
    // Unavailable is a failed endpoint, whose copy the descriptor carries.
    readonly property bool blocked: source && source.credsStatus === "blocked"
    // The Section's own intent to show. The renderer reads this rather than
    // `visible`, which QML reports as false while an ancestor is hidden.
    readonly property bool shown: blocked || unavailable

    // The commands the Script could not read past, as its report named them, so
    // the card can say which one to install. The list is the report's, not a
    // descriptor's: a Requirement is a property of the machine, not of a Source.
    readonly property string requirements: {
        if (!blocked || !source || !source.blockingRequirement)
            return "";
        return Sources.splitList(source.blockingRequirement).join(", ");
    }

    readonly property string title: {
        if (blocked)
            return api.tr("Blocked by a requirement");
        if (status && status.titleKey)
            return api.tr(status.titleKey);
        return api.tr("Usage endpoint unavailable");
    }
    readonly property string body: {
        if (blocked)
            return api.tr("This Source could not be read because a required command is unavailable") + ": " + requirements + ".";
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
