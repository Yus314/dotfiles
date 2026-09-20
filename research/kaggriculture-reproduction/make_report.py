"""Aggregate frozen, episode-disjoint evaluations and copy auditable results."""

import collections, hashlib, json, shutil, statistics
from pathlib import Path

ROOT = Path(__file__).parent
ART = ROOT / "artifacts"
OUT = ROOT / "reports"
OUT.mkdir(exist_ok=True)


def read(name):
    return json.loads((ART / name).read_text())


def pct(x):
    return f"{100 * x:.2f}%"


def summary(rows):
    ratios = [r["fraction_of_reference"] for r in rows]
    return {
        "episodes": len(rows),
        "mean_cash": statistics.mean(r["target_money"] for r in rows),
        "mean_cash_ratio": statistics.mean(ratios),
        "median_cash_ratio": statistics.median(ratios),
        "min_cash_ratio": min(ratios),
        "max_cash_ratio": max(ratios),
        "wins_vs_recorded_actions": sum(r["margin"] > 0 for r in rows),
        "cash_identities_verified": all(
            r["diagnostics"]["cash_identity_verified"] for r in rows
        ),
    }


def main():
    teacher = read("final-teacher.json")
    natural = read("final-rollout-endogenous.json")
    recorded = read("final-rollout-recorded.json")
    adaptive = read("adaptive-new-seeds.json")
    exported = read("exported-specified.json")[0]
    specified = read("specified-recorded.json")[0]
    native = read("development-v7-endogenous.json")[0]
    freeze = json.loads((ROOT / "FREEZE.json").read_text())
    expected = set(freeze["final_test_episodes"])
    for rows in [teacher, natural, recorded]:
        assert {r["episode"] for r in rows} == expected
    for name, sha in freeze["runtime_sha256"].items():
        assert hashlib.sha256((ROOT / name).read_bytes()).hexdigest() == sha
    assert native["action_sha256"] == exported["action_sha256"]
    assert native["money"] == exported["money"]
    assert len(adaptive) == 3
    totals = collections.Counter()
    correct = collections.Counter()
    operations = collections.defaultdict(collections.Counter)
    for r in teacher:
        totals.update(r["total"])
        correct.update(r["correct"])
        for op, values in r["by_operation"].items():
            operations[op].update(values)
    rates = {k: correct[k] / n for k, n in totals.items()}
    manifests = [
        "sample-manifest.json",
        "additional-train-manifest.json",
        "pilot-final-test-manifest.json",
        "final-test-manifest.json",
    ]
    ids = set()
    for name in manifests:
        ids.update(e["id"] for e in json.loads((ROOT / name).read_text())["episodes"])
    source_hashes = {}
    verified = 0
    for eid in ids:
        audit = json.loads((ROOT / "data" / f"analysis-{eid}.json").read_text())
        verified += audit["verified_transitions"]
        source_hashes[str(eid)] = audit["source_sha256"]
    (ROOT / "DATA_SHA256.json").write_text(json.dumps(source_hashes, indent=2))
    result = {
        "model_version": freeze["model_version"],
        "teacher": {
            "correct": dict(correct),
            "total": dict(totals),
            "rates": rates,
            "by_operation": dict(operations),
        },
        "endogenous_town": summary(natural),
        "recorded_town": summary(recorded),
        "verified_replay_episodes": len(ids),
        "verified_transitions": verified,
        "exported_inference": {
            "runtime_mean": exported["runtime_mean"],
            "runtime_p95": exported["runtime_p95"],
            "runtime_max": exported["runtime_max"],
            "native_exported_action_sha256": exported["action_sha256"],
            "all_719_actions_identical": True,
        },
        "submission_not_sent": True,
    }
    (OUT / "summary.json").write_text(json.dumps(result, indent=2))
    names = [
        "final-teacher.json",
        "final-rollout-endogenous.json",
        "final-rollout-recorded.json",
        "adaptive-new-seeds.json",
        "exported-specified.json",
        "specified-recorded.json",
        "development-v7-endogenous.json",
        "pilot-v6-teacher.json",
        "pilot-v6-rollout-endogenous.json",
        "pilot-v6-rollout-recorded.json",
        "training-metrics.json",
        "refinement-metrics.json",
        "planning-metrics.json",
        "sales-metrics.json",
        "split.json",
        "tests-final.log",
    ]
    for name in names:
        shutil.copy2(ART / name, OUT / name)
    natural_by = {r["episode"]: r for r in natural}
    recorded_by = {r["episode"]: r for r in recorded}
    table = []
    for r in teacher:
        eid = r["episode"]
        a = natural_by[eid]
        b = recorded_by[eid]
        table.append(
            f"| {eid} | {pct(r['rate']['unit'])} | {a['reference_target_money']:,.0f} | {a['target_money']:,.0f} | {b['target_money']:,.0f} |"
        )
    op_table = "\n".join(
        f"| {op} | {v['correct']:,} / {v['total']:,} | {pct(v['correct'] / v['total'])} |"
        for op, v in sorted(operations.items(), key=lambda z: -z[1]["total"])
    )
    pilot = read("pilot-v6-teacher.json")
    pilot_rate = sum(r["correct"]["unit"] for r in pilot) / sum(
        r["total"]["unit"] for r in pilot
    )
    pilot_money = statistics.mean(
        r["target_money"] for r in read("pilot-v6-rollout-endogenous.json")
    )
    adaptive_table = "\n".join(
        f"| {r['seed']} | {r['target_seat']} | {r['mode'].replace('closed_loop_vs_', '')} | {r['target_money']:,.0f} | {r['money'][1 - r['target_seat']]:,.0f} |"
        for r in adaptive
    )
    text = f"""# 再現実装と検証記録

対象：Majkel1337 / submission **56216119**。指定 episode：**111105944**。実装：**{freeze["model_version"]}**。固定時刻：`{freeze["frozen_at_utc"]}`。

公開リプレイから、未知の観測にも行動を返せる近似 agent を実装した。**完全再現には未達**。元の非公開プログラムの内部構造、探索法、言語、係数は同定できていない。この実装の勾配ブースティングや仕事割り当て処理は、観測された振る舞いを再現するために今回構築したものである。

**到達点**

- 未使用の最終評価 8 試合、全 **5,752 意思決定**を対象に、作業者の完全な行動一致率は **{pct(rates["unit"])}**（{correct["unit"]:,} / {totals["unit"]:,}）。
- 移動を除く作業の一致率は **{pct(rates["nonmovement"])}**。市場注文リスト全体の完全一致率は **{pct(rates["market_exact"])}**。注文の順序・数量も一致条件に含む。
- 最初から自律実行した場合、元試合に対する最終資金比は、通常ルールで平均 **{pct(result["endogenous_town"]["mean_cash_ratio"])}**、店舗順を元試合に固定した診断で平均 **{pct(result["recorded_town"]["mean_cash_ratio"])}**。この比率は行動の再現率でも、本家との対戦勝率でもない。
- 配布する NumPy 推論器は、指定試合で高速な scikit-learn 推論器と **全 719 手が一致**。アーカイブだけを展開した隔離プロセスでも読み込みと行動の一致を確認した。

![最終評価の行動一致率と資金](reports/evaluation-overview.png)

**評価対象の分離**

| 用途 | 試合数 | 扱い |
|---|---:|---|
| 学習 | 50 | 初期 18 試合と追加 32 試合。作業・移動・数量・計画・売却の学習に使用 |
| 開発 | 6 | 指定試合を含む。候補選択、修正、閾値の判断に使用 |
| 一次評価 | 8 | 数量予測版の自律運転の破綻を検出。以後、未使用評価とは呼ばない |
| 最終評価 | 8 | 修正版の固定後に評価。上記 64 試合とは重複なし |

最終評価の試合は、残る公開対戦を時系列の 8 層に分けて各層から固定乱数で 1 件選んだ。最良の試合だけを選んではいない。標本数は 8 件であり、相手の種類や店舗構成全体を十分に代表する保証はない。

試合 ID、選定条件、固定した実装・重みの SHA-256 は [FREEZE.json](FREEZE.json) と各 manifest に記録した。学習途中の開発指標は間引き観測で計測したため、最終評価の全ターン集計と直接の増減比較はしない。

**評価条件の意味**

1. **行動一致率**：本家が実際に見た観測を毎回入力し、その場で生成した行動と記録行動を比較する。前の予測の誤りは次の盤面に引き継がない。移動先を選び直す違い、運搬量の違い、冗長な仕事を避ける違いも不一致になる。
2. **通常の自律実行**：初期状態だけを元試合から取り、その後の自分の観測と行動は閉ループで更新する。相手は元試合の記録行動列を実行する。相手の非公開 agent は取得・実行していない。
3. **店舗順固定の診断**：2 と同じだが、その時点で公開される店舗名だけを元試合どおりに置き換える。自分の farm、inventory、market はそのまま進める。将来の店は agent に入力しない。これは公式ルールへの介入を含む診断であり、通常の競技結果とは分ける。

同じ seed でも、農場の空きマス数が変わると `_spawn_weeds` が消費する乱数の個数が変わり、後続の店舗抽選も変わる。したがって、通常の自律実行で元の資金と比べる際には、行動の違いに加えて需要の違いも混ざる。これは [公式エンジン](https://github.com/Kaggle/kaggle-environments/blob/master/kaggle_environments/envs/kaggriculture/kaggriculture.py) の日末更新順による。

記録された相手の行動は、変化した相場や店舗を見て再計画しない。固定店舗の条件でも本家の非公開 agent との実対戦にはならず、Leaderboard の順位やレートは推定していない。

**未使用 8 試合の全結果**

| episode | 作業者行動一致 | 本家の記録資金 | 自律・通常ルール | 自律・店舗順固定 |
|---|---:|---:|---:|---:|
{chr(10).join(table)}

通常ルールの資金比の中央値は {pct(result["endogenous_town"]["median_cash_ratio"])}、範囲は {pct(result["endogenous_town"]["min_cash_ratio"])}〜{pct(result["endogenous_town"]["max_cash_ratio"])}。店舗順固定では中央値 {pct(result["recorded_town"]["median_cash_ratio"])}、範囲 {pct(result["recorded_town"]["min_cash_ratio"])}〜{pct(result["recorded_town"]["max_cash_ratio"])}。100% を超えても、元 agent の行動をより正確に再現したことにはならない。

**行動別の一致**

| 元の操作 | 完全一致 / 件数 | 一致率 |
|---|---:|---:|
{op_table}

移動方向、運搬先、餌を取りに戻る判断は、現在地の作業そのものより難しい。市場の部分一致と注文リスト全体の一致も別の指標である。

**指定された試合**

本家の記録資金は **96,230**。修正版の自律実行は、通常ルールで **{exported["target_money"]:,.0f}**、店舗順固定で **{specified["target_money"]:,.0f}**。指定試合は開発に使ったため、未使用評価の集計には含めない。

店舗順固定での会計は `3,000 + {specified["diagnostics"]["income"]:,} - {specified["diagnostics"]["cost"]:,.0f} = {specified["target_money"]:,.0f}`。自律試行の収支を実際の約定から計測し、最終資金と一致することを検算した。詳しい商品別収支、収穫量、作物の枯死、家畜の逃亡、日末の在庫あふれは JSON に収録した。

**途中で棄却した候補も記録する**

売却数量を直接予測する候補は、開発用の売却機会で数量完全一致が 83.6% と高く、一次評価でも作業者行動は {pct(pilot_rate)} 一致した。しかし自律実行では初期の換金が足りず、種代が不足して成長が止まった。一次評価 8 試合の平均資金は **{pilot_money:,.0f}** に落ちた。

元の開発用指定試合でも同じ資金不足を再現し、売却割合を予測するモデルに戻した。このモデルの開発用数量誤差は 0.615 個、数量完全一致は 68.2%。最終版の採用根拠は、一手の一致度と自律運転の両方を満たすこととした。一次評価 8 試合は修正判断に関与したので除外し、別の未使用 8 試合を確保して再評価した。棄却候補の JSON も `reports/pilot-v6-*` に保存した。

**別 seed と適応する相手**

| seed | 自分の席 | 相手 | 自分の資金 | 相手の資金 |
|---|---:|---|---:|---:|
{adaptive_table}

starter は公式の簡単な agent、self は同じ再現 agent。これらは新しい展開でも 719 手を完走することと、両席で機能することの確認であり、首位級の相手に対する強さの証明ではない。

**実行と検証**

- 公式環境 1.32.7 による元リプレイの再実行：**{len(ids)} 試合、{verified:,} 遷移**で両者の公開 farm、各自の非公開 inventory、market、town、day、hour が一致。
- 配布用推論器：指定試合の平均 {exported["runtime_mean"]:.3f} 秒 / 手、95 パーセンタイル {exported["runtime_p95"]:.3f} 秒、最大 {exported["runtime_max"]:.3f} 秒。ローカル実測であり、Kaggle の実行環境での時間は未検証。
- 入口、観測非破壊、特徴の有限性、最終日の収穫・帰還期限、アーカイブ単体の読み込みを含む 7 テストが成功。
- 高速版と配布版の全行動ハッシュ：`{exported["action_sha256"]}`。
- Kaggle への提出は行っていない。

**残る差**

本家と異なる状態へ進んだ後の作業優先度と資金配分に、誤差が積み上がる。日単位の作付け・家畜目標は観測から学習した近似値で、元 agent の投資評価式ではない。次に改善するなら、最優先は複数人の移動・運搬・収穫をまとめて計画する処理と、種・餌・雇用に必要な資金を売却判断と一緒に扱う処理になる。

75 マスへの拡張や雇用人数は観測標本の傾向を規則化している。重複作業、種不足の一括無効化、最終日の持ち帰れない収穫は制約で避けるため、本家の無効手まで逐語的に模倣する設計ではない。未知のルール設定や将来バージョンへの追従は検証していない。

**成果物と出典**

- [使い方・再学習手順](README.ja.md)
- [評価の集計 JSON](reports/summary.json) / [全試合の行動一致](reports/final-teacher.json)
- [通常ルールの自律実行](reports/final-rollout-endogenous.json) / [店舗順固定の診断](reports/final-rollout-recorded.json)
- [元の振る舞いを詳しく解析した報告](REVERSE_ENGINEERING.ja.md)
- [対象 Leaderboard と指定 episode](https://www.kaggle.com/competitions/kaggriculture/leaderboard?submissionId=56216119&episodeId=111105944)
- [指定試合の公開リプレイ](https://www.kaggleusercontent.com/episodes/111105944.json)
- [公式ルール](https://github.com/Kaggle/kaggle-environments/blob/master/kaggle_environments/envs/kaggriculture/README.md)
- [公式 Python agent 読み込み処理](https://github.com/Kaggle/kaggle-environments/blob/master/kaggle_environments/agent.py)
"""
    (ROOT / "REPRODUCTION_REPORT.ja.md").write_text(text)
    print(json.dumps(result, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
