"""Focused differential controls; run with uv run tools/differential/compiler_diff.test.py."""
import contextlib
import importlib.util
import io
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

SPEC = importlib.util.spec_from_file_location("compiler_diff", Path(__file__).with_name("compiler_diff.py"))
diff = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(diff)


class FocusedCompilerDiffTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.tdb = Path(self.temp.name) / "tdb.tsv"
        self.compiler = Path(self.temp.name) / "compiler.tsv"

    def test_season_faction_and_field_reach_both_dumpers(self):
        with patch.object(diff, "DUMP_DIR", self.temp.name), \
                patch.object(diff, "lua_env", return_value={}), patch.object(diff, "run") as run:
            diff.dump_both("Vanilla", "/oracle", "lua5.1", "SoD", "Horde", "Quest.requiredRaces")
        tdb_command = run.call_args_list[0].args[0]
        compiler_command = run.call_args_list[1].args[0]
        expected = ["--faction=Horde", "--season=SoD", "--only=Quest.requiredRaces"]
        self.assertEqual(expected, tdb_command[-3:])
        self.assertEqual(expected, compiler_command[-3:])

    def test_focused_dump_preserves_nil_zero_and_missing_entities(self):
        self.tdb.write_text("Quest\t1\trequiredRaces\tnil\nQuest\t2\trequiredRaces\tnil\n")
        self.compiler.write_text("Quest\t1\trequiredRaces\t0\n")
        rows, compared, _, _ = diff.classify(self.tdb, self.compiler)
        self.assertEqual(1, compared)
        self.assertCountEqual([
            ("VALUE", b"Quest", b"1", b"requiredRaces", b"nil", b"0"),
            ("ID_ONLY_IN_TDB", b"Quest", b"2", b"-", b"<entity>", b"<absent>"),
        ], rows)

    def test_self_check_detects_one_addition_beside_an_existing_difference(self):
        self.tdb.write_text("Quest\t1\trequiredRaces\t0\nQuest\t2\trequiredRaces\t77\n")
        self.compiler.write_text("Quest\t1\trequiredRaces\t178\nQuest\t2\trequiredRaces\t77\n")
        original = self.tdb.read_bytes()
        with contextlib.redirect_stdout(io.StringIO()):
            result = diff.run_self_check("Vanilla", self.tdb, self.compiler, 1)
        self.assertEqual(0, result)
        self.assertEqual(original, self.tdb.read_bytes())

    def test_focused_difference_cannot_use_or_update_a_baseline(self):
        self.tdb.write_text("Quest\t1\trequiredRaces\t0\n")
        self.compiler.write_text("Quest\t1\trequiredRaces\t77\n")
        args = ["compiler_diff.py", "Vanilla", "--only=Quest.requiredRaces"]
        with patch.object(diff.sys, "argv", args), \
                patch.object(diff, "assert_questie_input", return_value="/oracle"), \
                patch.object(diff, "dump_both", return_value=(self.tdb, self.compiler)), \
                patch.object(diff, "read_baseline") as baseline, \
                contextlib.redirect_stdout(io.StringIO()), self.assertRaises(SystemExit) as exit:
            diff.main()
        self.assertEqual(1, exit.exception.code)
        baseline.assert_not_called()
        with patch.object(diff.sys, "argv", args + ["--update-baseline"]), \
                patch.object(diff, "assert_questie_input") as pin, self.assertRaises(SystemExit):
            diff.main()
        pin.assert_not_called()

    def test_empty_focused_dump_fails_without_self_check(self):
        self.tdb.write_text("")
        self.compiler.write_text("")
        with patch.object(diff.sys, "argv", ["compiler_diff.py", "Vanilla", "--only=Quest.requiredRaces"]), \
                patch.object(diff, "assert_questie_input", return_value="/oracle"), \
                patch.object(diff, "dump_both", return_value=(self.tdb, self.compiler)), \
                contextlib.redirect_stdout(io.StringIO()), self.assertRaises(SystemExit) as exit:
            diff.main()
        self.assertEqual(1, exit.exception.code)


if __name__ == "__main__":
    unittest.main()
