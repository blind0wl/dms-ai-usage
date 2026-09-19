.pragma library

.import "sources.js" as Sources

// The Listing conversation (#80). One machine per Source's settings editor: it
// asks the editor's Script for its Account listing, asks again with a candidate
// Custom Account row when the Add guard needs a verdict, and reports the
// outcome. Everything that decides when a question goes out, where an answer
// lands and what the two answers mean lives here, because that sequencing was
// the untested part; the editor keeps only what only it can know, namely
// whether the fields still hold the row a probe was asked about and whether
// its list is still the list that was asked.
//
// The machine returns actions and the caller performs effects: run this
// command in a Process, feed the lines and the exit code back, mirror the
// committed Listing into display state. That shape is what lets this file be
// driven by tests that speak exactly the events the editor's Processes speak.
//
// The listing and the probe are two independent conversations. A listing
// refresh and an Add probe can be out at once, on the editor's two Processes,
// and neither disturbs the other's stage. Each carries its own re-ask queue: a
// question asked while its conversation is busy is remembered and reported on
// the next exit, so the caller can ask it again with fresh inputs.

function create(pluginDirectory, pluginId, descriptor) {
    // The committed Listing: the Script's last whole answer, in the form the
    // editor mirrors into display state. A listing that failed leaves the last
    // answer standing beside the failed flag.
    var listing = {
        names: "", origins: "", shadowed: "",
        answered: false, absent: false, blocked: false,
        requirement: "", failed: false
    };

    // The listing question's in-flight answer. Every field is committed
    // together once the Script has finished, so what the page shows is always
    // one whole answer rather than half of one.
    var listPending = false;
    var listQueued = false;
    var pendingList = blankAnswer();

    // The Add guard's two questions: 0 idle, 1 the list as it stands asked,
    // 2 the list with the candidate row asked. `asked` snapshots the row and
    // the list both questions are about, so an answer is only ever about the
    // row it was asked for.
    var stage = 0;
    var addQueued = false;
    var asked = null;
    var baseline = blankAnswer();
    var candidate = blankAnswer();

    function blankAnswer() {
        return { names: "", origins: "", shadowed: "", answered: false };
    }

    // The command that asks the Script for a Listing: its listing mode, with
    // the Account arguments that are part of the question.
    function command(args) {
        return Sources.scriptCommand(pluginDirectory, pluginId, descriptor,
                                     [Sources.LIST_ACCOUNTS_FLAG].concat(args || []));
    }

    // Asks what the Script makes of the Custom Account list as it stands.
    // While a listing is out the ask is remembered: the caller re-asks on the
    // committed action, with whatever the list holds by then.
    function askList(list) {
        if (listPending) {
            listQueued = true;
            return { kind: "queued" };
        }
        pendingList = blankAnswer();
        listPending = true;
        return { kind: "run", command: command(Sources.accountArgs(descriptor, list)) };
    }

    // Asks the two questions behind an Add: first the list as it stands, then
    // the list with the candidate row appended. The difference between the two
    // answers is what the row would do, and the Script, not the editor, is
    // what says so. While a probe is out the ask is remembered.
    function askAdd(name, value, list) {
        if (stage !== 0) {
            addQueued = true;
            return { kind: "queued" };
        }
        asked = { name: name, value: value, list: (list || []).slice() };
        baseline = blankAnswer();
        candidate = blankAnswer();
        stage = 1;
        return { kind: "run", command: command(Sources.accountArgs(descriptor, asked.list)) };
    }

    // The listing answer, line by line. A line with no question out is
    // ignored: nothing asked it, so it decides nothing.
    function onListLine(line) {
        if (!listPending)
            return;
        readAnswer(pendingList, line, true);
    }

    // The probe answers, routed by stage: before the candidate question is out
    // a line belongs to the baseline, afterwards to the candidate.
    function onProbeLine(line) {
        if (stage === 0)
            return;
        readAnswer(stage === 2 ? candidate : baseline, line, false);
    }

    function readAnswer(answer, line, withStatus) {
        var pair = Sources.wirePair(line);
        if (!pair)
            return;
        if (pair.key === Sources.LIST_KEY) {
            answer.names = pair.value;
            answer.answered = true;
        } else if (pair.key === Sources.ORIGINS_KEY)
            answer.origins = pair.value;
        else if (pair.key === Sources.SHADOWED_KEY)
            answer.shadowed = pair.value;
        else if (withStatus && pair.key === Sources.STATUS_KEY) {
            answer.absent = pair.value === Sources.NOT_INSTALLED;
            answer.blocked = pair.value === Sources.BLOCKED;
        } else if (withStatus && pair.key === Sources.BLOCKING_REQUIREMENT)
            answer.requirement = pair.value;
    }

    // The listing question has finished. Only a Script that finished cleanly
    // commits: a failed one is marked as failed and the last answer stands.
    // Either way a queued ask is reported, so the caller asks it again.
    function onListExit(code) {
        if (!listPending)
            return { kind: "idle", rerun: false };
        listPending = false;
        var rerun = listQueued;
        listQueued = false;
        if (code !== 0) {
            listing.failed = true;
            return { kind: "failed", rerun: rerun };
        }
        listing.names = pendingList.names;
        listing.origins = pendingList.origins;
        listing.shadowed = pendingList.shadowed;
        listing.answered = pendingList.answered;
        listing.absent = pendingList.absent;
        listing.blocked = pendingList.blocked;
        listing.requirement = pendingList.requirement;
        listing.failed = false;
        return { kind: "committed", rerun: rerun };
    }

    // The probe has finished one of its two questions.
    //
    // A clean baseline hands the caller the candidate question to run or
    // decline: whether the fields still hold the row this probe is about is
    // the editor's knowledge, so declining is the editor calling abandonAdd().
    //
    // Anything that ends the second question, and any non-zero exit, produces
    // the verdict: Sources.addOutcome() over the two listings, or unreadable
    // when the Script could not be read at all. The verdict is tagged with the
    // row it was asked about, because an answer decides for that row and no
    // other.
    function onProbeExit(code) {
        if (stage === 0)
            return { kind: "idle" };
        if (stage === 1) {
            if (code !== 0)
                return finish({ reason: "unreadable" });
            stage = 2;
            var entry = { name: asked.name };
            entry[descriptor.accounts.argField] = asked.value;
            return { kind: "run", name: asked.name, value: asked.value, queued: addQueued,
                     command: command(Sources.accountArgs(descriptor, asked.list.concat([entry]))) };
        }
        if (code !== 0)
            return finish({ reason: "unreadable" });
        var outcome = Sources.addOutcome(
            Sources.listing(baseline.names, baseline.origins, baseline.shadowed, baseline.answered),
            Sources.listing(candidate.names, candidate.origins, candidate.shadowed, candidate.answered),
            asked.name);
        return finish(outcome);
    }

    function finish(outcome) {
        var act = { kind: "outcome", name: asked.name, value: asked.value,
                    outcome: outcome, queued: addQueued };
        stage = 0;
        addQueued = false;
        asked = null;
        baseline = null;
        candidate = null;
        return act;
    }

    // The editor declining a probe: the fields no longer hold the row the
    // questions were about, so the questions' answers decide nothing and the
    // probe is reset. A queued Add survives the reset and is reported, so the
    // editor asks it fresh.
    function abandonAdd() {
        var q = addQueued;
        stage = 0;
        addQueued = false;
        asked = null;
        baseline = null;
        candidate = null;
        return { kind: "reset", queued: q };
    }

    var machine = {
        askList: askList,
        askAdd: askAdd,
        onListLine: onListLine,
        onProbeLine: onProbeLine,
        onListExit: onListExit,
        onProbeExit: onProbeExit,
        abandonAdd: abandonAdd
    };
    machine.listing = listing;
    return machine;
}
