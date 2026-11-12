"""Execute the production integer tally body as C; no engine or live-server claim.

Pawn's integer subset here uses the same comparisons, loops and bounded small
nonnegative integers as C. Only the function signature and `new` declarations
are translated. No vote algorithm is copied into the harness. Mutation controls
must make the same compiled production-source assertions fail.
"""
from pathlib import Path
import itertools
import re
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "src/include/hub_votes.inc"


def function_body(source, name):
    start = source.index("stock " + name + "(")
    opening = source.index("{", start)
    depth = 1
    end = opening + 1
    while depth:
        depth += (source[end] == "{") - (source[end] == "}")
        end += 1
    return source[start:end]


def as_c(function):
    function = function.replace("stock approved_map_choice(const totals[], choices, electorate)",
                                "int approved_map_choice(const int totals[], int choices, int electorate)")
    function = re.sub(r"\bnew\b", "int", function)
    # Pawn permits semicolon-less statements; insert them only for this subset.
    lines = []
    for line in function.splitlines():
        stripped = line.strip()
        if stripped and not stripped.startswith("//") and not stripped.endswith(("{", "}", ";")):
            if not re.match(r"int \w+\(", stripped) and not (stripped.startswith(("for (", "while (")) and stripped.endswith(")")):
                line += ";"
        lines.append(line)
    return "\n".join(lines)


class VotePolicyTests(unittest.TestCase):
    def run_policy(self, mutation=None):
        source = function_body(SOURCE.read_text(), "approved_map_choice")
        if mutation:
            old, new = mutation
            self.assertIn(old, source)
            source = source.replace(old, new, 1)
        assertions = [
            "int t[6] = {0};",
            "assert(approved_map_choice(t, 0, 2) == -1);",
            "assert(approved_map_choice(t, 6, 2) == -1);",
            "assert(approved_map_choice(t, 1, 1) == -1);",
            "assert(approved_map_choice(t, 1, 33) == -1);",
            "t[0] = -1; assert(approved_map_choice(t, 1, 2) == -1);",
            "t[0] = 3; assert(approved_map_choice(t, 1, 2) == -1);",
            "t[0] = 3; t[1] = -1; assert(approved_map_choice(t, 1, 2) == -1);",
        ]
        # A two-choice election is fully enumerated through five humans.
        # These independently expressed properties cover abstention, keep-map,
        # fixed electorate quorum, ties and a unique plurality among change votes.
        for electorate in range(2, 6):
            for a, b, stay in itertools.product(range(electorate + 1), repeat=3):
                if a + b + stay > electorate:
                    expected = -1
                elif a + b <= electorate // 2 or a == b or max(a, b) <= stay:
                    expected = -1
                else:
                    expected = 0 if a > b else 1
                assertions.append(f"t[0]={a}; t[1]={b}; t[2]={stay}; assert(approved_map_choice(t, 2, {electorate}) == {expected});")
        c = "#include <assert.h>\n#define HUB_VOTE_CHOICES 5\n#define MAX_CLIENTS 32\n" + as_c(source)
        c += "\nint main(void) {\n" + "\n".join(assertions) + "\nreturn 0; }\n"
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory)
            (path / "policy.c").write_text(c)
            build = subprocess.run(["cc", "-std=c11", "-Wall", "-Wextra", "-Werror", str(path / "policy.c"), "-o", str(path / "policy")], capture_output=True, text=True)
            self.assertEqual(build.returncode, 0, build.stderr)
            return subprocess.run([str(path / "policy")], cwd=path, capture_output=True).returncode

    def test_actual_tally_source_properties(self):
        self.assertEqual(self.run_policy(), 0)

    def test_negative_mutations_are_detected(self):
        mutations = [
            ("cast > electorate", "cast < 0"),
            ("cast - totals[choices] <= electorate / 2", "cast < 0"),
            ("c != best && totals[c] == totals[best]", "c != best && totals[c] < 0"),
            ("totals[best] <= totals[choices]", "totals[best] < 0"),
            ("totals[c] < 0", "totals[c] < -100"),
        ]
        for mutation in mutations:
            with self.subTest(mutation=mutation):
                self.assertNotEqual(self.run_policy(mutation), 0)


if __name__ == "__main__":
    unittest.main()
