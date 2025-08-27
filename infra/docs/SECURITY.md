# Infrastructure Security Best Practices

## 🛡️ SOPS操作規則

### 正しい操作
```bash
# ✅ 推奨される操作
sops secrets.yaml                    # 直接編集
tf plan                              # 自動復号化
```

### 禁止される操作
```bash
# ❌ セキュリティリスクのある操作
sops --decrypt secrets.yaml > plain.yaml    # 平文ファイル作成禁止
cat secrets.yaml | grep -v sops             # 内容の標準出力禁止
echo "$SECRET_VALUE"                         # 機密情報のecho禁止
```

---

## 🔐 一時ファイル管理

### 自動管理されるファイル
```bash
# tfラッパーが自動管理するファイル
/tmp/oci_terraform_*.pem    # 自動作成 + 自動削除

# 確認用コマンド（通常は空の結果）
ls /tmp/oci_terraform_*     # 残存チェック
```

### 手動クリーンアップ
```bash
# 問題発生時の緊急クリーンアップ
rm -f /tmp/oci_terraform_*.pem
find /tmp -name "*terraform*" -type f -delete
```

---

## ✅ アクセス権限の確認

### 定期チェック項目
```bash
# SOPS鍵ファイルの権限確認
ls -la ~/.config/sops/age/keys.txt    # 600権限であることを確認

# インフラ設定ファイルの権限確認
ls -la infra/secrets/                 # SOPSファイルの権限確認
ls -la infra/services/*/secrets.yaml  # サービス別シークレットの確認
```

### 環境変数の確認
```bash
# 必要な環境変数の設定確認
echo $SOPS_AGE_KEY_FILE               # Age鍵ファイルパス
printenv | grep -E "(SOPS|AGE)"       # SOPS関連環境変数
```

---

## 📋 機密情報取扱い原則

### 画面共有・会議時
- **SOPS編集**: 画面共有中は避ける
- **tf planコマンド**: sensitive valueが表示される可能性に注意
- **ログ出力**: 機密情報が含まれる可能性があるため共有前に確認

### バックアップポリシー
- **許可**: 暗号化されたファイル（secrets.yaml等）のバックアップ
- **禁止**: 平文ファイルや復号化されたデータのバックアップ
- **推奨**: Git履歴による暗号化ファイルのバージョン管理

### ログ管理
```bash
# 安全なログ確認方法
tf plan 2>&1 | grep -v "sensitive"     # センシティブ情報を除外
tf apply 2>&1 | tee /tmp/tf.log        # ログファイルは一時的に使用
```

---

## 🚨 セキュリティインシデント対応

### 機密情報漏洩時
1. **即座の対応**: 該当シークレットの無効化・再生成
2. **影響調査**: 漏洩範囲の特定
3. **復旧作業**: 新しいシークレットでの再暗号化
4. **再発防止**: 手順とチェックリストの見直し

### 権限昇格検知時
```bash
# 不正アクセスが疑われる場合
git log --oneline --since="1 day ago"  # 最近の変更確認
tf plan                                # インフラ状態の確認
```

---

## 🔍 セキュリティ監査

### 定期確認項目
- [ ] SOPS鍵ファイルの権限（600）
- [ ] 一時ファイルの残存なし
- [ ] Git履歴に平文機密情報なし
- [ ] 環境変数の適切な設定
- [ ] tfラッパーの正常動作

### セキュリティスキャン
```bash
# 機密情報の誤コミットチェック
git log -p | grep -E "(password|secret|key|token)" --color=never
grep -r "BEGIN.*PRIVATE" . --exclude-dir=.git
```

このガイドラインに従うことで、**Enterprise-grade security posture**を維持できます。
