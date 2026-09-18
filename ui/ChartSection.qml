import QtQuick
import qs.Common
import qs.Widgets

// Daily activity card: Monday to Sunday bars with a hover tooltip.
//
// `overlay` is on for Sources with an Account selector. The grey bar is then the
// total and a coloured bar shows the selected Account's share, and the tooltip
// breaks the day down into total, Account share and cost.
StyledRect {
    id: root

    property var ctx: null
    property var section: null

    readonly property var source: ctx ? ctx.source : null
    readonly property var api: ctx ? ctx.api : null
    readonly property color brandColor: ctx && ctx.brandColor ? ctx.brandColor : Theme.primary
    readonly property var dayLabels: ctx ? ctx.dayLabels : []
    readonly property int todayIndex: ctx ? ctx.todayIndex : 0
    readonly property bool overlay: section ? section.overlay === true : false
    readonly property bool accountSelected: ctx ? ctx.accountSelected === true : false
    readonly property string accountName: ctx ? ctx.accountName : ""

    readonly property var dailyTokens: source && source.dailyTokens ? source.dailyTokens : [0, 0, 0, 0, 0, 0, 0]
    readonly property var dailyCosts: source && source.dailyCosts ? source.dailyCosts : [0, 0, 0, 0, 0, 0, 0]
    readonly property var accountDaily: source && source.accountDaily ? source.accountDaily : []
    readonly property real maxDaily: Math.max.apply(null, dailyTokens) || 1

    width: parent.width
    height: dailyCol.implicitHeight + Theme.spacingS * 2
    color: Theme.surfaceContainerHigh

    property int hoveredDay: -1

    function barHeight(value, availHeight) {
        if (value <= 0)
            return 0;
        return Math.max(value / maxDaily * availHeight, 3);
    }

    Column {
        id: dailyCol
        anchors.fill: parent
        anchors.margins: Theme.spacingS
        spacing: Theme.spacingXS

        StyledText {
            text: api.tr("Daily Activity")
            font.pixelSize: Theme.fontSizeSmall
            font.weight: Font.Medium
            color: Theme.surfaceVariantText
        }

        Item {
            width: parent.width
            height: 56

            Row {
                id: chartRow
                anchors.fill: parent
                spacing: Theme.spacingXS

                Repeater {
                    model: 7
                    delegate: Column {
                        width: (chartRow.width - 6 * Theme.spacingXS) / 7
                        height: chartRow.height
                        spacing: Theme.spacingXXS

                        Item {
                            id: barArea
                            width: parent.width
                            height: parent.height - dayLabel.height - 2

                            // Total bar. Every day is the Brand Colour; today
                            // is at full strength and the rest sit back, except
                            // while a hover picks one out. With an Account
                            // selected the total goes grey so the share stands.
                            Rectangle {
                                anchors.bottom: parent.bottom
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: Math.max(parent.width - 4, 4)
                                height: root.barHeight(root.dailyTokens[index], barArea.height)
                                radius: 2
                                color: root.overlay && root.accountSelected ? Theme.surfaceVariant : root.brandColor
                                opacity: root.hoveredDay >= 0 ? (index === root.hoveredDay ? 1.0 : 0.4) : (index === root.todayIndex ? 1.0 : 0.55)

                                Behavior on opacity {
                                    NumberAnimation {
                                        duration: 120
                                    }
                                }
                            }

                            // Selected Account's share.
                            Rectangle {
                                visible: root.overlay && root.accountSelected && root.accountDaily.length > 0
                                anchors.bottom: parent.bottom
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: Math.max(parent.width - 4, 4)
                                height: root.accountDaily.length > index ? root.barHeight(root.accountDaily[index], barArea.height) : 0
                                radius: 2
                                color: root.brandColor
                                opacity: root.hoveredDay >= 0 && index !== root.hoveredDay ? 0.4 : 1.0

                                Behavior on opacity {
                                    NumberAnimation {
                                        duration: 120
                                    }
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                enabled: root.dailyTokens[index] > 0
                                onEntered: root.hoveredDay = index
                                onExited: root.hoveredDay = -1
                            }
                        }

                        StyledText {
                            id: dayLabel
                            text: root.dayLabels[index]
                            font.pixelSize: Theme.fontSizeSmall - 1
                            color: index === root.hoveredDay ? root.brandColor : index === root.todayIndex ? root.brandColor : Theme.surfaceVariantText
                            anchors.horizontalCenter: parent.horizontalCenter
                        }
                    }
                }
            }
        }
    }

    // Tooltip on hover, a child of the card so it is not clipped by the chart.
    Rectangle {
        id: chartTooltip
        visible: root.hoveredDay >= 0 && root.dailyTokens[root.hoveredDay] > 0
        z: 10

        x: {
            var colW = (chartRow.width - 6 * Theme.spacingXS) / 7;
            var cx = root.hoveredDay * (colW + Theme.spacingXS) + colW / 2 - width / 2;
            var chartX = chartRow.mapToItem(chartTooltip.parent, 0, 0).x;
            var raw = chartX + cx;
            return Math.max(Theme.spacingS, Math.min(raw, parent.width - width - Theme.spacingS));
        }
        y: {
            var chartY = chartRow.mapToItem(chartTooltip.parent, 0, 0).y;
            return chartY - height - 2;
        }

        width: tooltipCol.implicitWidth + Theme.spacingXS * 2
        height: tooltipCol.implicitHeight + Theme.spacingXXS * 2
        radius: 4
        color: Theme.surfaceContainer

        Column {
            id: tooltipCol
            anchors.centerIn: parent
            spacing: 1

            // Total, marked as a total only when an Account share sits under it.
            StyledText {
                text: {
                    if (root.hoveredDay < 0)
                        return "";
                    var t = root.api.formatTokens(root.dailyTokens[root.hoveredDay]);
                    return root.overlay && root.accountSelected ? t + " " + root.api.tr("total") : t;
                }
                font.pixelSize: Theme.fontSizeSmall - 1
                font.weight: Font.DemiBold
                color: Theme.surfaceText
                anchors.horizontalCenter: parent.horizontalCenter
            }

            StyledText {
                visible: root.overlay && root.accountSelected && root.hoveredDay >= 0 && root.accountDaily.length > root.hoveredDay && root.accountDaily[root.hoveredDay] > 0
                text: {
                    if (root.hoveredDay < 0 || root.accountDaily.length <= root.hoveredDay)
                        return "";
                    return root.api.formatTokens(root.accountDaily[root.hoveredDay]) + " " + root.accountName;
                }
                font.pixelSize: Theme.fontSizeSmall - 1
                color: root.brandColor
                anchors.horizontalCenter: parent.horizontalCenter
            }

            StyledText {
                visible: root.hoveredDay >= 0 && root.dailyCosts[root.hoveredDay] > 0
                text: root.hoveredDay >= 0 ? root.api.formatCost(root.dailyCosts[root.hoveredDay]) : ""
                font.pixelSize: Theme.fontSizeSmall - 1
                color: Theme.surfaceVariantText
                anchors.horizontalCenter: parent.horizontalCenter
            }
        }
    }
}
