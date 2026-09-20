# Kaggriculture agent 再現実装

対象は Majkel1337 の submission **56216119**。公開リプレイから作成した近似 agent です。非公開のアルゴリズムや係数を特定したものではなく、完全再現には未達です。

- [再現度・評価条件・残る差](REPRODUCTION_REPORT.ja.md)
- [元 agent の行動分析](REVERSE_ENGINEERING.ja.md)
- [実装](policy.py) / [入口](main.py) / [固定した重みとコードのハッシュ](FREEZE.json)
- [配布用 agent](submission.tar.gz) / [コード・報告・評価結果一式](reproduction-bundle.zip)

**使う**

`submission.tar.gz` の直下に `main.py`、`policy.py`、`engine.py`、`models.json.gz` などが入ります。`main.py` は Kaggle の `agent(observation, configuration)` 形式です。推論時に必要な外部ライブラリは NumPy のみです。リプレイや学習用ファイルへの実行時依存はありません。Kaggle への提出は行っていません。

ローカルで関数を使う場合は、このディレクトリを Python の import path に追加して `from main import agent` とします。10 × 10、24 時間 × 30 日、719 回の意思決定という対象競技の既定設定用です。

**評価を再実行する**

Python 3.12 で検証しました。以下はこのディレクトリで実行します。

```bash
python3 -m venv .venv
.venv/bin/python -m pip install -r requirements-train.txt
.venv/bin/python fetch_data.py sample-manifest.json
.venv/bin/python fetch_data.py final-test-manifest.json
.venv/bin/python -m unittest test_invariants -v

# 配布用の NumPy 推論器で、指定試合を最初から自律実行
.venv/bin/python evaluate.py --exported --episodes 111105944 --output local-specified.json

# 本家が実際に見た盤面を入力して、全意思決定の行動一致率を測定
.venv/bin/python evaluate.py --exported --teacher --stride 1 \
  --manifest final-test-manifest.json --output local-teacher.json

# 店舗の出現順だけを元試合に固定した診断
.venv/bin/python evaluate.py --exported --town recorded \
  --manifest final-test-manifest.json --output local-recorded-towns.json
```

結果は `artifacts/` に出ます。リプレイの既定保存先は `data/` です。`KAGGRICULTURE_DATA` で変更できます。`--exported` を省く高速な評価には、再学習で生成する `artifacts/native-models.pkl` が必要です。

相手の既定動作は、その試合で記録された行動列です。**相手の非公開 agent を実行しているわけではありません。** `--opponent starter` は公式 starter が現在の盤面を見て再判断し、`--opponent self` は再現 agent 同士が再判断します。`--seed` と `--seat` も指定できます。

**学習を再実行する**

```bash
.venv/bin/python fetch_data.py additional-train-manifest.json
.venv/bin/python audit_replays.py
.venv/bin/python audit_replays.py --manifest additional-train-manifest.json
.venv/bin/python train.py --rebuild
.venv/bin/python refine.py --initial --rebuild
.venv/bin/python refine.py --rebuild
.venv/bin/python train_plans.py
.venv/bin/python train_sales.py
```

学習には 50 試合、開発には別の 6 試合を使用しました。学習済み重みを使う推論と、再学習による重みの生成は別です。提供済み重みの SHA-256 は `FREEZE.json` にあります。再学習のバイト単位の一致は保証しません。途中候補の失敗を検出した 8 試合と、その後に確保した最終評価用 8 試合を分けて記録しています。

**実装の構成**

1. 最初の 2 手は、最初の解析標本 24 試合で共通した定石。
2. 現在の盤面から水やり、収穫、給餌、施肥、植え付け、運搬などの仕事を生成。
3. 勾配ブースティング木で仕事に点数を付け、作業者間の重複と種の取り合いを調整。
4. 移動の軸、餌の持ち出し量、日ごとの作付け・家畜の目標を別のモデルで推定。
5. 公式エンジンと同じ処理で自分の作業後の在庫を予測し、売却・購入を決定。
6. 75 マスへの拡張、雇用、最終日の荷下ろしを観測された傾向と時間制約で処理。

入力は現在の自分の公開・非公開観測、相手の公開農場、市場、既に公開された町の店舗です。相手の非公開倉庫、将来の店舗、episode ID、seed、元リプレイの次の行動は推論に使いません。学習時に未来の最初の作業を移動先ラベルとして使っていますが、入力特徴はその時点の観測だけです。

`engine.py` の由来と変更点は [NOTICE.md](NOTICE.md)、元配布物のハッシュは [engine-provenance.json](engine-provenance.json)、ライセンスは [LICENSE.engine](LICENSE.engine) を参照してください。
