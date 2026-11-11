#!/usr/bin/env python3
"""Canal A: ajustes locais automáticos. Lista fechada, evidência de duas tarefas, um em teste, reversão."""
import importlib.util
from pathlib import Path
import tempfile
import time
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("ajustes", ROOT / "scripts/ajustes.py")
a = importlib.util.module_from_spec(spec)
spec.loader.exec_module(a)

class AjustesTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.w = Path(self.temp.name) / ".seiva"

    def tarefas(self, n, quedas=0, rodadas=1, tokens=1000, prefix="t"):
        for i in range(n):
            a.register_task(self.w, "%s%d" % (prefix, i), quedas, rodadas, tokens)
            time.sleep(0.01)

    def test_parameter_outside_closed_list_or_range_refused(self):
        with self.assertRaisesRegex(a.Invalid, "lista fechada"):
            a.add_evidence(self.w, "t1", "teto_de_rodadas", 5, "x")
        with self.assertRaisesRegex(a.Invalid, "fora do intervalo"):
            a.add_evidence(self.w, "t1", "context_limit", 400000, "x")  # só pode apertar, nunca afrouxar
        with self.assertRaisesRegex(a.Invalid, "fora do intervalo"):
            a.add_evidence(self.w, "t1", "stale_minutes", 1, "x")

    def test_one_task_of_evidence_applies_nothing(self):
        self.tarefas(2)
        self.assertIn("1 de 2", a.add_evidence(self.w, "t0", "stale_minutes", 30, "agente de 25 min cortado à toa"))
        self.assertEqual(15, a.effective(self.w, "stale_minutes"))

    def test_two_tasks_apply_and_show_in_transparency_line(self):
        self.tarefas(2)
        a.add_evidence(self.w, "t0", "stale_minutes", 30, "agente longo cortado à toa")
        msg = a.add_evidence(self.w, "t1", "stale_minutes", 25, "de novo")
        self.assertIn("AJUSTE APLICADO", msg)
        self.assertEqual(25, a.effective(self.w, "stale_minutes"))  # o mais perto do padrão
        self.assertIn("stale_minutes=25", a.show(self.w))
        self.assertIn("em teste", a.show(self.w))

    def test_without_baseline_tasks_nothing_is_applied(self):
        a.add_evidence(self.w, "t0", "stale_minutes", 30, "x")
        self.assertIn("faltam tarefas registradas", a.add_evidence(self.w, "t1", "stale_minutes", 30, "y"))
        self.assertEqual(15, a.effective(self.w, "stale_minutes"))

    def test_only_one_adjustment_in_test_at_a_time(self):
        self.tarefas(2)
        for t in ("t0", "t1"):
            a.add_evidence(self.w, t, "stale_minutes", 30, "x")
        a.add_evidence(self.w, "t0", "context_limit", 100000, "y")
        msg = a.add_evidence(self.w, "t1", "context_limit", 100000, "y")
        self.assertIn("um por vez", msg)
        self.assertEqual(150000, a.effective(self.w, "context_limit"))

    def test_worse_tasks_revert_automatically(self):
        self.tarefas(2, quedas=0, rodadas=1)
        for t in ("t0", "t1"):
            a.add_evidence(self.w, t, "stale_minutes", 30, "x")
        time.sleep(0.02)
        a.register_task(self.w, "p0", 2, 1, 1000)
        time.sleep(0.01)
        msg = a.register_task(self.w, "p1", 1, 2, 1000)
        self.assertIn("AJUSTE REVERTIDO", msg)
        self.assertEqual(15, a.effective(self.w, "stale_minutes"))
        self.assertEqual("revertido", a.load(self.w)["historico"][-1]["acao"])
        self.assertIn("nenhum em vigor", a.show(self.w))

    def test_not_worse_tasks_keep_adjustment(self):
        self.tarefas(2)
        for t in ("t0", "t1"):
            a.add_evidence(self.w, t, "stale_minutes", 30, "x")
        time.sleep(0.02)
        a.register_task(self.w, "p0", 0, 1, 1000)
        time.sleep(0.01)
        self.assertIn("AJUSTE MANTIDO", a.register_task(self.w, "p1", 0, 1, 1100))
        self.assertEqual(30, a.effective(self.w, "stale_minutes"))

    def test_token_jump_over_tolerance_reverts(self):
        self.tarefas(2, tokens=1000)
        for t in ("t0", "t1"):
            a.add_evidence(self.w, t, "stale_minutes", 30, "x")
        time.sleep(0.02)
        a.register_task(self.w, "p0", 0, 1, 2000)
        time.sleep(0.01)
        self.assertIn("tokens", a.register_task(self.w, "p1", 0, 1, 2000))

    def test_manual_revert_needs_reason(self):
        self.tarefas(2)
        for t in ("t0", "t1"):
            a.add_evidence(self.w, t, "stale_minutes", 30, "x")
        with self.assertRaisesRegex(a.Invalid, "motivo"):
            a.revert(self.w, "stale_minutes", " ")
        a.revert(self.w, "stale_minutes", "não gostei")
        self.assertEqual(15, a.effective(self.w, "stale_minutes"))

    def test_note_needs_two_tasks_and_is_short(self):
        self.assertIn("ainda inativa", a.add_note(self.w, "t0", "desempenho", "nesta base a lente de desempenho não achou nada"))
        self.assertNotIn("desempenho", a.show(self.w))
        self.assertIn("NOTA ATIVADA", a.add_note(self.w, "t1", "desempenho", "nesta base a lente de desempenho não achou nada"))
        self.assertIn("nota da lente desempenho", a.show(self.w))
        with self.assertRaisesRegex(a.Invalid, "entre 1 e"):
            a.add_note(self.w, "t2", "dados", "x" * 300)
        with self.assertRaisesRegex(a.Invalid, "lente fora"):
            a.add_note(self.w, "t2", "inventada", "x")

    def test_corrupt_file_never_breaks_task_and_falls_to_default(self):
        self.w.mkdir(parents=True)
        (self.w / "ajustes.json").write_text("{quebrado")
        self.assertEqual(15, a.effective(self.w, "stale_minutes"))
        with self.assertRaisesRegex(a.Invalid, "inválido"):
            a.load(self.w)

    def test_tampered_value_outside_range_is_ignored(self):
        self.w.mkdir(parents=True)
        (self.w / "ajustes.json").write_text('{"schema":1,"valores":{"context_limit":900000},"evidencias":[],"tarefas":[],"em_teste":null,"historico":[],"notas":[]}')
        self.assertEqual(150000, a.effective(self.w, "context_limit"))

    def test_module_has_no_network_and_never_touches_the_github_channel(self):
        src = (ROOT / "scripts/ajustes.py").read_text()
        for forbidden in ("import aprendizado", "from aprendizado", "urllib", "requests", "socket", "subprocess", "gh "):
            self.assertNotIn(forbidden, src)

    def test_estado_tarefa_reads_local_adjustment(self):
        spec2 = importlib.util.spec_from_file_location("estado_tarefa2", ROOT / "scripts/estado_tarefa.py")
        et = importlib.util.module_from_spec(spec2)
        spec2.loader.exec_module(et)
        self.tarefas(2)
        for t in ("t0", "t1"):
            a.add_evidence(self.w, t, "context_limit", 100000, "x")
        task = self.w / "tarefas" / "uma"
        task.mkdir(parents=True)
        self.assertEqual(100000, et.tuned(task, "context_limit"))
        self.assertEqual(15, et.tuned(task, "stale_minutes"))
        other = Path(self.temp.name) / "solta"
        other.mkdir()
        self.assertEqual(150000, et.tuned(other, "context_limit"))

if __name__ == "__main__":
    unittest.main()
