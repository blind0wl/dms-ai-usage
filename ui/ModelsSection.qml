import QtQuick
import qs.Common
import qs.Widgets

// Per-model token table for the current week. Each row carries a bar scaled
// against the week's total, so the rows read as a share of the whole.
//
// `nameStyle` exists because Sources report model names differently: Claude and
// ChatGPT report identifiers that need capitalising, Z.ai reports display-ready
// names like "GLM-4.6" that must be left alone.
StyledRect {
    id: root

    property var ctx: null
    property var section: null

    readonly property var source: ctx ? ctx.source : null
    readonly property var api: ctx ? ctx.api : null
    readonly property string nameStyle: section && section.nameStyle ? section.nameStyle : "raw"

    readonly property var models: source && source.models ? source.models : []
    readonly property real weekTokens: source ? (source.weekTokens || 0) : 0
    // The Section's own intent to show. The renderer reads this rather than
    // `visible`, which QML reports as false while an ancestor is hidden.
    readonly property bool shown: models.length > 0

    width: parent.width
    height: modelCardCol.implicitHeight + Theme.spacingM * 2
    color: Theme.surfaceContainerHigh
    visible: shown

    function displayName(name) {
        return nameStyle === "short" ? api.shortModelName(name) : name;
    }

    Column {
        id: modelCardCol
        anchors.fill: parent
        anchors.margins: Theme.spacingM
        spacing: Theme.spacingS

        StyledText {
            text: api.tr("Models This Week")
            font.pixelSize: Theme.fontSizeMedium
            font.weight: Font.Medium
            color: Theme.surfaceText
        }

        Column {
            id: modelCol
            width: parent.width
            spacing: Theme.spacingS

            Repeater {
                model: root.models
                delegate: Column {
                    id: modelRow
                    required property var modelData

                    // `real`, not `int`: a weekly per-model total can pass the
                    // signed 32-bit range (2.1B tokens) and wrap negative.
                    readonly property real tokens: modelData ? (modelData.modelTokens || 0) : 0

                    width: modelCol.width
                    spacing: 3

                    Row {
                        width: parent.width
                        spacing: Theme.spacingXS

                        StyledText {
                            text: root.displayName(modelRow.modelData ? modelRow.modelData.modelName : "")
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.surfaceText
                        }
                        StyledText {
                            text: root.api.formatTokens(modelRow.tokens)
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.surfaceVariantText
                        }
                    }

                    Rectangle {
                        id: trackBar
                        width: parent.width
                        height: 4
                        radius: 2
                        color: Theme.surfaceVariant

                        Rectangle {
                            width: root.weekTokens > 0 ? trackBar.width * Math.min(modelRow.tokens / root.weekTokens, 1) : 0
                            height: trackBar.height
                            radius: 2
                            color: Theme.primary
                        }
                    }
                }
            }
        }
    }
}
