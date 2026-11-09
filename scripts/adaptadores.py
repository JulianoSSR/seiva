#!/usr/bin/env python3
"""Adaptadores somente de métricas; nunca devolvem conteúdo de conversas.

Fontes: developers.openai.com/codex/app-server; geminicli.com/docs/cli/headless/;
cursor.com/docs/cli/reference/output-format; github.com/anomalyco/opencode.
Contadores preservam a semântica de cada fonte: input do Codex inclui cache.
Ausência é None, não zero. normalize é puro; o consumidor deduplica por id.
"""
from datetime import datetime
import hashlib
import json
import math
import os
import queue
import re
import subprocess
import threading
import time

_KEYS = ('input', 'output', 'cache_read', 'cache_write')
_ID = re.compile(r'^[\w./:@+\-]{1,256}$', re.ASCII)


def _obj(value):
    if not isinstance(value, dict):
        raise ValueError('estrutura de métricas inválida')
    return value


def _number(value):
    if value is None:
        return None
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        raise ValueError('número de métricas inválido')
    try:
        valid = math.isfinite(value) and value >= 0
    except OverflowError:
        valid = False
    if not valid:
        raise ValueError('número de métricas inválido')
    return value


def _label(value):
    if value is None:
        return None
    if not isinstance(value, str) or not _ID.fullmatch(value):
        raise ValueError('identificador de métricas inválido')
    return value


def _timestamp(value, milliseconds=False):
    if value is None:
        return None
    if isinstance(value, str):
        if milliseconds:
            raise ValueError('timestamp em milissegundos precisa ser numérico')
        try:
            parsed = datetime.fromisoformat(value.replace('Z', '+00:00'))
            if parsed.tzinfo is None:
                raise ValueError()
            value = parsed.timestamp()
        except (ValueError, OverflowError, OSError):
            raise ValueError('timestamp de métricas inválido') from None
    value = _number(value)
    value = value / 1000 if milliseconds else value
    if value > 253402300799:
        raise ValueError('timestamp de métricas inválido')
    return value


def _tokens(raw, names=None):
    raw = _obj(raw)
    names = names or dict(zip(_KEYS, _KEYS))
    result = {k: _number(raw.get(names[k])) for k in _KEYS}
    for k in ('reasoning',):
        if k in raw:
            result[k] = _number(raw[k])
    return result


def _quota(raw):
    raw = _obj(raw)
    result = {}
    for key in ('primary', 'secondary'):
        window = raw.get(key)
        if window is None:
            continue
        window = _obj(window)
        percent = _number(window.get('used_percent', window.get('usedPercent')))
        if percent is not None and percent > 100:
            raise ValueError('percentual de cota inválido')
        result[key] = {
            'used_percent': percent,
            'window_minutes': _number(window.get('window_minutes', window.get('windowDurationMins'))),
            'resets_at': _timestamp(window.get('resets_at', window.get('resetsAt'))),
        }
    return result


def _credits(raw):
    if raw is None:
        return None
    raw = _obj(raw)
    result = {}
    for source, target in (('hasCredits', 'has_credits'), ('unlimited', 'unlimited')):
        value = raw.get(source)
        if value is not None and not isinstance(value, bool):
            raise ValueError('indicador de créditos inválido')
        result[target] = value
    balance = raw.get('balance')
    if isinstance(balance, str):
        if len(balance) > 64:
            raise ValueError('saldo de créditos inválido')
        try:
            balance = float(balance)
        except ValueError:
            raise ValueError('saldo de créditos inválido') from None
    result['balance'] = _number(balance)
    return result


def _event(record, tokens, *, session=None, model=None, identity=None,
           timestamp=None, cumulative=False):
    event = {
        'timestamp': _timestamp(record.get('timestamp') if timestamp is None else timestamp),
        'session': _label(session if session is not None else record.get('session', record.get('session_id', record.get('sessionId')))),
        'model': _label(model if model is not None else record.get('model')),
        'tokens': tokens,
        'cumulative': cumulative,
    }
    # Hash only whitelisted metadata. A content field can never affect the id.
    identity = _label(identity) if identity is not None else None
    event['id'] = hashlib.sha256(json.dumps(
        [identity, event], sort_keys=True, separators=(',', ':')).encode()).hexdigest()
    if identity is not None:
        event['id'] = hashlib.sha256(json.dumps(
            [event['session'], identity], separators=(',', ':')).encode()).hexdigest()
    return event


def _codex(record):
    rpc = record.get('method') == 'thread/tokenUsage/updated'
    if rpc:
        payload = _obj(record.get('params'))
        info = _obj(payload.get('tokenUsage'))
        total, last = info.get('total'), info.get('last')
        names = dict(zip(_KEYS, ('inputTokens', 'outputTokens', 'cachedInputTokens', 'cacheWriteTokens')))
        context_limit = info.get('modelContextWindow')
    else:
        if record.get('type') != 'event_msg':
            return []
        payload = _obj(record.get('payload'))
        if payload.get('type') != 'token_count':
            return []
        info = payload.get('info')
        if info is None:
            return []
        info = _obj(info)
        total, last = info.get('total_token_usage'), info.get('last_token_usage')
        names = dict(zip(_KEYS, ('input_tokens', 'output_tokens', 'cached_input_tokens', 'cache_write_tokens')))
        context_limit = info.get('model_context_window')
    if total is None:
        return []
    event = _event(record, _tokens(total, names),
                   session=payload.get('threadId', payload.get('session_id')),
                   model=payload.get('model'), cumulative=True)
    if last is not None:
        event['delta_tokens'] = _tokens(last, names)
    if context_limit is not None or last is not None:
        used = None if last is None else _obj(last).get(names['input'])
        event['context'] = {'used': _number(used), 'limit': _number(context_limit)}
    quota = payload.get('rate_limits', payload.get('rateLimits'))
    if quota is not None:
        event['quota'] = _quota(quota)
    return [event]


def _claude(record):
    if record.get('type') != 'assistant':
        return []
    message = _obj(record.get('message'))
    if message.get('usage') is None:
        return []
    names = dict(zip(_KEYS, ('input_tokens', 'output_tokens', 'cache_read_input_tokens', 'cache_creation_input_tokens')))
    message_id = _label(message.get('id'))
    request_id = _label(record.get('requestId', record.get('request_id')))
    identity = hashlib.sha256(json.dumps([message_id, request_id]).encode()).hexdigest() if message_id or request_id else None
    event = _event(record, _tokens(message['usage'], names), model=message.get('model'), identity=identity)
    if 'costUSD' in record:
        event['cost'] = _number(record['costUSD'])
    return [event]


def _gemini(record):
    raw = record.get('result', record)
    if not isinstance(raw, dict) or raw.get('stats') is None:
        return []
    models = _obj(_obj(raw['stats']).get('models', {}))
    metadata = {key: raw.get(key, record.get(key))
                for key in ('timestamp', 'session', 'session_id', 'sessionId')}
    # O alias escolhido deve vir do resultado interno antes do envelope.
    nested_session = next((raw[key] for key in ('session', 'session_id', 'sessionId')
                           if key in raw), None)
    if nested_session is not None:
        metadata['session'] = nested_session
    metadata = {key: value for key, value in metadata.items() if value is not None}
    events = []
    names = dict(zip(_KEYS, ('prompt', 'candidates', 'cached', 'cache_write')))
    for model, stats in models.items():
        stats = _obj(stats)
        if 'tokens' not in stats:
            continue
        tokens = _tokens(stats['tokens'], names)
        if 'thoughts' in stats['tokens']:
            tokens['reasoning'] = _number(stats['tokens']['thoughts'])
        # A headless result sums all calls for this model in the run.
        event = _event(metadata, tokens, model=model, cumulative=True)
        events.append(event)
    return events


def _opencode(record):
    messages = record.get('messages')
    if messages is not None:
        if not isinstance(messages, list):
            raise ValueError('lista de métricas inválida')
        events = []
        for message in messages:
            events.extend(_opencode(_obj(message)))
        return events
    info = record.get('info', record)
    info = _obj(info)
    if info.get('role') != 'assistant' or info.get('tokens') is None:
        return []
    raw = _obj(info['tokens'])
    cache = _obj(raw.get('cache', {}))
    tokens = _tokens({**{k: raw[k] for k in ('input', 'output', 'reasoning') if k in raw},
                      'cache_read': cache.get('read'), 'cache_write': cache.get('write')})
    created = _obj(info.get('time', {})).get('created')
    timestamp = _timestamp(created, milliseconds=True) if created is not None else record.get('timestamp')
    event = _event(record, tokens, session=info.get('sessionID'), model=info.get('modelID'), identity=info.get('id'), timestamp=timestamp)
    if info.get('cost') is not None:
        event['cost'] = _number(info['cost'])
    return [event]


def _generic(record):
    if 'tokens' not in record:
        return []
    cumulative = record.get('cumulative', False)
    if not isinstance(cumulative, bool):
        raise ValueError('tipo de acumulador inválido')
    event = _event(record, _tokens(record['tokens']), identity=record.get('id'), cumulative=cumulative)
    if 'delta_tokens' in record:
        event['delta_tokens'] = _tokens(record['delta_tokens'])
    if 'context' in record:
        context = _obj(record['context'])
        event['context'] = {k: _number(context.get(k)) for k in ('used', 'limit')}
    if 'quota' in record:
        event['quota'] = _quota(record['quota'])
    if 'cost' in record:
        event['cost'] = _number(record['cost'])
    return [event]


def normalize(app, record):
    """Extrai eventos seguros. Registros alheios retornam []; inválidos falham.

    Cursor não oferece tokens no formato público atual: nunca infere uso de texto.
    O consumidor deve deduplicar ids e calcular diferenças por sessão para cumulative.
    """
    adapters = {'codex': _codex, 'claude': _claude, 'claude-code': _claude,
                'gemini': _gemini, 'gemini-cli': _gemini, 'opencode': _opencode,
                'generic': _generic, 'generico': _generic}
    if not isinstance(app, str):
        raise ValueError('aplicativo de métricas inválido')
    _obj(record)
    if app.lower() == 'cursor':
        raise ValueError('cursor: métricas de uso não disponíveis no formato público')
    adapter = adapters.get(app.lower())
    if adapter is None:
        raise ValueError('aplicativo de métricas não suportado')
    try:
        events = adapter(record)
        semantics = {'codex': 'input_includes_cache_read', 'gemini': 'input_includes_cache_read',
                     'gemini-cli': 'input_includes_cache_read', 'claude': 'input_excludes_cache',
                     'claude-code': 'input_excludes_cache', 'opencode': 'input_excludes_cache'}
        for event in events:
            event['tokens_semantics'] = semantics.get(app.lower(), 'source_reported')
        return events
    except (TypeError, KeyError, AttributeError, RecursionError):
        raise ValueError('estrutura de métricas inválida') from None


class _RpcFailure(Exception):
    pass


def codex_rpc(binary, timeout=15):
    """Sonda temporária somente de leitura, com prazo global e erros sanitizados."""
    result = {'models': [], 'quota': None, 'credits': None, 'observed_at': time.time(), 'errors': []}
    if isinstance(timeout, bool) or not isinstance(timeout, (int, float)) or not math.isfinite(timeout) or timeout <= 0:
        raise ValueError('prazo inválido')
    proc = None
    reader = None
    stopped = threading.Event()
    inbox = queue.Queue(maxsize=64)
    deadline = time.monotonic() + timeout
    sequence = 0

    def pump():
        try:
            while not stopped.is_set():
                line = proc.stdout.readline(1024 * 1024 + 1)
                if not line:
                    item = _RpcFailure('process_exit')
                elif len(line) > 1024 * 1024:
                    item = _RpcFailure('protocol_invalid')
                else:
                    try:
                        item = json.loads(line)
                    except (ValueError, UnicodeError):
                        item = _RpcFailure('protocol_invalid')
                while not stopped.is_set():
                    try:
                        inbox.put(item, timeout=.05)
                        break
                    except queue.Full:
                        pass
                if isinstance(item, _RpcFailure):
                    break
        except (OSError, ValueError):
            try:
                inbox.put_nowait(_RpcFailure('process_io'))
            except queue.Full:
                pass

    def send(value):
        if time.monotonic() >= deadline:
            raise _RpcFailure('timeout')
        proc.stdin.write((json.dumps(value) + '\n').encode())
        proc.stdin.flush()

    def request(method, params):
        nonlocal sequence
        sequence += 1
        send({'id': sequence, 'method': method, 'params': params})
        while True:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise _RpcFailure('timeout')
            try:
                response = inbox.get(timeout=remaining)
            except queue.Empty:
                raise _RpcFailure('timeout') from None
            if isinstance(response, _RpcFailure):
                raise response
            if not isinstance(response, dict):
                raise _RpcFailure('protocol_invalid')
            if response.get('id') != sequence:
                continue
            if 'error' in response:
                raise _RpcFailure(method.replace('/', '_') + '_unavailable')
            try:
                return _obj(response['result'])
            except (ValueError, KeyError):
                raise _RpcFailure('protocol_invalid') from None

    try:
        command = [os.fspath(binary), 'app-server', '--listen', 'stdio://']
        options = {'creationflags': subprocess.CREATE_NO_WINDOW} if os.name == 'nt' else {}
        proc = subprocess.Popen(command, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                stderr=subprocess.DEVNULL, **options)
        reader = threading.Thread(target=pump, daemon=True)
        reader.start()
        request('initialize', {'clientInfo': {'name': 'seiva_monitor', 'version': '1.0'}})
        send({'method': 'initialized', 'params': {}})
        try:
            cursor, seen = None, set()
            for _ in range(100):
                params = {'limit': 100, 'includeHidden': False}
                if cursor is not None:
                    params['cursor'] = cursor
                page = request('model/list', params)
                data = page.get('data')
                if not isinstance(data, list):
                    raise _RpcFailure('protocol_invalid')
                for model in data:
                    model = _obj(model)
                    efforts = model.get('supportedReasoningEfforts', [])
                    if not isinstance(efforts, list):
                        raise _RpcFailure('protocol_invalid')
                    model_id = _label(model.get('id'))
                    effort_ids = [_label(_obj(e).get('reasoningEffort')) for e in efforts]
                    if model_id is None or any(e is None for e in effort_ids):
                        raise _RpcFailure('protocol_invalid')
                    result['models'].append({'id': model_id, 'efforts': effort_ids})
                cursor = page.get('nextCursor')
                if cursor is None:
                    break
                cursor = _label(cursor)
                if cursor in seen:
                    raise _RpcFailure('pagination_invalid')
                seen.add(cursor)
            else:
                raise _RpcFailure('pagination_limit')
        except (_RpcFailure, ValueError) as exc:
            # Um catálogo parcial não comprova o conjunto de modelos disponíveis.
            result['models'] = []
            result['errors'].append(str(exc) if isinstance(exc, _RpcFailure) else 'protocol_invalid')
        try:
            limits = request('account/rateLimits/read', {})
            raw = limits.get('rateLimits')
            if raw is None:
                by_id = _obj(limits.get('rateLimitsByLimitId', {}))
                raw = by_id.get('codex')
            if raw is not None:
                result['quota'] = _quota(raw)
                result['credits'] = _credits(raw.get('credits'))
        except (_RpcFailure, ValueError) as exc:
            result['errors'].append(str(exc) if isinstance(exc, _RpcFailure) else 'protocol_invalid')
    except _RpcFailure as exc:
        result['errors'].append(str(exc))
    except (OSError, TypeError, ValueError):
        result['errors'].append('process_unavailable')
    finally:
        stopped.set()
        if proc is not None:
            if proc.poll() is None:
                proc.kill()
            proc.wait()
            if reader is not None:
                reader.join(timeout=1)
            for stream in (proc.stdin, proc.stdout):
                if stream is not None:
                    stream.close()
    result['errors'] = list(dict.fromkeys(result['errors']))
    return result
