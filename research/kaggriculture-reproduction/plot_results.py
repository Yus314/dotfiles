"""Standalone plots of the frozen evaluation (matplotlib optional)."""

import json
from pathlib import Path
import numpy as np
import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt

ROOT = Path(__file__).parent
REPORTS = ROOT / "reports"


def main():
    summary = json.loads((REPORTS / "summary.json").read_text())
    rates = summary["teacher"]["rates"]
    ops = summary["teacher"]["by_operation"]
    natural = json.loads((REPORTS / "final-rollout-endogenous.json").read_text())
    fixed = json.loads((REPORTS / "final-rollout-recorded.json").read_text())
    fixed = {r["episode"]: r for r in fixed}
    plt.rcParams.update(
        {
            "font.family": "DejaVu Sans",
            "axes.spines.top": False,
            "axes.spines.right": False,
            "font.size": 10,
        }
    )
    fig = plt.figure(figsize=(12, 8), layout="constrained")
    grid = fig.add_gridspec(2, 2, height_ratios=[1, 1.2])
    a = fig.add_subplot(grid[0, 0])
    b = fig.add_subplot(grid[0, 1])
    c = fig.add_subplot(grid[1, :])
    labels = ["All worker actions", "Nonmovement actions", "Entire market-order list"]
    values = [rates["unit"], rates["nonmovement"], rates["market_exact"]]
    a.barh(labels, [v * 100 for v in values], color=["#2b6cb0", "#2b6cb0", "#d18020"])
    a.invert_yaxis()
    a.set_xlim(0, 110)
    a.set_xlabel("Exact match (%)")
    a.set_title("Same observations as the original agent", loc="left", weight="bold")
    for i, v in enumerate(values):
        a.text(v * 100 + 1.5, i, f"{v * 100:.1f}%", va="center")
    selection = ["FEED", "WATER", "HARVEST", "MOVE", "PLANT", "PICKUP"]
    values = []
    for op in selection:
        names = ["NORTH", "WEST", "SOUTH", "EAST"] if op == "MOVE" else [op]
        values.append(
            sum(ops[k]["correct"] for k in names) / sum(ops[k]["total"] for k in names)
        )
    b.barh(selection, [v * 100 for v in values], color="#548375")
    b.invert_yaxis()
    b.set_xlim(0, 110)
    b.set_xlabel("Exact match including item and quantity (%)")
    b.set_title("Where behavior still differs", loc="left", weight="bold")
    for i, v in enumerate(values):
        b.text(v * 100 + 1.5, i, f"{v * 100:.1f}%", va="center")
    x = np.arange(len(natural))
    w = 0.25
    c.bar(
        x - w,
        [r["reference_target_money"] / 1000 for r in natural],
        w,
        label="Original replay",
        color="#9aa3ae",
    )
    c.bar(
        x,
        [fixed[r["episode"]]["target_money"] / 1000 for r in natural],
        w,
        label="Replica / recorded shops",
        color="#2b6cb0",
    )
    c.bar(
        x + w,
        [r["target_money"] / 1000 for r in natural],
        w,
        label="Replica / endogenous shops",
        color="#d18020",
    )
    c.set_xticks(x, [str(r["episode"]) for r in natural])
    c.set_ylabel("Final cash (thousands)")
    c.set_xlabel("Previously unused episode")
    c.set_title(
        "Autonomous play with recorded opponent actions", loc="left", weight="bold"
    )
    c.legend(frameon=False, ncol=3, loc="upper right")
    c.set_ylim(0, 165)
    fig.suptitle(
        "Kaggriculture reproduction v7 | 8 unseen episodes | 57,642 worker decisions",
        fontsize=15,
        weight="bold",
    )
    fig.text(
        0.5,
        -0.02,
        "Cash ratios are diagnostic comparisons, not action-reproduction rates or live leaderboard performance.",
        ha="center",
        fontsize=10,
        color="#4a5568",
    )
    fig.savefig(REPORTS / "evaluation-overview.png", dpi=180, bbox_inches="tight")
    fig.savefig(REPORTS / "evaluation-overview.pdf", bbox_inches="tight")
    plt.close(fig)


if __name__ == "__main__":
    main()
