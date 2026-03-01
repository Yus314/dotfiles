# CLAUDE.md

このファイルは、このリポジトリでコードを扱う際のClaude Code (claude.ai/code) へのガイダンスを提供します。

## アーキテクチャ概要

これは、モジュラー設定構造を持つNix Flakesを使用したNixOS/Nix-Darwin dotfilesリポジトリです。このリポジトリは、Linux (NixOS) とmacOS (Darwin) システム間の複数のホストに対するシステム設定を管理します。

### 主要な設定構造

- **flake.nix**: 入力、出力、ホスト設定を定義するメインのflake設定
- **flake-module.nix**: `hosts`属性セットからシステム設定を動的に生成するカスタムflakeモジュール
- **Makefile**: 一般的な操作のためのビルドツール設定
- **hosts** flake.nixでの定義は実際のシステム設定にマップされます：
  - `lawliet`: x86_64-linux デスクトップシステム
  - `watari`: aarch64-darwin macOSシステム
  - `ryuk`: x86_64-linux lab-main システム
  - `rem`: x86_64-linux lab-sub システム

### ディレクトリ構造

- `applications/`: アプリケーション固有の設定 (emacs, neovim, git, etc.)
- `homes/`: プラットフォーム (darwin/nixos) と共通設定で分割されたHome Manager設定
- `systems/`: プラットフォーム (darwin/nixos) とホスト固有の設定で分割されたシステムレベル設定
- `modules/`: home-manager、darwin、nix設定のための再利用可能なモジュール
- `pkgs/`: カスタムパッケージ定義
- `overlays/`: Nixpkgsオーバーレイ
- `secrets/`: SOPS暗号化されたシークレット
- `infra/`: Infrastructure as code (Cloudflare、GitHub用Terraform設定)

### 設定階層

1. **システムレベル**: `systems/{platform}/common.nix` → `systems/{platform}/{hostname}/`
2. **Home Managerレベル**: `homes/common.nix` → `homes/{platform}/common.nix` → `homes/{platform}/{hostname}/`
3. **アプリケーション**: `applications/`内の個別アプリケーション設定がhome設定でインポートされる

## 共通コマンド

### 設定のビルド

```bash
# 現在のシステム設定をビルド
make build

# すべてのシステム設定をビルド
make build-all

# 特定のプラットフォームをビルド
make x86_64-linux    # x86_64-linuxシステムをビルド
make aarch64-darwin  # aarch64-darwinシステムをビルド
```

### システム管理

```bash
# システム設定を切り替え（sudoによる権限昇格が必要）
nh os switch . -H {hostname}        # NixOS用 例: nh os switch . -H lawliet
nh darwin switch . -H {hostname}    # macOS/Darwin用 例: nh darwin switch . -H watari

# 注意: switchコマンドは実行中にsudoによる管理者権限が必要になります
# Claude Codeからは権限昇格ができないため、ユーザーが手動で実行してください

# Nixをインストール (存在しない場合)
make install_nix

# Nixをアンインストール
make uninstall_nix
```

### 開発

```bash
# ツール付きの開発シェルに入る
nix develop

# コードをフォーマット
nix fmt

# pre-commitフックを実行
nix flake check
```

### 直接的なNixコマンド

```bash
# 特定のホスト設定をビルド
nom build .#nixosConfigurations.lawliet.config.system.build.toplevel
nom build .#darwinConfigurations.watari.system
nom build .#nixosConfigurations.ryuk.config.system.build.toplevel
nom build .#nixosConfigurations.rem.config.system.build.toplevel

# 切り替えずにビルドとテスト
sudo nixos-rebuild build --flake .#lawliet
sudo darwin-rebuild build --flake .#watari
```

## 主要技術

- **Nix Flakes**: ロックされた依存関係を持つ宣言的システム設定
- **Home Manager**: ユーザー環境とdotfiles管理
- **nh**: 改良されたNixOS/nix-darwinヘルパーツール（システム切り替え用）
- **SOPS**: age/gpg暗号化によるシークレット管理
- **flake-parts**: モジュラーflake組織
- **treefmt-nix**: 複数のフォーマッター (nixfmt, biome, shfmt, stylua, taplo, terraform, yamlfmt) によるコードフォーマット
- **git-hooks.nix**: Pre-commitフック統合
- **disko**: 宣言的ディスクパーティション管理
- **xremap**: キーマッピング設定
- **nix-darwin**: macOS用Nix設定

## ホスト固有の注意点

- **デフォルトユーザー名**: すべてのシステムで`kaki`
- **Fish shell**: すべてのホストで設定されるプライマリシェル
- **GPG/SSH**: SSH認証用に設定されたGPGエージェント
- **入力メソッド**: 日本語入力用のfcitx5とcskk/SKK/Mozc (Linuxのみ)
- **分散ビルド**: クロスプラットフォームビルド用に設定 (buildMachines.nixを参照)
- **カスタムパッケージ**: cskk（カナ漢字変換）、fcitx5-cskk（入力メソッド）

## シークレット管理

シークレットはage暗号化を使用したSOPSで管理されます。キーファイル：
- `secrets/default.yaml`: メインシークレットファイル
- Ageキーの場所: `/home/kaki/.config/sops/age/keys.txt` (Linux)
- Darwin用GPGホーム: `${config.xdg.dataHome}/.gnupg`

## コード品質とフォーマット

このリポジトリは、自動化されたコードフォーマットと品質チェックのためにpre-commitフックを使用します：

- **自動フォーマット**: treefmt-nixを使用してコミット時にファイルが自動的にフォーマットされます
- **Pre-commit統合**: git-hooks.nixはコミット前にコード品質を確保します
- **CI/CD検証**: GitHub Actionsはすべての変更に対してチェックとビルドを実行します

変更をコミットする際、pre-commitフックが自動的にファイルをフォーマットする場合があります。この場合：
1. フォーマットされた変更が自動的に適用されます
2. コードの一貫性を保つため、これらのフォーマット変更を受け入れてください
3. フォーマットされたコードでコミットが続行されます

## コミットメッセージ規約

このリポジトリでは**Conventional Commits**規約を採用しています：

### 基本形式
```
<type>[optional scope]: <description>

[optional body]

[optional footer(s)]
```

### 主要なタイプ
- **feat**: 新機能
- **fix**: バグ修正
- **docs**: ドキュメントのみの変更
- **style**: コードの意味に影響しない変更（空白、フォーマット、セミコロンの欠落など）
- **refactor**: バグ修正でも機能追加でもないコード変更
- **perf**: パフォーマンスを向上させるコード変更
- **test**: 不足しているテストの追加や既存テストの修正
- **chore**: ビルドプロセスやドキュメント生成などの補助ツールやライブラリの変更

### 例
```bash
feat(applications): add neovim skkeleton plugin
fix(systems/nixos): resolve fcitx5 input method issue
docs: update README with new installation steps
chore(flake): update nixpkgs to latest unstable
```

### スコープの例
- `applications`: アプリケーション設定
- `homes`: Home Manager設定
- `systems`: システム設定
- `modules`: カスタムモジュール
- `pkgs`: カスタムパッケージ
- `infra`: インフラストラクチャ設定

### 重要な注意事項
- **共著者の記載**: このリポジトリではClaude Codeを共著者として記載しません
- コミットメッセージには「🤖 Generated with Claude Code」や「Co-Authored-By: Claude」などの記載を追加しないでください

## Terraform Infrastructure

`infra/`ディレクトリでOracle Cloud Infrastructure (OCI)バックエンドを使用したEnterprise-grade infrastructure管理を行います。

### tf-wrapper: 汎用Terraformラッパー（sops.nix統合版）

#### 概要

tf-wrapperはsops.nixとHome Managerの統合により、セキュアで自動化されたTerraform OCI バックエンド管理を提供します。一時ファイル不要でOCI認証情報を安全に管理し、任意のディレクトリからTerraformを実行できます。

#### 基本使用

```bash
# Home Manager経由で自動インストール済み（sops.nixにより設定も自動配置）
cd infra/services/cloudflare
tf-wrapper plan
tf-wrapper apply

# 直接実行
nix run .#tf-wrapper -- --version
```

#### 設定ファイル

sops.nixにより以下の設定ファイルが自動生成・配置されます：

- `~/.config/tf-wrapper/oci.yaml`: OCI認証設定（復号化済み）
- `~/.config/tf-wrapper/backend.yaml`: Terraformバックエンド設定（復号化済み）
- `~/.config/tf-wrapper/oci_private_key.pem`: OCI秘密鍵（復号化済み、権限600）
- `~/.config/tf-wrapper/profiles.yaml`: プロファイル設定（将来対応）

#### 他プロジェクトでの利用

tf-wrapperは任意のTerraformプロジェクトで即座に利用可能：

```bash
# 設定は既にsops.nixにより配置済み、追加設定不要
cd /path/to/other-terraform-project
tf-wrapper init
tf-wrapper apply
```

#### 環境変数

- `TF_WRAPPER_CONFIG_DIR_OVERRIDE`: 設定ディレクトリの上書き
- `TF_VAR_key`: Backend key（デフォルト: 自動生成）
- `TF_DEBUG=1`: デバッグ情報表示
- `TF_LOG_LEVEL=ERROR`: エラーのみ表示
- `TF_WRAPPER_CLEANUP_ENV=1`: 終了時に環境変数をクリーンアップ

#### セキュリティ機能

- sops.nixによる暗号化設定管理
- 一時ファイル不要（セキュリティリスク軽減）
- 秘密鍵ファイルの厳格な権限管理（600）
- 設定ファイルの自動復号化
- Home Manager統合による一元管理

### 📚 詳細ドキュメント

インフラ運用の詳細は以下を参照してください：

- **[🚀 運用ガイド](infra/docs/OPERATIONS.md)** - セットアップ、ワークフロー、検証手順
- **[🛡️ セキュリティ](infra/docs/SECURITY.md)** - SOPS管理、機密情報の取扱いポリシー
- **[🚨 トラブルシューティング](infra/docs/TROUBLESHOOTING.md)** - よくある問題と解決方法
- **[🔥 緊急時対応](infra/docs/EMERGENCY.md)** - インシデント対応手順

### アーキテクチャ概要

- **OCI Native Backend**: 状態管理にOracle Cloud Object Storage使用
- **SOPS暗号化**: Age + PGP二重保護による機密情報管理
- **Zero-Touch認証**: 自動化tfラッパーによる認証フロー
- **Enterprise Security**: 完全暗号化、監査証跡、ロールバック対応
