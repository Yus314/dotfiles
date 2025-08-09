# Infrastructure Troubleshooting Guide

## 🚨 よくある問題と解決策

### State lockエラー
```
Error: Error acquiring the state lock
Lock ID: e3afe03a-9aaa-f4d1-3c1a-f70da00ed8aa
```
**解決方法**:
```bash
tf force-unlock e3afe03a-9aaa-f4d1-3c1a-f70da00ed8aa
```
**原因**: 前回のterraform操作が異常終了した際にlockが残存

---

### SOPS復号化エラー
```
Failed to get the data key required to decrypt the SOPS file
```
**解決方法**:
```bash
# Age鍵の確認と設定
export SOPS_AGE_KEY_FILE="/home/kaki/.config/sops/age/keys.txt"
sops --decrypt secrets.yaml | head -1    # テスト実行

# 鍵ファイルの権限確認
ls -la ~/.config/sops/age/keys.txt       # 600権限であることを確認
```
**原因**: Age鍵の環境変数未設定、または鍵ファイルの権限問題

---

### OCI認証エラー
```
Service error:NotAuthenticated
HTTP status code: 401
```
**解決方法**:
```bash
# インフラ設定の確認
sops --decrypt ../../secrets/infrastructure.yaml | head -5

# tfラッパーでの認証確認
tf validate    # SOPS + OCI認証のテスト実行
```
**原因**: OCI認証情報の設定不備、または秘密鍵の問題

---

### 一時キーファイルの残存
```bash
# 症状: /tmp/oci_terraform_*.pem ファイルが残っている
ls /tmp/oci_terraform_*

# 解決方法: 手動クリーンアップ
rm -f /tmp/oci_terraform_*.pem
```
**原因**: tfラッパーの異常終了による自動削除の失敗

---

### Terraform Provider初期化エラー
```
Error: Failed to install provider
```
**解決方法**:
```bash
# Provider初期化のリトライ
tf init -upgrade

# Terraform lockファイルの再生成
rm .terraform.lock.hcl
tf init
```
**原因**: Provider version不整合、またはネットワーク問題

---

### SOPS編集時の文字化け
```
# 症状: sops secrets.yaml でエディタが正常に動作しない
```
**解決方法**:
```bash
# エディタの明示的指定
EDITOR=vim sops secrets.yaml

# または環境変数で設定
export EDITOR=vim
sops secrets.yaml
```

---

## 🔍 デバッグ方法

### 詳細ログの有効化
```bash
# Terraform詳細ログ
TF_LOG=DEBUG tf plan    # 全てのAPI呼び出しとレスポンスを表示
TF_LOG=TRACE tf plan    # 最も詳細なログレベル

# SOPS操作のデバッグ
sops --verbose secrets.yaml    # SOPS操作の詳細表示
```

### ネットワーク接続確認
```bash
# OCI API接続確認
curl -I https://objectstorage.ap-tokyo-1.oraclecloud.com/

# GitHub API接続確認
curl -I https://api.github.com/

# Cloudflare API接続確認
curl -I https://api.cloudflare.com/client/v4/
```

### 設定ファイル構文確認
```bash
# Terraform構文チェック
tf validate

# YAML構文チェック
python -c "import yaml; yaml.safe_load(open('secrets.yaml'))"

# JSON形式での設定表示（デバッグ用）
tf show -json | jq '.' > /tmp/tf_state.json
```

---

## 📞 エスカレーション基準

### Level 1: 自力解決可能
- State lockエラー
- SOPS復号化エラー
- Provider初期化エラー
- **対応時間**: 30分以内

### Level 2: 調査が必要
- OCI認証の継続的失敗
- 設定変更後のサービス異常
- 予期しないインフラ変更
- **対応時間**: 2時間以内

### Level 3: 緊急対応が必要
- 本番サービスの停止
- セキュリティインシデント
- データ損失の可能性
- **対応時間**: 即座

---

## 🔧 予防的メンテナンス

### 定期確認項目
```bash
# 週次確認
tf plan                                # 全サービスでdrift検出
ls /tmp/oci_terraform_*               # 一時ファイル残存確認

# 月次確認
git log --since="1 month ago" --oneline    # インフラ変更履歴
sops --decrypt secrets.yaml | wc -l        # シークレット管理状況確認
```

### ヘルスチェックスクリプト
```bash
#!/bin/bash
# infra-health-check.sh

echo "🔍 Infrastructure Health Check"
echo "================================"

# SOPS確認
if sops --decrypt secrets.yaml >/dev/null 2>&1; then
    echo "✅ SOPS decryption: OK"
else
    echo "❌ SOPS decryption: FAILED"
fi

# tf wrapper確認
if tf --version >/dev/null 2>&1; then
    echo "✅ tf wrapper: OK"
else
    echo "❌ tf wrapper: FAILED"
fi

# 一時ファイル確認
if [ -z "$(ls /tmp/oci_terraform_* 2>/dev/null)" ]; then
    echo "✅ Temp files: Clean"
else
    echo "⚠️ Temp files: Found residual files"
fi
```

このガイドを参考に、迅速な問題解決を実現してください。
