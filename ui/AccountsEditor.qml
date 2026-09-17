import QtQuick
import Quickshell.Io
import qs.Common
import qs.Services
import qs.Widgets
import "../sources.js" as Sources

// Generic editor for one Source's custom Account list, and a read-only view of
// the Accounts the Source's Script detects on its own.
//
// The same list of name/value pairs previously existed three times over, once
// per Source, differing only in the setting key, the labels and whether the
// value is a config directory or an API key. Those differences are descriptor
// data now.
//
// Detection is not descriptor data and is not repeated here. The Script that
// feeds the Popout's selector is asked the same question in its listing mode,
// with the same Account arguments, so this editor shows every Account the
// selector offers - including ones the user never added - under the origin the
// Script found each at.
Column {
    id: root

    property var settingsRoot: null
    property var descriptor: null

    property bool isLoading: false
    property var items: []

    // The Script's listing output, as it arrives: the Account list under the
    // descriptor's listKey, and the origins under its originsKey.
    property string listedAccounts: ""
    property string listedOrigins: ""

    readonly property var detected: Sources.detectedAccounts(root.listedAccounts, root.listedOrigins)

    readonly property var acct: descriptor ? descriptor.accounts : null
    readonly property string settingKey: acct ? acct.settingKey : ""
    readonly property string argField: acct ? acct.argField : "path"
    readonly property real nameColumnWidth: Math.min(130, Math.max(100, width * 0.27))
    readonly property real actionWidth: 92
    readonly property real valueColumnWidth: parent.width - nameColumnWidth - actionWidth - Theme.spacingXS * 2

    width: parent.width
    spacing: Theme.spacingS

    Component.onCompleted: {
        loadValue();
        refreshDetected();
    }
    onSettingKeyChanged: loadValue()
    // The Account arguments decide which of two Accounts sharing a name the
    // Script keeps, so the listing is asked again whenever they change.
    onItemsChanged: refreshDetected()

    function loadValue() {
        if (!settingsRoot || !settingKey)
            return;
        isLoading = true;
        items = settingsRoot.loadValue(settingKey, []);
        isLoading = false;
    }

    function saveItems(newItems) {
        items = newItems;
        if (!isLoading && settingsRoot)
            settingsRoot.saveValue(settingKey, items);
    }

    function addItem() {
        var name = nameInput.text.trim();
        var value = valueInput.text.trim();
        if (!name || !value)
            return;

        var entry = {
            name: name
        };
        entry[root.argField] = value;
        saveItems(items.concat([entry]));
        nameInput.text = "";
        valueInput.text = "";
        nameInput.forceActiveFocus();
    }

    function removeItem(index) {
        var updated = items.slice();
        updated.splice(index, 1);
        saveItems(updated);
    }

    // --- Detected Accounts ---

    readonly property var listCommand: {
        if (!root.settingsRoot || !root.descriptor)
            return [];
        return ["bash",
                Sources.scriptPath(PluginService.pluginDirectory, root.settingsRoot.pluginId, root.descriptor),
                Sources.LIST_ACCOUNTS_FLAG].concat(Sources.accountArgs(root.descriptor, root.items));
    }

    // Asks the Script which Accounts it would report and where each came from.
    // The Script answers before its first request, so this spends none of the
    // user's quota, and it is asked again rather than cached: the Account
    // arguments are part of the question.
    function refreshDetected() {
        // Both of these are still null while the component is being built, which
        // the handlers below can be reached from. Component.onCompleted asks
        // again once everything exists.
        if (!listProcess || !listCommand || listCommand.length === 0)
            return;
        listedAccounts = "";
        listedOrigins = "";
        listProcess.running = true;
    }

    function readListLine(line) {
        var at = line.indexOf("=");
        if (at < 0)
            return;
        var key = line.substring(0, at);
        var value = line.substring(at + 1);
        if (key === root.acct.listKey)
            root.listedAccounts = value;
        else if (key === root.acct.originsKey)
            root.listedOrigins = value;
    }

    Process {
        id: listProcess
        command: root.listCommand
        running: false
        stdout: SplitParser {
            onRead: data => root.readListLine(data.trim())
        }
    }

    StyledText {
        text: root.settingsRoot.tr(root.acct.titleKey)
        font.pixelSize: Theme.fontSizeSmall
        font.weight: Font.Medium
        color: Theme.surfaceText
    }

    StyledText {
        width: parent.width
        text: root.settingsRoot.tr(root.acct.descriptionKey)
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
        wrapMode: Text.WordWrap
    }

    Row {
        width: parent.width
        spacing: Theme.spacingXS

        StyledText {
            width: root.nameColumnWidth
            text: root.settingsRoot.tr("Name")
            font.pixelSize: Theme.fontSizeSmall
            font.weight: Font.Medium
            color: Theme.surfaceText
        }

        StyledText {
            width: root.valueColumnWidth
            text: root.settingsRoot.tr(root.acct.fieldLabelKey)
            font.pixelSize: Theme.fontSizeSmall
            font.weight: Font.Medium
            color: Theme.surfaceText
        }

        Item {
            width: root.actionWidth
            height: 1
        }
    }

    Row {
        width: parent.width
        spacing: Theme.spacingXS

        DankTextField {
            id: nameInput
            width: root.nameColumnWidth
            placeholderText: "work"
            Keys.onReturnPressed: root.addItem()
        }

        DankTextField {
            id: valueInput
            width: root.valueColumnWidth
            placeholderText: root.acct.placeholder
            Keys.onReturnPressed: root.addItem()
        }

        DankButton {
            width: root.actionWidth
            height: 40
            text: root.settingsRoot.tr("Add")
            onClicked: root.addItem()
        }
    }

    Column {
        width: parent.width
        spacing: Theme.spacingXS

        Repeater {
            model: root.items

            StyledRect {
                required property int index
                required property var modelData

                width: parent.width
                height: 44
                radius: Theme.cornerRadius
                color: Theme.withAlpha(Theme.surfaceContainerHigh, Theme.popupTransparency)
                border.width: 0

                Row {
                    anchors.fill: parent
                    anchors.margins: Theme.spacingXS
                    spacing: Theme.spacingXS

                    StyledText {
                        width: root.nameColumnWidth
                        anchors.verticalCenter: parent.verticalCenter
                        text: modelData.name || ""
                        color: Theme.surfaceText
                        font.pixelSize: Theme.fontSizeMedium
                        elide: Text.ElideRight
                    }

                    StyledText {
                        width: root.valueColumnWidth
                        anchors.verticalCenter: parent.verticalCenter
                        text: modelData[root.argField] || ""
                        color: Theme.surfaceVariantText
                        font.pixelSize: Theme.fontSizeMedium
                        elide: Text.ElideMiddle
                    }

                    Rectangle {
                        width: root.actionWidth
                        height: 32
                        anchors.verticalCenter: parent.verticalCenter
                        color: removeArea.containsMouse ? Theme.errorHover : Theme.error
                        radius: Theme.cornerRadius

                        StyledText {
                            anchors.centerIn: parent
                            text: root.settingsRoot.tr("Remove")
                            color: Theme.onError
                            font.pixelSize: Theme.fontSizeSmall
                            font.weight: Font.Medium
                        }

                        MouseArea {
                            id: removeArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.removeItem(index)
                        }
                    }
                }
            }
        }

        StyledText {
            text: root.settingsRoot.tr("No items added yet")
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.surfaceVariantText
            visible: root.items.length === 0
        }
    }

    // What the Script detects outside the settings list. Read-only, because
    // there is nothing here to edit: the Account comes from a key or a directory
    // the plugin does not own. Empty until the Script answers, which is what
    // keeps this from claiming a Source has no detected Accounts before it has
    // been asked.
    Column {
        id: detectedBlock

        width: parent.width
        spacing: Theme.spacingXS
        visible: root.detected.length > 0

        StyledText {
            text: root.settingsRoot.tr("Detected accounts")
            font.pixelSize: Theme.fontSizeSmall
            font.weight: Font.Medium
            color: Theme.surfaceText
        }

        StyledText {
            width: parent.width
            text: root.settingsRoot.tr("Detected outside the plugin. Add or remove them where they come from, not here.")
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.surfaceVariantText
            wrapMode: Text.WordWrap
        }

        Repeater {
            model: root.detected

            StyledRect {
                required property var modelData

                width: detectedBlock.width
                height: 44
                radius: Theme.cornerRadius
                color: Theme.withAlpha(Theme.surfaceContainerHigh, Theme.popupTransparency)
                border.width: 0

                Row {
                    anchors.fill: parent
                    anchors.margins: Theme.spacingXS
                    spacing: Theme.spacingXS

                    StyledText {
                        width: root.nameColumnWidth
                        anchors.verticalCenter: parent.verticalCenter
                        text: modelData.name || ""
                        color: Theme.surfaceText
                        font.pixelSize: Theme.fontSizeMedium
                        elide: Text.ElideRight
                    }

                    // The origin is a path or an environment variable's name, so
                    // it is shown as it is: the user's own word for where the key
                    // lives. A Script that reports no origin leaves this saying
                    // only that the Account was detected rather than lying about
                    // where from.
                    StyledText {
                        width: parent.width - root.nameColumnWidth - Theme.spacingXS
                        anchors.verticalCenter: parent.verticalCenter
                        text: modelData.origin
                            ? root.settingsRoot.tr("Detected from") + " " + modelData.origin
                            : root.settingsRoot.tr("Detected automatically")
                        color: Theme.surfaceVariantText
                        font.pixelSize: Theme.fontSizeMedium
                        elide: Text.ElideMiddle
                    }
                }
            }
        }
    }
}
