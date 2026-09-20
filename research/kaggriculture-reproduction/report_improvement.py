"""Summarize the predeclared v7/v8 comparison, including failed candidates."""

import collections
import json
from pathlib import Path

import numpy as np

ROOT = Path(__file__).parent
OUT = ROOT / "reports" / "improvement"


def read(name):
    return json.loads((OUT / name).read_text())


def grouped(rows):
    groups = collections.defaultdict(list)
    for row in rows:
        groups[row["variant"]].append(row)
    return groups


def agreement(rows):
    correct, total = collections.Counter(), collections.Counter()
    for row in rows:
        correct.update(row["teacher"]["correct"])
        total.update(row["teacher"]["total"])
    return {
        "correct": dict(correct),
        "total": dict(total),
        "rate": {k: correct[k] / n for k, n in total.items()},
    }


def paired(rows):
    groups = grouped(rows)
    a = {r["rollout"]["episode"]: r["rollout"] for r in groups["v7"]}
    b = {r["rollout"]["episode"]: r["rollout"] for r in groups["v8"]}
    assert set(a) == set(b) and len(a) == 12
    ids = sorted(a)
    delta = np.array([b[i]["target_money"] - a[i]["target_money"] for i in ids])
    rng = np.random.default_rng(20260920)
    ci = np.percentile(
        rng.choice(delta, size=(20000, len(delta))).mean(axis=1), [2.5, 97.5]
    )
    means = {
        v: np.mean([r["rollout"]["target_money"] for r in rs])
        for v, rs in groups.items()
    }
    diagnostics = {}
    for v, rs in groups.items():
        ds = [r["rollout"]["diagnostics"] for r in rs]
        diagnostics[v] = {
            "mean_income": float(np.mean([d["income"] for d in ds])),
            "mean_cost": float(np.mean([d["cost"] for d in ds])),
            "mean_animal_spending": float(
                np.mean(
                    [
                        sum(
                            x["coins"]
                            for k, x in d["ledger"].items()
                            if k.startswith("BUY_ANIMAL:")
                        )
                        for d in ds
                    ]
                )
            ),
            "mean_escapes": float(
                np.mean(
                    [
                        sum(
                            x
                            for k, x in d["losses"].items()
                            if k.startswith("escaped_")
                        )
                        for d in ds
                    ]
                )
            ),
        }
        assert all(d["cash_identity_verified"] for d in ds)
    return {
        "n": len(ids),
        "mean_cash": means,
        "relative_mean_gain": means["v8"] / means["v7"] - 1,
        "mean_paired_gain": float(delta.mean()),
        "median_paired_gain": float(np.median(delta)),
        "positive_pairs": int((delta > 0).sum()),
        "negative_pairs": int((delta < 0).sum()),
        "tied_pairs": int((delta == 0).sum()),
        "paired_bootstrap_mean_gain_95pct": ci.tolist(),
        "diagnostics": diagnostics,
        "episodes": [
            {
                "episode": i,
                "v7": a[i]["target_money"],
                "v8": b[i]["target_money"],
                "original": b[i]["reference_target_money"],
            }
            for i in ids
        ],
    }


def main():
    recorded_rows = read("validation-recorded.json")
    endogenous_rows = read("validation-endogenous.json")
    recorded, normal = paired(recorded_rows), paired(endogenous_rows)
    teacher = {v: agreement(rs) for v, rs in grouped(recorded_rows).items()}
    accepted = all(x["relative_mean_gain"] > 0 for x in [recorded, normal])
    summary = {
        "candidate_version": "v8",
        "accepted_as_default": accepted,
        "recorded": recorded,
        "endogenous": normal,
        "teacher": teacher,
    }
    (OUT / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")
    dev = grouped(
        sum((read(f"development-{p}.json") for p in ["crop", "livestock", "care"]), [])
    )
    dev_normal = grouped(read("development-normal-dev.json"))
    dev_lines = []
    for v in ["v7", "slack4", "soft2", "purchase_cap", "care2", "cap_care2"]:
        cash = np.mean([x["rollout"]["target_money"] for x in dev[v]])
        other = (
            f"{np.mean([x['rollout']['target_money'] for x in dev_normal[v]]):,.0f}"
            if v in dev_normal
            else "未評価"
        )
        dev_lines.append(f"| {v} | {cash:,.0f} | {other} |")
    pairs = {r["episode"]: r for r in normal["episodes"]}
    final_lines = [
        f"| {r['episode']} | {r['v7']:,.0f} | {r['v8']:,.0f} | {pairs[r['episode']]['v7']:,.0f} | {pairs[r['episode']]['v8']:,.0f} |"
        for r in recorded["episodes"]
    ]
    metric_lines = []
    for label, s in [("店舗順固定", recorded), ("通常ルール", normal)]:
        lo, hi = s["paired_bootstrap_mean_gain_95pct"]
        metric_lines.append(
            f"| {label} | {s['mean_cash']['v7']:,.0f} | {s['mean_cash']['v8']:,.0f} | {s['relative_mean_gain']:+.2%} | {s['positive_pairs']}/12 | {lo:+,.0f} 〜 {hi:+,.0f} |"
        )
    t7, t8 = teacher["v7"], teacher["v8"]
    disposition = (
        "事前に定めた両条件の平均収益改善を満たし、v8 を既定版に採用した。"
        if accepted
        else "事前に定めた両条件の平均収益改善を満たさなかったため、v7 を既定版に維持する。v8 は評価済み候補として保存する。"
    )
    text = f"""# v8 改善実験と未使用試合での検証

{disposition} 対象は Majkel1337 / submission 56216119。完全再現には引き続き未達。

**変更点**

家畜の購入判断に、現在観測できる農場・倉庫・作業者の所持数の合計が増えた履歴を加えた。逃げた家畜で現在数が減っても、以前と同じ目標数まで自動的に買い戻さず、累積の取得数と目標の差までに抑える。将来の目標が増えれば追加購入できる。配置・運搬は取得として数えず、購入注文が失敗した場合も取得済みとはみなさない。同じターンに取得と損失が相殺される場合には純増分だけを数えるため、厳密な購入台帳ではない。

履歴はプレイヤーごとに分離し、試合開始や観測の不連続で初期化する。プロセスが再起動した場合も現在数から再開できるが、それ以前の損失履歴は失われる。学習済み重み・特徴量・50 試合の学習データは v7 と同一。採用した設定は `animal_purchase_cap=true`、その他の改善候補は無効。

**開発用6試合での選択**

| 候補 | 平均資金・店舗順固定 | 平均資金・通常ルール |
|---|---:|---:|
{chr(10).join(dev_lines)}

`slack4` は作付け目標に4株の余裕を加える案、`soft2` は目標超過を禁止せず評価値を下げる案。植え付け一致率は上がったが、自律実行の平均収益が下がったため棄却した。`care2` は枯死・逃走の期限が迫る給餌・水やりの優先度を上げる案、`cap_care2` はそれと購入抑制を組み合わせた案。両条件で平均収益が最大だった `purchase_cap` を選んだ。

開発の行動一致は3ターンに1回、最終評価は全ターン。開発の絶対値を最終評価と直接比較しない。購入履歴も間引き観測では再初期化されるため、市場への影響の判定には連続した自律実行と最終評価を用いる。

**未使用12試合の比較**

以前に解析した72試合を除き、公開対戦の時系列を12層に分け固定乱数で各1試合を選んだ。候補選択前に manifest を固定し、候補のコード・重みを凍結した後に評価を開始した。v7 は保存済みの元コードを読み込んだ。評価を見てから係数を変えていない。

| 条件 | v7 平均資金 | v8 平均資金 | 増減 | 改善した試合 | 平均差の95%区間 |
|---|---:|---:|---:|---:|---:|
{chr(10).join(metric_lines)}

95%区間は試合単位の対応付きブートストラップ20,000回による参考値。12試合の小標本で、同一投稿の対戦同士にも関連がある。区間が0を含む場合、平均の改善だけで安定した優位を証明したとは扱わない。

作業者行動の完全一致は v7 **{t7["rate"]["unit"]:.2%}** → v8 **{t8["rate"]["unit"]:.2%}**（v8: {t8["correct"]["unit"]:,} / {t8["total"]["unit"]:,}）。市場注文リスト全体の一致は **{t7["rate"]["market_exact"]:.2%}** → **{t8["rate"]["market_exact"]:.2%}**。収益の改善と元 agent の厳密な行動再現は別の指標である。

![v7とv8の対応付き比較](reports/improvement/paired-cash.png)

店舗順固定では、1試合平均の家畜購入費が {recorded["diagnostics"]["v7"]["mean_animal_spending"]:,.0f} → {recorded["diagnostics"]["v8"]["mean_animal_spending"]:,.0f}、逃走数が {recorded["diagnostics"]["v7"]["mean_escapes"]:.2f} → {recorded["diagnostics"]["v8"]["mean_escapes"]:.2f} に減った。一方、売上は {recorded["diagnostics"]["v7"]["mean_income"]:,.0f} → {recorded["diagnostics"]["v8"]["mean_income"]:,.0f} に下がった。支出削減が生産機会も減らすため、単純な購入抑制だけでは安定した改善にならなかった。次の検討では、失った個体の買い直しを一律に止めず、残り期間の生産額と給餌・作業の余力を合わせて判断する必要がある。

| episode | 店舗順固定 v7 | 店舗順固定 v8 | 通常 v7 | 通常 v8 |
|---|---:|---:|---:|---:|
{chr(10).join(final_lines)}

**指定試合と評価の限界**

指定された開発試合 111105944 では、店舗順固定で **74,514 → 81,898**、通常ルールで **71,293 → 66,818**。本家の記録資金は96,230。指定試合の通常ルールでは悪化しており、全試合が改善したわけではない。

相手は各試合に記録された行動列を実行する。非公開の元 agent を実行した結果でも、Leaderboard の勝率・順位推定でもない。通常ルールでは農場の変化に伴う乱数消費によって後続の店舗構成も変わる。店舗順固定はその影響を取り除く診断で、将来の店舗情報を agent に渡さない。候補の効用はこの評価条件の範囲に限られる。

**再現に必要なファイル**

- [未採用の v8 実装](baselines/v8-candidate/policy.py) / [v8 候補アーカイブ](baselines/v8-candidate/submission.tar.gz)。既定の [submission.tar.gz](submission.tar.gz) は v7 を維持。
- [候補固定時のハッシュ](reports/improvement/candidate-freeze.json) / [選定した12試合](v8-validation-manifest.json)
- [集計JSON](reports/improvement/summary.json) / [開発・最終評価の生の計測結果](reports/improvement/)
- [v7 の記録](baselines/v7/REPRODUCTION_REPORT.ja.md) / [v7 の実装](baselines/v7/policy.py)
- `compare_variants.py` と `v8-comparison-variants.json` で同じ対応付き比較を再実行できる。通常ルールは `--town endogenous --skip-teacher`、店舗固定と全ターン一致は `--stride 1` を指定する。

候補の動作テスト9件が通過。NumPy版と高速評価版は指定試合の全719手が一致した。未使用12試合の元リプレイも全8,628遷移を公式エンジンで再現できた。新しい seed 20260921 の候補同士の自律対戦は両席とも完走し、最終資金は128,970対119,752。これらは動作検証であり、競技上の優位を示すものではない。
"""
    (ROOT / "IMPROVEMENT_REPORT.ja.md").write_text(text)
    import matplotlib

    matplotlib.use("Agg")
    import matplotlib.pyplot as plt

    fig, axes = plt.subplots(1, 2, figsize=(12, 5))
    for ax, label, s in zip(
        axes,
        ["Recorded shop sequence (diagnostic)", "Endogenous shops (standard rules)"],
        [recorded, normal],
    ):
        a = np.array([r["v7"] for r in s["episodes"]]) / 1000
        b = np.array([r["v8"] for r in s["episodes"]]) / 1000
        lo, hi = min(a.min(), b.min()) * 0.9, max(a.max(), b.max()) * 1.05
        ax.plot([lo, hi], [lo, hi], "--", color="gray", linewidth=1)
        ax.scatter(
            a,
            b,
            c=np.where(b > a, "#16856b", np.where(b < a, "#cb5a43", "#888888")),
            s=60,
        )
        ax.set(
            xlim=(lo, hi),
            ylim=(lo, hi),
            xlabel="v7 final cash (thousands)",
            ylabel="v8 final cash (thousands)",
            title=label,
        )
        ax.text(
            0.04,
            0.95,
            f"Mean change {s['relative_mean_gain']:+.1%}\n{s['positive_pairs']}/12 improved",
            transform=ax.transAxes,
            va="top",
        )
    fig.suptitle("12 previously unused episodes; opponents execute recorded actions")
    fig.tight_layout()
    fig.savefig(OUT / "paired-cash.png", dpi=170)
    fig.savefig(OUT / "paired-cash.pdf")
    print(
        json.dumps(
            {
                "accepted": accepted,
                "recorded_gain": recorded["relative_mean_gain"],
                "normal_gain": normal["relative_mean_gain"],
            }
        )
    )


if __name__ == "__main__":
    main()
