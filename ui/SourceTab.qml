import QtQuick
import qs.Common

// Renders one Source's popout tab from its descriptor's Section list.
//
// Each Section component takes a `section` (its own descriptor entry) and a
// shared `ctx` (the resolved Source state plus the formatters and actions it
// needs). Both are bound rather than assigned, so the cards stay reactive when
// the underlying state changes.
Column {
    id: root

    property var descriptor: null
    property var ctx: null

    width: parent.width
    spacing: Theme.spacingL

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
        }
        return null;
    }

    Repeater {
        model: root.descriptor ? root.descriptor.sections : []

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
            visible: item ? item.visible : true

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
}
