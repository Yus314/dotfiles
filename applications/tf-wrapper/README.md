# tf-wrapper Application Configuration

このディレクトリは tf-wrapper の Home Manager 設定とsops.nix統合を管理します。

## 構造

- `default.nix`: Home Manager 設定とSOPS秘密情報管理
- `secrets.yaml`: tf-wrapper専用のSOPS暗号化設定ファイル（OCI認証情報とバックエンド設定）
- `README.md`: このファイル

## 機能

### セキュリティ
- sops.nixによる暗号化設定管理（Age + PGP二重保護）
- 一時ファイル不要（セキュリティリスク軽減）
- 秘密鍵ファイルの厳格な権限管理（600）
- 設定ファイルの自動復号化

### 利便性
- Home Manager統合による一元管理
- 任意のディレクトリからの Terraform実行
- プロファイル機能（将来対応）
- 汎用プロジェクト対応

## セットアップ

このアプリケーション設定は `homes/common.nix` にインポートすることで有効化されます。

```nix
imports = [
  ../applications/tf-wrapper
];
```

## 設定ファイル配置場所

sops.nixにより以下の場所に設定ファイルが自動配置されます：

- `~/.config/tf-wrapper/oci.yaml`: OCI基本設定（復号化済み）
- `~/.config/tf-wrapper/backend.yaml`: Terraformバックエンド設定（復号化済み）
- `~/.config/tf-wrapper/oci_private_key.pem`: OCI秘密鍵（復号化済み、権限600）
- `~/.config/tf-wrapper/profiles.yaml`: 設定プロファイル（将来対応）

## 使用方法

### 基本使用
```bash
# インフラプロジェクトで
cd infra/services/cloudflare
tf-wrapper plan
tf-wrapper apply

# 他のプロジェクトでも即座に利用可能
cd /path/to/other-terraform-project
tf-wrapper init
tf-wrapper plan
```

### 環境変数
- `TF_WRAPPER_CONFIG_DIR_OVERRIDE`: 設定ディレクトリの上書き
- `TF_VAR_key`: Backend key（デフォルト: 自動生成）
- `TF_DEBUG=1`: デバッグ情報表示
- `TF_LOG_LEVEL=ERROR`: エラーのみ表示

## セキュリティ仕様

- **暗号化**: Age + PGP二重暗号化によるSOPS管理
- **鍵管理**: `/home/kaki/.config/sops/age/keys.txt`による復号化
- **権限**: 秘密鍵ファイルは 600 権限で保護
- **一時ファイル**: 不要（従来版の一時ファイルリスクを排除）

## 技術詳細

- **Nix統合**: writeShellScriptBin による軽量なパッケージ化
- **依存関係**: yq-go, terraform, coreutils（sopsは不要）
- **設定検索**: プロジェクトローカル → sops.nix管理ファイル → 環境変数
