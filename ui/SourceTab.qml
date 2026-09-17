import QtQuick
import qs.Common

// Renders one Popout tab's Section list. A Source's tab and the Overview's tab
// are both just an ordered list of Sections, so this stays the only renderer
// (ADR 0003).
//
// The compact scale is stated here, because this is where a tab's rhythm lives.
// It is three steps and nothing wider: `Theme.spacingS` for an inset or for the
// gap between two Sections, `Theme.spacingXS` for the rhythm inside one, and
// `Theme.spacingXXS` where a label sits directly on the value under it. Which
// in-card gap takes S and which takes XS is the Section's own call — a hero
// card's two columns get S, a list row's get XS — but no Section reaches for the
// roomier steps above S. A card's own headline is `Theme.fontSizeSmall` at
// `Font.Medium`, which is DMS's own compact header idiom; the tab's Source name
// stays a step above it at `Theme.fontSizeMedium` Bold.
//
// Two kinds of value are deliberately not on that scale. A drawn size is pixels,
// because it is geometry rather than spacing: a Window card's Ring, the activity
// chart's plot, a progress bar's height and radius. And a type size a step under
// the scale's floor is written `Theme.fontSizeSmall - 1`, DMS's own idiom for it,
// rather than as a bare number.
//
// Each Section component takes a `section` (its own entry in that list) and a
// shared `ctx`: the resolved Source state for a Source's tab, the ranking for the
// Overview's, plus the formatters and actions either needs. Both are bound rather
// than assigned, so the Sections stay reactive when the underlying state changes.
Column {
    id: root

    property var tab: null
    property var ctx: null

    width: parent.width
    spacing: Theme.spacingS

    function componentFor(type) {
        switch (type) {
        case "header":
            return headerComponent;
        case "accounts":
            return accountsComponent;
        case "login":
            return loginComponent;
        case "status":
            return statusComponent;
        case "windows":
            return windowsComponent;
        case "stats":
            return statsComponent;
        case "chart":
            return chartComponent;
        case "models":
            return modelsComponent;
        case "alltime":
            return alltimeComponent;
        case "overview":
            return overviewComponent;
        }
        return null;
    }

    Repeater {
        model: root.tab ? root.tab.sections : []

        delegate: Loader {
            id: sectionLoader

            width: root.width
            sourceComponent: root.componentFor(modelData.type)

            // A Section hides itself when it does not apply (a login card with
            // credentials present, a status card with the endpoint up, an
            // account selector with little to select). A Loader does not inherit
            // that, and a Column lays out a Loader on its height alone, so
            // without this every hidden card would leave a blank gap and push
            // the cards below it down.
            //
            // It reads `shown`, not `visible`. QML reports `visible` as false on
            // every item while an ancestor is hidden, and the popout primes its
            // content hidden, so mirroring `visible` hid every card and the body
            // stayed collapsed once the popout opened. `shown` is the Section's
            // own intent and ignores ancestors.
            visible: item ? item.shown !== false : true

            // Declarative bindings rather than assignments in onLoaded, so the
            // cards stay reactive and there is no window where the item exists
            // without its context.
            Binding {
                target: sectionLoader.item
                property: "section"
                value: modelData
                when: sectionLoader.item !== null
            }

            Binding {
                target: sectionLoader.item
                property: "ctx"
                value: root.ctx
                when: sectionLoader.item !== null
            }
        }
    }

    Component {
        id: headerComponent
        HeaderSection {}
    }

    Component {
        id: accountsComponent
        AccountsSection {}
    }

    Component {
        id: loginComponent
        LoginSection {}
    }

    Component {
        id: statusComponent
        StatusSection {}
    }

    Component {
        id: windowsComponent
        WindowsSection {}
    }

    Component {
        id: statsComponent
        StatsSection {}
    }

    Component {
        id: chartComponent
        ChartSection {}
    }

    Component {
        id: modelsComponent
        ModelsSection {}
    }

    Component {
        id: alltimeComponent
        AlltimeSection {}
    }

    Component {
        id: overviewComponent
        OverviewSection {}
    }
}
