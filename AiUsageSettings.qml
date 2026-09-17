import QtQuick
import qs.Common
import qs.Services
import qs.Widgets
import qs.Modules.Plugins
import "translations.js" as Tr
import "sources.js" as Sources
import "ui"

PluginSettings {
    id: root

    // Must match the id in plugin.json. The widget loads its settings as
    // "aiUsage", so a different id here would write to a key it never reads.
    pluginId: "aiUsage"

    property string lang: (SessionData.locale || Qt.locale().name).split(/[_-]/)[0]
    function tr(key) {
        return Tr.tr(key, lang);
    }

    // --- Source order ---
    // The stored list is the ordered set of enabled Sources. Order drives the
    // pill rings and the popout tabs. It is reconciled against the registry on
    // load so a stale list heals itself and a newly added Source appears.
    property var sourceOrder: []
    property bool sourceOrderLoaded: false

    Component.onCompleted: loadSourceOrder()

    function loadSourceOrder() {
        sourceOrderLoaded = false;
        sourceOrder = Sources.resolveList(root.loadValue("sources", null), root.loadValue("sourcesKnown", null));
        sourceOrderLoaded = true;
    }

    // DMS builds this page before it hands it its pluginService, so the read
    // above came back as "never configured" on the first open: every Source would
    // show as enabled, and the next toggle would save that as the user's order.
    // Re-read once the store is readable, and when the plugin's data changes.
    onPluginServiceChanged: root.loadSourceOrder()

    Connections {
        target: root.pluginService

        function onPluginDataChanged(changedPluginId) {
            if (changedPluginId === root.pluginId)
                root.loadSourceOrder();
        }
    }

    // `sources` is the enabled order. `sourcesKnown` is every registry id the
    // user has been shown, and is what lets a disabled Source stay disabled
    // while a Source added by an update still appears on its own.
    function saveSourceOrder() {
        if (!sourceOrderLoaded)
            return;
        root.saveValue("sources", sourceOrder);
        root.saveValue("sourcesKnown", Sources.ids());
    }

    function isEnabled(id) {
        return sourceOrder.indexOf(id) >= 0;
    }

    function setEnabled(id, enabled) {
        var list = sourceOrder.slice();
        var at = list.indexOf(id);
        if (enabled && at < 0)
            list.push(id);
        else if (!enabled && at >= 0)
            list.splice(at, 1);
        sourceOrder = list;
        saveSourceOrder();
    }

    function move(id, delta) {
        var list = sourceOrder.slice();
        var at = list.indexOf(id);
        if (at < 0)
            return;
        var to = at + delta;
        if (to < 0 || to >= list.length)
            return;
        var tmp = list[at];
        list[at] = list[to];
        list[to] = tmp;
        sourceOrder = list;
        saveSourceOrder();
    }

    // Enabled Sources first, in their configured order, then any disabled ones
    // in registry order so they can be switched back on.
    function displayOrder() {
        var out = [];
        for (var i = 0; i < sourceOrder.length; i++)
            out.push(sourceOrder[i]);
        var known = Sources.ids();
        for (var j = 0; j < known.length; j++) {
            if (out.indexOf(known[j]) < 0)
                out.push(known[j]);
        }
        return out;
    }

    readonly property var displayDescriptors: displayOrder().map(function (id) {
        return Sources.byId(id);
    })

    readonly property var accountDescriptors: Sources.SOURCES.filter(function (d) {
        return d.accounts !== undefined;
    })

    StyledText {
        width: parent.width
        text: root.tr("AI Usage")
        font.pixelSize: Theme.fontSizeLarge
        font.weight: Font.Medium
        color: Theme.surfaceText
    }

    StyledText {
        width: parent.width
        text: root.tr("Monitor the usage of your AI coding subscriptions. Rate limits and subscription tiers are detected automatically.")
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
        wrapMode: Text.WordWrap
    }

    SliderSetting {
        settingKey: "refreshInterval"
        label: root.tr("Refresh Interval")
        description: root.tr("How often to fetch usage data (minutes)")
        defaultValue: 2
        minimum: 2
        maximum: 15

        unit: "min"
        leftIcon: "schedule"
    }

    ToggleSetting {
        settingKey: "showPacing"
        label: root.tr("Show pacing")
        description: root.tr("Show whether usage is ahead of or behind the time window")
        defaultValue: true
    }

    Rectangle {
        width: parent.width
        height: 1
        color: Theme.outline
        opacity: 0.3
    }

    Column {
        id: sourcesSetting

        width: parent.width
        spacing: Theme.spacingM

        StyledText {
            text: root.tr("Sources")
            font.pixelSize: Theme.fontSizeMedium
            font.weight: Font.Medium
            color: Theme.surfaceText
        }

        StyledText {
            width: parent.width
            text: root.tr("Choose which Sources appear, and in what order. This sets both the taskbar ring order and the popout tab order.")
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.surfaceVariantText
            wrapMode: Text.WordWrap
        }

        // The Overview is not a Source: it ranks every visible Source against
        // the others, so it is toggleable but never movable and stays out of
        // the ordered `sources` array (ADR 0003). Pinned above the draggable
        // list rather than inside it, with no move buttons.
        ToggleSetting {
            settingKey: "overviewEnabled"
            label: root.tr("Overview")
            description: root.tr("Show the Overview tab, ranking your Sources by their tightest Window. It appears once two or more Sources are visible.")
            defaultValue: true
        }

        Repeater {
            model: root.displayDescriptors

            StyledRect {
                id: sourceRow

                required property int index
                required property var modelData

                readonly property bool isOn: root.isEnabled(modelData.id)
                // Only enabled Sources hold a position, so only they can move.
                readonly property bool inList: index < root.sourceOrder.length
                readonly property bool canMoveUp: inList && index > 0
                readonly property bool canMoveDown: inList && index < root.sourceOrder.length - 1

                width: parent.width
                height: 48
                radius: Theme.cornerRadius
                color: Theme.withAlpha(Theme.surfaceContainerHigh, Theme.popupTransparency)
                border.width: 0

                Row {
                    anchors.fill: parent
                    anchors.leftMargin: Theme.spacingM
                    anchors.rightMargin: Theme.spacingM
                    spacing: Theme.spacingS

                    DankIcon {
                        name: "monitoring"
                        size: 18
                        color: sourceRow.isOn ? Theme.primary : Theme.surfaceVariantText
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    StyledText {
                        width: Math.max(0, parent.width - 18 - moveButtons.width - toggleSwitch.width - Theme.spacingS * 3)
                        text: root.tr(modelData.labelKey)
                        font.pixelSize: Theme.fontSizeMedium
                        color: sourceRow.isOn ? Theme.surfaceText : Theme.surfaceVariantText
                        anchors.verticalCenter: parent.verticalCenter
                        elide: Text.ElideRight
                    }

                    Row {
                        id: moveButtons
                        spacing: Theme.spacingXS
                        anchors.verticalCenter: parent.verticalCenter
                        visible: sourceRow.inList

                        Repeater {
                            model: [{
                                delta: -1,
                                icon: "keyboard_arrow_up",
                                canMove: sourceRow.canMoveUp
                            }, {
                                delta: 1,
                                icon: "keyboard_arrow_down",
                                canMove: sourceRow.canMoveDown
                            }]

                            Rectangle {
                                required property var modelData

                                width: 28
                                height: 28
                                radius: 14
                                color: moveArea.containsMouse && modelData.canMove ? Theme.surfaceVariant : "transparent"

                                DankIcon {
                                    anchors.centerIn: parent
                                    name: modelData.icon
                                    size: 18
                                    color: modelData.canMove ? Theme.surfaceText : Theme.withAlpha(Theme.surfaceVariantText, 0.4)
                                }

                                MouseArea {
                                    id: moveArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    enabled: modelData.canMove
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.move(sourceRow.modelData.id, modelData.delta)
                                }
                            }
                        }
                    }

                    Rectangle {
                        id: toggleSwitch
                        width: 44
                        height: 24
                        radius: 12
                        anchors.verticalCenter: parent.verticalCenter
                        color: sourceRow.isOn ? Theme.primary : Theme.surfaceVariant

                        Behavior on color {
                            ColorAnimation {
                                duration: 120
                            }
                        }

                        Rectangle {
                            width: 18
                            height: 18
                            radius: 9
                            anchors.verticalCenter: parent.verticalCenter
                            x: sourceRow.isOn ? parent.width - width - 3 : 3
                            color: sourceRow.isOn ? Theme.primaryText : Theme.surfaceVariantText

                            Behavior on x {
                                NumberAnimation {
                                    duration: 120
                                }
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.setEnabled(sourceRow.modelData.id, !sourceRow.isOn)
                        }
                    }
                }
            }
        }
    }

    // Wrapped in a Column so PluginSettings re-parents it into the settings
    // column; a bare Repeater is not an Item and would not be laid out.
    Column {
        width: parent.width
        spacing: Theme.spacingM

        Repeater {
            model: root.accountDescriptors

            Column {
                required property int index
                required property var modelData

                width: parent.width
                spacing: Theme.spacingM

                Rectangle {
                    width: parent.width
                    height: 1
                    color: Theme.outline
                    opacity: 0.3
                    visible: index > 0
                }

                AccountsEditor {
                    settingsRoot: root
                    descriptor: modelData
                }
            }
        }
    }
}
