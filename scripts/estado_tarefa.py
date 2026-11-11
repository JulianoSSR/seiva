#!/usr/bin/env python3
# seiva · JulianoSSR · MIT
"""Estado persistente da Seiva. Só biblioteca padrão; JSON canônico, Markdown derivado."""
import argparse
import base64
import contextlib
import datetime as dt
import fcntl
import hashlib
import json
import os
from pathlib import Path
import re
import stat
import subprocess
import sys
import tempfile
import time
import uuid

NAMES = ["Terreno", "Triagem", "Reconhecer", "Propor", "Atacar o plano", "Decidir",
         "Construir", "Verificar", "Atacar o código", "Entregar e aprender"]
STATUSES = {"pendente", "em-curso", "feita", "pulada", "interrompida"}
# Tentativa: running -> interrompida (sem sinal ou por limite) -> concluido/failed/cancelled.
STALE_MINUTES = 15          # sem sinal por este tempo, "running" é suspeita de interrupção
CONTEXT_LIMIT = 150000      # tokens: pacote + contexto herdado acima disto pedem divisão
MAX_PARALLEL = 3            # tentativas running ao mesmo tempo
CATEGORIES = {"script", "rapido", "padrao", "forte", "profundo"}

class Invalid(Exception):
    pass

def tuned(task, param):
    """Valor em vigor: ajuste local automático (scripts/ajustes.py) ou o padrão. Falha de leitura cai no padrão."""
    default = {"stale_minutes": STALE_MINUTES, "context_limit": CONTEXT_LIMIT}[param]
    try:
        sys.path.insert(0, str(Path(__file__).resolve().parent))
        import ajustes
        return ajustes.effective_for_task(task, param)
    except Exception:
        return default
    finally:
        if sys.path and sys.path[0] == str(Path(__file__).resolve().parent):
            sys.path.pop(0)

def now():
    return dt.datetime.now().astimezone().isoformat(timespec="seconds")

def digest(data):
    return hashlib.sha256(data).hexdigest()

def atomic(path, data):
    path = Path(path)
    fd, tmp = tempfile.mkstemp(prefix=path.name + ".", dir=path.parent)
    try:
        with os.fdopen(fd, "wb") as f:
            f.write(data if isinstance(data, bytes) else data.encode())
            f.flush()
            os.fsync(f.fileno())
        os.replace(tmp, path)
    finally:
        if os.path.exists(tmp):
            os.unlink(tmp)

def jsonwrite(path, value):
    atomic(path, json.dumps(value, ensure_ascii=False, indent=2) + "\n")

@contextlib.contextmanager
def lock(path):
    fd = os.open(path, os.O_RDWR | os.O_CREAT | getattr(os, "O_NOFOLLOW", 0), 0o600)
    try:
        st = os.fstat(fd)
        if not stat.S_ISREG(st.st_mode) or st.st_nlink != 1:
            raise Invalid("trava exige arquivo regular sem links")
        with os.fdopen(fd, "a+b") as f:
            fd = None
            fcntl.flock(f, fcntl.LOCK_EX)
            yield
    finally:
        if fd is not None:
            os.close(fd)

def git(repo, *args, allowed=(0,)):
    p = subprocess.run(["git", "-C", str(repo), *args], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if p.returncode not in allowed:
        raise Invalid("git falhou: " + p.stderr.decode(errors="replace").strip())
    return p

def repo_at(path):
    p = subprocess.run(["git", "-C", str(path), "rev-parse", "--show-toplevel"],
                       stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    return Path(os.fsdecode(p.stdout).strip()).resolve() if p.returncode == 0 else None

def fingerprint(path):
    path = Path(path)
    try:
        st = path.lstat()
    except FileNotFoundError:
        return {"exists": False}
    if stat.S_ISLNK(st.st_mode):
        data, mode = os.fsencode(os.readlink(path)), "120000"
    elif stat.S_ISREG(st.st_mode):
        data, mode = path.read_bytes(), ("100755" if st.st_mode & 0o111 else "100644")
    else:
        raise Invalid("o escopo exige arquivo regular ou link: " + str(path))
    return {"exists": True, "sha256": digest(data), "mode": mode, "data": base64.b64encode(data).decode()}

def signature(fp):
    return {k: v for k, v in fp.items() if k != "data"}

def validate_task(task):
    task = Path(task).resolve()
    if not task.is_dir():
        raise Invalid("a pasta não existe: " + str(task))
    if (task / "tarefas").is_dir():
        raise Invalid(str(task) + " é pasta de trabalho; informe tarefas/<tarefa>")
    if task.name == "tarefas" and any((p / "progresso.md").is_file() or (p / "registro.md").is_file()
                                      for p in task.iterdir() if p.is_dir()):
        raise Invalid(str(task) + " é a pasta tarefas/; informe uma tarefa dentro dela")
    return task

def empty(task):
    return {"schema": 1, "task_id": str(uuid.uuid4()), "task_path": str(task), "created_at": now(), "created_at_epoch": time.time(),
            "updated_at": now(), "repository": None, "baseline": None, "claims": {},
            "stages": {str(n): {"name": name, "status": "pendente", "artifacts": {}, "dependencies": {}}
                       for n, name in enumerate(NAMES)}, "attempts": {}}

def artifact_path(task, name, extra_roots=()):
    candidate = Path(name) if Path(name).is_absolute() else task / name
    roots = [task.resolve()]
    own_repo = repo_at(task)
    if own_repo:
        # Tarefa legada não tem repository gravado; o perfil da pasta de trabalho continua alcançável.
        roots.append(own_repo)
    state_path = task / "estado.json"
    if state_path.is_file():
        state = json.loads(state_path.read_text())
        if state.get("repository"):
            roots.append(Path(state["repository"]).resolve())
        roots.extend(Path(r).resolve() for r in state.get("artifact_roots", []))
    roots.extend(Path(r).resolve() for r in extra_roots)
    lexical = Path(os.path.abspath(candidate))
    resolved = lexical.parent.resolve() / lexical.name
    if not any(resolved == r or r in resolved.parents for r in roots):
        raise Invalid("artefato fora do escopo: " + name)
    for parent in lexical.parents:
        if parent.is_symlink():
            raise Invalid("pai simbólico de artefato recusado: " + name)
        if parent in roots:
            break
    return resolved

def readstate(task, create=False):
    path = task / "estado.json"
    if path.exists():
        try:
            state = json.loads(path.read_text())
            if state.get("schema") != 1 or not state.get("task_id") or set(state["stages"]) != set(map(str, range(10))):
                raise ValueError("schema/etapas")
            for stage in state["stages"].values():
                if stage["status"].split(":", 1)[0] not in STATUSES:
                    raise ValueError("status")
                for field in ("artifacts", "dependencies"):
                    for name, value in stage.get(field, {}).items():
                        if not isinstance(name, str) or not re.fullmatch(r"[0-9a-f]{12,64}", value["sha256"]):
                            raise ValueError("hash de artefato")
            if not isinstance(state.get("attempts"), dict) or not isinstance(state.get("claims"), dict):
                raise ValueError("tentativas/escopos")
            return state
        except (ValueError, KeyError, TypeError) as e:
            raise Invalid("estado.json inválido: " + str(e)) from e
    state = empty(task)
    legacy = task / "progresso.md"
    if not legacy.exists():
        if create:
            return state
        raise Invalid(str(legacy) + " não existe: a tarefa é de antes do progresso.md; retome pelo registro.md")
    rows = {}
    for line in legacy.read_text().splitlines():
        if not re.match(r"^\| [0-9] ", line):
            continue
        cells = [x.strip() for x in line.split("|")]
        try:
            num = cells[1].split()[0]
            if num in rows or num not in state["stages"] or len(cells) != 6:
                raise ValueError("linha duplicada/inválida")
            status = cells[2]
            if status.split(":", 1)[0] not in STATUSES:
                raise ValueError("status")
            artifacts = {}
            for item in filter(None, (x.strip() for x in cells[4].split(","))):
                name, sep, hashval = item.rpartition("@")
                if not sep or not re.fullmatch(r"[0-9a-f]{12,64}", hashval):
                    raise ValueError("hash inválido")
                artifacts[name] = {"sha256": hashval, "legacy": True}
            rows[num] = {"name": NAMES[int(num)], "status": status, "when": cells[3],
                         "artifacts": artifacts, "dependencies": {}}
        except (ValueError, IndexError) as e:
            raise Invalid("progresso.md legado inválido; preserve o arquivo e corrija a linha: " + line) from e
    if set(rows) != set(state["stages"]):
        raise Invalid("progresso.md legado incompleto: esperadas dez etapas únicas; nenhuma conclusão inferida")
    state["stages"] = rows
    state["migrated_from"] = "progresso.md"
    repo = repo_at(task)
    state["repository"] = str(repo) if repo else None
    return state

def markdown(state):
    out = ["# Progresso — " + Path(state["task_path"]).name, "",
           "Derivado de estado.json; use scripts/progresso.sh para alterar.", "",
           "| Etapa | Status | Quando | Artefatos |", "|---|---|---|---|"]
    for n in range(10):
        s = state["stages"][str(n)]
        arts = ", ".join(k + "@" + v["sha256"][:12] for k, v in s["artifacts"].items())
        out.append("| %d %s | %s | %s | %s |" % (n, s["name"], s["status"], s.get("when", ""), arts))
    return "\n".join(out) + "\n"

def save(task, state):
    state["updated_at"] = now()
    legacy = task / "progresso.md"
    backup = task / "progresso.legado.md"
    if state.get("migrated_from") and not (task / "estado.json").exists() and legacy.is_file() and not backup.exists():
        # A primeira gravação de tarefa migrada guarda o arquivo original inteiro.
        atomic(backup, legacy.read_bytes())
    # JSON é a única autoridade. Falha no derivado não pode desfazer o estado confirmado.
    jsonwrite(task / "estado.json", state)
    atomic(task / "progresso.md", markdown(state))

def init(task, repo=None):
    task = validate_task(task)
    with lock(task / ".estado.lock"):
        state = readstate(task, create=True)
        if state["baseline"] is not None:
            return state
        repo = repo_at(repo or Path.cwd())
        if repo:
            names = set(filter(None, git(repo, "ls-files", "-z", "--cached", "--others", "--exclude-standard").stdout.split(b"\0")))
            head = git(repo, "rev-parse", "--verify", "HEAD", allowed=(0, 128))
            gitlinks = set()
            for entry in git(repo, "ls-files", "-s", "-z").stdout.split(b"\0"):
                meta, _, name = entry.partition(b"\t")
                if meta.startswith(b"160000 "):
                    gitlinks.add(os.fsdecode(name))
            if head.returncode == 0:
                names.update(filter(None, git(repo, "ls-tree", "-rz", "--name-only", "HEAD").stdout.split(b"\0")))
            files = {}
            for name in sorted(names):
                rel = os.fsdecode(name)
                # Metadados da tarefa não fazem parte da base do produto.
                p = repo / rel
                if p == task or task in p.parents:
                    continue
                if rel in gitlinks:
                    # Submódulo: registrado pelo commit, nunca entra em escopo de arquivo.
                    files[rel] = {"exists": True, "mode": "160000", "sha256": None, "gitlink": True}
                    continue
                files[rel] = fingerprint(p)
            state["repository"] = str(repo)
            state["baseline"] = {"captured_at": now(), "head": head.stdout.decode().strip() or None, "files": files}
        save(task, state)
        return state

def relative(repo, name):
    p = Path(name)
    p = p if p.is_absolute() else Path.cwd() / p
    # Não resolve o último link: o objeto versionado é o próprio link.
    p = p.parent.resolve() / p.name
    try:
        return p.relative_to(repo).as_posix()
    except ValueError:
        raise Invalid("arquivo fora do repositório: " + str(p))

def registry_path(repo):
    raw = git(repo, "rev-parse", "--git-common-dir").stdout.decode().strip()
    common = Path(raw)
    if not common.is_absolute():
        common = repo / common
    return common.resolve() / "seiva-escopos.json"

def base(task, names, exclusive=False):
    task = validate_task(task)
    if not exclusive:
        raise Invalid("a base não prova autoria: confirme --exclusive antes de editar ou use worktree isolada")
    with lock(task / ".estado.lock"):
        state = readstate(task)
        if not state["baseline"] or not state["repository"]:
            raise Invalid("tarefa sem base verificável: inicialize antes da primeira edição; não infira a base por HEAD")
        repo = Path(state["repository"])
        rels = sorted(set(relative(repo, n) for n in names))
        regpath = registry_path(repo)
        with lock(str(regpath) + ".lock"):
            registry = json.loads(regpath.read_text()) if regpath.exists() else {}
            for rel in rels:
                key = str(repo / rel)
                other = registry.get(key)
                if other and other["task_id"] != state["task_id"]:
                    raise Invalid("escopo já adquirido por outra tarefa: " + rel)
                expected = state["baseline"]["files"].get(rel, {"exists": False})
                if rel not in state["claims"] and signature(fingerprint(repo / rel)) != signature(expected):
                    raise Invalid("arquivo mudou antes da aquisição do escopo: " + rel)
            for rel in rels:
                registry[str(repo / rel)] = {"task_id": state["task_id"], "task_path": str(task)}
                state["claims"][rel] = {"policy": "exclusive", "acquired_at": now()}
            # Registry primeiro: queda pode deixar reserva, mas nunca deixa escrita sem exclusividade.
            jsonwrite(regpath, registry)
            save(task, state)
        print("BASE " + str(task) + " · " + str(len(rels)) + " arquivo(s) com escopo exclusivo")

def release(task):
    task = validate_task(task)
    with lock(task / ".estado.lock"):
        state = readstate(task)
        if not state["repository"]:
            return
        path = registry_path(Path(state["repository"]))
        with lock(str(path) + ".lock"):
            reg = json.loads(path.read_text()) if path.exists() else {}
            reg = {k: v for k, v in reg.items() if v["task_id"] != state["task_id"]}
            jsonwrite(path, reg)
            state["claims"] = {}
            save(task, state)

def diff(task, names):
    task = validate_task(task)
    with lock(task / ".estado.lock"):
        state = readstate(task)
        if not state["baseline"] or not state["repository"]:
            raise Invalid("tarefa sem base verificável: diff recusado; capture a base e adquira escopo antes de editar")
        repo = Path(state["repository"])
        rels = sorted(set(relative(repo, name) for name in names))
        regpath = registry_path(repo)
        with lock(str(regpath) + ".lock"):
            reg = json.loads(regpath.read_text()) if regpath.exists() else {}
            chunks, summary = [], []
            for rel in rels:
                if rel not in state["claims"] or reg.get(str(repo / rel), {}).get("task_id") != state["task_id"]:
                    raise Invalid("escopo exclusivo não adquirido: " + rel)
                old = state["baseline"]["files"].get(rel, {"exists": False})
                if old["exists"]:
                    data = base64.b64decode(old["data"], validate=True)
                    if digest(data) != old["sha256"] or old["mode"] not in {"100644", "100755", "120000"}:
                        raise Invalid("base corrompida: " + rel)
                current = fingerprint(repo / rel)
                if not old["exists"] and not current["exists"]:
                    raise Invalid("arquivo solicitado ausente na base e na entrega: " + rel)
                if signature(old) == signature(current):
                    summary.append(("sem-mudanca", rel))
                    continue
                # git diff --no-index produz patch binário aplicável sem alterar índice/árvore.
                with tempfile.TemporaryDirectory(prefix="seiva-diff-") as temp:
                    root = Path(temp)
                    for side, fp in (("a", old), ("b", current)):
                        p = root / side / rel
                        p.parent.mkdir(parents=True, exist_ok=True)
                        if fp["exists"]:
                            data = base64.b64decode(fp["data"])
                            if fp["mode"] == "120000":
                                os.symlink(os.fsdecode(data), p)
                            else:
                                p.write_bytes(data)
                                p.chmod(0o755 if fp["mode"] == "100755" else 0o644)
                    a = "a/" + rel if old["exists"] else "/dev/null"
                    b = "b/" + rel if current["exists"] else "/dev/null"
                    proc = subprocess.run(["git", "-c", "core.quotePath=false", "diff", "--no-index", "--binary",
                                           "--no-ext-diff", "--src-prefix=", "--dst-prefix=", "--", a, b],
                                          cwd=root, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
                    if proc.returncode not in (0, 1):
                        raise Invalid("erro ao montar diff de " + rel + ": " + proc.stderr.decode(errors="replace"))
                    patch = proc.stdout
                    # Em adição/deleção git usa o mesmo nome em ambos os lados do cabeçalho.
                    patch = patch.replace(("diff --git b/" + rel + " b/" + rel).encode(),
                                          ("diff --git a/" + rel + " b/" + rel).encode(), 1)
                    patch = patch.replace(("diff --git a/" + rel + " a/" + rel).encode(),
                                          ("diff --git a/" + rel + " b/" + rel).encode(), 1)
                    chunks.append(patch)
                summary.append(("apagado" if not current["exists"] else "alterado" if old["exists"] else "novo", rel))
            # Qualquer erro preserva o diff anterior.
            atomic(task / "diff.patch", b"".join(chunks))
        for status, rel in summary:
            print("%-10s %s" % (status, rel))
        print("linhas no diff: %s  ->  %s" % ((task / "diff.patch").read_bytes().count(b"\n"), task / "diff.patch"))

def artifact(task, name, extra_roots=()):
    if any(c in name for c in "|,\n\r\t "):
        raise Invalid("artefato com |, vírgula ou espaço no nome: " + name)
    path = artifact_path(task, name, extra_roots)
    if not path.is_file() or path.is_symlink():
        raise Invalid("artefato não existe ou é link: " + str(path))
    return {"sha256": digest(path.read_bytes())}

def mark(task, number, status, names, deps=(), attempt=None, evidence="", allow_roots=(), retroactive=False):
    task = validate_task(task)
    if number not in map(str, range(10)) or status.split(":", 1)[0] not in STATUSES or "\n" in status:
        raise Invalid("uso: progresso.sh <pasta-da-tarefa> marcar <0-9> <pendente|em-curso|feita|pulada> [artefato...]")
    status = status.replace("|", "/")
    if status.split(":", 1)[0] == "pulada" and not status.partition(":")[2].strip():
        raise Invalid("etapa pulada exige motivo: marcar N 'pulada: motivo'")
    if status.split(":", 1)[0] == "interrompida" and not status.partition(":")[2].strip():
        raise Invalid("etapa interrompida exige motivo: marcar N 'interrompida: limite de 5h às 16:39'")
    done = status.split(":", 1)[0] == "feita"
    arts = {name: artifact(task, name, allow_roots) for name in names} if done else {}
    if done and (not arts or (not attempt and not evidence.strip())):
        raise Invalid("etapa feita exige artefatos e --attempt concluído ou --evidence para etapa mecânica")
    if retroactive and (not done or attempt or not evidence.strip()):
        raise Invalid("--retroativa vale só para etapa feita, com --evidence dizendo onde a etapa foi feita, e sem --attempt")
    with lock(task / ".estado.lock"):
        state = readstate(task, create=True)
        state["artifact_roots"] = sorted(set(state.get("artifact_roots", []) + [str(Path(r).resolve()) for r in allow_roots]))
        proof = None
        if done and attempt:
            if not attempt_valid(task, state, attempt):
                raise Invalid("tentativa vinculada não tem conclusão válida")
            terminal = state["attempts"][attempt]["terminal"]
            if any(terminal["artifacts"].get(name, {}).get("sha256") != value["sha256"] for name, value in arts.items()):
                raise Invalid("artefatos da etapa não conferem com o terminal da tentativa")
            proof = {"kind": "attempt", "attempt_id": attempt}
        elif done:
            proof = {"kind": "retroativa" if retroactive else "mechanical", "evidence": evidence.strip()}
            if retroactive:
                proof["recorded_at"] = now()
        state["stages"][number].update(status=status, when=now(), artifacts=arts, proof=proof,
                                      dependencies={name: artifact(task, name, allow_roots) for name in deps})
        save(task, state)
        suffix = ", ".join(k + "@" + v["sha256"][:12] for k, v in arts.items())
        print("etapa " + number + ": " + status + (" · " + suffix if suffix else ""))

def changed(task, name, value):
    try:
        path = artifact_path(task, name)
    except Invalid:
        return "FORA-DO-ESCOPO"
    if not path.is_file() or path.is_symlink():
        return "SUMIU"
    return None if digest(path.read_bytes()).startswith(value["sha256"]) else "MUDOU"

def skip_reason(stage):
    return stage["status"].partition(":")[2].strip()

def legacy_unproven(stage):
    """Etapa vinda do progresso.md antigo, sem prova: pede revalidação, mas não é o ponto de retomada."""
    kind = stage["status"].split(":", 1)[0]
    if kind == "pulada":
        return not skip_reason(stage) and not stage.get("proof")
    return (kind == "feita" and not stage.get("proof") and bool(stage["artifacts"])
            and all(v.get("legacy") for v in stage["artifacts"].values()))

def resume_point(task, state):
    """Primeira etapa inválida, ignorando o legado sem prova (listado à parte)."""
    for n in range(10):
        s = state["stages"][str(n)]
        if not stage_valid(task, state, s) and not legacy_unproven(s):
            return str(n) + " " + s["name"] + " · " + s["status"]
    return None

def stage_valid(task, state, stage):
    if stage["status"].split(":", 1)[0] == "pulada":
        return bool(skip_reason(stage))
    if stage["status"].split(":", 1)[0] != "feita" or not stage["artifacts"]:
        return False
    proof = stage.get("proof") or {}
    if proof.get("kind") in ("mechanical", "retroativa"):
        proven = bool(proof.get("evidence", "").strip())
    elif proof.get("kind") == "attempt":
        aid = proof.get("attempt_id")
        proven = attempt_valid(task, state, aid)
        if proven:
            terminal = state["attempts"][aid]["terminal"]
            proven = all(terminal["artifacts"].get(name, {}).get("sha256") == value["sha256"]
                         for name, value in stage["artifacts"].items())
    else:
        proven = False
    return (proven and all(not changed(task, name, value) for name, value in stage["artifacts"].items())
            and all(not changed(task, name, value) for name, value in stage.get("dependencies", {}).items()))

def minutes_since(stamp):
    if not stamp:
        return None
    try:
        return (dt.datetime.now().astimezone() - dt.datetime.fromisoformat(stamp)).total_seconds() / 60
    except ValueError:
        return None

def check(task):
    task = validate_task(task)
    with lock(task / ".estado.lock"):
        state = readstate(task)
        # Conferir não altera a data de progresso. Tarefa legada é só lida: nada é gravado aqui.
        if not (task / "estado.json").exists():
            print("LEGADO · progresso.md antigo lido sem alteração; a 1ª marcação cria estado.json e guarda progresso.legado.md")
        elif not (task / "progresso.md").exists() or (task / "progresso.md").read_text() != markdown(state):
            atomic(task / "progresso.md", markdown(state))
        failures, nextstage = 0, None
        if (task / "estado.json").exists():
            stale = tuned(task, "stale_minutes")
            swept = sweep_state(task, state, stale)  # a varredura é automática; só grava se achar algo
            if swept:
                save(task, state)
                print("VARREDURA automática: " + ", ".join(swept) + " sem sinal há mais de %d min → interrompida" % stale)
        for aid, attempt in state["attempts"].items():
            if attempt.get("status") == "running" and attempt.get("terminal") is None:
                print("TENTATIVA " + aid + " running · " + attempt["agent"] +
                      " · consulte a ferramenta de execução antes de redisparar; registro não prova processo vivo")
            elif attempt.get("status") == "interrompida" and attempt.get("terminal") is None:
                failures += 0 if attempt.get("resolved_by") else 1
                spent = (attempt.get("interruption") or {}).get("tokens_spent")
                print("TENTATIVA " + aid + " interrompida · " + attempt["agent"] + " · tokens já gastos: " +
                      ("desconhecidos" if spent is None else str(spent)) +
                      (" · retomada por " + attempt["resolved_by"] if attempt.get("resolved_by") else
                       " · decida: aproveitar relatório válido (attempt-complete) ou redisparar com --retoma " + aid))
            if attempt.get("terminal") is None and attempt.get("status") in {"running", "interrompida"} and not attempt.get("model_category"):
                print("  ! " + aid + " sem categoria/modelo registrado: independência e custo não comprováveis")
        if state["attempts"] and state["stages"]["0"]["status"].split(":", 1)[0] == "pendente":
            print("AVISO há tentativas, mas a etapa 0 está pendente: se as etapas iniciais foram feitas fora do estado, "
                  "marque com --retroativa e --evidence (migração de tarefa legada)")
        for n in range(10):
            s = state["stages"][str(n)]
            status = s["status"].split(":", 1)[0]
            stale = [name for name, value in s.get("dependencies", {}).items() if changed(task, name, value)]
            valid = stage_valid(task, state, s)
            legacy = legacy_unproven(s)
            if nextstage is None and not valid and not legacy:
                nextstage = str(n) + " " + s["name"]
            if status == "pendente":
                continue
            notes = ""
            if status == "feita" and not valid:
                failures += 1
                notes += (" · LEGADO SEM PROVA (revalide antes de fechar; não refaça a etapa)" if legacy
                          else " · NAO-COMPROVADA (revalide evidência ou tentativa vinculada)")
            if status == "pulada" and not valid:
                failures += 1
                notes += " · PULADA SEM MOTIVO (registre o motivo)"
            if stale:
                failures += 1
                notes += " · DEPENDENCIA MUDOU: " + ", ".join(stale)
            if status == "feita" and (s.get("proof") or {}).get("kind") == "retroativa":
                notes += " · RETROATIVA (marcada depois; prova é a evidência registrada, não uma tentativa)"
            if status == "interrompida":
                notes += " · INTERROMPIDA (retome esta etapa; confira tentativas antes de redisparar)"
            if status == "feita":
                for name, value in s["artifacts"].items():
                    result = changed(task, name, value)
                    if result:
                        failures += 1
                        notes += " · " + name + " " + result
                        if result == "MUDOU":
                            notes += " depois de feita (olhe o artefato; não refaça a etapa)"
                    else:
                        notes += " · " + name + " confere"
            print(str(n) + " " + s["name"] + " · " + s["status"] + notes)
        ctx = task / "contexto-tarefa.md"
        if ctx.is_file():
            tokens = ctx.stat().st_size * 10 // 35
            print("contexto-tarefa.md ≈ %s tokens (estimativa por bytes; alvo até 1.500)%s" %
                  (tokens, " · ACIMA do alvo: enxugue antes de parar" if tokens > 1500 else ""))
        else:
            print("contexto-tarefa.md não existe: escreva antes de parar")
        print("PROXIMA " + (nextstage or "nenhuma"))
        return int(bool(failures))

def pending(work):
    work = Path(work).resolve()
    found = []
    for task in (work / "tarefas").iterdir() if (work / "tarefas").is_dir() else []:
        if not task.is_dir():
            continue
        if not (task / "progresso.md").exists() and not (task / "estado.json").exists():
            if (task / "registro.md").exists():
                found.append((task.stat().st_mtime, task, "legada · retome pelo registro.md"))
            continue
        try:
            state = readstate(task)
        except Invalid as e:
            found.append((task.stat().st_mtime, task, "INVALIDA · " + str(e)))
            continue
        if stage_valid(task, state, state["stages"]["9"]):
            continue
        stage = resume_point(task, state) or "sem etapa pendente"
        unproven = [str(n) for n in range(10) if legacy_unproven(state["stages"][str(n)])]
        if unproven:
            stage += " · legado sem prova: " + ",".join(unproven)
        stamp = (task / ("estado.json" if (task / "estado.json").exists() else "progresso.md")).stat().st_mtime
        found.append((stamp, task, stage))
    for stamp, task, stage in sorted(found, key=lambda x: (-x[0], str(x[1])))[:5]:
        print(str(task) + " · " + stage + " · mexida em " + dt.datetime.fromtimestamp(stamp).strftime("%Y-%m-%d %H:%M"))
    if not found:
        print("nenhuma tarefa por terminar em " + str(work / "tarefas"))

def attempt_start(task, attempt_id, agent, package, report, model=None, category=None, context_tokens=None,
                  above_limit="", resume=None, max_parallel=MAX_PARALLEL):
    task = validate_task(task)
    if not re.fullmatch(r"[A-Za-z0-9._-]+", attempt_id):
        raise Invalid("identificador de tentativa inválido")
    if category is not None and category not in CATEGORIES:
        raise Invalid("categoria inválida; use: " + ", ".join(sorted(CATEGORIES)))
    with lock(task / ".estado.lock"):
        state = readstate(task, create=True)
        if attempt_id in state["attempts"]:
            raise Invalid("tentativa já registrada; use novo identificador")
        package_hash = artifact(task, package)
        report_path = artifact_path(task, report)
        package_tokens = artifact_path(task, package).stat().st_size * 10 // 35
        total = package_tokens + (context_tokens or 0)
        limit = tuned(task, "context_limit")
        if total > limit and not above_limit.strip():
            raise Invalid("pacote + contexto herdado ≈ %d tokens, acima de %d: divida a tarefa ou grave o contexto curto e "
                          "abra outra sessão; para seguir mesmo assim, --acima-do-limite 'motivo'" % (total, limit))
        running = 0
        for existing in state["attempts"].values():
            if existing.get("terminal") is not None:
                continue
            same_job = existing.get("agent") == agent and existing.get("package_hash") == package_hash["sha256"]
            same_report = artifact_path(task, existing["report"]) == report_path
            if existing.get("status") == "running":
                running += 1
                if same_job or same_report:
                    raise Invalid("tentativa running sobreposta: " + existing["attempt_id"] +
                                  "; consulte a ferramenta de execução e registre cancelled/failed antes de redisparar")
            elif existing.get("status") == "interrompida" and (same_job or same_report) and not existing.get("resolved_by"):
                if resume != existing["attempt_id"]:
                    raise Invalid("tentativa interrompida do mesmo trabalho: " + existing["attempt_id"] +
                                  "; aproveite o relatório válido (attempt-complete) ou decida redisparar com --retoma " +
                                  existing["attempt_id"])
        if running >= max_parallel:
            raise Invalid("já há %d tentativas running (limite %d); espere terminar ou aumente --max-paralelo com motivo" %
                          (running, max_parallel))
        if resume:
            old = state["attempts"].get(resume)
            if not old or old.get("status") != "interrompida" or old.get("terminal") is not None:
                raise Invalid("--retoma exige uma tentativa interrompida e sem conclusão: " + str(resume))
            old["resolved_by"] = attempt_id
        state["attempts"][attempt_id] = {"task_id": state["task_id"], "attempt_id": attempt_id, "agent": agent,
            "package": package, "package_hash": package_hash["sha256"], "report": report,
            "status": "running", "started_at": now(), "last_seen_at": now(), "terminal": None,
            "model": model, "model_category": category,
            "package_tokens_est": package_tokens, "inherited_context_tokens": context_tokens,
            "above_limit_reason": above_limit.strip() or None, "resumes": resume,
            "report_before": signature(fingerprint(artifact_path(task, report)))}
        save(task, state)
        print("ATTEMPT " + attempt_id + " running · pacote ≈ %d tokens · contexto herdado: %s" %
              (package_tokens, "não informado" if context_tokens is None else context_tokens))
        if category is None or model is None:
            print("AVISO categoria/modelo não registrados: o relatório não poderá afirmar independência nem custo por papel")

def attempt_ping(task, attempt_id):
    task = validate_task(task)
    with lock(task / ".estado.lock"):
        state = readstate(task)
        a = state["attempts"].get(attempt_id)
        if not a or a["terminal"] is not None or a.get("status") != "running":
            raise Invalid("tentativa ausente, terminal ou não running")
        a["last_seen_at"] = now()
        save(task, state)
        print("ATTEMPT " + attempt_id + " sinal " + a["last_seen_at"])

def attempt_interrupt(task, attempt_id, reason, tokens=None):
    task = validate_task(task)
    if not reason.strip():
        raise Invalid("interrupção exige motivo (limite de uso, sessão fechada, falha)")
    with lock(task / ".estado.lock"):
        state = readstate(task)
        a = state["attempts"].get(attempt_id)
        if not a or a["terminal"] is not None or a.get("status") != "running":
            raise Invalid("tentativa ausente, terminal ou não running")
        interrupt(a, reason, tokens)
        save(task, state)
        print("ATTEMPT " + attempt_id + " interrompida")

def interrupt(attempt, reason, tokens=None):
    attempt["status"] = "interrompida"
    attempt["interruption"] = {"at": now(), "last_seen_at": attempt.get("last_seen_at"),
                               "reason": reason.strip(), "tokens_spent": tokens}

def signal_age(task, a):
    """Minutos desde o último sinal: o maior entre o ping e a última gravação do relatório."""
    stamps = []
    for value in (a.get("last_seen_at"), a.get("started_at")):
        if value:
            try:
                stamps.append(dt.datetime.fromisoformat(value).timestamp())
            except ValueError:
                pass
    try:
        stamps.append(artifact_path(task, a["report"]).stat().st_mtime)
    except (OSError, Invalid):
        pass
    return (time.time() - max(stamps)) / 60 if stamps else None

def sweep_state(task, state, stale_minutes):
    found = []
    for aid, a in state["attempts"].items():
        if a.get("status") != "running" or a["terminal"] is not None:
            continue
        age = signal_age(task, a)
        if age is not None and age > stale_minutes:
            interrupt(a, "sem sinal há %d min" % age)
            found.append(aid)
    return found

def attempt_sweep(task, stale_minutes=None):
    """running sem sinal recente vira interrompida. Não redispara nada."""
    task = validate_task(task)
    stale_minutes = tuned(task, "stale_minutes") if stale_minutes is None else stale_minutes
    with lock(task / ".estado.lock"):
        state = readstate(task)
        found = sweep_state(task, state, stale_minutes)
        if found:
            save(task, state)
        print("INTERROMPIDAS " + (", ".join(found) if found else "nenhuma"))
        for aid in found:
            print("  " + aid + ": tokens já gastos desconhecidos; informe com attempt-interrupt --tokens se a ferramenta mostrar")

def attempt_watch(task, interval=60, duration=3600, stale_minutes=None):
    """Vigia limitado à tarefa: varre a cada intervalo e para quando não há running ou ao fim da duração.
    Não é daemon: quem o inicia (em segundo plano, pela ferramenta do harness) é a execução da leva."""
    task = validate_task(task)
    stale_minutes = tuned(task, "stale_minutes") if stale_minutes is None else stale_minutes
    end = time.time() + duration
    print("VIGIA %s · a cada %ds · até %ds" % (task.name, interval, duration), flush=True)
    while True:
        with lock(task / ".estado.lock"):
            state = readstate(task)
            found = sweep_state(task, state, stale_minutes)
            if found:
                save(task, state)
            running = [aid for aid, a in state["attempts"].items() if a.get("status") == "running" and a["terminal"] is None]
        for aid in found:
            print("INTERROMPIDA " + aid + " · sem sinal: decida aproveitar relatório válido ou --retoma " + aid, flush=True)
        if not running:
            print("VIGIA fim · nenhuma tentativa running", flush=True)
            return 0
        if time.time() >= end:
            print("VIGIA fim · duração esgotada com running: " + ", ".join(running) + " (sem vigia; rode attempt-sweep na retomada)", flush=True)
            return 0
        time.sleep(min(interval, max(1, end - time.time())))

def attempt_complete(task, attempt_id, status, names, evidence, real_model=None, tokens=None):
    task = validate_task(task)
    if status not in {"concluido", "parcial", "bloqueado", "failed", "cancelled"}:
        raise Invalid("status terminal inválido")
    if not evidence.strip():
        raise Invalid("conclusão exige evidência")
    with lock(task / ".estado.lock"):
        state = readstate(task)
        a = state["attempts"].get(attempt_id)
        if not a or a["task_id"] != state["task_id"] or a["terminal"] is not None:
            raise Invalid("tentativa ausente ou já terminal")
        if changed(task, a["package"], {"sha256": a["package_hash"]}):
            raise Invalid("pacote mudou durante a tentativa")
        if status == "concluido" and a["report"] not in names:
            raise Invalid("conclusão exige relatório explícito entre os artefatos")
        if status == "concluido":
            validate_report(task, state, a)
        arts = {name: artifact(task, name) for name in names}
        if status == "concluido" and signature(fingerprint(artifact_path(task, a["report"]))) == a.get("report_before"):
            raise Invalid("relatório preexistente não comprova esta tentativa; produza um relatório desta execução")
        after_interruption = a.get("status") == "interrompida"
        if after_interruption and status == "concluido":
            # Relatório completo de agente cortado depois de gravar o marcador final vale; o fato fica registrado.
            a["completed_after_interruption"] = True
        a["status"] = status
        if real_model:
            a["model_real"] = real_model
        if tokens is not None:
            a["tokens_spent"] = tokens
        a["terminal"] = {"task_id": state["task_id"], "attempt_id": attempt_id, "status": status,
                         "artifacts": arts, "evidence": evidence, "completed_at": now()}
        save(task, state)
        print("ATTEMPT " + attempt_id + " " + status)
        if status in {"failed", "bloqueado"}:
            from aprendizado import runtime_failure
            runtime_failure(task, state)

def validate_report(task, state, attempt):
    path = artifact_path(task, attempt["report"])
    if path.is_symlink() or not path.is_file():
        raise Invalid("relatório ausente ou simbólico")
    text = path.read_text()
    lines = text.splitlines()
    expected = "<!-- seiva:fim " + state["task_id"] + " " + attempt["attempt_id"] + " -->"
    if not lines or lines[-1] != expected or not "\n".join(lines[:-1]).strip():
        raise Invalid("relatório vazio, truncado ou sem marcador final da tarefa e tentativa")
    if re.search(r"(?im)^STATUS:\s*(parcial|bloqueado|failed|cancelled)\s*$", text):
        raise Invalid("relatório declara status parcial ou bloqueado")

def usage(task, which, values, model=None, source=""):
    task = validate_task(task)
    if which not in {"antes", "depois"}:
        raise Invalid("uso: usage antes|depois")
    if not source.strip():
        raise Invalid("medição exige --fonte (ex.: /usage da sessão, medir.sh)")
    clean = {k: v for k, v in values.items() if v is not None}
    if not clean:
        raise Invalid("informe ao menos um número (--entrada, --saida, --cache-leitura, --cache-escrita)")
    with lock(task / ".estado.lock"):
        state = readstate(task, create=True)
        snaps = state.setdefault("usage", {})
        snaps[which] = {"at": now(), "source": source.strip(), "model": model, **clean}
        if which == "depois" and "antes" in snaps:
            snaps["delta"] = {k: clean[k] - snaps["antes"][k] for k in clean if k in snaps["antes"]}
            before = {k for k in snaps["antes"] if k in {"input", "output", "cache_read", "cache_write"}}
            snaps["delta"]["partial"] = sorted(before ^ set(clean))  # campo medido só de um lado
        save(task, state)
        print("USO " + which + " " + json.dumps(snaps[which], ensure_ascii=False))
        if "delta" in snaps and which == "depois":
            d = {k: v for k, v in snaps["delta"].items() if k != "partial"}
            print("FECHAMENTO " + " · ".join("%s %s" % (k, v) for k, v in sorted(d.items())) +
                  " · compare com a tarefa anterior pela mesma fonte")

def attempt_valid(task, state, attempt_id):
    a = state["attempts"].get(attempt_id)
    if not a or not a.get("terminal"):
        return False
    terminal = a["terminal"]
    try:
        validate_report(task, state, a)
    except (Invalid, OSError, ValueError):
        return False
    return (terminal.get("task_id") == state["task_id"] and terminal.get("attempt_id") == attempt_id
            and terminal.get("status") == "concluido" and bool(terminal.get("evidence"))
            and a["report"] in terminal.get("artifacts", {})
            and not changed(task, a["package"], {"sha256": a["package_hash"]})
            and all(not changed(task, name, value) for name, value in terminal["artifacts"].items()))

def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=["init", "base", "release", "diff", "mark", "check", "pending",
                                           "attempt-start", "attempt-complete", "attempt-check",
                                           "attempt-ping", "attempt-interrupt", "attempt-sweep", "attempt-watch", "usage"])
    parser.add_argument("task")
    parser.add_argument("args", nargs="*")
    parser.add_argument("--exclusive", action="store_true")
    parser.add_argument("--artifact", action="append", default=[])
    parser.add_argument("--depends", action="append", default=[])
    parser.add_argument("--attempt")
    parser.add_argument("--allow-root", action="append", default=[])
    parser.add_argument("--evidence", default="")
    parser.add_argument("--retroativa", action="store_true")
    parser.add_argument("--modelo")
    parser.add_argument("--categoria")
    parser.add_argument("--contexto-tokens", type=int)
    parser.add_argument("--acima-do-limite", default="")
    parser.add_argument("--retoma")
    parser.add_argument("--max-paralelo", type=int, default=MAX_PARALLEL)
    parser.add_argument("--modelo-real")
    parser.add_argument("--tokens", type=int)
    parser.add_argument("--motivo", default="")
    parser.add_argument("--stale-minutos", type=float, default=None)
    parser.add_argument("--fonte", default="")
    parser.add_argument("--intervalo", type=int, default=60)
    parser.add_argument("--duracao", type=int, default=3600)
    parser.add_argument("--entrada", type=int)
    parser.add_argument("--saida", type=int)
    parser.add_argument("--cache-leitura", type=int)
    parser.add_argument("--cache-escrita", type=int)
    ns = parser.parse_intermixed_args(argv)
    try:
        cmd, task, args = ns.command, Path(ns.task), ns.args
        if cmd == "init" and not args: init(task)
        elif cmd == "base" and args: base(task, args, ns.exclusive)
        elif cmd == "release" and not args: release(task)
        elif cmd == "diff" and args: diff(task, args)
        elif cmd == "mark" and len(args) >= 2: mark(task, args[0], args[1], args[2:], ns.depends, ns.attempt, ns.evidence, ns.allow_root, ns.retroativa)
        elif cmd == "check" and not args: return check(task)
        elif cmd == "pending" and not args: pending(task)
        elif cmd == "attempt-start" and len(args) == 4:
            attempt_start(task, *args, model=ns.modelo, category=ns.categoria, context_tokens=ns.contexto_tokens,
                          above_limit=ns.acima_do_limite, resume=ns.retoma, max_parallel=ns.max_paralelo)
        elif cmd == "attempt-complete" and len(args) == 2:
            attempt_complete(task, *args, ns.artifact, ns.evidence, ns.modelo_real, ns.tokens)
        elif cmd == "attempt-ping" and len(args) == 1: attempt_ping(task, args[0])
        elif cmd == "attempt-interrupt" and len(args) == 1: attempt_interrupt(task, args[0], ns.motivo, ns.tokens)
        elif cmd == "attempt-sweep" and not args: attempt_sweep(task, ns.stale_minutos)
        elif cmd == "attempt-watch" and not args: return attempt_watch(task, ns.intervalo, ns.duracao, ns.stale_minutos)
        elif cmd == "usage" and len(args) == 1:
            usage(task, args[0], {"input": ns.entrada, "output": ns.saida, "cache_read": ns.cache_leitura,
                                  "cache_write": ns.cache_escrita}, ns.modelo, ns.fonte)
        elif cmd == "attempt-check" and len(args) == 1:
            task = validate_task(task)
            with lock(task / ".estado.lock"):
                return 0 if attempt_valid(task, readstate(task), args[0]) else 1
        else: raise Invalid("argumentos inválidos para " + cmd)
        return 0
    except (Invalid, OSError, ValueError) as e:
        print("estado-tarefa: " + str(e), file=sys.stderr)
        return 2

if __name__ == "__main__":
    sys.exit(main())
