#!/usr/bin/env bash
# Feed sanitized member responses through the real collector and State reader.
set -eu
ROOT=$(cd "$(dirname "$0")/.." && pwd)
python3 - "$ROOT" <<'PY'
import copy,json,os,pathlib,subprocess,sys,tempfile
root=pathlib.Path(sys.argv[1])
fixture=json.loads((root/'tests/fixtures/claude-enterprise-usage.json').read_text())
with tempfile.TemporaryDirectory() as tmp:
 base=pathlib.Path(tmp); home=base/'home'; config=home/'.claude'; config.mkdir(parents=True)
 (config/'projects').mkdir()
 (config/'.credentials.json').write_text(json.dumps({'claudeAiOauth':{'subscriptionType':'enterprise','accessToken':'test-only'}}))
 bin=base/'bin'; bin.mkdir()
 (bin/'claude').write_text('#!/bin/sh\necho 2.1.291\n')
 (bin/'curl').write_text('''#!/bin/sh
for arg do
 case "$arg" in
  *api/oauth/usage*) cat "$ENTERPRISE_BODY"; printf '\\n%s' "$ENTERPRISE_STATUS"; exit 0;;
 esac
done
printf '{}'
''')
 for f in bin.iterdir():f.chmod(0o755)
 env=dict(os.environ,HOME=str(home),PATH=str(bin)+':'+os.environ['PATH'],ENTERPRISE_BODY=str(base/'body'),ENTERPRISE_STATUS='200')
 def run(name,body,status='200',cache=False):
  env['ENTERPRISE_STATUS']=status
  (base/'body').write_text(json.dumps(body) if not isinstance(body,str) else body)
  if not cache:(config/'usage-cache.json').unlink(missing_ok=True)
  result=subprocess.run(['bash',str(root/'get-claude-usage')],env=env,text=True,capture_output=True,check=True).stdout
  (base/(name+'.out')).write_text(result)
  values=dict(line.split('=',1) for line in result.splitlines() if '=' in line)
  return values
 def check(ok,label):
  if not ok:raise AssertionError(label)
  print('PASS:',label)
 v=run('enterprise',fixture)
 check(v['CREDS_STATUS']=='ok','spend-only Enterprise response is authenticated')
 check(v['FIVE_HOUR_UTIL']==v['SEVEN_DAY_UTIL']=='none','absent rate Windows are explicit')
 spend=json.loads(v['SPEND'])
 check(spend['usedMinor']==811 and spend['limitMinor']==20000 and spend['currency']=='USD' and spend['exponent']==2,'minor amounts and currency survive collection')
 check(v['MONTH_COST']=='0.00','reported spend is separate from local Cost')
 check(json.loads((config/'usage-cache.json').read_text())['data']['spend']==fixture['spend'],'spend-only response is cached')
 v=run('cached',{},cache=True)
 check(v['CREDS_STATUS']=='ok' and json.loads(v['SPEND'])==spend,'fresh Enterprise cache is accepted')
 for name,change in [('zero',{'used':{'amount_minor':0,'currency':'USD','exponent':2}}),('unlimited',{'limit':None}),('disabled',{'enabled':False}),('zero_limit',{'limit':{'amount_minor':0,'currency':'USD','exponent':2}})]:
  body=copy.deepcopy(fixture);body['spend'].update(change)
  v=run(name,body)
  check(v['CREDS_STATUS']=='ok',name+' is a valid Account reading')
  check(json.loads(v['SPEND'])['currency']=='USD',name+' preserves currency')
 body=copy.deepcopy(fixture);del body['spend']['limit'];v=run('unknown_limit',body)
 check(v['CREDS_STATUS']=='ok' and json.loads(v['SPEND'])['limitKind']=='unknown','missing allowance remains unknown')
 body=copy.deepcopy(fixture);del body['spend'];v=run('legacy',body)
 check(v['CREDS_STATUS']=='ok' and json.loads(v['SPEND'])['usedMinor']==811,'extra_usage response is supported')
 for name,currency,exponent in [('jpy','JPY',0),('eur','EUR',3)]:
  body=copy.deepcopy(fixture)
  for key in ('used','limit'):
   body['spend'][key].update(currency=currency,exponent=exponent)
  v=run(name,body);record=json.loads(v['SPEND'])
  check(record['currency']==currency and record['exponent']==exponent,name+' preserves original currency and exponent')
 body={'five_hour':{'utilization':12,'resets_at':'2030-01-01T00:00:00Z'},'seven_day':{'utilization':34},'extra_usage':{'is_enabled':False}}
 v=run('subscription',body)
 check(v['CREDS_STATUS']=='ok' and v['SPEND']=='null' and v['FIVE_HOUR_UTIL']=='12','subscription Windows remain supported')
 for name,body,status in [('unknown',{},'200'),('array',[],'200'),('scalar',1,'200'),('nested_spend',{'spend':{'enabled':True,'used':3}},'200'),('nested_window',{'five_hour':3},'200'),('malformed','not json','200'),('401','', '401'),('403',{},'403'),('429',fixture,'429'),('500',fixture,'500')]:
  v=run(name,body,status)
  check(v['CREDS_STATUS']==('expired' if status in ('401','403') else 'unavailable'),name+' has correct failure status')
  if status not in ('401','403'):check(v['SPEND']=='keep' and v['FIVE_HOUR_UTIL']=='keep',name+' preserves stale readings')
 body=copy.deepcopy(fixture);body['spend']['limit']['currency']='EUR';v=run('mismatch',body)
 check(v['CREDS_STATUS']=='unavailable','currency mismatch is rejected')
 body=copy.deepcopy(fixture);body['spend']['used']['amount_minor']=-1;v=run('negative',body)
 check(v['CREDS_STATUS']=='unavailable','negative spend is rejected')
 subprocess.run(['node',str(root/'tests/claude-enterprise-state.cjs'),str(root),str(base)],check=True)
PY
