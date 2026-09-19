import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Services
import qs.Widgets
import qs.Modules.Plugins
import "translations.js" as Tr
import "sources.js" as Sources
import "state.js" as State
import "format.js" as Format
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

    // The currency rate the cost figures are read through. One Source's Script
    // reports it and every Source's costs use it, so it lands on that Source's
    // State like any other key and the one the widget formats with is derived
    // from there rather than written into the widget mid-report.
    readonly property real usdEurRate: {
        for (var id in sourceData) {
            var rate = sourceData[id] ? sourceData[id].usdEurRate : 0;
            if (rate > 0)
                return rate;
        }
        return 0;
    }

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
        return Format.todayIndex(Date.now());
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

    // A Source is shown when it is enabled and not hidden. Hidden is the shared
    // decision (Sources.isHidden): a Source falls out of the Pill, the Popout and
    // the Overview only after two consecutive Not installed reports, and any
    // other report brings it back. Before the first fetch there is no count, so
    // the Source shows and the pill does not flicker.
    readonly property var visibleDescriptors: {
        void (sourceData);
        var out = [];
        for (var i = 0; i < enabledDescriptors.length; i++) {
            var d = enabledDescriptors[i];
            var st = sourceData[d.id];
            if (!st || st.hidden !== true)
                out.push(d);
        }
        return out;
    }

    readonly property var visibleIds: visibleDescriptors.map(function (d) {
        return d.id;
    })

    // --- Popout tabs ---

    // The visible Sources' states, in settings order, each carrying its own id:
    // what `Sources.overviewRows` ranks. A Source whose first fetch has not
    // landed yet still yields a state, so its Overview row is on the strip from
    // the start and says it has no reading, rather than leaving the tab absent
    // until the first fetch lands.
    readonly property var overviewStates: root.visibleDescriptors.map(function (d) {
        return root.overviewState(d.id);
    })

    // One Overview row per visible Source, ranked by Tightest Window. Ranking is
    // a property of the whole set, so it comes from the registry rather than from
    // any one Source's descriptor (ADR 0003), and it is empty when there are
    // fewer than two Sources to compare.
    readonly property var overviewRows: Sources.overviewRows(root.overviewStates)

    // The Overview's own toggle is on and there is something to rank. Below two
    // visible Sources the tab is absent, so the single-Source installs inherited
    // from upstream see the popout they already know.
    readonly property bool overviewShown: root.overviewEnabled && root.overviewRows.length > 0

    // The Popout's tabs, in strip order: the Overview first, then one tab per
    // visible Source. One list drives both the strip and the tab body, so the two
    // cannot disagree about what is showing.
    readonly property var popoutTabs: root.popoutTabsFor(root.overviewShown, root.visibleDescriptors)

    // The Overview leads the strip whenever it applies, so the tab that ranks
    // every Source is the one the popout opens on.
    function popoutTabsFor(overviewShown, descriptors) {
        return overviewShown ? [Sources.OVERVIEW_TAB].concat(descriptors) : descriptors;
    }

    readonly property var popoutTabIds: root.popoutTabs.map(function (tab) {
        return tab.id;
    })

    // Empty until the user picks a tab, so the popout opens on the first tab,
    // which is the Overview whenever it applies.
    property string popoutTabId: ""

    readonly property string activeTabId: root.resolveTabId(root.popoutTabId, root.popoutTabIds)

    readonly property var activeTab: {
        for (var i = 0; i < root.popoutTabs.length; i++) {
            if (root.popoutTabs[i].id === root.activeTabId)
                return root.popoutTabs[i];
        }
        return null;
    }

    // The tab a stored choice selects: the choice itself while it is still on the
    // strip, and the first tab otherwise. Deriving it rather than storing it
    // means the popout can never come up with nothing selected, and a tab the
    // user picked keeps winning while it is still there.
    function resolveTabId(stored, ids) {
        if (stored && ids.indexOf(stored) >= 0)
            return stored;
        return ids.length > 0 ? ids[0] : "";
    }

    // A Source's state for the Overview, with its id attached. Unlike stateFor(),
    // a Source whose first fetch has not landed yet yields the empty state rather
    // than nothing, so it produces a row that says it has no reading yet.
    function overviewState(id) {
        var st = root.stateFor(id) || State.empty();
        st.id = id;
        return st;
    }

    onVisibleIdsChanged: root.updatePillVisibility()

    function updatePillVisibility() {
        if (root.visibleIds.length === 0)
            root.setVisibilityOverride(false);
        else
            root.clearVisibilityOverride();
    }

    Component.onCompleted: root.updatePillVisibility()

    // --- Per-Source state ---

    // One line of one Source's report, read into that Source's State. The
    // reading itself is state.js's; what belongs here is where the State lives,
    // because a QML property has to be reassigned for its bindings to
    // re-evaluate.
    function readReportLine(id, line) {
        var read = State.readLine(root.sourceData[id], root.accountData[id], id, line);
        if (read.state !== root.sourceData[id]) {
            var states = Object.assign({}, root.sourceData);
            states[id] = read.state;
            root.sourceData = states;
        }
        if (read.accounts !== root.accountData[id]) {
            var overlays = Object.assign({}, root.accountData);
            overlays[id] = read.accounts;
            root.accountData = overlays;
        }
    }

    // An Account can disappear between one report and the next. render() already
    // refuses to draw a selection the Source no longer lists, but the Account
    // picker reads the stored selection directly, so the widget drops it here
    // rather than the reader reaching sideways into it mid-report.
    onSourceDataChanged: root.dropMissingSelections()

    function dropMissingSelections() {
        for (var id in root.selectedAccount) {
            var sel = root.selectedAccount[id];
            if (!sel || sel === "all")
                continue;
            var st = root.sourceData[id];
            if (st && st.accounts && st.accounts.indexOf(sel) < 0)
                root.selectAccount(id, "all");
        }
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

    // The State a Section renders. The selected Account and today's day index
    // are the widget's to know, so they are handed over rather than parsed into
    // the State where a midnight rollover would leave them stale.
    function stateFor(id) {
        return State.render(root.sourceData[id], root.accountData[id], {
            selected: root.selectedAccount[id] || "all",
            todayIndex: root.todayIndex
        });
    }

    // Whether a Source has a reading the Pill can draw.
    function pillHasReading(id) {
        return State.hasCurrentReading(root.sourceData[id]);
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
        return root.windowLabelForLength(root.windowSeconds(source.id, which), which);
    }

    // The label for a Window known only by its slot and its length. A descriptor
    // that names its Windows never gets here; one whose script reports the length
    // (ChatGPT, Z.ai) falls back to the length itself, and a Window whose length
    // has not arrived yet falls back to its slot's generic name.
    function windowLabelForLength(seconds, which) {
        var generic = which === "primary" ? "Primary Window" : "Secondary Window";
        return root.formatWindowLabel(seconds, generic);
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

    function settingList(key) {
        return root.accountSettings[key] || [];
    }

    // The Account arguments the fetch runs with, built by the registry so the
    // settings editor's listing call builds them the same way: the Script keeps
    // the first registration of a name, so the two calls have to agree.
    function accountArgs(id) {
        var d = Sources.byId(id);
        if (!d || !d.accounts)
            return [];
        return Sources.accountArgs(d, root.settingList(d.accounts.settingKey));
    }

    function commandFor(id) {
        return Sources.scriptCommand(PluginService.pluginDirectory, root.pluginId, Sources.byId(id), root.accountArgs(id));
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

    // Every enabled Source is fetched on every scheduled cycle, whether or not
    // it is currently shown: visibility is a display filter over data that keeps
    // arriving, so a hidden Source whose credentials come back reappears within
    // one cycle with no restart and no settings write (ADR 0004).
    function fetchEnabled() {
        for (var i = 0; i < root.sourceOrder.length; i++)
            root.requestFetch(root.sourceOrder[i]);
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
                onRead: data => root.readReportLine(sourceId, data.trim())
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
                root.fetchEnabled();
                return;
            }
            for (var i = 0; i < root.sourceOrder.length; i++) {
                var id = root.sourceOrder[i];
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
        onTriggered: root.fetchEnabled()
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

        function utilisationColor(id, pct) {
            return root.utilisationColor(id, pct);
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

        function windowLabelForLength(seconds, which) {
            return root.windowLabelForLength(seconds, which);
        }

        function formatCountdown(resetMs) {
            return root.formatCountdown(resetMs);
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

        function loginInProgress(id) {
            return root.loginInProgress[id] === true;
        }

        function selectAccount(id, name) {
            root.selectAccount(id, name);
        }

        // Selecting a tab is what a press on an Overview row does: the Overview
        // answers "which one", the Source's own tab answers "why".
        function selectTab(id) {
            root.popoutTabId = id;
        }
    }

    // Everything a Section needs beyond its own entry in the tab's Section list.
    // The Overview's tab is not a Source, so its Sections read the ranking instead
    // of one Source's state, and no non-Source travels under the Descriptor name.
    function contextFor(id) {
        if (id === Sources.OVERVIEW_TAB.id) {
            return {
                api: root.api,
                rows: root.overviewRows
            };
        }
        var d = Sources.byId(id);
        var sel = root.selectedAccount[id] || "all";
        return {
            source: root.stateFor(id),
            sourceId: id,
            brandColor: root.brandColor(id),
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
            loginInProgress: root.api.loginInProgress(id)
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
            headerText: root.tr("AI Usage Monitor")
            showCloseButton: true

            // The host already insets plugin popout content by Theme.spacingS
            // (its own popoutColumn), so this body adds the same inset rather
            // than a wider one on top of it: the tab strip and the Sections get
            // the panel's width to use, and the two insets cannot disagree.
            Column {
                width: parent.width - Theme.spacingS * 2
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: Theme.spacingS

                // Only one tab's Sections render at a time, keeping the popout
                // short on small screens. Hidden when there is nothing to switch
                // between: with the Overview absent that is a single Source, and
                // an all-hidden pill already hides the whole widget.
                Row {
                    width: parent.width
                    spacing: Theme.spacingXS
                    visible: root.popoutTabs.length > 1

                    Repeater {
                        model: root.popoutTabs

                        delegate: Rectangle {
                            required property var modelData

                            // The active chip wears the Source's Brand Colour.
                            // The Overview is not a Source, so it keeps the
                            // theme's primary; white reads on every brand colour
                            // while primaryText reads on the theme's primary.
                            readonly property bool branded: root.hasBrandColor(modelData.id)
                            readonly property bool active: root.activeTabId === modelData.id

                            width: (parent.width - Theme.spacingXS * (root.popoutTabs.length - 1)) / root.popoutTabs.length
                            height: 32
                            radius: 16
                            color: active ? root.brandColor(modelData.id) : Theme.surfaceVariant

                            Behavior on color {
                                ColorAnimation {
                                    duration: 120
                                }
                            }

                            StyledText {
                                anchors.centerIn: parent
                                // A fifth tab in a 380px strip, so the longest
                                // Source name elides rather than spilling over
                                // its neighbours. NoWrap is what lets the styling
                                // base's ElideRight apply: Qt ignores elide on
                                // wrapped text.
                                width: parent.width - Theme.spacingS
                                text: root.tr(modelData.labelKey)
                                horizontalAlignment: Text.AlignHCenter
                                wrapMode: Text.NoWrap
                                font.pixelSize: Theme.fontSizeSmall
                                font.weight: active ? Font.Medium : Font.Normal
                                color: active ? (branded ? "#ffffff" : Theme.primaryText) : Theme.surfaceVariantText
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.popoutTabId = modelData.id
                            }
                        }
                    }
                }

                SourceTab {
                    tab: root.activeTab
                    ctx: root.activeTab ? root.contextFor(root.activeTab.id) : null
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

    // The pure formatters are format.js's (tests/test-format.sh runs it
    // directly). These stay so the template and the api object keep their
    // shapes while the widget supplies the language and the clock.
    function formatTokens(n) {
        return Format.formatTokens(n);
    }

    function shortModelName(name) {
        return Format.shortModelName(name);
    }

    function progressColor(pct) {
        if (pct > 80)
            return Theme.error;
        if (pct > 50)
            return Theme.warning;
        return Theme.primary;
    }

    // A Source's Brand Colour: its own fixed colour, carried on its descriptor
    // rather than the shell theme (ADR 0001). The Overview is not a Source, so
    // it has none and falls back to the theme's primary.
    function brandColor(id) {
        var d = Sources.byId(id);
        return d && d.brandColor ? d.brandColor : Theme.primary;
    }

    function hasBrandColor(id) {
        var d = Sources.byId(id);
        return !!(d && d.brandColor);
    }

    // The colour a Utilisation reads: the Brand Colour at or under 50%, then the
    // theme's warning and error past the thresholds. The Pill's Ring keeps
    // `progressColor` instead, and does not use the Brand Colour.
    function utilisationColor(id, pct) {
        if (pct > 80)
            return Theme.error;
        if (pct > 50)
            return Theme.warning;
        return root.brandColor(id);
    }

    function paceInfo(util, resetMs, windowMs) {
        return Format.paceInfo(util, resetMs, windowMs, countdownNow);
    }

    function paceLabel(p) {
        return Format.paceLabel(p, lang);
    }

    function paceColor(status) {
        if (status === "over_quota")
            return Theme.error;
        if (status === "over")
            return Theme.warning;
        return Theme.surfaceVariantText;
    }

    function resetClockLabel(resetMs) {
        return Format.resetClockLabel(resetMs);
    }

    // The countdownNow argument is what makes QML bindings re-evaluate on the
    // tick; formatCountdown's old `void (countdownNow)` hint died with the
    // move, because the dependency is now an explicit read at this call site.
    function formatCountdown(resetMs) {
        return Format.formatCountdown(resetMs, lang, countdownNow);
    }

    function formatWindowLabel(seconds, genericKey) {
        return Format.formatWindowLabel(seconds, genericKey, lang);
    }

    function formatCost(usd) {
        return Format.formatCost(usd, lang, usdEurRate);
    }

    function formatTier(tier) {
        return Format.formatTier(tier, lang);
    }

    function formatSubscription(subType, tier) {
        return Format.formatSubscription(subType, tier, lang);
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
}
