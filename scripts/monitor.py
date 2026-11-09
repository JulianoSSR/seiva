#!/usr/bin/env python3
# seiva · JulianoSSR · MIT
"""Contabilidade local incremental e reserva compartilhada. Nenhuma chamada de modelo."""
import argparse
import contextlib
import datetime as dt
import hashlib
import json
import math
import os
from pathlib import Path
import shutil
import stat
import sqlite3
import subprocess
import sys
import tempfile
import time
import uuid

from adaptadores import normalize, codex_rpc


def epoch(value):
    if value is None:
        return None
    if isinstance(value, (float, int)) and math.isfinite(value):
        return float(value)
    parsed = dt.datetime.fromisoformat(str(value).replace('Z', '+00:00'))
    if parsed.tzinfo is None:
        raise ValueError('horário precisa de fuso')
    return parsed.timestamp()


def number(value):
    if isinstance(value, bool) or not isinstance(value, (int, float)) or not math.isfinite(value) or value < 0:
        raise ValueError('número inválido')
    return value


def git(*args, cwd=None):
    p = subprocess.run(['git', *args], cwd=cwd, capture_output=True, text=True)
    if p.returncode:
        raise ValueError('Git recusou operação: ' + args[0])
    return p.stdout.strip()


def private_task(value):
    task = Path(value).resolve(strict=True)
    if not task.is_dir() or (task/'tarefas').is_dir() or task.name == 'tarefas':
        raise ValueError('informe a pasta da tarefa')
    repo = Path(git('rev-parse', '--show-toplevel', cwd=task)).resolve()
    rel = task.relative_to(repo)
    p = subprocess.run(['git', 'check-ignore', '-q', '--', str(rel)], cwd=repo)
    if p.returncode != 0:
        raise ValueError('artefatos privados exigem tarefa ignorada pelo Git')
    return task, repo


@contextlib.contextmanager
def locked(path):
    import fcntl
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    fd = os.open(path, os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW, 0o600)
    with os.fdopen(fd, 'a+b') as f:
        info = os.fstat(f.fileno())
        if not stat.S_ISREG(info.st_mode) or info.st_nlink != 1:
            raise ValueError('trava precisa ser arquivo regular exclusivo')
        os.fchmod(f.fileno(), 0o600)
        fcntl.flock(f, fcntl.LOCK_EX)
        yield
        fcntl.flock(f, fcntl.LOCK_UN)


def atomic(path, data):
    path = Path(path)
    if path.is_symlink():
        raise ValueError('destino simbólico recusado')
    fd, name = tempfile.mkstemp(prefix='.'+path.name, dir=path.parent)
    try:
        with os.fdopen(fd, 'w', encoding='utf-8') as f:
            os.fchmod(f.fileno(), 0o600)
            json.dump(data, f, ensure_ascii=False, indent=2, allow_nan=False)
            f.write('\n')
            f.flush()
            os.fsync(f.fileno())
        os.replace(name, path)
    finally:
        if os.path.exists(name):
            os.unlink(name)


def reading(value, unit, source, when, scope, mode='observado', **extra):
    return dict(value=value, unit=unit, source=source, observed_at=when,
                scope=scope, mode=mode if value is not None else 'indisponível', **extra)


def database(task):
    path = task/'monitor.sqlite3'
    if path.is_symlink():
        raise ValueError('cache simbólico recusado')
    db = sqlite3.connect(path, timeout=30)
    os.chmod(path, 0o600)
    db.executescript('''CREATE TABLE IF NOT EXISTS sources
        (source TEXT PRIMARY KEY, inode TEXT, offset INTEGER, prefix TEXT);
        CREATE TABLE IF NOT EXISTS events
        (app TEXT, session TEXT, id TEXT, ts REAL, data TEXT,
         PRIMARY KEY(app,session,id));''')
    return db


def ingest(db, app, source):
    path = Path(source).resolve(strict=True)
    if not path.is_file():
        raise ValueError('fonte precisa ser arquivo regular')
    source_id = hashlib.sha256(str(path).encode()).hexdigest()
    stat = path.stat()
    inode = str((stat.st_dev, stat.st_ino))
    old = db.execute('SELECT inode,offset,prefix FROM sources WHERE source=?', (source_id,)).fetchone()
    with path.open('rb') as f:
        # Prefixo só numérico (hash) detecta substituição, inclusive copytruncate.
        prefix = hashlib.sha256(f.read(min(old[1], 256) if old else 0)).hexdigest()
        offset = old[1] if old and old[0] == inode and old[1] <= stat.st_size else 0
        if old and old[2] != prefix:
            offset = 0
        f.seek(offset)
        while True:
            position = f.tell()
            line = f.readline(8 * 1024 * 1024 + 1)
            if not line:
                break
            if len(line) > 8 * 1024 * 1024:
                raise ValueError('evento excede limite de 8 MiB')
            if not line.endswith(b'\n'):
                f.seek(position)
                break  # escritor ativo: reaproveitar na próxima atualização
            if not line.strip():
                continue
            try:
                raw = json.loads(line)
                events = normalize(app, raw)
            except (ValueError, TypeError, KeyError, AttributeError):
                raise ValueError('evento inválido na fonte; cache anterior preservado') from None
            for event in events:
                event['session'] = event.get('session') or source_id
                event['timestamp'] = epoch(event.get('timestamp'))
                eid = str(event.get('id') or hashlib.sha256(json.dumps(event, sort_keys=True).encode()).hexdigest())
                db.execute('INSERT OR REPLACE INTO events VALUES(?,?,?,?,?)',
                    (app, event['session'], eid, event['timestamp'], json.dumps(event, allow_nan=False)))
        offset = f.tell()
        f.seek(0)
        prefix = hashlib.sha256(f.read(min(offset, 256))).hexdigest()
    db.execute('INSERT OR REPLACE INTO sources VALUES(?,?,?,?)', (source_id, inode, offset, prefix))
    return source_id


def summarize(db, app, start, end, now):
    rows = db.execute('SELECT data FROM events WHERE app=? ORDER BY ts,id', (app,)).fetchall()
    totals = {k: None for k in ('input', 'output', 'cache_read', 'cache_write')}
    prev, latest, count, undated = {}, None, 0, 0
    last_context, last_quota = None, None
    costs, cost_count = 0, 0
    for row in rows:
        e = json.loads(row[0]); ts = e.get('timestamp')
        if ts is None:
            undated += 1
            continue
        session = (e['session'], e.get('model')); values = e.get('tokens') or {}
        prior = prev.get(session)
        if e.get('cumulative'):
            prev[session] = values
        if not start <= ts <= end:
            continue
        latest = e; count += 1
        if e.get('context') is not None: last_context = e
        if e.get('quota') is not None: last_quota = e
        for key in totals:
            v = values.get(key)
            if v is None:
                continue
            number(v)
            if e.get('cumulative'):
                if prior and prior.get(key) is not None and v >= prior[key]:
                    v -= prior[key]
                else:
                    v = (e.get('delta_tokens') or {}).get(key)
                    if v is None:
                        continue  # total da sessão não é total da tarefa
            totals[key] = (totals[key] or 0) + number(v)
        if e.get('cost') is not None:
            costs += number(e['cost']); cost_count += 1
    scope = {'start': start, 'end': end, 'app': app}
    source = app + ':registros-locais'
    last_ts = latest.get('timestamp') if latest else None
    context = last_context.get('context', {}) if last_context else {}
    context_ts = last_context.get('timestamp') if last_context else None
    used, limit = context.get('used'), context.get('limit')
    quota = last_quota.get('quota') if last_quota else None
    quota_ts = last_quota.get('timestamp') if last_quota else None
    if quota is not None:
        quota = json.loads(json.dumps(quota))
        for window in quota.values():
            if isinstance(window, dict) and window.get('resets_at') is not None and window['resets_at'] <= now:
                window['used_percent'] = None
                window['status'] = 'janela expirada; atualizar fonte'
    age = max(0, now-last_ts) if last_ts else None
    return {'schema': 1, 'observed_at': now, 'scope': scope,
        'tokens': {k: reading(v, 'tokens', source, last_ts, scope) for k,v in totals.items()},
        'context': {'used': reading(used, 'tokens', source, context_ts, 'session'),
                    'available': reading(max(0, limit-used) if limit is not None and used is not None else None,
                                         'tokens', source, context_ts, 'session')},
        'quota': reading(quota if quota_ts is not None and 0 <= now-quota_ts <= 300 else None,
                         'percent/window/reset', source, quota_ts, 'account'),
        'credits': reading(None, 'credits', source, None, 'account'),
        'cost': reading(costs if cost_count else None, 'USD', source, last_ts, scope),
        'forecast': reading(None, 'tokens', 'selecionar', None, 'next-wave'),
        'events': count, 'undated_events_excluded': undated, 'source_age_seconds': age,
        'tokens_semantics':latest.get('tokens_semantics') if latest else None,
        'stale': age is None or age > 300,
        'limitations': ['quota percentual não é saldo em tokens',
            'observar consumo não interrompe agentes',
            'eventos sem horário são excluídos do intervalo',
            'contexto representa último evento, não soma de tokens',
            'atribuição por intervalo das fontes informadas; exclusividade da sessão não é demonstrada',
            'somente fontes fornecidas: agentes omitidos não entram na soma']}


def collect(args):
    task, _ = private_task(args.tarefa)
    now = time.time()
    state = task/'estado.json'
    if args.inicio:
        start = epoch(args.inicio)
    elif state.exists():
        st = json.loads(state.read_text())
        start = epoch(st.get('created_at') or st.get('created') or st.get('criado_em'))
        if start is None:
            raise ValueError('estado sem início; informe --inicio com fuso')
    else:
        raise ValueError('tarefa sem início verificável; informe --inicio')
    end = epoch(args.fim) if args.fim else now
    if start > end:
        raise ValueError('intervalo invertido')
    with locked(task/'monitor.lock'):
        with contextlib.closing(database(task)) as db:
            with db:
                for source in args.fonte:
                    ingest(db, args.app, source)
            report = summarize(db, args.app, start, end, now)
        if args.rpc_bin:
            if args.app != 'codex':
                raise ValueError('--rpc-bin só é válido para Codex')
            live = codex_rpc(args.rpc_bin)
            if live.get('quota') is not None:
                report['quota'] = reading(live['quota'], 'percent/window/reset',
                                          'codex:account/rateLimits/read', now, 'account')
            report['credits'] = reading(live.get('credits'), 'credits', 'codex:account/rateLimits/read', now, 'account')
            report['rpc_errors'] = live.get('errors', [])
        atomic(task/'consumo.json', report)
    return report


def capabilities(app, binary=None):
    command = {'claude':'claude', 'codex':'codex', 'gemini':'gemini',
               'opencode':'opencode', 'cursor':'cursor-agent', 'generic':None}[app]
    executable = binary or (shutil.which(command) if command else None)
    version = None
    if executable:
        try:
            p = subprocess.run([executable, '--version'], capture_output=True, timeout=10, text=True)
            # Apenas primeira linha, sem stderr/configuração ou saída arbitrária.
            if p.returncode == 0:
                import re
                match = re.search(r'\b\d+\.\d+\.\d+[A-Za-z0-9.+-]*', p.stdout)
                version = match.group(0) if match else None
        except (OSError, subprocess.TimeoutExpired):
            pass
    now = time.time()
    result = {'schema':1, 'app':app, 'observed_at':now, 'valid_until':now+300,
        'installed_version':version, 'models':[], 'model_per_agent':None,
        'clean_context':None, 'parallel_limit':None, 'isolation':None,
        'write_restriction':None, 'tools':None, 'usage_source':'local-events' if app != 'cursor' else None,
        'quota_source':None, 'updates':'bounded-poll', 'validation':'não validado no aplicativo',
        'errors':[]}
    if app == 'codex' and executable:
        live = codex_rpc(executable)
        result.update(models=live.get('models', []), errors=live.get('errors', []))
        result['quota_source'] = 'account/rateLimits/read' if live.get('quota') is not None else None
        result['quota'] = live.get('quota')
        result['validation'] = 'RPC real' if result['models'] else 'RPC indisponível'
    return result


def ledger_path(repo):
    common = Path(git('rev-parse', '--git-common-dir', cwd=repo))
    if not common.is_absolute():
        common = repo/common
    return common.resolve()/'seiva-budget.json'


def select(args):
    task, repo = private_task(args.tarefa)
    caps = json.loads(Path(args.capacidades).read_text())
    request = json.loads(Path(args.tarefas).read_text())
    history = json.loads(Path(args.historico).read_text()) if args.historico else []
    now = time.time()
    if epoch(caps.get('valid_until')) is None or epoch(caps['valid_until']) < now:
        raise ValueError('capacidades expiradas: descubra novamente')
    budget = request.get('budget', {})
    observed = epoch(budget.get('observed_at'))
    if not budget.get('source') or observed is None or not 0 <= now-observed <= 300:
        raise ValueError('saldo ausente/antigo: não é possível reservar com segurança')
    available = number(args.saldo_tokens if args.saldo_tokens is not None else budget.get('tokens'))
    # Nunca derivado de assinatura percentual. Produtor deve declarar unidade explicitamente.
    if budget.get('unit') != 'tokens':
        raise ValueError('saldo precisa de unidade tokens; percentual não é conversível')
    actual = {m['id']:m for m in caps.get('models', [])}
    done = set(request.get('completed', []))
    ready = [t for t in request.get('tasks', []) if t['id'] not in done and t.get('authorized') is True
             and set(t.get('depends_on', [])) <= done]
    ready.sort(key=lambda t: (-number(t.get('priority', 0)), t['id']))
    choices, skipped = [], []
    for task_spec in ready:
        options = []
        minimum = max(number(task_spec.get('risk', 0)), number(task_spec.get('complexity', 0)))
        for candidate in task_spec.get('candidates', []):
            model = candidate['model']; detected = actual.get(model)
            if not detected or number(candidate.get('quality', 0)) < minimum:
                continue
            if candidate.get('effort') and candidate['effort'] not in detected.get('efforts', []):
                continue
            if not set(task_spec.get('required_tools', [])) <= set(caps.get('tools') or []):
                continue
            if not set(task_spec.get('required_tools', [])) <= set(candidate.get('tools', [])):
                continue
            if number(candidate.get('context_limit', 0)) < number(task_spec.get('context_tokens', 0)):
                continue
            if task_spec.get('independent') and caps.get('clean_context') is not True:
                continue
            samples = [h for h in history if h.get('model') == model and
                       h.get('kind') == task_spec.get('kind') and h.get('risk') == task_spec.get('risk')]
            # Histórico comparável inclui falhas e retrabalho, nunca só as corridas limpas.
            successful = sum(h.get('accepted') is True for h in samples)
            if len(samples) >= 3 and not successful:
                continue
            if len(samples) >= 3 and successful:
                estimate = sum(number(h['total_tokens']) for h in samples)/successful
                mode = 'estimativa por tokens totais por sucesso'
                uncertainty = [min(number(h['total_tokens']) for h in samples),
                               max(number(h['total_tokens']) for h in samples)]
            else:
                estimate = (number(candidate.get('estimated_tokens')) + number(candidate.get('review_tokens'))
                            + number(candidate.get('rework_tokens')) + number(candidate.get('closing_tokens',100))) * 1.5
                mode = 'estimativa conservadora sem histórico suficiente'
                uncertainty = [estimate/1.5, estimate*1.5]
            options.append({'task':task_spec['id'], 'model':model, 'effort':candidate.get('effort'),
                'tokens':math.ceil(estimate), 'cost':candidate.get('estimated_cost'), 'sample_size':len(samples),
                'mode':mode, 'uncertainty_tokens':uncertainty,
                'reason':'capacidade e risco atendidos; menor previsão total com revisão, correção e fechamento'})
        if options:
            choices.append(min(options, key=lambda c:c['tokens']))
        else:
            skipped.append({'task':task_spec['id'], 'reason':'sem modelo equivalente disponível; salvar e aguardar ou dividir mantendo validações'})
    path = ledger_path(repo)
    with locked(path.with_suffix('.lock')):
        ledger = json.loads(path.read_text()) if path.exists() else {'reservations':{}}
        reservations = {k:v for k,v in ledger['reservations'].items() if v['expires_at'] > now}
        if args.reserva in reservations:
            raise ValueError('reserva já ativa: libere antes de recalcular')
        reserved = sum(v['tokens'] for v in reservations.values())
        margin = available-reserved
        selected = []
        parallel = caps.get('parallel_limit') or 1
        for c in choices:
            if len(selected) >= parallel or c['tokens'] > margin:
                skipped.append({'task':c['task'], 'reason':'não cabe com reservas/revisão ou limite de paralelismo'})
            else:
                selected.append(c); margin -= c['tokens']
        total = sum(c['tokens'] for c in selected)
        if selected:
            reservations[args.reserva] = {'tokens':total,'expires_at':now+900,
                'task':hashlib.sha256(str(task).encode()).hexdigest(), 'budget_source':budget['source']}
        atomic(path, {'reservations':reservations})
        result = {'schema':1,'observed_at':now,'budget_source':budget['source'],
            'budget_age_seconds':now-observed, 'margin_tokens':margin,'chosen':selected,
            'skipped':skipped, 'reservation':args.reserva if selected else None,
            'limitations':['custo financeiro separado da decisão por tokens',
                'qualidade e ferramentas dos candidatos exigem evidência do responsável',
                'reserva expira em 15 minutos: renovar antes de disparar; não interrompe execução',
                'reservas compartilhadas neste repositório e suas worktrees; outros repositórios exigem saldo já descontado']}
        atomic(task/'proxima-leva.json',result)
    return result


def release(args):
    task, repo = private_task(args.tarefa)
    path = ledger_path(repo)
    with locked(path.with_suffix('.lock')):
        state = json.loads(path.read_text()) if path.exists() else {'reservations':{}}
        item = state['reservations'].get(args.reserva)
        if item and item['task'] != hashlib.sha256(str(task).encode()).hexdigest():
            raise ValueError('reserva pertence a outra tarefa')
        state['reservations'].pop(args.reserva,None)
        atomic(path,state)
    return {'released':args.reserva}


def main():
    os.umask(0o077)
    p = argparse.ArgumentParser(description=__doc__)
    sub = p.add_subparsers(dest='action',required=True)
    for command in ('coletar','vigiar'):
        c = sub.add_parser(command)
        c.add_argument('--app',choices=['codex','claude','gemini','opencode','cursor','generic'],required=True)
        c.add_argument('--tarefa',required=True)
        c.add_argument('--fonte',action='append',default=[])
        c.add_argument('--inicio'); c.add_argument('--fim'); c.add_argument('--rpc-bin')
        if command == 'vigiar':
            c.add_argument('--intervalo',type=int,default=15); c.add_argument('--duracao',type=int,default=300)
    c = sub.add_parser('capacidades')
    c.add_argument('--app',choices=['codex','claude','gemini','opencode','cursor','generic'],required=True)
    c.add_argument('--rpc-bin'); c.add_argument('--saida')
    c = sub.add_parser('selecionar')
    for key in ('tarefa','capacidades','tarefas','reserva'):
        c.add_argument('--'+key,required=True)
    c.add_argument('--historico'); c.add_argument('--saldo-tokens',type=float)
    c = sub.add_parser('liberar'); c.add_argument('--tarefa',required=True); c.add_argument('--reserva',required=True)
    args = p.parse_args()
    try:
        if args.action == 'capacidades':
            result = capabilities(args.app,args.rpc_bin)
            if args.saida: atomic(Path(args.saida).resolve(),result)
        elif args.action == 'selecionar': result = select(args)
        elif args.action == 'liberar': result = release(args)
        elif args.action == 'vigiar':
            if not 5 <= args.intervalo <= 60 or not 1 <= args.duracao <= 3600:
                raise ValueError('intervalo 5–60 s; duração 1–3600 s')
            deadline = time.monotonic()+args.duracao
            while True:
                result = collect(args)
                print(json.dumps(result,ensure_ascii=False),flush=True)
                if time.monotonic()+args.intervalo > deadline: return 0
                time.sleep(args.intervalo)
        else: result = collect(args)
        print(json.dumps(result,ensure_ascii=False,allow_nan=False))
        return 0
    except (OSError,ValueError,KeyError,TypeError,sqlite3.Error,subprocess.SubprocessError):
        print('monitor: operação recusada; confira formato, permissões, fonte e validade dos dados (nenhum payload exposto)',file=sys.stderr)
        return 2


if __name__ == '__main__':
    raise SystemExit(main())
