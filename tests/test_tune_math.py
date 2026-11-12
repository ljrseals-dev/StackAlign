# SPDX-License-Identifier: MIT
# Author: Lewis James Seals Jr.
"""PROVISIONAL harness. Drives the real bash lib/tune.sh; no second implementation.
Only cases pinned by the master prompt v8 summary are asserted. T1-T28 proper
live in docs/TUNING.md (unavailable) and are NOT reproduced here."""
import pathlib, subprocess, unittest

TUNE = pathlib.Path(__file__).resolve().parent.parent / "lib" / "tune.sh"


def run(*args):
    p = subprocess.run(["bash", str(TUNE), *map(str, args)],
                       capture_output=True, text=True)
    kv = dict(l.split("=", 1) for l in p.stdout.splitlines() if "=" in l)
    return p.returncode, kv


class Pinned(unittest.TestCase):
    def test_512_noswap(self):
        rc, kv = run(512, 0, "lean")
        self.assertEqual(rc, 0)
        self.assertEqual((kv["max_children"], kv["buffer_pool_mib"]), ("1", "48"))
        self.assertEqual(kv["warning"], "concurrency_1")

    def test_512_swap512(self):
        rc, kv = run(512, 512, "lean")
        self.assertEqual(rc, 0)
        self.assertEqual((kv["max_children"], kv["buffer_pool_mib"]), ("4", "64"))

    def test_max_connections_formula(self):
        _, kv = run(512, 512, "lean")
        self.assertEqual(kv["max_connections"], str(4 * 2 + 0 + 5))

    def test_refusal_tiny(self):
        rc, kv = run(256, 0, "lean")
        self.assertNotEqual(rc, 0)
        self.assertEqual(kv["error"], "no_room_after_fixed")

    def test_standard_refuses_not_guesses(self):
        rc, kv = run(4096, 0, "standard")
        self.assertNotEqual(rc, 0)
        self.assertEqual(kv["error"], "standard_not_implemented")


if __name__ == "__main__":
    unittest.main(verbosity=2)
