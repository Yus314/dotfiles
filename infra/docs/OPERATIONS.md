# Infrastructure Operations Guide

## 🚀 初回セットアップ手順

### Prerequisites確認
```bash
# 必要なツールの存在確認
which sops age terraform nix    # 全て見つかることを確認

# SOPS鍵の確認
ls -la ~/.config/sops/age/keys.txt    # age鍵が存在することを確認
echo $SOPS_AGE_KEY_FILE               # 環境変数設定の確認
```

### tfラッパーのインストール
```bash
# 初回のみ実行
cd infra
scripts/install-tf-wrapper.sh    # PATHへのシンボリックリンク作成

# インストール確認
which tf                          # /usr/local/bin/tf が表示されることを確認
tf --version                      # バージョン情報とSOPS統合確認
```

### 認証テスト
```bash
# 各サービスで認証テスト
cd infra/services/cloudflare
tf validate    # SOPS復号化 + OCI認証の動作確認

cd ../github
tf validate    # GitHub用認証確認
```

**✅ セットアップ完了の確認**: 全てのコマンドがエラーなく完了すること

---

## 📋 標準運用ワークフロー

### Phase 1: 変更計画
```bash
# 1. 現在の状況確認
cd infra/services/{service}
tf plan    # 現在の差分確認（通常はNo changesが表示される）

# 2. 設定ファイルの編集
# main.tf, secrets.yaml等を編集

# 3. 構文検証
tf validate
```

### Phase 2: 影響確認
```bash
# 4. 変更内容の詳細確認
tf plan    # 🔍 必ず実行し、変更内容を詳細に確認
```

**⚠️ STOP**: planの結果を**必ず人間が確認**してから次へ進む

### Phase 3: 本番適用
```bash
# 5. 承認後の適用
tf apply    # 再度確認プロンプトが表示される

# 6. 適用結果の確認
tf plan     # No changesが表示されることを確認（冪等性確認）
```

### Phase 4: 変更記録
```bash
# 7. 変更のコミット
git add -A
git commit -m "feat(infra): describe your change

- Specific change details
- Business justification
- Impact assessment"
```

---

## 🔍 検証とテスト手順

### terraform planの読み方
```bash
# 期待される表示例
tf plan
```
```
No changes. Your infrastructure matches the configuration.
```
**✅ 理想的**: 既存インフラとの差分なし

```
Plan: 1 to add, 0 to change, 0 to destroy.
```
**⚠️ 要確認**: 追加・変更・削除の詳細を必ず確認

### 変更内容の安全確認
```bash
# センシティブ値の確認
tf plan | grep "sensitive value"    # 機密情報が適切にマスクされている確認

# 意図しない変更の検出
tf plan | grep -E "(destroy|replace)"    # 破壊的変更の有無確認
```

### ロールバック手順
```bash
# Git based rollback
git log --oneline -10               # 最近のコミット確認
git revert HEAD                     # 直前変更の取り消し
tf plan && tf apply                 # インフラ状態の復元

# 緊急時の強制ロールバック
git reset --hard HEAD~1             # 危険: 未コミット変更も消失
tf plan && tf apply                 # 強制状態復元
```

---

このガイドに従うことで、**安全で効率的なインフラ運用**を実現できます。
