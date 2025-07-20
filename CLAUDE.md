# CLAUDE.md

このファイルは、このリポジトリでコードを扱う際のClaude Code (claude.ai/code) へのガイダンスを提供します。

## アーキテクチャ概要

これは、モジュラー設定構造を持つNix Flakesを使用したNixOS/Nix-Darwin dotfilesリポジトリです。このリポジトリは、Linux (NixOS) とmacOS (Darwin) システム間の複数のホストに対するシステム設定を管理します。

### 主要な設定構造

- **flake.nix**: 入力、出力、ホスト設定を定義するメインのflake設定
- **flake-module.nix**: `hosts`属性セットからシステム設定を動的に生成するカスタムflakeモジュール
- **Taskfile.yml**: 一般的な操作のためのタスクランナー設定
- **hosts** flake.nixでの定義は実際のシステム設定にマップされます：
  - `watari`: x86_64-linux デスクトップシステム
  - `lawliet`: x86_64-linux （現在はLinux、元々はaarch64-darwin macOSシステム）
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
task build

# すべてのシステム設定をビルド
task build-all

# 特定のプラットフォームをビルド
task linux    # x86_64-linuxシステムをビルド
task darwin   # aarch64-darwinシステムをビルド
```

### システム管理

```bash
# 現在のホスト向けにシステム設定を切り替え
task switch

# Nixをインストール (存在しない場合)
task install_nix

# Nixをアンインストール
task uninstall_nix
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
nom build .#nixosConfigurations.watari.config.system.build.toplevel
nom build .#nixosConfigurations.lawliet.config.system.build.toplevel
nom build .#darwinConfigurations.lawliet.system  # Darwin設定（現在は無効）

# 切り替えずにビルドとテスト
sudo nixos-rebuild build --flake .#watari
sudo nixos-rebuild build --flake .#lawliet
```

## 主要技術

- **Nix Flakes**: ロックされた依存関係を持つ宣言的システム設定
- **Home Manager**: ユーザー環境とdotfiles管理
- **SOPS**: age/gpg暗号化によるシークレット管理
- **flake-parts**: モジュラーflake組織
- **treefmt-nix**: 複数のフォーマッター (nixfmt, biome, shfmt, stylua, taplo, terraform, yamlfmt) によるコードフォーマット
- **git-hooks.nix**: Pre-commitフック統合
- **disko**: 宣言的ディスクパーティション管理
- **xremap**: キーマッピング設定
- **impermanence**: 永続化設定管理
- **nix-darwin**: macOS用Nix設定（現在は未使用）

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