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
    // The Overview is its own toggle, not a member of sourceOrder: it ranks
    // Sources against each other and is never movable (ADR 0003).
    property bool overviewEnabled: pluginData.overviewEnabled !== false
    // Every Source's custom Account list, keyed by the setting key its
    // descriptor declares. One binding rather than a property and a change
    // handler per Source, so a Source added to the registry needs no widget
    // edit; pluginData is reassigned whole when settings are saved, which
    // re-evaluates this binding.
    property var accountSettings: {
        var out = {};
        for (var i = 0; i < Sources.SOURCES.length; i++) {
            var d = Sources.SOURCES[i];
            if (d.accounts)
                out[d.accounts.settingKey] = pluginData[d.accounts.settingKey] || [];
        }
        return out;
    }
    property var lastAccountSettings: null
    property real usdEurRate: 0

    // The ordered list of enabled Sources. Order drives the pill rings and the
    // popout tabs. An absent value turns everything on; unknown ids are dropped
    // and newly added Sources appended, so a stale stored list heals itself.
    property var sourceOrder: Sources.resolveList(pluginData.sources, pluginData.sourcesKnown)

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

    // Empty until the user picks a tab. The popout prefers that choice, and
    // otherwise falls back to the first visible Source, which is the first one
    // in the configured order. Deriving the active id rather than storing it
    // means the popout can never come up with nothing selected.
    property string popoutSourceTab: ""

    readonly property string activeSourceId: {
        var ids = root.visibleIds;
        if (root.popoutSourceTab && ids.indexOf(root.popoutSourceTab) >= 0)
            return root.popoutSourceTab;
        return ids.length > 0 ? ids[0] : "";
    }

    readonly property var activeDescriptor: Sources.byId(root.activeSourceId)

    onVisibleIdsChanged: {
        root.ensureActiveTab();
        root.updatePillVisibility();
    }

    function ensureActiveTab() {
        var ids = root.visibleIds;
        if (ids.length === 0)
            return;
        if (ids.indexOf(root.popoutSourceTab) < 0)
            root.popoutSourceTab = ids[0];
    }

    function updatePillVisibility() {
        if (root.visibleIds.length === 0)
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
                util: pd.primaryUtil !== undefined ? pd.primaryUtil : base.primary.util,
                resetMs: pd.primaryReset !== undefined ? root.parseResetMs(pd.primaryReset) : base.primary.resetMs,
                windowSeconds: base.primary.windowSeconds
            };
            st.secondary = {
                util: pd.secondaryUtil !== undefined ? pd.secondaryUtil : base.secondary.util,
                resetMs: pd.secondaryReset !== undefined ? root.parseResetMs(pd.secondaryReset) : base.secondary.resetMs,
                windowSeconds: base.secondary.windowSeconds
            };
            // The daily chart keeps the aggregate in dailyTokens and dailyCosts,
            // so its grey bars stay the total and the cost tooltip stays the day
            // total, and carries the Account's own series separately for the
            // coloured share.
            st.accountDaily = pd.daily || [];
            st.models = pd.weekModels || [];
            // All-time figures are only tracked in aggregate.
            st.alltime = { sessions: 0, messages: 0, firstSession: "" };
        }

        // The Today figure follows the selected Account when there is one, and
        // the aggregate otherwise.
        var todaySeries = pd && pd.daily ? pd.daily : st.dailyTokens;
        st.todayTokens = (todaySeries && todaySeries[root.todayIndex]) || 0;
        return st;
    }

    // Whether a Source has a reading the Pill can draw. Before the first fetch
    // the state is "unknown" and the ring draws at zero so it does not flicker.
    // Once a Source reports missing credentials or an unavailable endpoint there
    // is no reading, so the ring goes hollow rather than showing a zero.
    function pillHasReading(id) {
        var st = root.sourceData[id];
        if (!st)
            return true;
        return st.credsStatus === "ok" || st.credsStatus === "unknown";
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
        return root.accountSettings[key] || [];
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

    // Refetch a Source whose Account list changed, so a newly added Account
    // appears without waiting for the next poll. pluginData changes for every
    // setting, so compare the lists rather than refetching on any save.
    function refetchChangedAccounts() {
        var prev = root.lastAccountSettings;
        var next = root.accountSettings;
        root.lastAccountSettings = next;
        // The first evaluation is the baseline, not a change: every key would
        // otherwise read as new. Startup fetching is onSourceOrderChanged's job.
        if (prev === null)
            return;
        // The binding can be evaluated while the component is still being
        // built, before sourceOrder exists. onSourceOrderChanged fetches
        // everything at that point anyway.
        if (!root.sourceOrder)
            return;
        for (var i = 0; i < Sources.SOURCES.length; i++) {
            var d = Sources.SOURCES[i];
            if (!d.accounts)
                continue;
            var key = d.accounts.settingKey;
            if (JSON.stringify(prev[key]) === JSON.stringify(next[key]))
                continue;
            if (root.sourceOrder.indexOf(d.id) >= 0)
                root.requestFetch(d.id);
        }
    }

    onAccountSettingsChanged: root.refetchChangedAccounts()

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

    // The command string is assembled here rather than handed to the Process
    // as a bare program name, because Quickshell's own PATH is
    // a bare `/usr/local/bin:/usr/bin` and would not find a `claude` under
    // ~/.local/bin or ~/.npm-global/bin, leaving the button stuck on
    // "Logging in…" because the Process never spawned and never exited. The
    // program, its args and any environment come from the descriptor, so a new
    // Source's login needs no branch here. Every value that can carry a space
    // or quote is shell-quoted, the env value and the args alike.
    function loginCommandFor(d, id) {
        var cmd = "";
        if (d.login.env && d.login.env.accountField) {
            var value = root.accountFieldFor(id, root.selectedAccount[id] || "all", d.login.env.accountField);
            if (value)
                cmd = d.login.env.variable + "=" + root.shellQuote(value) + " ";
        }
        cmd += 'PATH="$PATH:' + root.cliSearchPathAdditions + '" exec ' + d.login.program;
        var args = d.login.args || [];
        for (var i = 0; i < args.length; i++)
            cmd += " " + root.shellQuote(args[i]);
        return ["bash", "-c", cmd];
    }

    // One Process per descriptor that has a CLI login, built the same way the
    // fetch processes are, so two Sources can log in at once and a new Source's
    // login needs no Process here.
    readonly property var cliLoginDescriptors: Sources.SOURCES.filter(function (d) {
        return d.login && d.login.kind === "cli";
    })

    property var loginProcesses: ({})

    // The command each login Process was started with, keyed by Source id.
    // Snapshotted at press time so changing the Account selection during a login
    // cannot rewrite a running Process's command.
    property var loginCommands: ({})

    function loginProcessFor(id) {
        return root.loginProcesses[id] || null;
    }

    function startLogin(id) {
        var d = Sources.byId(id);
        if (!d || !d.login || d.login.kind !== "cli")
            return;
        var p = root.loginProcessFor(id);
        // Re-pressing a Source whose login is already running does nothing new,
        // but that press is never silent: the Source already shows the progress
        // state the first press set. Another Source's press is unaffected
        // because each has its own Process.
        if (!p || p.running)
            return;
        var next = Object.assign({}, root.loginCommands);
        next[id] = root.loginCommandFor(d, id);
        root.loginCommands = next;
        root.setLoginInProgress(id, true);
        p.running = true;
    }

    Instantiator {
        id: loginPool
        model: root.cliLoginDescriptors

        delegate: Process {
            required property var modelData

            readonly property string sourceId: modelData.id

            command: root.loginCommands[sourceId] || []
            running: false

            onExited: (exitCode, exitStatus) => {
                root.setLoginInProgress(sourceId, false);
                root.requestFetch(sourceId);
            }
        }

        // Indexed by model position rather than by a property on the created
        // object, which keeps the delegate's identity out of these handlers.
        onObjectAdded: (index, object) => {
            var next = Object.assign({}, root.loginProcesses);
            next[root.cliLoginDescriptors[index].id] = object;
            root.loginProcesses = next;
        }

        onObjectRemoved: (index, object) => {
            var next = Object.assign({}, root.loginProcesses);
            delete next[root.cliLoginDescriptors[index].id];
            root.loginProcesses = next;
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

        function startLogin(id) {
            root.startLogin(id);
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
                model: root.visibleDescriptors

                delegate: Row {
                    id: hGroup
                    required property var modelData
                    required property int index

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
                        hasReading: root.pillHasReading(hGroup.modelData.id)
                        showPaceTick: false
                    }

                    StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        text: {
                            if (!root.pillHasReading(hGroup.modelData.id))
                                return "--";
                            var st = root.stateFor(hGroup.modelData.id);
                            var p = root.paceFor(st, "primary");
                            var over = root.showPacing && p && (p.status === "over" || p.status === "over_quota");
                            return Math.round(st ? st.primary.util : 0) + "%" + (over ? " ↑" : "");
                        }
                        font.pixelSize: Theme.barTextSize(root.barThickness, root.barConfig?.fontScale, root.barConfig?.maximizeWidgetText)
                        color: {
                            if (!root.pillHasReading(hGroup.modelData.id))
                                return Theme.surfaceVariantText;
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
                model: root.visibleDescriptors

                delegate: Column {
                    id: vGroup
                    required property var modelData
                    required property int index

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
                        hasReading: root.pillHasReading(vGroup.modelData.id)
                        showPaceTick: false
                    }

                    StyledText {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: {
                            if (!root.pillHasReading(vGroup.modelData.id))
                                return "--";
                            var st = root.stateFor(vGroup.modelData.id);
                            var p = root.paceFor(st, "primary");
                            var over = root.showPacing && p && (p.status === "over" || p.status === "over_quota");
                            return Math.round(st ? st.primary.util : 0) + "%" + (over ? " ↑" : "");
                        }
                        font.pixelSize: Theme.barTextSize(root.barThickness, root.barConfig?.fontScale, root.barConfig?.maximizeWidgetText)
                        color: {
                            if (!root.pillHasReading(vGroup.modelData.id))
                                return Theme.surfaceVariantText;
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
                            color: root.activeSourceId === modelData.id ? Theme.primary : Theme.surfaceVariant

                            Behavior on color {
                                ColorAnimation {
                                    duration: 120
                                }
                            }

                            StyledText {
                                anchors.centerIn: parent
                                text: root.tr(modelData.labelKey)
                                font.pixelSize: Theme.fontSizeSmall
                                font.weight: root.activeSourceId === modelData.id ? Font.Medium : Font.Normal
                                color: root.activeSourceId === modelData.id ? Theme.primaryText : Theme.surfaceVariantText
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

    // The value of one field on a named Account of a Source, from the Account's
    // entry in the plugin settings. "all"/"default" (or unrecognized names)
    // fall back to "" — the login command's own default — so logging in as the
    // aggregate never redirects the CLI away from its detected config.
    function accountFieldFor(id, name, field) {
        if (!name || name === "all" || name === "default")
            return "";
        var d = Sources.byId(id);
        if (!d || !d.accounts)
            return "";
        var list = root.settingList(d.accounts.settingKey);
        for (var i = 0; i < list.length; i++) {
            var a = list[i];
            if (a && a.name === name && a[field])
                return a[field];
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

        // Every key that belongs to an Account is named by the descriptor: the
        // list of Accounts, the two Window slots' Account keys, and the rest of
        // the Account overlay fields. They write a different map from the
        // Source's own state, so they are dispatched before the switch below.
        if (d.accounts && key === d.accounts.listKey) {
            root.applyAccounts(id, val);
            return;
        }
        if (root.parseWindowKey(d, id, "primary", key, val))
            return;
        if (root.parseWindowKey(d, id, "secondary", key, val))
            return;
        if (root.parseAccountKey(d, id, key, val))
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
            }
        });
    }

    // The per-Account output keys a Source declares in its descriptor's
    // `accounts.fields` map. The field names are the overlay's own, so no
    // Source's Window shape leaks into this adapter. Returns true when handled.
    function parseAccountKey(d, id, key, val) {
        var spec = d.accounts && d.accounts.fields ? d.accounts.fields[key] : null;
        if (!spec)
            return false;
        if (spec.type === "number")
            root.applyAccountNumber(id, val, spec.field);
        else if (spec.type === "boolean")
            root.applyAccountBool(id, val, spec.field);
        else if (spec.type === "series")
            root.applyAccountList(id, val, spec.field);
        else if (spec.type === "models")
            root.applyAccountModels(id, val, spec.field);
        else
            root.applyAccountField(id, val, spec.field);
        return true;
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

    function applyAccountModels(id, val, field) {
        var models = root.parseAccountModels(val);
        root.mutateAccounts(id, function (acct) {
            for (var name in models)
                acct(name)[field] = models[name];
        });
    }
}
