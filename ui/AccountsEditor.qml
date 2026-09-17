import QtQuick
import Quickshell.Io
import qs.Common
import qs.Services
import qs.Widgets
import "../sources.js" as Sources

// One Source's Accounts, in two labelled lists: the Custom Accounts the user
// adds here and can edit, and the Detected Accounts the Source's Script finds on
// this machine, which are read-only because the plugin does not own them.
//
// Detection is not descriptor data and is not repeated here. The Script that
// feeds the Popout's selector is asked the same question in its listing mode,
// with the same Account arguments the fetch uses, so this editor shows every
// Account the selector offers under the origin the Script found each at.
//
// A clash between the two lists is shown rather than resolved silently. The
// Script keeps the first registration of a name or of a value, so a Custom
// Account can take a detected one's place and change the credential the Source
// authenticates with; the Script reports what it refused for exactly that reason,
// and the refused Account stays visible here marked as overridden or not in use.
Column {
    id: root

    property var settingsRoot: null
    property var descriptor: null

    property bool isLoading: false
    property var items: []

    // The Script's listing, as it arrives: the Accounts under the descriptor's
    // listKey, their origins under its originsKey, and the registrations it
    // refused under its shadowedKey.
    property string listedAccounts: ""
    property string listedOrigins: ""
    property string listedShadowed: ""
    // Set when the Script that answers the listing fails, so a listing that never
    // arrived is not shown as a Source with nothing detected.
    property bool listFailed: false
    // Set when the Account list changes while the Script is answering the
    // previous one, so the answer the editor keeps describes the list it was
    // asked about rather than the one the user just edited.
    property bool listPending: false

    readonly property var detected: Sources.detectedAccounts(root.listedAccounts, root.listedOrigins, root.listedShadowed)
    // The Custom Account rows the Script did not register: another Account
    // already holds their name or their value, so the selector cannot offer them
    // and their row here does nothing. The listing is the only thing that can say
    // which rows those are, so it says nothing until it has answered with an
    // Account: an uninstalled Source leaves every row unmarked.
    readonly property var unregistered: Sources.unregisteredRows(root.listedAccounts, root.listedOrigins, root.items)

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
    onSettingKeyChanged: {
        loadValue();
        refreshDetected();
    }
    // The Account arguments decide which of two Accounts sharing a name the
    // Script keeps, so the listing is asked again whenever they change.
    onItemsChanged: refreshDetected()

    // DMS builds this page, and everything inside it, before it hands the page
    // its pluginService, so the first read of the store above came back empty.
    // The settings page's own reload hook walks its direct children, and this
    // editor sits inside a Column, so it watches for the two moments the list can
    // have moved underneath it instead.
    Connections {
        target: root.settingsRoot
        ignoreUnknownSignals: true

        function onPluginServiceChanged() {
            root.reloadFromStore(true);
        }
    }

    Connections {
        target: root.settingsRoot ? root.settingsRoot.pluginService : null

        function onPluginDataChanged(changedPluginId) {
            if (root.settingsRoot && changedPluginId === root.settingsRoot.pluginId)
                root.reloadFromStore();
        }
    }

    function loadValue() {
        if (!settingsRoot || !settingKey)
            return;
        isLoading = true;
        items = settingsRoot.loadValue(settingKey, []);
        isLoading = false;
    }

    // Re-reads the Custom Account list from the store, which is the only thing
    // that knows what a fresh page should show. A change that does not move the
    // list (a sibling setting being saved, or this editor's own write coming
    // back) is left alone rather than asked of the Script again - unless this is
    // the store becoming readable, when the listing has to be asked whatever the
    // list says, because the one already asked was asked without it.
    function reloadFromStore(askAnyway) {
        if (!settingsRoot || !settingKey)
            return;
        var stored = settingsRoot.loadValue(settingKey, []);
        if (JSON.stringify(stored) === JSON.stringify(root.items)) {
            if (askAnyway)
                refreshDetected();
            return;
        }
        root.items = stored;
    }

    function saveItems(newItems) {
        items = newItems;
        if (!isLoading && settingsRoot)
            settingsRoot.saveValue(settingKey, newItems);
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

    // The warning line a Custom Account row carries, or "" when it needs none.
    // A row the Script did not register is either shadowed by a detected Account -
    // which the Script names, because a clash of values puts a row of another name
    // in its place - or refused for something the Script cannot name, such as a
    // config directory that does not exist.
    function customRowStatus(index, name) {
        if (root.unregistered.indexOf(index) < 0) {
            var replaced = Sources.displacedOrigin(root.detected, name);
            return replaced
                ? root.settingsRoot.tr("replacing what the Script detected") + " (" + replaced + ")"
                : "";
        }
        var shadowing = Sources.shadowingAccount(root.listedOrigins, root.listedShadowed, name);
        if (shadowing)
            return root.settingsRoot.tr("not in use - the Script kept") + " \"" + shadowing.name + "\" ("
                + root.settingsRoot.tr("Detected from") + " " + shadowing.origin + ")";
        return root.settingsRoot.tr("not in use - the Script did not register it. Check its name and value.");
    }

    // --- Asking the Script ---

    // The command is built here, as the list is asked for, rather than bound to a
    // property: the Account arguments are part of the question, and a command
    // evaluated before this change would answer for the list the user has just
    // edited.
    function refreshDetected() {
        // The Script is reached through these, which are still null while the
        // component is being built, which the handlers above can be reached from.
        if (!listProcess || !root.settingsRoot || !root.descriptor)
            return;
        // The Account arguments are the Custom Account list, so a listing asked
        // before the store is readable would answer the wrong question: it would
        // show a detected Account as live that a Custom row is about to replace.
        if (!root.settingsRoot.pluginService)
            return;
        if (listProcess.running) {
            root.listPending = true;
            return;
        }
        root.listFailed = false;
        listProcess.command = Sources.scriptCommand(PluginService.pluginDirectory, root.settingsRoot.pluginId, root.descriptor,
                                                   [Sources.LIST_ACCOUNTS_FLAG].concat(Sources.accountArgs(root.descriptor, root.items)));
        listProcess.running = true;
    }

    function readListLine(line) {
        var pair = Sources.wirePair(line);
        if (!pair)
            return;
        if (pair.key === root.acct.listKey)
            root.listedAccounts = pair.value;
        else if (pair.key === root.acct.originsKey)
            root.listedOrigins = pair.value;
        else if (pair.key === root.acct.shadowedKey)
            root.listedShadowed = pair.value;
    }

    Process {
        id: listProcess
        running: false

        stdout: SplitParser {
            onRead: data => root.readListLine(data.trim())
        }

        onExited: (exitCode, exitStatus) => {
            root.listFailed = exitCode !== 0;
            if (root.listPending) {
                root.listPending = false;
                Qt.callLater(root.refreshDetected);
            }
        }
    }

    // --- Custom Accounts: what the user adds, and what can be edited here ---

    Row {
        spacing: Theme.spacingXS

        StyledText {
            text: root.settingsRoot.tr(root.acct.titleKey)
            font.pixelSize: Theme.fontSizeSmall
            font.weight: Font.Medium
            color: Theme.surfaceText
        }

        StyledText {
            anchors.verticalCenter: parent.verticalCenter
            text: root.settingsRoot.tr("Editable")
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.primary
        }
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

                // The Script's verdict on this row: it was refused, or it took a
                // detected Account's place. Either way the Source authenticates
                // with something the user should be told about.
                readonly property string status: root.customRowStatus(index, modelData.name)

                width: parent.width
                height: status.length > 0 ? 62 : 44
                radius: Theme.cornerRadius
                color: Theme.withAlpha(Theme.surfaceContainerHigh, Theme.popupTransparency)
                border.width: status.length > 0 ? 1 : 0
                border.color: Theme.withAlpha(Theme.warning, 0.5)

                Column {
                    anchors.fill: parent
                    anchors.margins: Theme.spacingXS
                    spacing: Theme.spacingXXS

                    Row {
                        width: parent.width
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

                    Row {
                        width: parent.width
                        spacing: Theme.spacingXXS
                        visible: status.length > 0

                        DankIcon {
                            anchors.verticalCenter: parent.verticalCenter
                            name: "warning"
                            size: 14
                            color: Theme.warning
                        }

                        StyledText {
                            width: parent.width - 14 - Theme.spacingXXS
                            anchors.verticalCenter: parent.verticalCenter
                            text: status
                            color: Theme.warning
                            font.pixelSize: Theme.fontSizeSmall
                            elide: Text.ElideRight
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

    // --- Detected Accounts: what the Script found, and what cannot be edited ---

    Column {
        id: detectedBlock

        width: parent.width
        spacing: Theme.spacingXS
        visible: root.detected.length > 0 || root.listFailed

        Row {
            spacing: Theme.spacingXS

            StyledText {
                text: root.settingsRoot.tr(root.acct.detectedTitleKey)
                font.pixelSize: Theme.fontSizeSmall
                font.weight: Font.Medium
                color: Theme.surfaceText
            }

            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                text: root.settingsRoot.tr("Read-only")
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceVariantText
            }
        }

        StyledText {
            width: parent.width
            text: root.settingsRoot.tr("Found on this machine, not added here. Change them at their origin.")
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.surfaceVariantText
            wrapMode: Text.WordWrap
        }

        Repeater {
            model: root.detected

            StyledRect {
                required property var modelData

                // The Script refused this registration because a Custom Account
                // had already taken its name or its value, so the Source is
                // authenticating with what the user typed instead of this.
                readonly property bool overridden: modelData.overridden === true

                width: detectedBlock.width
                height: overridden ? 62 : 44
                radius: Theme.cornerRadius
                color: Theme.withAlpha(Theme.surfaceContainer, Theme.popupTransparency)
                border.width: 1
                border.color: Theme.withAlpha(overridden ? Theme.warning : Theme.outline, overridden ? 0.5 : 0.3)

                Column {
                    anchors.fill: parent
                    anchors.margins: Theme.spacingXS
                    spacing: Theme.spacingXXS

                    Row {
                        width: parent.width
                        spacing: Theme.spacingXS

                        StyledText {
                            width: root.nameColumnWidth
                            anchors.verticalCenter: parent.verticalCenter
                            text: modelData.name || ""
                            color: overridden ? Theme.warning : Theme.surfaceText
                            font.pixelSize: Theme.fontSizeMedium
                            elide: Text.ElideRight
                        }

                        // The origin is a path or an environment variable's name,
                        // so it is shown as it is: the user's own word for where
                        // the credential lives. A Script that reports no origin
                        // leaves this saying only that the origin is unknown
                        // rather than inventing one.
                        StyledText {
                            width: parent.width - root.nameColumnWidth - Theme.spacingXS
                            anchors.verticalCenter: parent.verticalCenter
                            text: modelData.origin
                                ? root.settingsRoot.tr("Detected from") + " " + modelData.origin
                                : root.settingsRoot.tr("Origin unknown")
                            color: Theme.surfaceVariantText
                            font.pixelSize: Theme.fontSizeMedium
                            elide: Text.ElideMiddle
                        }
                    }

                    Row {
                        width: parent.width
                        spacing: Theme.spacingXXS
                        visible: overridden

                        DankIcon {
                            anchors.verticalCenter: parent.verticalCenter
                            name: "warning"
                            size: 14
                            color: Theme.warning
                        }

                        StyledText {
                            width: parent.width - 14 - Theme.spacingXXS
                            anchors.verticalCenter: parent.verticalCenter
                            // The winner is named because a clash of values puts a
                            // Custom row of a different name in this Account's
                            // place, and a line that only said "a Custom Account"
                            // would leave the user guessing which row it was.
                            text: root.settingsRoot.tr(root.acct.overriddenKey)
                                + (modelData.winner ? " \"" + modelData.winner + "\"" : "")
                            color: Theme.warning
                            font.pixelSize: Theme.fontSizeSmall
                            elide: Text.ElideRight
                        }
                    }
                }
            }
        }

        // A listing that never arrived is not the same as a Source with nothing
        // detected, and showing the two the same way is how the selector's
        // Accounts went missing from this page in the first place. The copy names
        // no Account word of its own, because Claude's page calls them Profiles.
        StyledText {
            width: parent.width
            text: root.settingsRoot.tr("Could not ask the Script what it detects.")
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.surfaceVariantText
            wrapMode: Text.WordWrap
            visible: root.listFailed
        }
    }
}
