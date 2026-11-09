#!/usr/bin/env python3
# seiva · JulianoSSR · MIT
import concurrent.futures
import importlib.util
import json
from pathlib import Path
import sqlite3
import subprocess
import sys
import tempfile
import time
import types
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'scripts'))
import monitor


class MonitorTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        subprocess.run(['git','init','-q',str(self.root)],check=True)
        (self.root/'.gitignore').write_text('.seiva/\n')
        self.task = self.root/'.seiva/tarefas/t'
        self.task.mkdir(parents=True)
        (self.task/'estado.json').write_text(json.dumps({'created_at':time.time()-30}))
        self.source = self.root/'events.jsonl'
        self.source.write_text('')
    def tearDown(self):
        self.tmp.cleanup()
    def event(self,id='1',timestamp=None,**extra):
        return dict(id=id,timestamp=timestamp or time.time(),session='s',model='model',
                    tokens={'input':10,'output':2,'cache_read':3,'cache_write':0},**extra)
    def append(self,event):
        with self.source.open('a') as f: f.write(json.dumps(event)+'\n')
    def args(self,**kw):
        return types.SimpleNamespace(tarefa=str(self.task),app='generic',fonte=[str(self.source)],
                     inicio=None,fim=None,rpc_bin=None,**kw)
    def collect(self):
        return monitor.collect(self.args())
    def test_missing_is_unknown(self):
        result=self.collect()
        self.assertIsNone(result['tokens']['input']['value'])
        self.assertEqual(result['quota']['mode'],'indisponível')
    def test_increment_and_duplicate(self):
        self.append(self.event()); a=self.collect()
        self.append(self.event(timestamp=time.time()))
        self.assertEqual(self.collect()['tokens']['input']['value'],10)
        self.append(self.event('2'))
        self.assertEqual(self.collect()['tokens']['input']['value'],20)
    def test_incomplete_write_then_resume(self):
        self.append(self.event())
        with self.source.open('a') as f: f.write('{"id":')
        self.assertEqual(self.collect()['events'],1)
        with self.source.open('a') as f:
            f.write('"2","timestamp":'+str(time.time())+',"session":"s","tokens":{"input":4}}\n')
        self.assertEqual(self.collect()['tokens']['input']['value'],14)
    def test_malformed_rolls_back_cache_and_report(self):
        self.append(self.event()); self.collect()
        before=(self.task/'consumo.json').read_bytes()
        with self.source.open('a') as f: f.write('not-json\n')
        with self.assertRaises(ValueError): self.collect()
        self.assertEqual((self.task/'consumo.json').read_bytes(),before)
    def test_scope_excludes_previous_work(self):
        self.append(self.event('old',timestamp=time.time()-300))
        self.append(self.event('new'))
        self.assertEqual(self.collect()['tokens']['input']['value'],10)
    def test_cumulative_uses_baseline(self):
        a=self.event('old',timestamp=time.time()-300,cumulative=True)
        a['tokens']['input']=1000
        b=self.event('new',cumulative=True); b['tokens']['input']=1015
        self.append(a);self.append(b)
        self.assertEqual(self.collect()['tokens']['input']['value'],15)
    def test_cumulative_without_baseline_not_entire_session(self):
        self.append(self.event(cumulative=True))
        self.assertIsNone(self.collect()['tokens']['input']['value'])
    def test_cumulative_restart_uses_last_request(self):
        self.append(self.event('a',cumulative=True,delta_tokens={'input':10}))
        b=self.event('b',cumulative=True,delta_tokens={'input':4});b['tokens']['input']=4
        self.append(b)
        self.assertEqual(self.collect()['tokens']['input']['value'],14)
    def test_stale_quota_unknown(self):
        (self.task/'estado.json').write_text(json.dumps({'created_at':time.time()-1000}))
        self.append(self.event(timestamp=time.time()-600,quota={'used_percent':10}))
        r=self.collect();self.assertTrue(r['stale']);self.assertIsNone(r['quota']['value'])
    def test_truncation_reread_deduplicated(self):
        self.append(self.event());self.collect()
        self.source.write_text(json.dumps(self.event())+'\n')
        self.assertEqual(self.collect()['events'],1)
    def test_no_conversation_cache(self):
        event=self.event();event['prompt']='PRIVATE-CONVERSATION-DO-NOT-CACHE'
        self.append(event);self.collect()
        self.assertNotIn(b'PRIVATE-CONVERSATION-DO-NOT-CACHE',(self.task/'monitor.sqlite3').read_bytes())
    def test_concurrent_collectors(self):
        self.append(self.event())
        with concurrent.futures.ThreadPoolExecutor(2) as pool:
            results=list(pool.map(lambda _:self.collect(),range(2)))
        self.assertEqual([x['tokens']['input']['value'] for x in results],[10,10])
    def test_multiple_cumulative_models_same_session(self):
        for id,model,total,ts in [('a','A',100,time.time()-300),('b','B',200,time.time()-299),
                                   ('c','A',110,time.time()-2),('d','B',220,time.time()-1)]:
            e=self.event(id,timestamp=ts,cumulative=True);e['model']=model;e['tokens']['input']=total
            self.append(e)
        self.assertEqual(self.collect()['tokens']['input']['value'],30)
    def test_copytruncate_short_source(self):
        self.source.write_text(json.dumps(self.event('a'))+'\n');self.collect()
        self.source.write_text(json.dumps(self.event('b'))+'\n')
        self.assertEqual(self.collect()['events'],2)
    def test_lock_symlink_does_not_touch_target(self):
        victim=self.root/'victim';victim.write_text('keep');victim.chmod(0o644)
        (self.task/'monitor.lock').symlink_to(victim)
        with self.assertRaises(OSError):self.collect()
        self.assertEqual(victim.stat().st_mode & 0o777,0o644)
    def test_quota_survives_later_token_event(self):
        self.append(self.event('q',timestamp=time.time()-3,quota={'primary':{'used_percent':20}}))
        self.append(self.event('t',timestamp=time.time()-2))
        self.assertEqual(self.collect()['quota']['value']['primary']['used_percent'],20)
    def test_reset_window_not_reported_as_old_percent(self):
        self.append(self.event(quota={'primary':{'used_percent':90,'resets_at':time.time()-1}}))
        self.assertIsNone(self.collect()['quota']['value']['primary']['used_percent'])
    def test_undetected_required_tool_blocks_selection(self):
        args,caps,tasks,cp,tp=self.selection();caps['tools']=None;cp.write_text(json.dumps(caps))
        self.assertEqual(monitor.select(args)['chosen'],[])
    def test_completed_task_not_dispatched(self):
        args,caps,tasks,cp,tp=self.selection();tasks['completed']=['T'];tp.write_text(json.dumps(tasks))
        self.assertEqual(monitor.select(args)['chosen'],[])
    def test_no_success_history_not_cheap_fallback(self):
        args,*_=self.selection();hist=self.root/'history.json'
        hist.write_text(json.dumps([{'model':'large','kind':'fix','risk':2,'total_tokens':10000,'accepted':False}]*3))
        args.historico=str(hist)
        self.assertEqual(monitor.select(args)['chosen'],[])
    def test_atomic_error_keeps_previous(self):
        out=self.task/'out.json';monitor.atomic(out,{'valid':1})
        with patch.object(monitor.os,'replace',side_effect=OSError('synthetic')):
            with self.assertRaises(OSError): monitor.atomic(out,{'valid':2})
        self.assertEqual(json.loads(out.read_text()),{'valid':1})
    def test_private_task_required(self):
        folder=self.root/'tracked';folder.mkdir()
        with self.assertRaises(ValueError):monitor.private_task(folder)
    def selection(self,tokens=100000,models=None):
        caps={'valid_until':time.time()+300,'models':models or [{'id':'small','efforts':['low']},{'id':'large','efforts':['high']}],
              'parallel_limit':2,'clean_context':True,'tools':['shell']}
        tasks={'budget':{'tokens':tokens,'unit':'tokens','source':'test explicitly allocated tokens',
                         'observed_at':time.time()},'tasks':[{'id':'T','kind':'fix','risk':2,'complexity':1,
                         'authorized':True,'context_tokens':100,'required_tools':['shell'],
                         'candidates':[{'model':'small','quality':1,'tools':['shell'],'context_limit':1000,
                            'estimated_tokens':100,'review_tokens':50,'rework_tokens':20,'effort':'low'},
                           {'model':'large','quality':3,'tools':['shell'],'context_limit':1000,
                            'estimated_tokens':1000,'review_tokens':500,'rework_tokens':200,'effort':'high'}]}]}
        cp=self.root/'caps.json';tp=self.root/'tasks.json'
        cp.write_text(json.dumps(caps));tp.write_text(json.dumps(tasks))
        args=types.SimpleNamespace(tarefa=str(self.task),capacidades=str(cp),tarefas=str(tp),
                       historico=None,saldo_tokens=None,reserva='wave1')
        return args,caps,tasks,cp,tp
    def test_sensitive_never_downgraded(self):
        args,*_=self.selection(models=[{'id':'small','efforts':['low']}])
        r=monitor.select(args);self.assertEqual(r['chosen'],[]);self.assertIsNone(r['reservation'])
    def test_reserves_review_and_rework(self):
        args,*_=self.selection(tokens=2000)
        self.assertEqual(monitor.select(args)['chosen'],[])
    def test_shared_reservation(self):
        args,*_=self.selection(tokens=3000)
        r=monitor.select(args);self.assertEqual(r['chosen'][0]['model'],'large')
        args.reserva='wave2';self.assertEqual(monitor.select(args)['chosen'],[])
        args.reserva='wave1';monitor.release(args)
        self.assertEqual(len(monitor.select(args)['chosen']),1)
    def test_duplicate_reservation_refused(self):
        args,*_=self.selection();monitor.select(args)
        with self.assertRaises(ValueError):monitor.select(args)
    def test_percent_not_tokens(self):
        args,caps,tasks,cp,tp=self.selection();tasks['budget']['unit']='percent';tp.write_text(json.dumps(tasks))
        with self.assertRaises(ValueError):monitor.select(args)
    def test_expired_capabilities(self):
        args,caps,tasks,cp,tp=self.selection();caps['valid_until']=time.time()-1;cp.write_text(json.dumps(caps))
        with self.assertRaises(ValueError):monitor.select(args)
    def test_unauthorized_and_dependencies(self):
        args,caps,tasks,cp,tp=self.selection();tasks['tasks'][0]['authorized']=False;tp.write_text(json.dumps(tasks))
        self.assertEqual(monitor.select(args)['chosen'],[])
        tasks['tasks'][0].update(authorized=True,depends_on=['other']);tp.write_text(json.dumps(tasks))
        self.assertEqual(monitor.select(args)['chosen'],[])
    def test_history_includes_failures(self):
        args,*_=self.selection();hist=self.root/'history.json'
        hist.write_text(json.dumps([{'model':'large','kind':'fix','risk':2,'total_tokens':n,'accepted':i==2}
                                   for i,n in enumerate([1000,1000,1000])]))
        args.historico=str(hist)
        r=monitor.select(args);self.assertEqual(r['chosen'][0]['tokens'],3000)
    def test_cost_not_token_optimization(self):
        args,caps,tasks,cp,tp=self.selection();small=tasks['tasks'][0]['candidates'][0]
        small.update(quality=3,estimated_tokens=3000,estimated_cost=.01)
        tasks['tasks'][0]['candidates'][1]['estimated_cost']=10
        tp.write_text(json.dumps(tasks))
        self.assertEqual(monitor.select(args)['chosen'][0]['model'],'large')


if __name__=='__main__':unittest.main()
