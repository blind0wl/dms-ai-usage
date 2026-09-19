.pragma library
.import "translations.js" as Tr

// The widget's pure formatters: the figures, clocks, pacing labels and plan
// names the Pill and every Section render the same way. Everything here takes
// what it needs as arguments - the language, the exchange rate, the clock -
// so the module owns no state and tests/test-format.sh runs it directly under
// Node. What reads the widget's State stays on the widget: paceFor,
// countdownFor, windowLabelFor and windowLabelForLength.

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

// Returns { timeFrac, delta, status } for a usage window.
// status: over_quota | over | under | on | unknown
function paceInfo(util, resetMs, windowMs, now) {
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
    var remaining = resetMs - now;
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

function paceLabel(p, lang) {
    if (!p)
        return "";
    if (p.status === "over_quota")
        return Tr.tr("Over quota", lang);
    if (p.status === "over")
        return Math.round(p.delta) + "% " + Tr.tr("over pace", lang);
    if (p.status === "under")
        return Math.round(-p.delta) + "% " + Tr.tr("under pace", lang);
    if (p.status === "on")
        return Tr.tr("On pace", lang);
    return "";
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

function formatCountdown(resetMs, lang, now) {
    if (!resetMs)
        return "";
    var remaining = Math.max(0, resetMs - now);
    if (remaining <= 0)
        return Tr.tr("Resetting...", lang);
    var days = Math.floor(remaining / 86400000);
    var hours = Math.floor((remaining % 86400000) / 3600000);
    var mins = Math.floor((remaining % 3600000) / 60000);
    if (days > 0)
        return days + "d " + hours + "h " + (mins < 10 ? "0" : "") + mins + "m" + resetClockLabel(resetMs);
    return hours + "h " + (mins < 10 ? "0" : "") + mins + "m" + resetClockLabel(resetMs);
}

// `wham/usage` names its windows "primary" and "secondary" with no fixed
// duration in the field name, but does carry each window's length, so label
// with the real duration. genericKey covers the window before its length has
// arrived (0 means not fetched, not "unknown length").
function formatWindowLabel(seconds, genericKey, lang) {
    if (!seconds || seconds <= 0)
        return Tr.tr(genericKey, lang);
    if (seconds === 604800)
        return Tr.tr("Weekly Window", lang);
    if (seconds === 18000)
        return Tr.tr("5h Window", lang);
    if (seconds % 86400 === 0)
        return (seconds / 86400) + "d " + Tr.tr("Window", lang);
    var hours = Math.round(seconds / 3600);
    return hours + "h " + Tr.tr("Window", lang);
}

function formatCost(usd, lang, usdEurRate) {
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

function formatTier(tier, lang) {
    if (!tier || tier === "unknown")
        return "";
    if (tier.indexOf("max_20x") >= 0)
        return Tr.tr("Max", lang) + " 20x";
    if (tier.indexOf("max_5x") >= 0)
        return Tr.tr("Max", lang) + " 5x";
    if (tier.indexOf("max") >= 0)
        return Tr.tr("Max", lang);
    if (tier.indexOf("pro") >= 0)
        return Tr.tr("Pro", lang);
    if (tier.indexOf("free") >= 0)
        return Tr.tr("Free", lang);
    if (tier.indexOf("team") >= 0)
        return Tr.tr("Team", lang);
    if (tier.indexOf("enterprise") >= 0)
        return Tr.tr("Enterprise", lang);
    // A tier outside that list names no plan the user bought: Claude Pro
    // reports "default_claude_ai", which read as "Pro · Default Claude Ai".
    return "";
}

function formatSubscription(subType, tier, lang) {
    var tierLabel = formatTier(tier, lang);
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

// Which day-series bucket is today: Monday=0 through Sunday=6. The widget's
// todayIndex property calls this on the countdown tick so a midnight rollover
// re-buckets the day figures.
function todayIndex(now) {
    var dow = new Date(now).getDay();
    return dow === 0 ? 6 : dow - 1;
}
