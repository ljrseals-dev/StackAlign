# SPDX-License-Identifier: MIT
# Author: Lewis James Seals Jr.
"""Black-box tests for the Bash M2a memory arithmetic.

The harness invokes the production Bash implementation. It contains no second
implementation of the sizing formulas.
"""
import os
import pathlib
import subprocess
import unittest

TUNE = pathlib.Path(__file__).resolve().parent.parent / "lib" / "tune.sh"


def run(ram, swap, profile, *, env=None, floor=False):
    args = ["bash", str(TUNE), str(ram), str(swap), profile]
    if floor:
        args.append("floor")
    merged = os.environ.copy()
    if env:
        merged.update({k: str(v) for k, v in env.items()})
    proc = subprocess.run(args, capture_output=True, text=True, env=merged)
    values = {}
    for line in proc.stdout.splitlines():
        if "=" in line:
            key, value = line.split("=", 1)
            values[key] = value
    return proc.returncode, values, proc.stdout, proc.stderr


PLAIN = {
    "SA_OS_MIB": 200, "SA_DB_BASE_MIB": 120, "SA_PHP_MASTER_MIB": 15,
    "SA_NGINX_MIB": 10, "SA_OPCACHE_MIB": 32, "SA_SAFETY_MIB": 0,
    "SA_WORKER_MIB": 0, "SA_REDIS_SESSIONS_MIB": 0,
    "SA_REDIS_CACHE_MIB": 0, "SA_PHP_CHILD_MIB": 32,
    "SA_WORKER_DB_CONNECTIONS": 0,
}


class TuningContract(unittest.TestCase):
    # T1: reserve decomposition; plain primary has no lean safety reserve.
    def test_T1_reserve_decomposition(self):
        rc, v, *_ = run(512, 0, "lean", env=PLAIN)
        self.assertEqual(rc, 0)
        keys = ("reserve_os_mib", "reserve_db_base_mib", "reserve_php_master_mib",
                "reserve_nginx_mib", "reserve_opcache_mib", "reserve_safety_mib",
                "reserve_worker_mib", "reserve_redis_sessions_mib",
                "reserve_redis_cache_mib")
        self.assertEqual(sum(int(v[k]) for k in keys), int(v["reserve_mib"]))
        self.assertEqual(v["reserve_safety_mib"], "0")

    # T2: usable memory includes half swap, capped at one quarter RAM.
    def test_T2_swap_usable_ceiling(self):
        rc, v, *_ = run(512, 512, "lean", env=PLAIN)
        self.assertEqual(rc, 0)
        self.assertEqual((v["usable_mib"], v["ceiling_mib"]), ("640", "576"))

    # T3: pinned 512 MiB no-swap lean result.
    def test_T3_512_no_swap(self):
        rc, v, *_ = run(512, 0, "lean", env=PLAIN)
        self.assertEqual(rc, 0)
        self.assertEqual((v["max_children"], v["buffer_pool_mib"]), ("1", "48"))
        self.assertEqual(v["warning"], "concurrency_1")

    # T4: pinned 512 MiB RAM + 512 MiB swap lean result.
    def test_T4_512_swap512(self):
        rc, v, *_ = run(512, 512, "lean", env=PLAIN)
        self.assertEqual(rc, 0)
        self.assertEqual((v["max_children"], v["buffer_pool_mib"]), ("4", "64"))

    # T5: 1 GiB no-swap allows four children and the largest lean buffer.
    def test_T5_1024_no_swap(self):
        rc, v, *_ = run(1024, 0, "lean", env=PLAIN)
        self.assertEqual(rc, 0)
        self.assertEqual((v["max_children"], v["buffer_pool_mib"]), ("4", "64"))

    # T6: policy floor does not replace arithmetic refusal.
    def test_T6_wordpress_low_ram_is_arithmetic_refusal(self):
        env = {**PLAIN, "SA_WORKLOAD": "wordpress", "SA_PHP_CHILD_MIB": 128, "SA_WORKER_MIB": 64}
        rc, v, *_ = run(512, 0, "lean", env=env)
        self.assertNotEqual(rc, 0)
        self.assertIn(v.get("error"), {"no_room_after_fixed", "no_candidate_fits"})

    # T7: fixed worker and Redis costs are included in reserve output.
    def test_T7_xcart_fixed_cost_decomposition(self):
        env = {**PLAIN, "SA_WORKLOAD": "xcart_5_6", "SA_WORKER_MIB": 128, "SA_REDIS_SESSIONS_MIB": 32,
               "SA_REDIS_CACHE_MIB": 64, "SA_SAFETY_MIB": 140}
        rc, v, *_ = run(512, 512, "lean", env=env)
        self.assertNotEqual(rc, 0)
        self.assertEqual(v["reserve_worker_mib"], "128")
        self.assertEqual(v["reserve_redis_sessions_mib"], "32")
        self.assertEqual(v["reserve_redis_cache_mib"], "64")
        self.assertEqual(v["error"], "no_room_after_fixed")

    # T8: guarded X-Cart workload can fit at 2 GiB with explicit costs.
    def test_T8_xcart_2048_standard(self):
        env = {**PLAIN, "SA_WORKLOAD": "xcart_5_6", "SA_WORKER_MIB": 128, "SA_REDIS_SESSIONS_MIB": 32,
               "SA_REDIS_CACHE_MIB": 64, "SA_SAFETY_MIB": 140}
        rc, v, *_ = run(2048, 0, "standard", env=env)
        self.assertEqual(rc, 0)
        self.assertGreaterEqual(int(v["max_children"]), 1)
        self.assertGreaterEqual(int(v["buffer_pool_mib"]), 128)

    # T9: below advisory floor may refuse only for arithmetic reasons.
    def test_T9_xcart_1536_advisory_or_arithmetic(self):
        env = {**PLAIN, "SA_WORKLOAD": "xcart_5_6", "SA_MIN_RAM_MIB": 2048,
               "SA_WORKER_MIB": 128, "SA_REDIS_SESSIONS_MIB": 32,
               "SA_REDIS_CACHE_MIB": 64, "SA_SAFETY_MIB": 140}
        rc, v, *_ = run(1536, 0, "standard", env=env)
        self.assertEqual(v.get("warning"), "advisory_ram")
        if rc != 0:
            self.assertIn(v.get("error"), {"no_room_after_fixed", "buffer_pool_no_valid_range", "no_candidate_fits"})

    # T10: slave_web defaults to no local MariaDB base cost.
    def test_T10_slave_web_local_db_cost_can_be_zero(self):
        env = {k: v for k, v in PLAIN.items() if k != "SA_DB_BASE_MIB"}
        rc_primary, primary, *_ = run(512, 0, "lean", env=env)
        rc_slave, slave, *_ = run(512, 0, "lean", env={**env, "SA_ROLE": "slave_web"})
        self.assertEqual(rc_primary, 0)
        self.assertEqual(rc_slave, 0)
        self.assertEqual(primary["reserve_db_base_mib"], "120")
        self.assertEqual(slave["reserve_db_base_mib"], "0")
        self.assertEqual(int(primary["reserve_mib"]) - int(slave["reserve_mib"]), 120)

    # T11: worker database connections are included exactly once.
    def test_T11_worker_db_connections(self):
        env = {**PLAIN, "SA_WORKER_DB_CONNECTIONS": 4}
        rc, v, *_ = run(512, 512, "lean", env=env)
        self.assertEqual(rc, 0)
        self.assertEqual(v["max_connections"], str(int(v["max_children"]) * 2 + 4 + 5))

    # T12: auto profile boundary.
    def test_T12_auto_profile_boundary(self):
        rc1, v1, *_ = run(2047, 4096, "auto", env=PLAIN)
        rc2, v2, *_ = run(2048, 4096, "auto", env=PLAIN)
        self.assertEqual(v1["profile"], "lean")
        self.assertEqual(v2["profile"], "standard")

    # T13: standard buffer-pool lower boundary 639/640/641.
    def test_T13_buffer_pool_lower_boundary(self):
        # Fixtures derive db_available from the specified 40/60 PHP/DB split.
        fixtures = ((639, 1064, None), (640, 1066, 128), (641, 1067, 129))
        for db, remaining, expected in fixtures:
            reserve = 3686 - remaining
            rc, v, *_ = run(4096, 0, "standard", env={**PLAIN, "SA_OS_MIB": reserve,
                "SA_DB_BASE_MIB": 0, "SA_PHP_MASTER_MIB": 0, "SA_NGINX_MIB": 0,
                "SA_OPCACHE_MIB": 0})
            if expected is None:
                self.assertNotEqual(rc, 0)
            else:
                self.assertEqual(rc, 0)
                self.assertEqual(int(v["buffer_pool_mib"]), expected)

    # T14: standard upper/raw clamp crossover and large values.
    def test_T14_buffer_pool_upper_and_raw(self):
        cases = ((854, 1422, 342), (1280, 2132, 768),
                 (1281, 2134, 768), (2000, 3332, 1200))
        for db, remaining, expected in cases:
            reserve = 3686 - remaining - 57
            env = {**PLAIN, "SA_OS_MIB": reserve, "SA_DB_BASE_MIB": 0,
                   "SA_PHP_MASTER_MIB": 15, "SA_NGINX_MIB": 10, "SA_OPCACHE_MIB": 32}
            rc, v, *_ = run(4096, 0, "standard", env=env)
            self.assertEqual(rc, 0)
            self.assertEqual(int(v["buffer_pool_mib"]), expected)

    # T15: unknown workload is rejected rather than silently defaulted.
    def test_T15_unknown_workload(self):
        rc, v, *_ = run(512, 0, "lean", env={**PLAIN, "SA_WORKLOAD": "mystery"})
        self.assertNotEqual(rc, 0)
        self.assertEqual(v["error"], "unknown_workload")

    # T16: unknown role is rejected rather than silently defaulted.
    def test_T16_unknown_role(self):
        rc, v, *_ = run(512, 0, "lean", env={**PLAIN, "SA_ROLE": "database_slave"})
        self.assertNotEqual(rc, 0)
        self.assertEqual(v["error"], "unknown_role")

    # T17: independent Redis overrides are consumed independently.
    def test_T17_redis_overrides_independent(self):
        env = {**PLAIN, "SA_REDIS_SESSIONS_MIB": 20, "SA_REDIS_CACHE_MIB": 40}
        rc, v, *_ = run(512, 512, "lean", env=env)
        self.assertEqual(rc, 0)
        self.assertEqual((v["reserve_redis_sessions_mib"], v["reserve_redis_cache_mib"]), ("20", "40"))

    # T18: external/disabled Redis has zero local memory cost.
    def test_T18_external_redis_zero_local_cost(self):
        env = {**PLAIN, "SA_REDIS_SESSIONS_MIB": 0, "SA_REDIS_CACHE_MIB": 0}
        rc, v, *_ = run(512, 0, "lean", env=env)
        self.assertEqual(rc, 0)
        self.assertEqual(v["reserve_redis_sessions_mib"], "0")
        self.assertEqual(v["reserve_redis_cache_mib"], "0")

    # T19: strict numeric lexical validation.
    def test_T19_numeric_lexical_rejections(self):
        for value in ("", "-1", "+1", "1.0", " 1", "01", "1x"):
            rc, v, *_ = run(value, 0, "lean", env=PLAIN)
            self.assertNotEqual(rc, 0, value)
            self.assertEqual(v.get("error"), "invalid_numeric_input", value)

    # T20: reject values outside the supported unsigned range.
    def test_T20_numeric_overflow(self):
        for value in (4294967296, "18446744073709551616", "9" * 100):
            rc, v, *_ = run(value, 0, "lean", env=PLAIN)
            self.assertNotEqual(rc, 0)
            self.assertEqual(v["error"], "numeric_input_overflow")

    # T21: zero child RSS is invalid.
    def test_T21_zero_child_rss(self):
        rc, v, *_ = run(512, 0, "lean", env={**PLAIN, "SA_PHP_CHILD_MIB": 0})
        self.assertNotEqual(rc, 0)
        self.assertEqual(v["error"], "invalid_child_rss")

    # T22: arithmetic refusal is reported, not converted into policy success.
    def test_T22_refusal_is_explicit(self):
        rc, v, *_ = run(256, 0, "lean", env={**PLAIN, "SA_MIN_RAM_MIB": 1024})
        self.assertNotEqual(rc, 0)
        self.assertEqual(v["warning"], "advisory_ram")
        self.assertEqual(v["error"], "no_room_after_fixed")

    # T23: advisory policy metadata does not enter arithmetic reserve.
    def test_T23_policy_floor_not_a_fixed_cost(self):
        rc, v, *_ = run(512, 512, "lean", env={**PLAIN, "SA_MIN_RAM_MIB": 1024})
        self.assertEqual(rc, 0)
        self.assertEqual(v["reserve_mib"], "377")
        self.assertEqual(v["warning"], "advisory_ram")

    # T24: explicit fixed-cost override is used exactly once.
    def test_T24_db_base_override(self):
        rc, v, *_ = run(512, 0, "lean", env={**PLAIN, "SA_DB_BASE_MIB": 80})
        self.assertEqual(rc, 0)
        self.assertEqual(v["reserve_db_base_mib"], "80")
        self.assertEqual(v["reserve_mib"], "337")

    # T25: environment values are parsed as numbers, never evaluated as shell.
    def test_T25_shell_syntax_is_data_not_executed(self):
        marker = pathlib.Path("/tmp/stackalign-tune-injection-marker")
        marker.unlink(missing_ok=True)
        rc, v, *_ = run(512, 0, "lean", env={**PLAIN, "SA_OS_MIB": "$(touch /tmp/stackalign-tune-injection-marker)"})
        self.assertNotEqual(rc, 0)
        self.assertFalse(marker.exists())
        self.assertEqual(v["error"], "invalid_numeric_input")

    # T26: valid standard pool is reported even when PHP cannot fit one child.
    def test_T26_pool_reported_when_no_php_child_fits(self):
        env = {**PLAIN, "SA_OS_MIB": 1800, "SA_DB_BASE_MIB": 0,
               "SA_PHP_MASTER_MIB": 0, "SA_NGINX_MIB": 0, "SA_OPCACHE_MIB": 0,
               "SA_PHP_CHILD_MIB": 500}
        rc, v, *_ = run(3388, 0, "standard", env=env)
        self.assertNotEqual(rc, 0)
        self.assertEqual(v["error"], "no_candidate_fits")
        self.assertEqual(v["buffer_pool_mib"], "238")

    # T27: exact lean arithmetic floor.
    def test_T27_lean_floor_391(self):
        env = {**PLAIN, "SA_OS_MIB": 200, "SA_DB_BASE_MIB": 120,
               "SA_PHP_MASTER_MIB": 15, "SA_NGINX_MIB": 10,
               "SA_OPCACHE_MIB": 32, "SA_PHP_CHILD_MIB": 30}
        rc390, *_ = run(390, 4096, "lean", env=env)
        rc391, v391, *_ = run(391, 4096, "lean", env=env)
        self.assertNotEqual(rc390, 0)
        self.assertEqual(rc391, 0)
        self.assertEqual((v391["max_children"], v391["buffer_pool_mib"]), ("1", "32"))
        rc, vf, *_ = run(391, 4096, "lean", env=env, floor=True)
        self.assertEqual(rc, 0)
        self.assertEqual(vf["arithmetic_floor_mib"], "391")

    # T28: auto profile standard floor 3389 and its two preceding boundaries.
    def test_T28_standard_floor_3389(self):
        env = {**PLAIN, "SA_OS_MIB": 1800, "SA_DB_BASE_MIB": 0,
               "SA_PHP_MASTER_MIB": 0, "SA_NGINX_MIB": 0, "SA_OPCACHE_MIB": 0,
               "SA_PHP_CHILD_MIB": 500}
        rc2047, v2047, *_ = run(2047, 0, "auto", env=env)
        rc2048, v2048, *_ = run(2048, 0, "auto", env=env)
        rc3388, v3388, *_ = run(3388, 0, "auto", env=env)
        rc3389, v3389, *_ = run(3389, 0, "auto", env=env)
        self.assertNotEqual(rc2047, 0)
        self.assertEqual(v2047["profile"], "lean")
        self.assertNotEqual(rc2048, 0)
        self.assertEqual(v2048["error"], "buffer_pool_no_valid_range")
        self.assertNotEqual(rc3388, 0)
        self.assertEqual(v3388["error"], "no_candidate_fits")
        self.assertEqual(rc3389, 0)
        self.assertEqual(v3389["buffer_pool_mib"], "238")
        rc, vf, *_ = run(3389, 0, "auto", env=env, floor=True)
        self.assertEqual(rc, 0)
        self.assertEqual(vf["arithmetic_floor_mib"], "3389")


if __name__ == "__main__":
    unittest.main(verbosity=2)
