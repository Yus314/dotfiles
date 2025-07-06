# dotfiles

個人用のNixOS/macOS dotfiles リポジトリです。Nix Flakesを使用してシステム設定を宣言的に管理しています。

## 概要

このリポジトリは、複数のホスト（Linux/macOS）にわたるシステム設定をNix Flakesを使って管理する個人用dotfilesです。NixOSとnix-darwinの両方に対応しており、Home Managerを使用してユーザー環境を統合的に管理します。

## 主な特徴

- **Nix Flakes**: 依存関係を固定した宣言的なシステム設定
- **クロスプラットフォーム**: NixOS（Linux）とnix-darwin（macOS）の両方をサポート
- **Home Manager**: ユーザー環境とdotfilesの統合管理
- **SOPS**: 暗号化された秘密情報の管理
- **モジュラー設計**: 再利用可能なコンポーネント構造

## システム構成

### 管理対象ホスト

- **watari**: x86_64-linux デスクトップシステム
- **lawliet**: aarch64-darwin (macOS) システム  
- **ryuk**: x86_64-linux ラボメインシステム
- **rem**: x86_64-linux ラボサブシステム

### ディレクトリ構造

```
dotfiles/
├── applications/     # アプリケーション別設定（emacs, neovim, git等）
├── homes/           # Home Manager設定（プラットフォーム別）
├── systems/         # システムレベル設定（プラットフォーム別・ホスト別）
├── modules/         # 再利用可能なモジュール
├── pkgs/           # カスタムパッケージ定義
├── overlays/       # nixpkgsオーバーレイ
├── secrets/        # SOPS暗号化された秘密情報
├── infra/          # Infrastructure as Code（Terraform）
├── flake.nix       # メインFlake設定
└── Taskfile.yml    # タスクランナー設定
```

## セットアップ・使用方法

### 必要な前提条件

- Nix（Flakes有効）
- go-task（推奨）

### 基本コマンド

```bash
# 現在のシステム設定をビルド
task build

# 全システム設定をビルド
task build-all

# macOSでシステム設定を適用
task switch

# 開発環境シェルに入る
nix develop

# コード整形
nix fmt

# Pre-commitフックを実行
nix flake check
```

### プラットフォーム別ビルド

```bash
# Linux (x86_64) システムのビルド
task linux

# macOS (aarch64) システムのビルド  
task darwin
```

## 設定の特徴

### 共通設定

- **デフォルトユーザー**: `kaki`
- **シェル**: Fish
- **認証**: GPG agentによるSSH認証
- **日本語入力**: fcitx5 + SKK/Mozc（Linux）
- **分散ビルド**: クロスプラットフォームビルド対応

### 主要アプリケーション

- **エディタ**: Emacs（org-mode設定）, Neovim
- **ターミナル**: Kitty, Wezterm, Alacritty  
- **ブラウザ**: Qutebrowser, Google Chrome, Vivaldi
- **Git**: lazygit統合
- **シェル**: Fish + Starship プロンプト

## 秘密情報管理

SOPS（age暗号化）を使用して秘密情報を管理：

- メインファイル: `secrets/default.yaml`
- age キー: `~/.config/sops/age/keys.txt`（Linux）
- GPG ホーム: `${config.xdg.dataHome}/.gnupg`（macOS）

## Infrastructure as Code

`infra/` ディレクトリにTerraformを使用したインフラ設定：

- Cloudflare DNS/トンネル設定
- GitHub リポジトリ管理

## 開発

### フォーマッター

- nixfmt (Nix)
- biome (TypeScript/JavaScript)
- shfmt (Shell)
- stylua (Lua) 
- yamlfmt (YAML)
- terraform fmt

### Pre-commitフック

- nil (Nix linter)
- shellcheck
- treefmt

## ライセンス

個人用設定のため、参考程度にご利用ください。

[![Ask DeepWiki](https://deepwiki.com/badge.svg)](https://deepwiki.com/Yus314/dotfiles)
