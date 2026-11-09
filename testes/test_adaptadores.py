#!/usr/bin/env python3
# Fixtures sintéticas; não lê históricos nem credenciais.
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import unittest
from unittest import mock
spec = importlib.util.spec_from_file_location('adaptadores', Path(__file__).resolve().parents[1] / 'scripts/adaptadores.py')
a = importlib.util.module_from_spec(spec)
spec.loader.exec_module(a)

class NormalizeTests(unittest.TestCase):
    def test_codex_jsonl(self):
        event, = a.normalize('codex', {'timestamp': '2026-01-01T00:00:00Z', 'type': 'event_msg',
            'payload': {'type': 'token_count', 'session_id': 's1', 'info': {
                'total_token_usage': {'input_tokens': 100, 'output_tokens': 20, 'cached_input_tokens': 40},
                'last_token_usage': {'input_tokens': 15, 'output_tokens': 3}, 'model_context_window': 200000},
                'rate_limits': {'primary': {'used_percent': 25, 'window_minutes': 300, 'resets_at': 1800000000}}}})
        self.assertEqual(event['tokens'], {'input': 100, 'output': 20, 'cache_read': 40, 'cache_write': None})
        self.assertTrue(event['cumulative'])
        self.assertEqual(event['delta_tokens']['input'], 15)
        self.assertEqual(event['context'], {'used': 15, 'limit': 200000})
        self.assertEqual(event['quota']['primary']['used_percent'], 25)
        self.assertEqual(event['timestamp'], 1767225600)
        self.assertEqual(event['session'], 's1')
        self.assertEqual(event['tokens_semantics'], 'input_includes_cache_read')

    def test_codex_app_server_notification(self):
        event, = a.normalize('codex', {'method': 'thread/tokenUsage/updated', 'params': {
            'threadId': 'thread1', 'tokenUsage': {'total': {'inputTokens': 7, 'outputTokens': 2, 'cachedInputTokens': 4},
                'last': {'inputTokens': 3}, 'modelContextWindow': 100}}})
        self.assertEqual(event['session'], 'thread1')
        self.assertEqual(event['tokens']['cache_read'], 4)
        self.assertIsNone(event['timestamp'])

    def test_claude_identity_deduplicates_content(self):
        record = {'type': 'assistant', 'timestamp': 1767225600, 'sessionId': 's', 'requestId': 'r',
                  'message': {'id': 'm', 'model': 'claude-sonnet', 'content': 'PRIVATE-CONTENT',
                    'usage': {'input_tokens': 3, 'output_tokens': 4, 'cache_read_input_tokens': 5, 'cache_creation_input_tokens': 6}}}
        first, = a.normalize('claude', record)
        record['message']['content'] = 'OTHER-PRIVATE-CONTENT'
        record['message']['usage']['output_tokens'] = 9
        last, = a.normalize('claude-code', record)
        self.assertEqual(first['id'], last['id'])
        self.assertNotIn('PRIVATE', json.dumps(first))
        self.assertFalse(first['cumulative'])
        self.assertEqual(first['tokens']['cache_write'], 6)

    def test_gemini_models_and_thoughts(self):
        events = a.normalize('gemini', {'timestamp': 123, 'session_id': 's', 'response': 'PRIVATE', 'stats': {'models': {
            'gemini-a': {'tokens': {'prompt': 10, 'candidates': 4, 'cached': 2, 'thoughts': 3}},
            'gemini-b': {'tokens': {'prompt': 5}}}}})
        self.assertEqual(len(events), 2)
        self.assertEqual(events[0]['tokens']['reasoning'], 3)
        self.assertEqual(events[0]['tokens']['output'], 4)
        self.assertTrue(events[0]['cumulative'])
        self.assertIsNone(events[1]['tokens']['output'])
        self.assertNotIn('PRIVATE', json.dumps(events))

    def test_opencode_export(self):
        events = a.normalize('opencode', {'messages': [{'info': {'role': 'user'}, 'parts': ['PRIVATE']},
            {'info': {'role': 'assistant', 'id': 'm', 'sessionID': 's', 'modelID': 'model-a',
                'time': {'created': 1767225600000}, 'cost': .002,
                'tokens': {'input': 8, 'output': 4, 'reasoning': 2, 'cache': {'read': 3, 'write': 1}}}, 'parts': ['PRIVATE']}]})
        self.assertEqual(len(events), 1)
        self.assertEqual(events[0]['timestamp'], 1767225600)
        self.assertEqual(events[0]['tokens']['output'], 4)
        self.assertEqual(events[0]['tokens']['reasoning'], 2)
        self.assertEqual(events[0]['cost'], .002)
        self.assertNotIn('PRIVATE', json.dumps(events))

    def test_opencode_rejects_iso_in_numeric_millisecond_field(self):
        with self.assertRaises(ValueError):
            a.normalize('opencode', {'info': {'role': 'assistant', 'tokens': {'input': 1},
                'time': {'created': '2026-01-01T00:00:00Z'}}})

    def test_gemini_nested_result_keeps_own_metadata(self):
        event, = a.normalize('gemini', {'timestamp': 100, 'session': 'outer', 'result': {
            'timestamp': '2026-01-01T00:00:00Z', 'session_id': 'nested', 'response': 'PRIVATE',
            'stats': {'models': {'gemini-a': {'tokens': {'prompt': 3}}}}}})
        self.assertEqual(event['timestamp'], 1767225600)
        self.assertEqual(event['session'], 'nested')
        self.assertNotIn('PRIVATE', json.dumps(event))
        event, = a.normalize('gemini', {'timestamp': 100, 'session_id': 'outer', 'result': {
            'stats': {'models': {'gemini-a': {'tokens': {'prompt': 3}}}}}})
        self.assertEqual(event['timestamp'], 100)
        self.assertEqual(event['session'], 'outer')

    def test_generic_whitelist_and_nulls(self):
        event, = a.normalize('generic', {'id': 'e', 'timestamp': 123, 'tokens': {'input': 0, 'secret': 'PRIVATE'},
            'context': {'used': 1, 'limit': 2, 'text': 'PRIVATE'},
            'delta_tokens': {'input': 2, 'content': 'PRIVATE'}, 'text': 'PRIVATE'})
        self.assertEqual(event['tokens']['input'], 0)
        self.assertEqual(event['delta_tokens']['input'], 2)
        self.assertIsNone(event['delta_tokens']['output'])
        self.assertIsNone(event['tokens']['output'])
        self.assertNotIn('PRIVATE', json.dumps(event))

    def test_invalid_numbers_fail_sanitized(self):
        for number in (-1, float('nan'), float('inf'), True, 'PRIVATE', 10**1000):
            with self.assertRaises(ValueError) as error:
                a.normalize('generic', {'tokens': {'input': number}})
            self.assertNotIn('PRIVATE', str(error.exception))

    def test_invalid_timestamp_fail_sanitized(self):
        for stamp in (-1, True, 'PRIVATE', '2026-01-01', 10**15):
            with self.assertRaises(ValueError) as error:
                a.normalize('generic', {'timestamp': stamp, 'tokens': {}})
            self.assertNotIn('PRIVATE', str(error.exception))

    def test_unrelated_records_are_ignored(self):
        self.assertEqual(a.normalize('codex', {'type': 'response_item', 'payload': {'text': 'PRIVATE'}}), [])
        self.assertEqual(a.normalize('claude', {'type': 'user'}), [])
        self.assertEqual(a.normalize('gemini', {'response': 'PRIVATE'}), [])

    def test_unsupported_cursor_is_explicit(self):
        with self.assertRaisesRegex(ValueError, 'cursor:'):
            a.normalize('cursor', {'type': 'result', 'result': 'PRIVATE'})

    def test_malformed_usage_and_quota(self):
        for record in ({'tokens': []}, {'tokens': {}, 'quota': {'primary': {'used_percent': 101}}},
                       {'tokens': {}, 'cumulative': 'PRIVATE'}, {'tokens': {}, 'model': 'PRIVATE CONTENT'}):
            with self.assertRaises(ValueError) as error:
                a.normalize('generic', record)
            self.assertNotIn('PRIVATE', str(error.exception))

class RpcTests(unittest.TestCase):
    def run_server(self, source, timeout=2):
        with tempfile.TemporaryDirectory() as directory:
            script = Path(directory) / 'fake.py'
            script.write_text(source, encoding='utf-8')
            original = subprocess.Popen
            children = []
            commands = []
            def start(command, **kwargs):
                commands.append(command)
                child = original([sys.executable, '-u', str(script)], **kwargs)
                children.append(child)
                return child
            with mock.patch.object(a.subprocess, 'Popen', side_effect=start):
                result = a.codex_rpc('synthetic-codex', timeout=timeout)
            self.assertTrue(all(child.poll() is not None for child in children))
            self.assertEqual(commands[0], ['synthetic-codex', 'app-server', '--listen', 'stdio://'])
            return result

    def test_read_only_handshake_pagination_quota(self):
        result = self.run_server('''import json, sys
initialized = False
for line in sys.stdin:
 r=json.loads(line); method=r['method']
 if method == 'initialized':
  initialized=True; continue
 if method == 'initialize': result={}
 elif method == 'model/list' and initialized:
  second=bool(r['params'].get('cursor'))
  result={'data':[{'id':'model-b' if second else 'model-a','supportedReasoningEfforts':[{'reasoningEffort':'high','description':'PRIVATE'}]}], 'nextCursor':None if second else 'next'}
 elif method == 'account/rateLimits/read' and initialized:
  result={'rateLimits':{'primary':{'usedPercent':20,'windowDurationMins':300,'resetsAt':1800000000},'credits':{'hasCredits':True,'unlimited':False,'balance':'12.5','text':'PRIVATE'}}}
 else: sys.exit(3)
 print(json.dumps({'id':r['id'],'result':result}),flush=True)
''')
        self.assertEqual(result['errors'], [])
        self.assertEqual(result['models'], [{'id': 'model-a', 'efforts': ['high']}, {'id': 'model-b', 'efforts': ['high']}])
        self.assertEqual(result['quota']['primary']['window_minutes'], 300)
        self.assertEqual(result['credits'], {'has_credits': True, 'unlimited': False, 'balance': 12.5})
        self.assertNotIn('PRIVATE', json.dumps(result))

    def test_timeout_kills_child(self):
        started = time.monotonic()
        result = self.run_server('import time; time.sleep(30)', timeout=.15)
        self.assertIn('timeout', result['errors'])
        self.assertLess(time.monotonic() - started, 3)

    def test_errors_do_not_disclose_server_message(self):
        result = self.run_server('''import json,sys
for line in sys.stdin:
 r=json.loads(line)
 if 'id' not in r: continue
 print(json.dumps({'id':r['id'],'error':{'code':-1,'message':'PRIVATE SECRET'}}),flush=True)
''')
        self.assertEqual(result['errors'], ['initialize_unavailable'])
        self.assertNotIn('PRIVATE', json.dumps(result))

    def test_quota_survives_unsupported_models(self):
        result = self.run_server('''import json,sys
for line in sys.stdin:
 r=json.loads(line)
 if 'id' not in r:continue
 if r['method']=='model/list': response={'error':{'message':'PRIVATE'}}
 elif r['method']=='account/rateLimits/read':response={'result':{'rateLimits':{'primary':{'usedPercent':0}}}}
 else:response={'result':{}}
 print(json.dumps({'id':r['id'],**response}),flush=True)
''')
        self.assertEqual(result['errors'], ['model_list_unavailable'])
        self.assertEqual(result['quota']['primary']['used_percent'], 0)
        self.assertIsNone(result['credits'])
        self.assertIsNone(result['quota']['primary']['resets_at'])

    def test_credits_validation_and_whitelist(self):
        self.assertEqual(a._credits({'hasCredits': True, 'balance': '0', 'text': 'PRIVATE'}),
                         {'has_credits': True, 'unlimited': None, 'balance': 0})
        for raw in ({'balance': 'PRIVATE'}, {'balance': 'nan'}, {'balance': -1}, {'hasCredits': 'PRIVATE'}):
            with self.assertRaises(ValueError) as error:
                a._credits(raw)
            self.assertNotIn('PRIVATE', str(error.exception))

    def test_invalid_catalog_entries_are_not_available_models(self):
        for invalid in ({}, {'id': 'model-a', 'supportedReasoningEfforts': [{}]},
                        {'id': 'model-a', 'supportedReasoningEfforts': [{'reasoningEffort': 4}]}):
            source = '''import json,sys
bad = %s
for line in sys.stdin:
 r=json.loads(line)
 if 'id' not in r: continue
 if r['method']=='model/list': result={'data':[{'id':'valid'},bad], 'nextCursor':None}
 elif r['method']=='account/rateLimits/read': result={'rateLimits':{'primary':{'usedPercent':10}}}
 else: result={}
 print(json.dumps({'id':r['id'],'result':result}),flush=True)
''' % repr(invalid)
            result = self.run_server(source)
            self.assertEqual(result['models'], [])
            self.assertIn('protocol_invalid', result['errors'])
            self.assertEqual(result['quota']['primary']['used_percent'], 10)

    def test_malformed_protocol(self):
        result = self.run_server("print('PRIVATE INVALID JSON',flush=True)")
        self.assertEqual(result['errors'], ['protocol_invalid'])
        self.assertNotIn('PRIVATE', json.dumps(result))

if __name__ == '__main__':
    unittest.main()
