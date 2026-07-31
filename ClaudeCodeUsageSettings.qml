import QtQuick
import qs.Common
import qs.Widgets
import qs.Modules.Plugins
import "translations.js" as Tr

PluginSettings {
    id: root
    pluginId: "claudeCodeUsage"

    property string lang: Qt.locale().name.split(/[_-]/)[0]
    function tr(key) {
        return Tr.tr(key, lang);
    }

    StyledText {
        width: parent.width
        text: root.tr("Claude Code Usage")
        font.pixelSize: Theme.fontSizeLarge
        font.weight: Font.Medium
        color: Theme.surfaceText
    }

    StyledText {
        width: parent.width
        text: root.tr("Monitor your Claude Code subscription usage. Rate limits and subscription tier are detected automatically via the Anthropic API.")
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

    ListSettingWithInput {
        settingKey: "customProfiles"
        label: root.tr("Custom Profiles")
        description: root.tr("Track extra Claude config directories. Point at a CLAUDE_CONFIG_DIR (the folder containing projects/). ~/.claude, Claude Code Switcher and claude-code-profiles are detected automatically.")
        defaultValue: []
        fields: [
            {
                id: "name",
                label: root.tr("Name"),
                placeholder: "work",
                width: 130,
                required: true
            },
            {
                id: "path",
                label: root.tr("Config directory"),
                placeholder: "~/.ccp/data/work",
                width: 230,
                required: true
            }
        ]
    }
}
