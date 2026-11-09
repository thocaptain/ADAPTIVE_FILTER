"""Compare actual Verilator CSV against the pre-existing Python numerical model."""
import csv
import ast
import math
import json
from pathlib import Path
import sys

root = Path(__file__).resolve().parents[2]
source = root / "01_bench/full_demo_v26_clt_awgn_fixed_paper.py"
# Execute the actual scalar reference functions, without importing its optional
# NumPy/SciPy simulation/plotting dependencies. No source text is modified.
names = {"seed_mix32", "taus88_step", "stage1_offsets", "sat_scalar"}
tree = ast.parse(source.read_text(encoding="utf-8"))
selected = [node for node in tree.body if isinstance(node, ast.FunctionDef) and node.name in names]
if len(selected) != len(names):
    raise RuntimeError("Scalar reference functions missing from existing model")
reference = {"MASK32": (1 << 32)-1, "math": math}
exec(compile(ast.Module(body=selected, type_ignores=[]), str(source), "exec"), reference)
with Path(sys.argv[1]).open(newline="") as stream:
    rows = list(csv.DictReader(stream))
config = json.loads(Path("capture_config.json").read_text())
sigma_q12 = config["sigma_q12"]
if len(rows) != 4096:
    raise RuntimeError(f"Expected 4096 captured samples, got {len(rows)}")
offsets = reference["stage1_offsets"](12, 12)
states = []
for lane in range(1, 13):
    state = []
    for factor, bias, minimum in [(101, 1, 2), (211, 3, 8), (307, 7, 16)]:
        value = reference["seed_mix32"](0x0A5B + factor*lane + bias)
        state.append(value + minimum if value < minimum else value)
    states.append(state)
for index, row in enumerate(rows):
    total = 0
    for lane, offset in enumerate(offsets):
        word, *states[lane] = reference["taus88_step"](*states[lane])
        rotated = ((word << 11) & reference["MASK32"]) | (word >> 21)
        total += ((word ^ (word >> 7) ^ rotated) >> offset) & 4095
    expected = reference["sat_scalar"](((total - 24570) * sigma_q12) // 4096)
    tx, clean, actual, channel = (int(row[k]) for k in
                                 ("tx_q12", "clean_q12", "noise_q12", "channel_q12"))
    if int(row["sample"]) != index or clean != tx or actual != int(expected):
        raise RuntimeError(f"Python reference mismatch at sample {index}")
    if channel != reference["sat_scalar"](tx + int(expected)):
        raise RuntimeError(f"Channel sum mismatch at sample {index}")
print(f"PASS: {len(rows)} Verilator samples match Python reference recurrences/mixing bit for bit.")
