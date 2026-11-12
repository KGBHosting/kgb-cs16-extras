"""Execute the actual bounded Pawn token parser, translating its integer subset."""
from pathlib import Path
import subprocess
import tempfile
import unittest

from test_vote_policy import SOURCE, function_body, as_c


class CycleParserTests(unittest.TestCase):
    def run_parser(self, mutation=False):
        body = function_body(SOURCE.read_text(), "cycle_map_token")
        if mutation:
            body = body.replace("length >= limit", "length > limit")
        body = body.replace("stock cycle_map_token(const line[], token[], limit)",
                            "int cycle_map_token(const int line[], int token[], int limit)")
        cases = [
            ("de_dust2", 31, "de_dust2"),
            ("de_dust2\t// comment", 31, "de_dust2"),
            ("de_dust2 // comment", 31, "de_dust2"),
            ("x" * 31, 31, "x" * 31),
            ("x" * 32, 31, ""),
            ("de_dust2_extra", 8, ""),
            ("", 31, ""),
            ("\tde_dust2", 31, ""),
            ("de_dust2", 0, ""),
            ("de_dust2", 32, ""),
        ]
        assertions = []
        for number, (line, limit, result) in enumerate(cases):
            ints = ",".join(map(str, map(ord, line)))
            assertions.append("{ int line[] = {" + (ints + "," if ints else "") + "0}; int token[33] = {0};")
            assertions.append(f"assert(cycle_map_token(line, token, {limit}) == {len(result)});")
            assertions.extend(f"assert(token[{i}] == {value});" for i, value in enumerate([*map(ord, result), 0]))
            assertions.append("}")
        code = "#include <assert.h>\n" + as_c(body) + "\nint main(void) {\n" + "\n".join(assertions) + "\nreturn 0; }"
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory)
            (path / "parser.c").write_text(code)
            result = subprocess.run(["cc", "-std=c11", "-Wall", "-Wextra", "-Werror", str(path / "parser.c"), "-o", str(path / "parser")], capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            return subprocess.run([str(path / "parser")], cwd=path, capture_output=True).returncode

    def test_full_tokens_tabs_and_capacity(self):
        self.assertEqual(self.run_parser(), 0)

    def test_boundary_mutation_is_rejected(self):
        self.assertNotEqual(self.run_parser(mutation=True), 0)
