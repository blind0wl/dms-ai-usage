const fs = require('fs'), path = require('path'), vm = require('vm'), assert = require('assert');
const [root, fixtures] = process.argv.slice(2);
function load(name, extra = {}) {
    const ctx = vm.createContext({ console, ...extra });
    vm.runInContext(fs.readFileSync(path.join(root, name), 'utf8').replace(/^\.pragma library\s*/,'').replace(/^\.import.*$/mg,''),ctx);
    return ctx;
}
const Sources = load('sources.js'), State = load('state.js',{Sources});
function read(name, prev = { state: State.empty(), accounts: {} }) {
    return fs.readFileSync(path.join(fixtures,name+'.out'),'utf8').trim().split('\n')
        .reduce((r,line) => State.readLine(r.state,r.accounts,'claude',line),prev);
}
const ent = read('enterprise');
assert.strictEqual(ent.state.primary.reported,false);
assert.strictEqual(Sources.tightestWindow(ent.state),null);
assert.ok(Math.abs(Sources.pillUtilisation(ent.state) - 4.055) < 1e-9);
assert.strictEqual(Sources.overviewRow(ent.state).windowLabelKey,'Monthly budget');
const render = r => State.render(r.state,r.accounts,{selected:'default'});
assert.ok(Math.abs(Sources.pillUtilisation(render(ent)) - 4.055) < 1e-9);
const stale = read('500',ent);
assert.strictEqual(stale.state.spend.usedMinor,811);
assert.strictEqual(render(stale).spend.usedMinor,811);
assert.strictEqual(Sources.overviewRow(stale.state).stale,true);
assert.strictEqual(State.hasCurrentReading(stale.state),false);
const sub = read('subscription',ent);
assert.strictEqual(sub.state.spend,null);
assert.strictEqual(render(sub).spend,null);
assert.strictEqual(Sources.pillUtilisation(sub.state),12);
const switched = read('enterprise',sub);
assert.strictEqual(Sources.tightestWindow(render(switched)),null);
assert.ok(Math.abs(Sources.pillUtilisation(render(switched)) - 4.055) < 1e-9);
const zero = read('zero');
assert.strictEqual(Sources.pillUtilisation(zero.state),0);
for (const name of ['unlimited','disabled','zero_limit','unknown_limit']) {
    const r = read(name,ent);
    assert.strictEqual(Sources.pillUtilisation(r.state),null,name);
    assert.strictEqual(Sources.pillUtilisation(render(r)),null,name+' Account');
    assert.strictEqual(Sources.overviewRow(r.state).ranked,false,name+' no invented percent');
    assert.strictEqual(r.state.spend.currency,'USD');
}
// A selected Profile has its own last-good reading even when default has none.
let r = read('unknown');
for (const line of fs.readFileSync(path.join(fixtures,'enterprise.out'),'utf8').trim().split('\n')) {
    if (line.startsWith('ACCOUNT_')) r = State.readLine(r.state,r.accounts,'claude',line.replace(/default:/g,'work:'));
}
r = State.readLine(r.state,r.accounts,'claude','ACCOUNTS=default,work');
const work = State.render(r.state,r.accounts,{selected:'work'});
assert.strictEqual(work.hasData,true);
assert.ok(Math.abs(Sources.pillUtilisation(work) - 4.055) < 1e-9);
console.log('PASS: collector-to-State, Profile switching, stale budgets, zero and absent allowances');

let failed = State.readLine(ent.state, ent.accounts, 'claude', 'ACCOUNTS=default,work');
failed = State.readLine(failed.state,failed.accounts,'claude','ACCOUNT_CREDS_STATUS=work:unavailable');
failed = State.readLine(failed.state,failed.accounts,'claude','ACCOUNT_SPEND=work:keep');
const unread = State.render(failed.state,failed.accounts,{selected:'work'});
assert.strictEqual(unread.hasData,false);
assert.strictEqual(unread.spend,null);
assert.strictEqual(Sources.pillUtilisation(unread),null);
console.log('PASS: failed new Profile cannot inherit default budget or rate readings');
