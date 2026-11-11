#!/usr/bin/env python3
# seiva · JulianoSSR · MIT
"""Ajustes locais automáticos da Seiva instalada (canal A).

Só mexe em `ajustes.json` na pasta de trabalho privada do projeto; nunca nos arquivos da skill.
Lista fechada de parâmetros, um ajuste em teste por vez, evidência de duas tarefas, reversão
automática se as tarefas seguintes piorarem. Não fala com rede e não toca o canal do GitHub
(aprendizado.py): sugestão para o repositório segue o rito próprio, com consentimento.
"""
import argparse
import contextlib
import datetime as dt
import fcntl
import json
import os
from pathlib import Path
import statistics
import sys
import tempfile

# Lista fechada. Mudar esta lista é decisão do mantenedor, nunca do próprio mecanismo.
PARAMS = {
    "stale_minutes": {"padrao": 15, "min": 5, "max": 60, "tipo": int},
    "context_limit": {"padrao": 150000, "min": 50000, "max": 150000, "tipo": int},  # só pode apertar
}
LENSES = {"seguranca", "dados", "design", "desempenho", "operacao", "contrato"}
NOTE_MAX = 200
EVIDENCE_MIN = 2          # tarefas distintas
OBSERVE_TASKS = 2         # tarefas depois do ajuste antes de decidir
BASELINE_TASKS = 2        # tarefas antes do ajuste usadas como comparação
TOKEN_TOLERANCE = 1.2     # tokens 20% acima da linha de base contam como piora

class Invalid(Exception):
    pass

def now():
    return dt.datetime.now().astimezone().isoformat(timespec="seconds")

def empty():
    return {"schema": 1, "valores": {}, "evidencias": [], "tarefas": [], "em_teste": None, "historico": [], "notas": []}

def path_for(work):
    return Path(work) / "ajustes.json"

@contextlib.contextmanager
def lock(work):
    work = Path(work)
    work.mkdir(parents=True, exist_ok=True)
    fd = os.open(work / ".ajustes.lock", os.O_RDWR | os.O_CREAT, 0o600)
    with os.fdopen(fd, "a+b") as f:
        fcntl.flock(f, fcntl.LOCK_EX)
        yield

def load(work):
    p = path_for(work)
    if not p.exists():
        return empty()
    try:
        data = json.loads(p.read_text())
        if data.get("schema") != 1:
            raise ValueError("schema")
        for key, val in data.get("valores", {}).items():
            check_value(key, val)
        return data
    except (ValueError, TypeError) as e:
        raise Invalid("ajustes.json inválido; nenhum ajuste vale até corrigir ou apagar o arquivo: " + str(e)) from e

def save(work, data):
    p = path_for(work)
    fd, tmp = tempfile.mkstemp(prefix="ajustes.", dir=p.parent)
    try:
        with os.fdopen(fd, "w") as f:
            json.dump(data, f, ensure_ascii=False, indent=2)
            f.write("\n")
            f.flush()
            os.fsync(f.fileno())
        os.replace(tmp, p)
    finally:
        if os.path.exists(tmp):
            os.unlink(tmp)

def check_value(param, value):
    spec = PARAMS.get(param)
    if not spec:
        raise Invalid("parâmetro fora da lista fechada: " + str(param) + " (permitidos: " + ", ".join(PARAMS) + ")")
    if isinstance(value, bool) or not isinstance(value, spec["tipo"]) or not spec["min"] <= value <= spec["max"]:
        raise Invalid("%s=%r fora do intervalo %s..%s" % (param, value, spec["min"], spec["max"]))

def effective(work, param):
    """Valor em vigor: ajuste local válido ou o padrão. Arquivo inválido nunca derruba a tarefa: cai no padrão."""
    try:
        return load(work)["valores"].get(param, PARAMS[param]["padrao"])
    except Invalid:
        return PARAMS[param]["padrao"]

def work_of_task(task):
    """Pasta de trabalho da tarefa (a que contém tarefas/), ou None."""
    task = Path(task).resolve()
    if task.parent.name == "tarefas":
        return task.parent.parent
    return None

def effective_for_task(task, param):
    work = work_of_task(task)
    return effective(work, param) if work else PARAMS[param]["padrao"]

# --- registro de tarefa e evidência ---------------------------------------------------------

def register_task(work, task_id, quedas, rodadas, tokens):
    """Linha de medição da tarefa fechada. Usada para comparar antes e depois de um ajuste."""
    with lock(work):
        data = load(work)
        if any(t["id"] == task_id for t in data["tarefas"]):
            raise Invalid("tarefa já registrada: " + task_id)
        data["tarefas"].append({"id": task_id, "em": now(), "quedas": quedas, "rodadas": rodadas, "tokens": tokens,
                                "ajuste_em_vigor": (data["em_teste"] or {}).get("param")})
        message = evaluate(data)
        save(work, data)
    return message

def add_evidence(work, task_id, param, value, reason):
    if param == "nota":
        raise Invalid("nota tem comando próprio: nota")
    check_value(param, value)
    if not reason.strip():
        raise Invalid("evidência exige motivo medido (o que aconteceu na tarefa)")
    with lock(work):
        data = load(work)
        if any(e["task"] == task_id and e["param"] == param for e in data["evidencias"]):
            raise Invalid("esta tarefa já deu evidência para " + param)
        data["evidencias"].append({"task": task_id, "param": param, "valor": value, "motivo": reason.strip()[:300], "em": now()})
        message = maybe_apply(data, param)
        save(work, data)
    return message

def maybe_apply(data, param):
    evid = [e for e in data["evidencias"] if e["param"] == param and e.get("aplicada") is None]
    tasks = {e["task"] for e in evid}
    if len(tasks) < EVIDENCE_MIN:
        return "EVIDÊNCIA %s: %d de %d tarefas; nada aplicado" % (param, len(tasks), EVIDENCE_MIN)
    if data["em_teste"]:
        return "EVIDÊNCIA %s: pronta, mas há um ajuste em teste (%s); um por vez, espera a decisão" % (param, data["em_teste"]["param"])
    last = evid[-EVIDENCE_MIN:]
    # Valor mais conservador entre as evidências: para os dois parâmetros, o mais próximo do padrão.
    default = PARAMS[param]["padrao"]
    chosen = min((e["valor"] for e in last), key=lambda v: abs(v - default))
    before = data["valores"].get(param, default)
    if chosen == before:
        for e in last:
            e["aplicada"] = "sem-efeito"
        return "EVIDÊNCIA %s: valor já em vigor (%s); nada a aplicar" % (param, before)
    baseline = data["tarefas"][-BASELINE_TASKS:]
    if len(baseline) < BASELINE_TASKS:
        return "EVIDÊNCIA %s: pronta, mas faltam tarefas registradas para comparar depois (%d de %d); nada aplicado" % (
            param, len(baseline), BASELINE_TASKS)
    data["valores"][param] = chosen
    for e in last:
        e["aplicada"] = now()
    data["em_teste"] = {"param": param, "antes": before, "depois": chosen, "desde": now(),
                        "linha_de_base": [t["id"] for t in baseline], "observadas": []}
    data["historico"].append({"em": now(), "acao": "aplicado", "param": param, "antes": before, "depois": chosen,
                              "tarefas": sorted({e["task"] for e in last})})
    return "AJUSTE APLICADO %s: %s -> %s (em teste por %d tarefas; reverte sozinho se piorar)" % (param, before, chosen, OBSERVE_TASKS)

def metrics(tasks):
    def avg(key):
        vals = [t[key] for t in tasks if t.get(key) is not None]
        return statistics.mean(vals) if vals else None
    return {"quedas": avg("quedas"), "rodadas": avg("rodadas"), "tokens": avg("tokens")}

def evaluate(data):
    test = data["em_teste"]
    if not test:
        return "tarefa registrada"
    ids = [t["id"] for t in data["tarefas"]]
    after = [t for t in data["tarefas"] if t["id"] not in test["linha_de_base"]
             and t["em"] >= test["desde"]]
    if len(after) < OBSERVE_TASKS:
        return "tarefa registrada · ajuste %s em teste: %d de %d tarefas observadas" % (test["param"], len(after), OBSERVE_TASKS)
    after = after[:OBSERVE_TASKS]
    base = metrics([t for t in data["tarefas"] if t["id"] in test["linha_de_base"]])
    new = metrics(after)
    worse = []
    for key in ("quedas", "rodadas"):
        if base[key] is not None and new[key] is not None and new[key] > base[key]:
            worse.append("%s %.1f -> %.1f" % (key, base[key], new[key]))
    if base["tokens"] and new["tokens"] and new["tokens"] > base["tokens"] * TOKEN_TOLERANCE:
        worse.append("tokens %.0f -> %.0f" % (base["tokens"], new["tokens"]))
    if worse:
        data["valores"].pop(test["param"], None)
        if test["antes"] != PARAMS[test["param"]]["padrao"]:
            data["valores"][test["param"]] = test["antes"]
        data["historico"].append({"em": now(), "acao": "revertido", "param": test["param"], "antes": test["depois"],
                                  "depois": test["antes"], "motivo": "; ".join(worse)})
        data["em_teste"] = None
        return "AJUSTE REVERTIDO %s: voltou a %s porque piorou (%s)" % (test["param"], test["antes"], "; ".join(worse))
    data["historico"].append({"em": now(), "acao": "mantido", "param": test["param"], "valor": test["depois"],
                              "medido": {"antes": base, "depois": new}})
    data["em_teste"] = None
    return "AJUSTE MANTIDO %s=%s: sem piora nas %d tarefas observadas" % (test["param"], test["depois"], OBSERVE_TASKS)

def revert(work, param, reason):
    if not reason.strip():
        raise Invalid("reversão manual exige motivo")
    with lock(work):
        data = load(work)
        if param not in data["valores"]:
            raise Invalid("nenhum ajuste em vigor para " + param)
        old = data["valores"].pop(param)
        if data["em_teste"] and data["em_teste"]["param"] == param:
            data["em_teste"] = None
        data["historico"].append({"em": now(), "acao": "revertido-manual", "param": param, "antes": old,
                                  "depois": PARAMS[param]["padrao"], "motivo": reason.strip()})
        save(work, data)
    return "AJUSTE REVERTIDO %s: voltou ao padrão %s" % (param, PARAMS[param]["padrao"])

# --- nota de aviso por lente ----------------------------------------------------------------

def add_note(work, task_id, lens, text):
    if lens not in LENSES:
        raise Invalid("lente fora da lista: " + ", ".join(sorted(LENSES)))
    text = text.strip()
    if not text or len(text) > NOTE_MAX:
        raise Invalid("nota entre 1 e %d caracteres" % NOTE_MAX)
    with lock(work):
        data = load(work)
        same = [n for n in data["notas"] if n["lente"] == lens and n["texto"] == text]
        if any(task_id in n["tarefas"] for n in same):
            raise Invalid("esta tarefa já confirmou esta nota")
        if same:
            note = same[0]
            note["tarefas"].append(task_id)
        else:
            note = {"lente": lens, "texto": text, "tarefas": [task_id], "ativa": False, "em": now()}
            data["notas"].append(note)
        if len(note["tarefas"]) >= EVIDENCE_MIN and not note["ativa"]:
            note["ativa"] = True
            data["historico"].append({"em": now(), "acao": "nota-ativada", "lente": lens, "tarefas": note["tarefas"]})
            message = "NOTA ATIVADA (%s): %s" % (lens, text)
        else:
            message = "NOTA %s: %d de %d tarefas; ainda inativa" % (lens, len(note["tarefas"]), EVIDENCE_MIN)
        save(work, data)
    return message

def remove_note(work, lens, reason):
    if not reason.strip():
        raise Invalid("remoção exige motivo")
    with lock(work):
        data = load(work)
        keep = [n for n in data["notas"] if not (n["lente"] == lens and n["ativa"])]
        if len(keep) == len(data["notas"]):
            raise Invalid("nenhuma nota ativa para a lente " + lens)
        data["notas"] = keep
        data["historico"].append({"em": now(), "acao": "nota-removida", "lente": lens, "motivo": reason.strip()})
        save(work, data)
    return "NOTA removida (%s)" % lens

# --- transparência --------------------------------------------------------------------------

def show(work):
    """Linha que o fechamento da tarefa leva à resposta: o que está valendo sem decisão do usuário."""
    data = load(work)
    lines = []
    for param, value in sorted(data["valores"].items()):
        state = "em teste" if data["em_teste"] and data["em_teste"]["param"] == param else "mantido"
        lines.append("%s=%s (padrão %s, %s)" % (param, value, PARAMS[param]["padrao"], state))
    for n in data["notas"]:
        if n["ativa"]:
            lines.append("nota da lente %s: %s" % (n["lente"], n["texto"]))
    if not lines:
        return "AJUSTES AUTOMÁTICOS: nenhum em vigor; a Seiva roda com os padrões"
    return "AJUSTES AUTOMÁTICOS EM VIGOR (feitos sem pedido seu, reversíveis): " + " · ".join(lines)

def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=["tarefa", "evidencia", "nota", "remover-nota", "reverter", "mostrar"])
    parser.add_argument("--trabalho", required=True, help="pasta de trabalho privada (a que contém tarefas/)")
    parser.add_argument("--tarefa-id")
    parser.add_argument("--param")
    parser.add_argument("--valor", type=int)
    parser.add_argument("--motivo", default="")
    parser.add_argument("--lente")
    parser.add_argument("--texto", default="")
    parser.add_argument("--quedas", type=int)
    parser.add_argument("--rodadas", type=int)
    parser.add_argument("--tokens", type=int)
    ns = parser.parse_args(argv)
    try:
        c, w = ns.command, ns.trabalho
        if c == "tarefa" and ns.tarefa_id:
            print(register_task(w, ns.tarefa_id, ns.quedas, ns.rodadas, ns.tokens))
        elif c == "evidencia" and ns.tarefa_id and ns.param and ns.valor is not None:
            print(add_evidence(w, ns.tarefa_id, ns.param, ns.valor, ns.motivo))
        elif c == "nota" and ns.tarefa_id and ns.lente:
            print(add_note(w, ns.tarefa_id, ns.lente, ns.texto))
        elif c == "remover-nota" and ns.lente:
            print(remove_note(w, ns.lente, ns.motivo))
        elif c == "reverter" and ns.param:
            print(revert(w, ns.param, ns.motivo))
        elif c == "mostrar":
            print(show(w))
        else:
            raise Invalid("argumentos insuficientes para " + c)
        return 0
    except (Invalid, OSError) as e:
        print("ajustes: " + str(e), file=sys.stderr)
        return 2

if __name__ == "__main__":
    sys.exit(main())
