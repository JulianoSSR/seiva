#!/usr/bin/env python3
"""Regressões isoladas: estado, migração, escopo, diff e terminais de tentativa."""
import concurrent.futures
import importlib.util
import io
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from contextlib import redirect_stdout

ROOT = Path(__file__).resolve().parents[1]
CORE = ROOT / "scripts/estado_tarefa.py"
spec = importlib.util.spec_from_file_location("estado_tarefa", CORE)
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)

class StateTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.repo = self.root / "repo"
        self.repo.mkdir()
        subprocess.run(["git", "init", "-q", str(self.repo)], check=True)
        self.task = self.root / "work/tarefas/uma"
        self.task.mkdir(parents=True)
        self.cwd = Path.cwd()
        os.chdir(self.repo)
        self.addCleanup(os.chdir, self.cwd)
        self.addCleanup(self.temp.cleanup)

    def quiet(self, fun, *args, **kwargs):
        with redirect_stdout(io.StringIO()):
            return fun(*args, **kwargs)

    def proved_mark(self, task, number, status, names, **kwargs):
        # Etapas mecânicas de fixture registram prova explícita e um artefato real.
        if status.split(":", 1)[0] == "feita":
            if not names:
                (task / "proof.txt").write_text("fixture: conferência mecânica")
                names = ["proof.txt"]
            kwargs.setdefault("evidence", "fixture: conferência mecânica registrada")
        return self.quiet(m.mark, task, number, status, names, **kwargs)

    def cli(self, *args):
        return subprocess.run(["python3", str(CORE), *map(str, args)], capture_output=True, text=True)

    def init(self):
        self.quiet(m.init, self.task, self.repo)

    def base(self, *names):
        self.quiet(m.base, self.task, names, exclusive=True)

    def state(self):
        return json.loads((self.task / "estado.json").read_text())

    def diff(self, *names):
        self.quiet(m.diff, self.task, names)
        return (self.task / "diff.patch").read_bytes()

    def test_init_snapshots_staged_unstaged_without_index_change(self):
        p = self.repo / "tracked"
        p.write_text("staged\n")
        subprocess.run(["git", "add", "tracked"], check=True)
        index = (self.repo / ".git/index").read_bytes()
        p.write_text("preexisting unstaged\n")
        self.init()
        self.base("tracked")
        self.assertEqual(index, (self.repo / ".git/index").read_bytes())
        p.write_text("task version\n")
        patch = self.diff("tracked")
        self.assertIn(b"-preexisting unstaged", patch)
        self.assertNotIn(b"-staged", patch)
        self.assertEqual(index, (self.repo / ".git/index").read_bytes())

    def test_diff_requires_explicit_exclusivity(self):
        (self.repo / "a").write_text("x")
        self.init()
        with self.assertRaisesRegex(m.Invalid, "não prova autoria"):
            m.base(self.task, ["a"])
        with self.assertRaisesRegex(m.Invalid, "escopo exclusivo"):
            m.diff(self.task, ["a"])

    def test_diff_refuses_legacy_without_inventing_head_base(self):
        (self.task / "registro.md").write_text("legacy")
        self.proved_mark(self.task, "0", "pendente", [])
        with self.assertRaisesRegex(m.Invalid, "sem base verificável"):
            m.diff(self.task, ["a"])

    def test_acquisition_after_edit_is_refused(self):
        (self.repo / "a").write_text("before")
        self.init()
        (self.repo / "a").write_text("edited")
        with self.assertRaisesRegex(m.Invalid, "antes da aquisição"):
            self.base("a")

    def test_scope_conflict_release_and_isolation(self):
        (self.repo / "a").write_text("before")
        self.init()
        other = self.root / "work/tarefas/outra"
        other.mkdir()
        self.quiet(m.init, other, self.repo)
        self.base("a")
        with self.assertRaisesRegex(m.Invalid, "outra tarefa"):
            m.base(other, ["a"], exclusive=True)
        self.quiet(m.release, self.task)
        self.quiet(m.base, other, ["a"], exclusive=True)

    def test_diff_failure_preserves_last_patch(self):
        (self.repo / "a").write_text("before")
        self.init()
        self.base("a")
        (self.task / "diff.patch").write_text("old patch")
        with self.assertRaises(m.Invalid):
            self.diff("outside")
        self.assertEqual("old patch", (self.task / "diff.patch").read_text())

    def test_file_outside_repo_rejected(self):
        self.init()
        with self.assertRaisesRegex(m.Invalid, "fora do repositório"):
            self.base(str(self.root / "outside"))

    def test_symlink_parent_cannot_escape_repo(self):
        (self.repo / "escape").symlink_to(self.root, target_is_directory=True)
        self.init()
        with self.assertRaisesRegex(m.Invalid, "fora do repositório"):
            self.base("escape/outside")

    def assert_patch(self, old, new, name="a"):
        p = self.repo / name
        p.parent.mkdir(parents=True, exist_ok=True)
        if old is not None:
            p.write_bytes(old)
        self.init()
        self.base(name)
        if new is None:
            p.unlink()
        else:
            p.write_bytes(new)
        patch = self.diff(name)
        if old is None:
            p.unlink()
        else:
            p.write_bytes(old)
        proc = subprocess.run(["git", "apply", "--check", "--binary", "-"], input=patch, capture_output=True)
        self.assertEqual(0, proc.returncode, proc.stderr.decode())
        subprocess.run(["git", "apply", "--binary", "-"], input=patch, check=True)
        self.assertEqual(new, p.read_bytes() if p.exists() else None)
        return patch

    def test_added_file_patch_applies(self):
        self.assert_patch(None, b"new\n")

    def test_removed_file_patch_applies(self):
        self.assert_patch(b"old\n", None)

    def test_modified_file_patch_applies(self):
        self.assert_patch(b"old\n", b"new\n")

    def test_binary_patch_applies(self):
        self.assert_patch(b"\0old", b"\0new")

    def test_path_with_spaces_patch_applies(self):
        self.assert_patch(b"old\n", b"new\n", "dir/file with spaces")

    def test_executable_mode_in_diff(self):
        p = self.repo / "run.sh"
        p.write_text("x\n")
        p.chmod(0o644)
        self.init()
        self.base("run.sh")
        p.chmod(0o755)
        patch = self.diff("run.sh")
        self.assertIn(b"old mode 100644", patch)
        self.assertIn(b"new mode 100755", patch)

    def test_symlink_target_in_diff(self):
        p = self.repo / "link"
        p.symlink_to("old")
        self.init()
        self.base("link")
        p.unlink()
        p.symlink_to("new")
        patch = self.diff("link")
        self.assertIn(b"120000", patch)
        self.assertIn(b"-old", patch)
        self.assertIn(b"+new", patch)

    def test_unchanged_and_duplicate_scope(self):
        (self.repo / "a").write_text("before")
        self.init()
        self.base("a", "a")
        self.assertEqual(b"", self.diff("a", "a"))

    def test_new_unknown_path_cannot_be_claimed_after_creation(self):
        self.init()
        (self.repo / "new").write_text("made too soon")
        with self.assertRaisesRegex(m.Invalid, "antes da aquisição"):
            self.base("new")

    def test_corrupt_json_never_falls_back_to_markdown(self):
        self.init()
        (self.task / "estado.json").write_text("{")
        with self.assertRaisesRegex(m.Invalid, "estado.json inválido"):
            m.check(self.task)

    def test_empty_markdown_never_means_done(self):
        (self.task / "progresso.md").write_text("")
        with self.assertRaisesRegex(m.Invalid, "incompleto"):
            m.check(self.task)

    def test_legacy_migration_preserves_recorded_hashes(self):
        (self.task / "a").write_text("first")
        fp = m.digest(b"first")[:12]
        state = m.empty(self.task)
        state["stages"]["0"].update(status="feita", artifacts={"a": {"sha256": fp}})
        (self.task / "progresso.md").write_text(m.markdown(state))
        (self.task / "a").write_text("changed")
        self.assertEqual(1, self.quiet(m.check, self.task))
        self.assertEqual(fp, self.state()["stages"]["0"]["artifacts"]["a"]["sha256"])

    def test_duplicate_legacy_stage_rejected(self):
        state = m.empty(self.task)
        md = m.markdown(state)
        (self.task / "progresso.md").write_text(md + "| 0 Terreno | feita | | |\n")
        with self.assertRaisesRegex(m.Invalid, "legado inválido"):
            m.check(self.task)

    def test_json_authority_repairs_markdown(self):
        self.init()
        self.proved_mark(self.task, "1", "em-curso", [])
        (self.task / "progresso.md").write_text("corrupted projection")
        self.quiet(m.check, self.task)
        self.assertIn("| 1 Triagem | em-curso", (self.task / "progresso.md").read_text())

    def test_mark_missing_artifact_does_not_create_state(self):
        with self.assertRaises(m.Invalid):
            m.mark(self.task, "0", "feita", ["missing"])
        self.assertFalse((self.task / "estado.json").exists())
        self.assertFalse((self.task / "progresso.md").exists())

    def test_hash_change_warns_without_redoing_completed_stage(self):
        (self.task / "a").write_text("first")
        self.proved_mark(self.task, "0", "feita", ["a"])
        (self.task / "a").write_text("other")
        out = io.StringIO()
        with redirect_stdout(out):
            rc = m.check(self.task)
        self.assertEqual(1, rc)
        self.assertIn("PROXIMA 0 Terreno", out.getvalue())
        self.assertIn("NAO-COMPROVADA", out.getvalue())
        self.assertEqual("feita", self.state()["stages"]["0"]["status"])

    def test_only_explicit_hash_dependencies_invalidate_stage(self):
        (self.task / "source").write_text("first")
        self.proved_mark(self.task, "0", "feita", [])
        self.proved_mark(self.task, "1", "feita", [], deps=["source"])
        self.proved_mark(self.task, "2", "feita", [])
        (self.task / "source").write_text("other")
        out = io.StringIO()
        with redirect_stdout(out):
            m.check(self.task)
        self.assertIn("PROXIMA 1 Triagem", out.getvalue())
        self.assertEqual("feita", self.state()["stages"]["2"]["status"])

    def test_concurrent_marks_keep_both_updates(self):
        self.init()
        (self.task / "proof.txt").write_text("checked")
        def run(n):
            return subprocess.run(["python3", str(CORE), "mark", str(self.task), str(n), "feita", "proof.txt",
                                   "--evidence", "fixture: checked"],
                                  capture_output=True)
        with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
            results = list(pool.map(run, [1, 2]))
        self.assertTrue(all(p.returncode == 0 for p in results))
        self.assertEqual(["feita", "feita"], [self.state()["stages"][str(n)]["status"] for n in [1, 2]])

    def test_pending_searches_beyond_twenty_completed_tasks(self):
        self.init()
        for n in range(25):
            task = self.root / ("work/tarefas/done-%02d" % n)
            task.mkdir()
            self.proved_mark(task, "9", "feita", [])
        out = io.StringIO()
        with redirect_stdout(out):
            m.pending(self.root / "work")
        self.assertIn(str(self.task), out.getvalue())

    def test_pending_uses_state_update_time_not_directory_time(self):
        self.init()
        other = self.root / "work/tarefas/other"
        other.mkdir()
        self.proved_mark(other, "0", "pendente", [])
        # directory mtime intentionally newer, state file intentionally older
        os.utime(self.task, (100, 100))
        os.utime(other, (200, 200))
        os.utime(self.task / "estado.json", (500, 500))
        os.utime(self.task / "progresso.md", (500, 500))
        os.utime(other / "estado.json", (300, 300))
        os.utime(other / "progresso.md", (300, 300))
        out = io.StringIO()
        with redirect_stdout(out):
            m.pending(self.root / "work")
        self.assertTrue(out.getvalue().startswith(str(self.task)))

    def start(self, report_preexisting=False):
        (self.task / "package.md").write_text("instructions")
        if report_preexisting:
            (self.task / "report.md").write_text("old report")
        self.quiet(m.attempt_start, self.task, "r1", "agent", "package.md", "report.md")

    def report(self, text):
        # O produtor da fixture escreve o envelope ao terminar, antes da confirmação.
        task_id = self.state()["task_id"]
        (self.task / "report.md").write_text(text + "\n<!-- seiva:fim " + task_id + " r1 -->\n")

    def complete(self):
        self.quiet(m.attempt_complete, self.task, "r1", "concluido", ["report.md"], "test passed")

    def test_existing_report_is_not_terminal(self):
        self.start(report_preexisting=True)
        self.assertFalse(m.attempt_valid(self.task, self.state(), "r1"))
        with self.assertRaisesRegex(m.Invalid, "preexistente|marcador final"):
            self.complete()

    def test_terminal_binds_task_attempt_artifacts_evidence(self):
        self.start()
        self.report("current report")
        self.complete()
        state = self.state()
        terminal = state["attempts"]["r1"]["terminal"]
        self.assertEqual(state["task_id"], terminal["task_id"])
        self.assertEqual("r1", terminal["attempt_id"])
        self.assertEqual("test passed", terminal["evidence"])
        self.assertTrue(m.attempt_valid(self.task, state, "r1"))
        (self.task / "report.md").write_text("later edit")
        self.assertFalse(m.attempt_valid(self.task, state, "r1"))

    def test_terminal_without_evidence_refused(self):
        self.start()
        self.report("current")
        with self.assertRaisesRegex(m.Invalid, "evidência"):
            m.attempt_complete(self.task, "r1", "concluido", ["report.md"], "")
        self.assertIsNone(self.state()["attempts"]["r1"]["terminal"])

    def test_terminal_missing_report_or_changed_package_refused(self):
        self.start()
        with self.assertRaisesRegex(m.Invalid, "relatório explícito"):
            m.attempt_complete(self.task, "r1", "concluido", [], "proof")
        self.report("current")
        (self.task / "package.md").write_text("new instructions")
        with self.assertRaisesRegex(m.Invalid, "pacote mudou"):
            self.complete()

    def test_attempt_id_cannot_be_reused(self):
        self.start()
        with self.assertRaisesRegex(m.Invalid, "já registrada"):
            self.start()

    def test_partial_is_terminal_but_not_complete(self):
        self.start()
        self.quiet(m.attempt_complete, self.task, "r1", "parcial", [], "blocked by missing capability")
        self.assertFalse(m.attempt_valid(self.task, self.state(), "r1"))
        with self.assertRaisesRegex(m.Invalid, "já terminal"):
            self.complete()

    def test_cli_options_before_paths(self):
        (self.repo / "a").write_text("first")
        self.init()
        proc = self.cli("base", self.task, "--exclusive", "a")
        self.assertEqual(0, proc.returncode, proc.stderr)

    def test_cli_bad_stage_is_error_and_no_files_created(self):
        proc = self.cli("mark", self.task, "10", "feita")
        self.assertEqual(2, proc.returncode)
        self.assertFalse((self.task / "estado.json").exists())

    def test_check_does_not_change_progress_timestamp(self):
        self.init()
        stamp = (self.task / "estado.json").stat().st_mtime_ns
        self.quiet(m.check, self.task)
        self.assertEqual(stamp, (self.task / "estado.json").stat().st_mtime_ns)

    def test_check_repairs_missing_markdown_from_json(self):
        self.init()
        (self.task / "progresso.md").unlink()
        self.quiet(m.check, self.task)
        self.assertEqual(10, sum(line.startswith("| ") and len(line) > 2 and line[2].isdigit()
                                 for line in (self.task / "progresso.md").read_text().splitlines()))

    def test_corrupt_baseline_refuses_to_replace_previous_diff(self):
        (self.repo / "a").write_text("before")
        self.init()
        self.base("a")
        state = self.state()
        state["baseline"]["files"]["a"]["data"] = "YmFk"
        (self.task / "estado.json").write_text(json.dumps(state))
        (self.task / "diff.patch").write_text("previous")
        with self.assertRaisesRegex(m.Invalid, "base corrompida"):
            self.diff("a")
        self.assertEqual("previous", (self.task / "diff.patch").read_text())

    def test_schema_rejects_empty_artifact_hash(self):
        self.init()
        state = self.state()
        state["stages"]["0"].update(status="feita", artifacts={"a": {"sha256": ""}})
        (self.task / "estado.json").write_text(json.dumps(state))
        with self.assertRaisesRegex(m.Invalid, "estado.json inválido"):
            self.quiet(m.check, self.task)

    def test_cli_write_failure_does_not_report_success(self):
        from unittest.mock import patch
        self.init()
        (self.task / "proof.txt").write_text("checked")
        with patch.object(m.os, "replace", side_effect=PermissionError("denied")):
            with redirect_stdout(io.StringIO()):
                self.assertEqual(2, m.main(["mark", str(self.task), "0", "feita", "proof.txt",
                                           "--evidence", "fixture: checked"]))
        self.assertEqual("pendente", self.state()["stages"]["0"]["status"])

    def test_stage_done_requires_artifacts_and_explicit_proof(self):
        (self.task / "report.md").write_text("STATUS: parcial")
        with self.assertRaisesRegex(m.Invalid, "exige artefatos"):
            m.mark(self.task, "0", "feita", [])
        with self.assertRaisesRegex(m.Invalid, "exige artefatos"):
            m.mark(self.task, "0", "feita", ["report.md"])
        self.assertFalse((self.task / "estado.json").exists())

    def test_stage_can_link_only_valid_completed_attempt(self):
        self.start()
        self.report("partial report")
        with self.assertRaisesRegex(m.Invalid, "conclusão válida"):
            m.mark(self.task, "0", "feita", ["report.md"], attempt="r1")
        self.complete()
        self.quiet(m.mark, self.task, "0", "feita", ["report.md"], attempt="r1")
        self.assertTrue(m.stage_valid(self.task, self.state(), self.state()["stages"]["0"]))
        (self.task / "report.md").write_text("later edit")
        self.assertFalse(m.stage_valid(self.task, self.state(), self.state()["stages"]["0"]))

    def test_stage_link_rejects_unbound_artifact(self):
        self.start()
        self.report("current report")
        self.complete()
        (self.task / "other.md").write_text("not produced by attempt")
        with self.assertRaisesRegex(m.Invalid, "não conferem"):
            m.mark(self.task, "0", "feita", ["other.md"], attempt="r1")

    def test_legacy_done_without_proof_requires_revalidation(self):
        state = m.empty(self.task)
        for stage in state["stages"].values():
            stage["status"] = "feita"
        (self.task / "progresso.md").write_text(m.markdown(state))
        out = io.StringIO()
        with redirect_stdout(out):
            self.assertEqual(1, m.check(self.task))
        self.assertIn("PROXIMA 0 Terreno", out.getvalue())
        self.assertNotIn("PROXIMA nenhuma", out.getvalue())

    def test_terminal_rejects_empty_truncated_and_other_attempt_report(self):
        self.start()
        for text in ["", "STATUS: concluido", "<!-- seiva:fim " + self.state()["task_id"] + " r1 -->",
                     "content\n<!-- seiva:fim " + self.state()["task_id"] + " r0 -->",
                     "content\n<!-- seiva:fim other-task r1 -->"]:
            (self.task / "report.md").write_text(text)
            with self.assertRaisesRegex(m.Invalid, "vazio, truncado"):
                self.complete()
            self.assertIsNone(self.state()["attempts"]["r1"]["terminal"])

    def test_terminal_rejects_declared_partial_even_with_footer(self):
        self.start()
        self.report("STATUS: parcial")
        with self.assertRaisesRegex(m.Invalid, "status parcial"):
            self.complete()

    def test_task_lock_refuses_symlink_and_hardlink(self):
        target = self.root / "outside-lock"
        target.write_text("preserve")
        (self.task / ".estado.lock").symlink_to(target)
        proc = self.cli("init", self.task)
        self.assertEqual(2, proc.returncode)
        self.assertEqual("preserve", target.read_text())
        (self.task / ".estado.lock").unlink()
        os.link(target, self.task / ".estado.lock")
        proc = self.cli("init", self.task)
        self.assertEqual(2, proc.returncode)
        self.assertEqual("preserve", target.read_text())

    def test_artifact_requires_task_or_declared_repository_scope(self):
        outside = self.root / "outside"
        outside.write_text("private")
        with self.assertRaisesRegex(m.Invalid, "fora do escopo"):
            m.mark(self.task, "0", "feita", [str(outside)], evidence="checked")
        self.quiet(m.mark, self.task, "0", "feita", [str(outside)], evidence="checked",
                   allow_roots=[self.root])
        self.assertTrue(m.stage_valid(self.task, self.state(), self.state()["stages"]["0"]))

    def test_artifact_rejects_parent_symlink(self):
        target = self.task / "actual"
        target.mkdir()
        (target / "proof.txt").write_text("checked")
        (self.task / "alias").symlink_to(target, target_is_directory=True)
        with self.assertRaisesRegex(m.Invalid, "pai simbólico"):
            m.mark(self.task, "0", "feita", ["alias/proof.txt"], evidence="checked")

    def test_missing_diff_path_is_failure_not_success(self):
        self.init()
        self.base("missing")
        with self.assertRaisesRegex(m.Invalid, "ausente na base"):
            self.diff("missing")
        self.assertFalse((self.task / "diff.patch").exists())

    def test_running_attempt_blocks_new_id_for_same_job_or_report(self):
        self.start()
        with self.assertRaisesRegex(m.Invalid, "running sobreposta"):
            m.attempt_start(self.task, "r2", "agent", "package.md", "different.md")
        (self.task / "other-package.md").write_text("different instructions")
        with self.assertRaisesRegex(m.Invalid, "running sobreposta"):
            m.attempt_start(self.task, "r2", "other-agent", "other-package.md", "report.md")
        # Caminho absoluto e relativo do mesmo relatório não autorizam duplicação.
        with self.assertRaisesRegex(m.Invalid, "running sobreposta"):
            m.attempt_start(self.task, "r2", "other-agent", "other-package.md", str(self.task / "report.md"))

    def test_cancelled_attempt_allows_explicit_retry_with_new_id(self):
        self.start()
        self.quiet(m.attempt_complete, self.task, "r1", "cancelled", [], "runtime confirmou cancelamento")
        self.quiet(m.attempt_start, self.task, "r2", "agent", "package.md", "report.md")
        self.assertEqual("running", self.state()["attempts"]["r2"]["status"])

    def test_check_lists_running_attempt_without_inventing_runtime_liveness(self):
        self.start()
        out = io.StringIO()
        with redirect_stdout(out):
            m.check(self.task)
        self.assertIn("TENTATIVA r1 running", out.getvalue())
        self.assertIn("registro não prova processo vivo", out.getvalue())
        self.assertIn("consulte a ferramenta de execução", out.getvalue())

if __name__ == "__main__":
    unittest.main()
