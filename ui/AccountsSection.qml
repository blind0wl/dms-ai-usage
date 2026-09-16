import QtQuick
import qs.Common
import qs.Widgets

// Account selector. Renders as tabs up to five entries and as a dropdown beyond
// that, and hides entirely when there is only one real Account to choose from.
//
// The first entry is always the aggregate, labelled "All".
Item {
    id: root

    property var ctx: null
    property var section: null

    readonly property var api: ctx ? ctx.api : null
    readonly property var accounts: ctx && ctx.accounts ? ctx.accounts : []
    readonly property string selected: ctx && ctx.selected ? ctx.selected : "all"
    readonly property string label: ctx && ctx.descriptor && ctx.descriptor.accounts ? api.tr(ctx.descriptor.accounts.labelKey) : ""

    readonly property bool useTabs: accounts.length <= 5

    width: parent.width
    height: selectorLoader.height
    // count > 2 means the aggregate plus at least two real Accounts.
    visible: accounts.length > 2

    function labelFor(name) {
        return name === "all" ? api.tr("All") : name;
    }

    Loader {
        id: selectorLoader
        width: parent.width
        // Explicit height binding: a Loader defaults to zero without one.
        height: item ? item.implicitHeight : 0
        sourceComponent: root.useTabs ? accountTabsComponent : accountDropdownComponent
    }

    Component {
        id: accountTabsComponent
        Row {
            spacing: Theme.spacingXS

            Repeater {
                model: root.accounts
                delegate: Rectangle {
                    required property var modelData

                    width: tabLabel.implicitWidth + Theme.spacingM * 2
                    height: 32
                    radius: 16
                    color: root.selected === modelData ? Theme.primary : Theme.surfaceVariant

                    Behavior on color {
                        ColorAnimation {
                            duration: 120
                        }
                    }

                    StyledText {
                        id: tabLabel
                        anchors.centerIn: parent
                        text: root.labelFor(modelData)
                        font.pixelSize: Theme.fontSizeSmall
                        font.weight: root.selected === modelData ? Font.Medium : Font.Normal
                        color: root.selected === modelData ? Theme.primaryText : Theme.surfaceVariantText
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.api.selectAccount(root.ctx.source.id, modelData)
                    }
                }
            }
        }
    }

    Component {
        id: accountDropdownComponent
        Rectangle {
            // z:100 on the popup is scoped to this subtree, so cards below can
            // overlap while it is open. Acceptable for the >5 Accounts case.
            width: parent ? parent.width : 0
            height: 36
            radius: 8
            color: Theme.surfaceVariant

            Row {
                anchors.fill: parent
                anchors.leftMargin: Theme.spacingM
                anchors.rightMargin: Theme.spacingM
                spacing: Theme.spacingXS

                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.label + ":"
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceVariantText
                }

                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.labelFor(root.selected)
                    font.pixelSize: Theme.fontSizeSmall
                    font.weight: Font.Medium
                    color: Theme.surfaceText
                }
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: accountDropdownPopup.visible = !accountDropdownPopup.visible
            }

            MouseArea {
                visible: accountDropdownPopup.visible
                anchors.fill: root
                z: 99
                onClicked: accountDropdownPopup.visible = false
            }

            Rectangle {
                id: accountDropdownPopup
                visible: false
                z: 100
                anchors.top: parent.bottom
                anchors.topMargin: 4
                anchors.left: parent.left
                width: parent.width
                height: dropdownCol.implicitHeight + Theme.spacingS * 2
                radius: 8
                color: Theme.surfaceContainer

                Column {
                    id: dropdownCol
                    anchors.fill: parent
                    anchors.margins: Theme.spacingS
                    spacing: 2

                    Repeater {
                        model: root.accounts
                        delegate: Rectangle {
                            required property var modelData

                            width: parent.width
                            height: 28
                            radius: 4
                            color: root.selected === modelData ? Theme.primary : "transparent"

                            StyledText {
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.left: parent.left
                                anchors.leftMargin: Theme.spacingXS
                                text: root.labelFor(modelData)
                                font.pixelSize: Theme.fontSizeSmall
                                color: root.selected === modelData ? Theme.primaryText : Theme.surfaceText
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    root.api.selectAccount(root.ctx.source.id, modelData);
                                    accountDropdownPopup.visible = false;
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
