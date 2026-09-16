import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Services
import qs.Widgets
import qs.Modules.Plugins
import "translations.js" as Tr
import "sources.js" as Sources
import "ui"

PluginComponent {
    id: root

    // i18n
    property string lang: (SessionData.locale || Qt.locale().name).split(/[_-]/)[0]
    function tr(key) {
        return Tr.tr(key, lang);
    }

    property int refreshEpoch: 0
    readonly property var dayLabelsByLanguage: ({
        en: ["Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"],
        fr: ["Lu", "Ma", "Me", "Je", "Ve", "Sa", "Di"],
        es: ["Lu", "Ma", "Mi", "Ju", "Vi", "Sá", "Do"]
    })
    property var dayLabels: dayLabelsByLanguage[lang] || dayLabelsByLanguage.en

    // --- Settings ---
    property int refreshInterval: (pluginData.refreshInterval || 2) * 60000
    property bool showPacing: pluginData.showPacing !== false
    property var customProfiles: pluginData.customProfiles || []
    property var customChatgptAccounts: pluginData.customChatgptAccounts || []
    property var customZaiAccounts: pluginData.customZaiAccounts || []
    property var customOpencodeAccounts: pluginData.customOpencodeAccounts || []
    property real usdEurRate: 0

    // The ordered list of enabled Sources. Order drives the pill rings and the
    // popout tabs. An absent value turns everything on; unknown ids are dropped
    // and newly added Sources appended, so a stale stored list heals itself.
    property var sourceOrder: Sources.resolveList(pluginData.sources)

    // --- Runtime state ---
    // sourceData and selectedAccount are keyed by Source id. accountData is
    // keyed by Source id and then Account name.
    property var sourceData: ({})
    property var accountData: ({})
    property var selectedAccount: ({})
    property var loginInProgress: ({})
    property var refreshPending: ({})
    property bool isLoading: true

    // Parallel to Sources.SOURCES: the Process for the Source at the same index.
    property var sourceProcesses: []

    // Live countdown, refreshed on its own timer so countdowns tick between
    // fetches.
    property real countdownNow: Date.now()
    property int todayIndex: {
        void (countdownNow);
        var dow = new Date().getDay();
        return dow === 0 ? 6 : dow - 1;
    }

    // --- Registry views ---

    readonly property var enabledDescriptors: {
        var out = [];
        for (var i = 0; i < sourceOrder.length; i++) {
            var d = Sources.byId(sourceOrder[i]);
            if (d)
                out.push(d);
        }
        return out;
    }

    // A Source is shown when it is enabled AND its script has not reported that
    // it is not installed. Credentials arriving as "unknown" before the first
    // fetch counts as shown, so the pill does not flicker.
    readonly property var visibleDescriptors: {
        void (sourceData);
        var out = [];
        for (var i = 0; i < enabledDescriptors.length; i++) {
            var d = enabledDescriptors[i];
            var st = sourceData[d.id];
            if (!st || st.credsStatus !== "not_installed")
                out.push(d);
        }
        return out;
    }

    readonly property var visibleIds: visibleDescriptors.map(function (d) {
        return d.id;
    })

    // Sources that still hold a current reading get a Pill Ring. A Source whose
    // endpoint is unavailable keeps its popout tab but drops out of the Pill,
    // so a stale percentage is never shown as though it were current.
    readonly property var pillDescriptors: {
        void (sourceData);
        var out = [];
        for (var i = 0; i < visibleDescriptors.length; i++) {
            var d = visibleDescriptors[i];
            var st = sourceData[d.id];
            if (!st || st.credsStatus !== "unavailable")
                out.push(d);
        }
        return out;
    }

    readonly property var pillIds: pillDescriptors.map(function (d) {
        return d.id;
    })

    // Empty until ensureActiveTab picks the first visible Source, which is the
    // first one in the configured order. Hardcoding an id here ignored that
    // order, and left nothing selected when the id named a Source that was off.
    // After the user picks a tab, this holds their choice for the session.
    property string popoutSourceTab: ""

    readonly property var activeDescriptor: Sources.byId(popoutSourceTab)

    onVisibleIdsChanged: {
        root.ensureActiveTab();
        root.updatePillVisibility();
    }

    onPillIdsChanged: root.updatePillVisibility()

    function ensureActiveTab() {
        var ids = root.visibleIds;
        if (ids.length === 0)
            return;
        if (ids.indexOf(root.popoutSourceTab) < 0)
            root.popoutSourceTab = ids[0];
    }

    function updatePillVisibility() {
        if (root.pillIds.length === 0)
            root.setVisibilityOverride(false);
        else
            root.clearVisibilityOverride();
    }

    Component.onCompleted: {
        root.ensureActiveTab();
        root.updatePillVisibility();
    }

    // --- Per-Source state ---

    function emptyState() {
        return {
            credsStatus: "unknown",
            // True once a fetch has reported a good reading. An endpoint failure
            // with nothing to fall back on shows no Window cards at all rather
            // than a fabricated zero.
            hasData: false,
            plan: "",
            planTier: "",
            extraUsageEnabled: false,
            primary: { util: 0, resetMs: 0, windowSeconds: 0 },
            secondary: { util: 0, resetMs: 0, windowSeconds: 0 },
            weekTokens: 0,
            monthTokens: 0,
            weekCalls: 0,
            weekMessages: 0,
            weekSessions: 0,
            todayCost: 0,
            weekCost: 0,
            monthCost: 0,
            dailyTokens: [0, 0, 0, 0, 0, 0, 0],
            dailyCosts: [0, 0, 0, 0, 0, 0, 0],
            models: [],
            alltime: { sessions: 0, messages: 0, firstSession: "" },
            accounts: []
        };
    }

    function updateSource(id, mutate) {
        var next = Object.assign({}, root.sourceData);
        var st = Object.assign({}, next[id] || root.emptyState());
        mutate(st);
        next[id] = st;
        root.sourceData = next;
    }

    function setWindow(st, which, field, value) {
        var w = Object.assign({}, st[which] || { util: 0, resetMs: 0, windowSeconds: 0 });
        w[field] = value;
        st[which] = w;
    }

    // The Source's Window length. Prefers what the script reported and falls
    // back to the descriptor, which is where fixed-length Sources declare it.
    function windowSeconds(id, which) {
        var st = root.sourceData[id];
        var w = st ? st[which] : null;
        if (w && w.windowSeconds > 0)
            return w.windowSeconds;
        var d = Sources.byId(id);
        if (d && d.windows[which] && d.windows[which].windowSeconds)
            return d.windows[which].windowSeconds;
        return 0;
    }

    // The state a Section renders: the Source's aggregate values, with the
    // selected Account's values laid over them when one is selected.
    function stateFor(id) {
        var base = root.sourceData[id];
        if (!base)
            return null;

        var sel = root.selectedAccount[id] || "all";
        var pd = sel !== "all" ? (root.accountData[id] || {})[sel] : null;
        var st = Object.assign({}, base);
        st.id = id;

        if (pd) {
            if (pd.weekTokens !== undefined)
                st.weekTokens = pd.weekTokens;
            if (pd.monthTokens !== undefined)
                st.monthTokens = pd.monthTokens;
            if (pd.weekMessages !== undefined)
                st.weekMessages = pd.weekMessages;
            if (pd.weekSessions !== undefined)
                st.weekSessions = pd.weekSessions;
            if (pd.todayCost !== undefined)
                st.todayCost = pd.todayCost;
            if (pd.weekCost !== undefined)
                st.weekCost = pd.weekCost;
            if (pd.monthCost !== undefined)
                st.monthCost = pd.monthCost;
            if (pd.subscriptionType !== undefined)
                st.plan = pd.subscriptionType;
            if (pd.rateLimitTier !== undefined)
                st.planTier = pd.rateLimitTier;
            if (pd.credsStatus !== undefined)
                st.credsStatus = pd.credsStatus;
            if (pd.extraUsageEnabled !== undefined)
                st.extraUsageEnabled = pd.extraUsageEnabled;
            st.primary = {
                util: pd.fiveHourUtil !== undefined ? pd.fiveHourUtil : base.primary.util,
                resetMs: pd.fiveHourReset !== undefined ? root.parseResetMs(pd.fiveHourReset) : base.primary.resetMs,
                windowSeconds: base.primary.windowSeconds
            };
            st.secondary = {
                util: pd.sevenDayUtil !== undefined ? pd.sevenDayUtil : base.secondary.util,
                resetMs: pd.sevenDayReset !== undefined ? root.parseResetMs(pd.sevenDayReset) : base.secondary.resetMs,
                windowSeconds: base.secondary.windowSeconds
            };
            st.dailyTokens = pd.daily || base.dailyTokens;
            st.dailyCosts = pd.dailyCosts || base.dailyCosts;
            st.accountDaily = pd.daily || [];
            st.models = pd.weekModels || [];
            // All-time figures are only tracked in aggregate.
            st.alltime = { sessions: 0, messages: 0, firstSession: "" };
        }

        st.todayTokens = (st.dailyTokens && st.dailyTokens[root.todayIndex]) || 0;
        return st;
    }

    function paceFor(source, which) {
        if (!source)
            return null;
        var w = source[which] || {};
        return root.paceInfo(w.util || 0, w.resetMs || 0, root.windowSeconds(source.id, which) * 1000);
    }

    function countdownFor(source, which) {
        if (!source)
            return "";
        var w = source[which] || {};
        return root.formatCountdown(w.resetMs || 0);
    }

    function windowLabelFor(source, which) {
        if (!source)
            return "";
        var d = Sources.byId(source.id);
        var w = d && d.windows[which] ? d.windows[which] : null;
        if (w && w.labelKey)
            return root.tr(w.labelKey);
        var generic = which === "primary" ? "Primary Window" : "Secondary Window";
        return root.formatWindowLabel(root.windowSeconds(source.id, which), generic);
    }

    function accountNames(id) {
        var st = root.sourceData[id];
        var names = st && st.accounts ? st.accounts.slice() : [];
        if (names.indexOf("all") < 0)
            names.unshift("all");
        return names;
    }

    function selectAccount(id, name) {
        var next = Object.assign({}, root.selectedAccount);
        next[id] = name;
        root.selectedAccount = next;
    }

    // --- Fetching ---

    function scriptPathFor(id) {
        var d = Sources.byId(id);
        return PluginService.pluginDirectory + "/" + root.pluginId + "/" + d.script;
    }

    function settingList(key) {
        if (key === "customProfiles")
            return root.customProfiles;
        if (key === "customChatgptAccounts")
            return root.customChatgptAccounts;
        if (key === "customZaiAccounts")
            return root.customZaiAccounts;
        if (key === "customOpencodeAccounts")
            return root.customOpencodeAccounts;
        return [];
    }

    function accountArgs(id) {
        var d = Sources.byId(id);
        if (!d.accounts)
            return [];
        var field = d.accounts.argField;
        var list = root.settingList(d.accounts.settingKey);
        var out = [];
        for (var i = 0; i < list.length; i++) {
            var a = list[i];
            if (a && a.name && a[field])
                out.push(a.name + "=" + a[field]);
        }
        return out;
    }

    function commandFor(id) {
        return ["timeout", "120", "bash", root.scriptPathFor(id)].concat(root.accountArgs(id));
    }

    function processFor(id) {
        var at = Sources.ids().indexOf(id);
        return at >= 0 && root.sourceProcesses[at] ? root.sourceProcesses[at] : null;
    }

    // Wrapped in `timeout` as a watchdog: a run that never exits (a hung
    // `claude --version`, a stalled curl) would otherwise freeze that Source on
    // stale values until the plugin reloaded.
    function requestFetch(id) {
        var p = root.processFor(id);
        if (!p)
            return;
        if (p.running) {
            var next = Object.assign({}, root.refreshPending);
            next[id] = true;
            root.refreshPending = next;
        } else {
            p.running = true;
        }
    }

    function fetchVisible() {
        for (var i = 0; i < root.visibleIds.length; i++)
            root.requestFetch(root.visibleIds[i]);
    }

    function accountsChanged(settingKey) {
        for (var i = 0; i < Sources.SOURCES.length; i++) {
            var d = Sources.SOURCES[i];
            if (d.accounts && d.accounts.settingKey === settingKey && root.sourceOrder.indexOf(d.id) >= 0)
                root.requestFetch(d.id);
        }
    }

    onCustomProfilesChanged: root.accountsChanged("customProfiles")
    onCustomChatgptAccountsChanged: root.accountsChanged("customChatgptAccounts")
    onCustomZaiAccountsChanged: root.accountsChanged("customZaiAccounts")
    onCustomOpencodeAccountsChanged: root.accountsChanged("customOpencodeAccounts")

    // Toggling a Source on fetches immediately rather than waiting a tick.
    onSourceOrderChanged: {
        root.ensureActiveTab();
        root.updatePillVisibility();
        for (var i = 0; i < root.sourceOrder.length; i++)
            root.requestFetch(root.sourceOrder[i]);
    }

    function onSourceExited(id, exitCode) {
        if (exitCode === 0)
            root.isLoading = false;
        var pending = root.refreshPending[id];
        if (pending) {
            var next = Object.assign({}, root.refreshPending);
            delete next[id];
            root.refreshPending = next;
            Qt.callLater(function () {
                root.requestFetch(id);
            });
        }
    }

    function setLoginInProgress(id, value) {
        var next = Object.assign({}, root.loginInProgress);
        next[id] = value;
        root.loginInProgress = next;
    }

    Instantiator {
        id: processPool
        model: Sources.SOURCES

        delegate: Process {
            required property var modelData

            readonly property string sourceId: modelData.id

            command: root.commandFor(sourceId)
            running: false

            stdout: SplitParser {
                onRead: data => root.parseLine(sourceId, data.trim())
            }

            onExited: (exitCode, exitStatus) => root.onSourceExited(sourceId, exitCode)
        }

        // Indexed by model position rather than by a property on the created
        // object, which keeps the delegate's identity out of these handlers.
        onObjectAdded: (index, object) => {
            var next = root.sourceProcesses.slice();
            next[index] = object;
            root.sourceProcesses = next;
        }

        onObjectRemoved: (index, object) => {
            var next = root.sourceProcesses.slice();
            next[index] = null;
            root.sourceProcesses = next;
        }
    }

    // Countdown tick. Also refetches a Source whose Window has just reset, so it
    // does not sit on "Resetting..." until the next scheduled poll, and refetches
    // everything after a gap long enough to mean the machine woke from sleep.
    Timer {
        interval: 60000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            var now = Date.now();
            var elapsed = now - root.countdownNow;
            root.countdownNow = now;

            if (elapsed > 120000) {
                root.fetchVisible();
                return;
            }
            for (var i = 0; i < root.visibleIds.length; i++) {
                var id = root.visibleIds[i];
                var st = root.sourceData[id];
                if (!st)
                    continue;
                var expired = (st.primary.resetMs && st.primary.resetMs <= now) || (st.secondary.resetMs && st.secondary.resetMs <= now);
                if (expired)
                    root.requestFetch(id);
            }
        }
    }

    Timer {
        interval: root.refreshInterval
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.fetchVisible()
    }

    // --- CLI logins ---

    function startLogin(action) {
        if (action === "claudeLogin") {
            if (claudeLoginProcess.running)
                return;
            var profile = root.selectedAccount["claude"] || "all";
            var dir = root.configDirForProfile(profile);
            var envPrefix = dir ? "CLAUDE_CONFIG_DIR=" + root.shellQuote(dir) + " " : "";
            claudeLoginProcess.command = ["bash", "-c", envPrefix + "PATH=\"$PATH:" + root.cliSearchPathAdditions + "\" exec claude auth login --claudeai"];
            root.setLoginInProgress("claude", true);
            claudeLoginProcess.running = true;
        } else if (action === "chatgptLogin") {
            if (chatgptLoginProcess.running)
                return;
            root.setLoginInProgress("chatgpt", true);
            chatgptLoginProcess.running = true;
        }
    }

    // `command` is set by startLogin rather than declared, because Quickshell's
    // own PATH is a bare `/usr/local/bin:/usr/bin` and would not find a `claude`
    // under ~/.local/bin or ~/.npm-global/bin, leaving the button stuck on
    // "Logging in…" because the Process never spawned and never exited.
    Process {
        id: claudeLoginProcess
        running: false

        onExited: (exitCode, exitStatus) => {
            root.setLoginInProgress("claude", false);
            root.requestFetch("claude");
        }
    }

    Process {
        id: chatgptLoginProcess
        command: ["bash", "-c", "PATH=\"$PATH:" + root.cliSearchPathAdditions + "\" exec codex login"]
        running: false

        onExited: (exitCode, exitStatus) => {
            root.setLoginInProgress("chatgpt", false);
            root.requestFetch("chatgpt");
        }
    }

    popoutWidth: 380
    popoutHeight: 740

    // --- Shared helpers exposed to the Section components ---

    readonly property QtObject api: QtObject {
        function tr(key) {
            return root.tr(key);
        }

        function formatTokens(n) {
            return root.formatTokens(n);
        }

        function formatCost(usd) {
            return root.formatCost(usd);
        }

        function shortModelName(name) {
            return root.shortModelName(name);
        }

        function progressColor(pct) {
            return root.progressColor(pct);
        }

        function formatSubscription(subType, tier) {
            return root.formatSubscription(subType, tier);
        }

        function pace(source, which) {
            return root.paceFor(source, which);
        }

        function countdown(source, which) {
            return root.countdownFor(source, which);
        }

        function windowLabel(source, which) {
            return root.windowLabelFor(source, which);
        }

        function paceLabel(p) {
            return root.paceLabel(p);
        }

        function paceColor(status) {
            return root.paceColor(status);
        }

        function startLogin(action) {
            root.startLogin(action);
        }

        function selectAccount(id, name) {
            root.selectAccount(id, name);
        }
    }

    // Everything a Section needs beyond its own descriptor entry.
    function contextFor(id) {
        var d = Sources.byId(id);
        var sel = root.selectedAccount[id] || "all";
        return {
            source: root.stateFor(id),
            api: root.api,
            descriptor: d,
            label: d ? root.tr(d.labelKey) : "",
            showPacing: root.showPacing,
            dayLabels: root.dayLabels,
            todayIndex: root.todayIndex,
            accounts: root.accountNames(id),
            selected: sel,
            accountSelected: sel !== "all",
            accountName: sel,
            loginInProgress: root.loginInProgress[id] === true
        };
    }

    // --- Taskbar pills ---

    horizontalBarPill: Component {
        Row {
            spacing: Theme.spacingXS

            Repeater {
                model: root.pillDescriptors

                delegate: Row {
                    id: hGroup
                    required property var modelData

                    spacing: Theme.spacingXS

                    Rectangle {
                        width: 1
                        height: root.iconSize * 0.7
                        anchors.verticalCenter: parent.verticalCenter
                        color: Theme.outline
                        opacity: 0.5
                        visible: index > 0
                    }

                    Ring {
                        width: root.iconSize
                        height: root.iconSize
                        anchors.verticalCenter: parent.verticalCenter
                        percent: root.stateFor(hGroup.modelData.id) ? root.stateFor(hGroup.modelData.id).primary.util : 0
                        pace: root.paceFor(root.stateFor(hGroup.modelData.id), "primary")
                        showPaceTick: false
                    }

                    StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        text: {
                            var st = root.stateFor(hGroup.modelData.id);
                            var p = root.paceFor(st, "primary");
                            var over = root.showPacing && p && (p.status === "over" || p.status === "over_quota");
                            return Math.round(st ? st.primary.util : 0) + "%" + (over ? " ↑" : "");
                        }
                        font.pixelSize: Theme.barTextSize(root.barThickness, root.barConfig?.fontScale, root.barConfig?.maximizeWidgetText)
                        color: {
                            var p = root.paceFor(root.stateFor(hGroup.modelData.id), "primary");
                            var over = root.showPacing && p && (p.status === "over" || p.status === "over_quota");
                            return over ? root.paceColor(p.status) : Theme.surfaceText;
                        }
                    }
                }
            }
        }
    }

    verticalBarPill: Component {
        Column {
            spacing: Theme.spacingXS || 4

            Repeater {
                model: root.pillDescriptors

                delegate: Column {
                    id: vGroup
                    required property var modelData

                    spacing: Theme.spacingXS || 4

                    Rectangle {
                        width: root.iconSize * 0.7
                        height: 1
                        anchors.horizontalCenter: parent.horizontalCenter
                        color: Theme.outline
                        opacity: 0.5
                        visible: index > 0
                    }

                    Ring {
                        width: root.iconSize
                        height: root.iconSize
                        anchors.horizontalCenter: parent.horizontalCenter
                        percent: root.stateFor(vGroup.modelData.id) ? root.stateFor(vGroup.modelData.id).primary.util : 0
                        pace: root.paceFor(root.stateFor(vGroup.modelData.id), "primary")
                        showPaceTick: false
                    }

                    StyledText {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: {
                            var st = root.stateFor(vGroup.modelData.id);
                            var p = root.paceFor(st, "primary");
                            var over = root.showPacing && p && (p.status === "over" || p.status === "over_quota");
                            return Math.round(st ? st.primary.util : 0) + "%" + (over ? " ↑" : "");
                        }
                        font.pixelSize: Theme.barTextSize(root.barThickness, root.barConfig?.fontScale, root.barConfig?.maximizeWidgetText)
                        color: {
                            var p = root.paceFor(root.stateFor(vGroup.modelData.id), "primary");
                            var over = root.showPacing && p && (p.status === "over" || p.status === "over_quota");
                            return over ? root.paceColor(p.status) : Theme.surfaceText;
                        }
                    }
                }
            }
        }
    }

    // --- Popout ---

    popoutContent: Component {
        PopoutComponent {
            headerText: root.tr("AI Usage")
            showCloseButton: true

            Column {
                width: parent.width - Theme.spacingM * 2
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: Theme.spacingL

                // Only one Source's cards render at a time, keeping the popout
                // short on small screens. Hidden when there is nothing to switch
                // between; an all-hidden pill already hides the whole widget.
                Row {
                    width: parent.width
                    spacing: Theme.spacingXS
                    visible: root.visibleDescriptors.length > 1

                    Repeater {
                        model: root.visibleDescriptors

                        delegate: Rectangle {
                            required property var modelData

                            width: (parent.width - Theme.spacingXS * (root.visibleDescriptors.length - 1)) / root.visibleDescriptors.length
                            height: 32
                            radius: 16
                            color: root.popoutSourceTab === modelData.id ? Theme.primary : Theme.surfaceVariant

                            Behavior on color {
                                ColorAnimation {
                                    duration: 120
                                }
                            }

                            StyledText {
                                anchors.centerIn: parent
                                text: root.tr(modelData.labelKey)
                                font.pixelSize: Theme.fontSizeSmall
                                font.weight: root.popoutSourceTab === modelData.id ? Font.Medium : Font.Normal
                                color: root.popoutSourceTab === modelData.id ? Theme.primaryText : Theme.surfaceVariantText
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.popoutSourceTab = modelData.id
                            }
                        }
                    }
                }

                SourceTab {
                    descriptor: root.activeDescriptor
                    ctx: root.activeDescriptor ? root.contextFor(root.activeDescriptor.id) : null
                }

                // Bottom padding to match the sides, compensating Column spacing.
                Item {
                    width: 1
                    height: 1
                }
            }
        }
    }

    // --- Helpers ---

    function formatTokens(n) {
        if (n >= 1000000000)
            return (n / 1000000000).toFixed(1) + "B";
        if (n >= 1000000)
            return (n / 1000000).toFixed(1) + "M";
        if (n >= 1000)
            return (n / 1000).toFixed(1) + "K";
        return Math.round(n).toString();
    }

    function shortModelName(name) {
        if (!name || name.length === 0)
            return name;
        return name.charAt(0).toUpperCase() + name.slice(1);
    }

    function progressColor(pct) {
        if (pct > 80)
            return Theme.error;
        if (pct > 50)
            return Theme.warning;
        return Theme.primary;
    }

    // Returns { timeFrac, delta, status } for a usage window.
    // status: over_quota | over | under | on | unknown
    function paceInfo(util, resetMs, windowMs) {
        util = util || 0;
        if (!resetMs || !windowMs)
            return util >= 100 ? {
                timeFrac: 1,
                delta: util,
                status: "over_quota"
            } : {
                timeFrac: 0,
                delta: 0,
                status: "unknown"
            };
        var remaining = resetMs - countdownNow;
        var timeFrac = (windowMs - remaining) / windowMs;
        if (timeFrac < 0)
            timeFrac = 0;
        else if (timeFrac > 1)
            timeFrac = 1;
        var delta = util - timeFrac * 100;
        var status;
        if (util >= 100)
            status = "over_quota";
        else if (delta >= 5)
            status = "over";
        else if (delta <= -5)
            status = "under";
        else
            status = "on";
        return {
            timeFrac: timeFrac,
            delta: delta,
            status: status
        };
    }

    function paceLabel(p) {
        if (!p)
            return "";
        if (p.status === "over_quota")
            return tr("Over quota");
        if (p.status === "over")
            return Math.round(p.delta) + "% " + tr("over pace");
        if (p.status === "under")
            return Math.round(-p.delta) + "% " + tr("under pace");
        if (p.status === "on")
            return tr("On pace");
        return "";
    }

    function paceColor(status) {
        if (status === "over_quota")
            return Theme.error;
        if (status === "over")
            return Theme.warning;
        return Theme.surfaceVariantText;
    }

    // Local wall clock of a reset instant, appended to countdowns so they can be
    // reconciled against provider dashboards that render resets in their own
    // timezone (Z.ai's shows Asia/Shanghai). The date appears only when the
    // reset falls on another calendar day.
    function resetClockLabel(resetMs) {
        var resetDate = new Date(resetMs);
        var sameDay = Qt.formatDateTime(resetDate, "yyyy-MM-dd") === Qt.formatDateTime(new Date(), "yyyy-MM-dd");
        if (!sameDay)
            return " (" + Qt.formatDateTime(resetDate, "ddd HH:mm") + ")";
        return " (" + Qt.formatDateTime(resetDate, "HH:mm") + ")";
    }

    function formatCountdown(resetMs) {
        void (countdownNow);
        if (!resetMs)
            return "";
        var remaining = Math.max(0, resetMs - countdownNow);
        if (remaining <= 0)
            return tr("Resetting...");
        var days = Math.floor(remaining / 86400000);
        var hours = Math.floor((remaining % 86400000) / 3600000);
        var mins = Math.floor((remaining % 3600000) / 60000);
        if (days > 0)
            return days + "d " + hours + "h " + (mins < 10 ? "0" : "") + mins + "m" + resetClockLabel(resetMs);
        return hours + "h " + (mins < 10 ? "0" : "") + mins + "m" + resetClockLabel(resetMs);
    }

    // Unix-seconds strings are all-digit; ISO-8601 strings always contain a
    // non-digit (dashes, "T", colons), so a digit-only test tells them apart.
    function parseResetMs(val) {
        if (!val)
            return 0;
        if (/^[0-9]+$/.test(val))
            return parseFloat(val) * 1000;
        var ms = new Date(val).getTime();
        return isNaN(ms) ? 0 : ms;
    }

    // `wham/usage` names its windows "primary" and "secondary" with no fixed
    // duration in the field name, but does carry each window's length, so label
    // with the real duration. genericKey covers the window before its length has
    // arrived (0 means not fetched, not "unknown length").
    function formatWindowLabel(seconds, genericKey) {
        if (!seconds || seconds <= 0)
            return root.tr(genericKey);
        if (seconds === 604800)
            return root.tr("Weekly Window");
        if (seconds === 18000)
            return root.tr("5h Window");
        if (seconds % 86400 === 0)
            return (seconds / 86400) + "d " + root.tr("Window");
        var hours = Math.round(seconds / 3600);
        return hours + "h " + root.tr("Window");
    }

    function formatCost(usd) {
        var useEur = lang === "fr" && usdEurRate > 0;
        var n = useEur ? usd * usdEurRate : usd;
        var sym = useEur ? "" : "$";
        var suffix = useEur ? " €" : "";
        if (n >= 1000)
            return sym + (n / 1000).toFixed(1) + "K" + suffix;
        if (n >= 100)
            return sym + Math.round(n) + suffix;
        if (n >= 10)
            return sym + n.toFixed(1) + suffix;
        return sym + n.toFixed(2) + suffix;
    }

    function formatTier(tier) {
        if (!tier || tier === "unknown")
            return "";
        if (tier.indexOf("max_20x") >= 0)
            return tr("Max") + " 20x";
        if (tier.indexOf("max_5x") >= 0)
            return tr("Max") + " 5x";
        if (tier.indexOf("max") >= 0)
            return tr("Max");
        if (tier.indexOf("pro") >= 0)
            return tr("Pro");
        if (tier.indexOf("free") >= 0)
            return tr("Free");
        if (tier.indexOf("team") >= 0)
            return tr("Team");
        if (tier.indexOf("enterprise") >= 0)
            return tr("Enterprise");
        return tier.replace(/_/g, " ").replace(/\b\w/g, function (c) {
            return c.toUpperCase();
        });
    }

    function formatSubscription(subType, tier) {
        var tierLabel = formatTier(tier);
        if (!subType || subType === "unknown")
            return tierLabel;
        // Normalize subscriptionType like "claude_pro" → "Pro", "claude_max" → "Max"
        var subLabel = subType.replace(/^claude[_-]?/i, "").replace(/_/g, " ").replace(/\b\w/g, function (c) {
            return c.toUpperCase();
        });
        if (tierLabel && tierLabel !== subLabel)
            return subLabel + " · " + tierLabel;
        return subLabel || tierLabel;
    }

    // Resolves the CLAUDE_CONFIG_DIR to log into for a given Account name.
    // "all"/"default" (or unrecognized names, e.g. auto-discovered ccs/ccp
    // profiles the widget doesn't know the path for) fall back to "" — the login
    // command's own default (~/.claude).
    function configDirForProfile(name) {
        if (!name || name === "all" || name === "default")
            return "";
        for (var i = 0; i < root.customProfiles.length; i++) {
            var p = root.customProfiles[i];
            if (p && p.name === name && p.path)
                return p.path;
        }
        return "";
    }

    // Common install locations for CLIs installed via nvm/npm/cargo/etc, not
    // covered by Quickshell's own bare PATH. The login commands run via `bash -c`
    // with this same widening so `claude`/`codex` resolve wherever they live.
    readonly property string cliSearchPathAdditions: "$HOME/.local/bin:$HOME/.npm-global/bin:$HOME/bin:$HOME/go/bin:$HOME/.cargo/bin:$HOME/.volta/bin:$HOME/.claude/local"

    function shellQuote(s) {
        return "'" + String(s).replace(/'/g, "'\\''") + "'";
    }

    // --- Script output parsing ---

    // Applies a CREDS_STATUS value to one Source's state. A good reading is the
    // only thing that counts as data; an endpoint failure reports no Window
    // values, so the last good reading survives in state and the status card
    // above it marks those values as stale rather than current.
    function applyCredsStatus(st, val) {
        st.credsStatus = val;
        if (val === "ok")
            st.hasData = true;
    }

    function parseLine(id, line) {
        if (!line)
            return;
        var idx = line.indexOf("=");
        if (idx < 0)
            return;
        var key = line.substring(0, idx);
        var val = line.substring(idx + 1);
        var d = Sources.byId(id);
        if (!d)
            return;

        // Window keys are named by the descriptor, so what each Source calls its
        // primary and secondary windows does not matter here. The Account keys
        // are handled here too rather than in the switch below, because they
        // write a different map and nesting two state writes would let the
        // outer one clobber the inner.
        if (root.parseWindowKey(d, id, "primary", key, val))
            return;
        if (root.parseWindowKey(d, id, "secondary", key, val))
            return;
        if (root.parseAccountKey(id, key, val))
            return;

        root.updateSource(id, function (st) {
            switch (key) {
            case "PLAN_TYPE":
                st.plan = val;
                break;
            case "SUBSCRIPTION_TYPE":
                st.plan = val;
                break;
            case "RATE_LIMIT_TIER":
                st.planTier = val;
                break;
            case "EXTRA_USAGE_ENABLED":
                st.extraUsageEnabled = (val === "true");
                break;
            case "CREDS_STATUS":
                root.applyCredsStatus(st, val);
                break;
            case "WEEK_MESSAGES":
                st.weekMessages = parseInt(val) || 0;
                break;
            case "WEEK_SESSIONS":
                st.weekSessions = parseInt(val) || 0;
                break;
            case "WEEK_CALLS":
                st.weekCalls = parseInt(val) || 0;
                break;
            case "WEEK_TOKENS":
                st.weekTokens = parseFloat(val) || 0;
                break;
            case "MONTH_TOKENS":
                st.monthTokens = parseFloat(val) || 0;
                break;
            case "ALLTIME_SESSIONS":
                st.alltime = Object.assign({}, st.alltime, { sessions: parseInt(val) || 0 });
                break;
            case "ALLTIME_MESSAGES":
                st.alltime = Object.assign({}, st.alltime, { messages: parseInt(val) || 0 });
                break;
            case "FIRST_SESSION":
                st.alltime = Object.assign({}, st.alltime, { firstSession: val });
                break;
            case "WEEK_MODELS":
                st.models = root.parseModels(val);
                break;
            case "DAILY":
                st.dailyTokens = root.parseDaily(val);
                break;
            case "DAILY_COSTS":
                st.dailyCosts = root.parseDaily(val);
                break;
            case "TODAY_COST":
                st.todayCost = parseFloat(val) || 0;
                break;
            case "WEEK_COST":
                st.weekCost = parseFloat(val) || 0;
                break;
            case "MONTH_COST":
                st.monthCost = parseFloat(val) || 0;
                break;
            case "USD_EUR_RATE":
                root.usdEurRate = parseFloat(val) || 0;
                break;
            case "ACCOUNTS":
                st.accounts = val.length > 0 ? val.split(",") : [];
                break;
            }
        });
    }

    // Account keys write the per-Account overlay map rather than the Source's
    // own state, so they are dispatched separately. Returns true when handled.
    function parseAccountKey(id, key, val) {
        switch (key) {
        case "PROFILES":
            root.applyAccounts(id, val);
            return true;
        case "PROFILE_SUBSCRIPTION":
            root.applyAccountField(id, val, "subscriptionType");
            return true;
        case "PROFILE_TIER":
            root.applyAccountField(id, val, "rateLimitTier");
            return true;
        case "PROFILE_CREDS_STATUS":
            root.applyAccountField(id, val, "credsStatus");
            return true;
        case "PROFILE_FIVE_HOUR_RESET":
            root.applyAccountField(id, val, "fiveHourReset");
            return true;
        case "PROFILE_SEVEN_DAY_RESET":
            root.applyAccountField(id, val, "sevenDayReset");
            return true;
        case "PROFILE_WEEK_TOKENS":
            root.applyAccountNumber(id, val, "weekTokens");
            return true;
        case "PROFILE_MONTH_TOKENS":
            root.applyAccountNumber(id, val, "monthTokens");
            return true;
        case "PROFILE_WEEK_MESSAGES":
            root.applyAccountNumber(id, val, "weekMessages");
            return true;
        case "PROFILE_WEEK_SESSIONS":
            root.applyAccountNumber(id, val, "weekSessions");
            return true;
        case "PROFILE_FIVE_HOUR_UTIL":
            root.applyAccountNumber(id, val, "fiveHourUtil");
            return true;
        case "PROFILE_SEVEN_DAY_UTIL":
            root.applyAccountNumber(id, val, "sevenDayUtil");
            return true;
        case "PROFILE_TODAY_COST":
            root.applyAccountNumber(id, val, "todayCost");
            return true;
        case "PROFILE_WEEK_COST":
            root.applyAccountNumber(id, val, "weekCost");
            return true;
        case "PROFILE_MONTH_COST":
            root.applyAccountNumber(id, val, "monthCost");
            return true;
        case "PROFILE_EXTRA_USAGE":
            root.applyAccountBool(id, val, "extraUsageEnabled");
            return true;
        case "PROFILE_DAILY":
            root.applyAccountList(id, val, "daily");
            return true;
        case "PROFILE_DAILY_COSTS":
            root.applyAccountList(id, val, "dailyCosts");
            return true;
        case "PROFILE_WEEK_MODELS":
            root.applyAccountModels(id, val);
            return true;
        }
        return false;
    }

    function parseWindowKey(d, id, which, key, val) {
        var w = d.windows[which];
        if (!w)
            return false;
        if (key === w.util) {
            root.updateSource(id, function (st) {
                root.setWindow(st, which, "util", parseFloat(val) || 0);
            });
            return true;
        }
        if (key === w.reset) {
            root.updateSource(id, function (st) {
                root.setWindow(st, which, "resetMs", root.parseResetMs(val));
            });
            return true;
        }
        if (w.windowSecondsKey && key === w.windowSecondsKey) {
            root.updateSource(id, function (st) {
                root.setWindow(st, which, "windowSeconds", parseFloat(val) || 0);
            });
            return true;
        }
        return false;
    }

    function parseDaily(val) {
        var parts = val.split(",");
        var arr = [];
        for (var i = 0; i < 7; i++)
            arr.push(i < parts.length ? (parseFloat(parts[i]) || 0) : 0);
        return arr;
    }

    function parseModels(val) {
        var out = [];
        if (!val || val.length === 0)
            return out;
        var pairs = val.split(",");
        for (var i = 0; i < pairs.length; i++) {
            var eq = pairs[i].indexOf("=");
            if (eq >= 0)
                out.push({
                    modelName: pairs[i].substring(0, eq),
                    modelTokens: parseInt(pairs[i].substring(eq + 1)) || 0
                });
        }
        return out;
    }

    // --- Per-Account overlay state ---

    // "name:a,b,c|name2:..." — a per-Account 7-day series.
    function parseAccountSeries(val) {
        var out = {};
        var blocks = val.split("|");
        for (var i = 0; i < blocks.length; i++) {
            var colon = blocks[i].indexOf(":");
            if (colon < 0)
                continue;
            out[blocks[i].substring(0, colon)] = root.parseDaily(blocks[i].substring(colon + 1));
        }
        return out;
    }

    // "name:value,name2:value2" — a per-Account scalar.
    function parseAccountScalars(val) {
        var out = {};
        var entries = val.split(",");
        for (var i = 0; i < entries.length; i++) {
            var colon = entries[i].indexOf(":");
            if (colon < 0)
                continue;
            out[entries[i].substring(0, colon)] = entries[i].substring(colon + 1);
        }
        return out;
    }

    // "name:model=123,model2=456|name2:..." — per-Account model breakdowns.
    function parseAccountModels(val) {
        var out = {};
        var blocks = val.split("|");
        for (var i = 0; i < blocks.length; i++) {
            var colon = blocks[i].indexOf(":");
            if (colon < 0)
                continue;
            out[blocks[i].substring(0, colon)] = root.parseModels(blocks[i].substring(colon + 1));
        }
        return out;
    }

    function mutateAccounts(id, mutate) {
        var next = Object.assign({}, root.accountData);
        var forSource = Object.assign({}, next[id] || {});
        mutate(function (name) {
            if (!forSource[name])
                forSource[name] = {};
            else
                forSource[name] = Object.assign({}, forSource[name]);
            return forSource[name];
        });
        next[id] = forSource;
        root.accountData = next;
    }

    function applyAccounts(id, val) {
        var names = val.length > 0 ? val.split(",") : [];
        root.updateSource(id, function (st) {
            st.accounts = names;
        });
        // Drop a selection that no longer exists so the tab falls back to the
        // aggregate rather than showing an empty overlay.
        var sel = root.selectedAccount[id] || "all";
        if (sel !== "all" && names.indexOf(sel) < 0)
            root.selectAccount(id, "all");
    }

    function applyAccountField(id, val, field) {
        var scalars = root.parseAccountScalars(val);
        root.mutateAccounts(id, function (acct) {
            for (var name in scalars)
                acct(name)[field] = scalars[name];
        });
    }

    function applyAccountNumber(id, val, field) {
        var scalars = root.parseAccountScalars(val);
        root.mutateAccounts(id, function (acct) {
            for (var name in scalars)
                acct(name)[field] = parseFloat(scalars[name]) || 0;
        });
    }

    function applyAccountBool(id, val, field) {
        var scalars = root.parseAccountScalars(val);
        root.mutateAccounts(id, function (acct) {
            for (var name in scalars)
                acct(name)[field] = scalars[name] === "true";
        });
    }

    function applyAccountList(id, val, field) {
        var series = root.parseAccountSeries(val);
        root.mutateAccounts(id, function (acct) {
            for (var name in series)
                acct(name)[field] = series[name];
        });
    }

    function applyAccountModels(id, val) {
        var models = root.parseAccountModels(val);
        root.mutateAccounts(id, function (acct) {
            for (var name in models)
                acct(name).weekModels = models[name];
        });
    }
}
