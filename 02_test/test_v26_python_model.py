"""Numerical contract checks for the MATLAB-to-Python reference port."""
import importlib.util
import sys
import unittest
from dataclasses import replace
from pathlib import Path

import numpy as np

MODEL = Path(__file__).resolve().parents[1] / "01_bench" / "full_demo_v26_clt_awgn_fixed_paper.py"
SPEC = importlib.util.spec_from_file_location("v26_model", MODEL)
model = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = model
SPEC.loader.exec_module(model)


class NumericalContracts(unittest.TestCase):
    def test_matlab_rounding_at_half_lsb(self):
        np.testing.assert_array_equal(model.q_from_real(np.array([-1.5, -0.5, 0.5, 1.5]) / 4096), [-2, -1, 1, 2])

    def test_multiply_truncates_negative_toward_minus_infinity(self):
        self.assertEqual(int(model.q_mul(-1, 2048)), -1)
        np.testing.assert_array_equal(model.q_from_real([-100, 100]), [-32768, 32767])

    def test_unsigned_taus88_manually_derived_first_two_words(self):
        word, a, b, c = model.taus88_step(2, 8, 16)
        self.assertEqual((word, a, b, c), (2105472, 8192, 128, 2097152))
        word, a, b, c = model.taus88_step(a, b, c)
        self.assertEqual((word, a, b, c), (33565824, 33554560, 2048, 9216))

    def test_lane_center_gain_and_prefix_reproducibility(self):
        cfg = model.Config()
        self.assertEqual(model.clt_parameters(cfg), (24570, 4096))
        self.assertEqual(model.stage1_offsets(12, 12), [0, 4, 8, 12, 16, 20, 3, 7, 11, 15, 19, 2])
        short, debug = model.generate_clt(16, cfg)
        long, _ = model.generate_clt(32, cfg)
        np.testing.assert_array_equal(short, long[:16])
        np.testing.assert_array_equal(short, debug["uniforms"].sum(axis=1).astype(np.int64) - 24570)

    def test_slicer_ties_match_source_and_documented_alternative(self):
        cfg = model.Config()
        values = np.array([-2, 0, 2]) * 4096
        np.testing.assert_array_equal(model.pam_slice_fx(values, cfg), [-3, -1, 1])
        np.testing.assert_array_equal(model.pam_slice_fx(values, replace(cfg, slicer_ties="upper")), [-1, 1, 3])

    def test_gray_adjacent_errors_cost_one_bit(self):
        counts = model.error_counts(np.array([-3, -1, 1]), np.array([-1, 1, 3]))
        self.assertEqual(counts["bit_errors"], 3)
        self.assertEqual(counts["symbol_errors"], 3)

    def test_uniform_symbol_pairs_match_analytic_uncorrected_isi_ber(self):
        # h0=1, h1=.5: six of the sixteen equally likely (previous,current)
        # pairs cross one adjacent threshold, hence BER=6/32=3/16.
        current = np.tile(model.LEVELS, 4)
        previous = np.repeat(model.LEVELS, 4)
        received = model.q_from_real(current + 0.5 * previous)
        counts = model.error_counts(current, model.pam_slice_fx(received, model.Config()))
        self.assertEqual(counts["symbol_errors"], 6)
        self.assertEqual(counts["ber"], 3 / 16)

    def test_perfect_delayed_link_exposes_legacy_baseline_alignment_bug(self):
        cfg = model.Config(isi=0, mu=0, init_main_tap=1, train_len=16, adapt=False)
        symbols = model.make_symbols(512, 1)
        result = model.run_case(symbols, np.zeros(512, dtype=np.int64), cfg, "plain", use_noise=False, debug_samples=0)
        self.assertEqual(result["metrics"]["noeq"]["bit_errors"], 0)
        self.assertEqual(result["metrics"]["eq"]["bit_errors"], 0)
        self.assertGreater(result["metrics"]["legacy_noeq"]["ber"], 0.4)

    def test_known_dfe_taps_cancel_half_postcursor_exactly(self):
        cfg = model.Config(train_len=16, adapt=False)
        symbols = model.make_symbols(512, 7)
        result = model.run_case(symbols, np.zeros(512, dtype=np.int64), cfg, "plain", use_noise=False,
                                initial_w=[0, 4096, 0], initial_b=[2048], debug_samples=0)
        np.testing.assert_array_equal(result["core"]["y_fx"][2:], symbols[1:-1] * 4096)
        self.assertEqual(result["metrics"]["eq"]["bit_errors"], 0)
        self.assertEqual(result["core"]["counters"]["updates"], 0)

    def test_projection_bounds_visible_taps(self):
        cfg = model.Config(train_len=64, mu=0.5, w_min=-0.25, w_max=0.25, b_min=-0.125, b_max=0.125)
        symbols = model.make_symbols(128, 3)
        result = model.run_case(symbols, np.zeros(128, dtype=np.int64), cfg, "robust_proj", use_noise=False)
        self.assertGreater(result["core"]["counters"]["projection_hits"], 0)
        self.assertTrue(all(abs(v) <= 1024 for v in result["core"]["w_fx"]))
        self.assertTrue(all(abs(v) <= 512 for v in result["core"]["b_fx"]))

    def test_hand_calculated_q20_update_and_feedback_sign(self):
        # n=1 has y=e=0 and slices to -1. At n=2, y=2.25,
        # desired=3, e=.75, mu_acc=524. The Q20 deltas are
        # [round(524*.75*4.5), 524*.75*3, 0] = [1769,1179,0].
        # Feedback uses -delta_b, hence b_acc=393 and visible b=2.
        cfg = model.Config(train_len=2)
        result = model.dfe_core(np.array([12288, 18432]), np.array([12288, 12288]), cfg, debug_samples=2)
        self.assertEqual(result["w_fx"], [7, 3077, 0])
        self.assertEqual(result["b_fx"], [2])
        np.testing.assert_array_equal(result["y_fx"], [0, 9216])

    def test_sm_sign_censors_zero_error_updates(self):
        cfg = model.Config(isi=0, init_main_tap=1, train_len=64)
        symbols = model.make_symbols(128, 5)
        result = model.run_case(symbols, np.zeros(128, dtype=np.int64), cfg, "sm_sign", use_noise=False)
        self.assertEqual(result["core"]["counters"]["updates"], 0)
        self.assertEqual(result["core"]["counters"]["sm_sign_skips"], 128)

    def test_tap_history_preserves_update_timing_and_exact_final_sample(self):
        cfg = model.Config(train_len=2)
        result = model.dfe_core(np.array([12288, 18432]), np.array([12288, 12288]), cfg,
                                debug_samples=2, store_tap_history=True)
        np.testing.assert_array_equal(result["tap_after_fx"], [[0, 3072, 0, 0], [7, 3077, 0, 2]])
        summary = model.adaptive_tap_summary(dict(core=result), cfg)
        self.assertEqual([row["final_after_update_fx"] for row in summary["taps"]], [7, 3077, 0, 2])
        self.assertEqual([row["used_for_last_output_fx"] for row in summary["taps"]], [0, 3072, 0, 0])

    def test_signal_window_aligns_equalized_output_with_the_same_tx_symbol(self):
        cfg = model.Config(train_len=16, adapt=False)
        symbols = model.make_symbols(128, 7)
        result = model.run_case(symbols, np.zeros(128, dtype=np.int64), cfg, "plain", use_noise=False,
                                initial_w=[0, 4096, 0], initial_b=[2048], debug_samples=0)
        window = model.signal_window(result, cfg, count=32, start=32)
        np.testing.assert_array_equal(window["eq_sample"], window["tx_sample"] + 1)
        np.testing.assert_array_equal(window["y"], window["tx"])
        np.testing.assert_array_equal(window["decision"], window["tx"])
        self.assertTrue(window["after_training"])


if __name__ == "__main__":
    unittest.main()
