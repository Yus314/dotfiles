# dotfiles

個人用のNixOS/macOS dotfiles リポジトリです。Nix Flakesを使用してシステム設定を宣言的に管理しています。

## 目的 (Vision)

このリポジトリは、**継続的に進化する、再現可能な開発環境の実現**を目的とした個人用dotfiles管理プロジェクトです。

単なる設定のバックアップではなく、所有者と共に成長し、常に最適な状況へと適応し続ける*「生きた作業基盤」*として設計されています。ツールや環境の制約から開発者を解放し、本来の創造的な作業に完全集中できる状態を実現します。

### 核心的な価値

- **摩擦のない作業環境**: 環境構築の煩わしさ、OS間の差異、設定変更に伴うリスクを極限まで削減
- **思考の流れを維持**: 設定変更による待ち時間や手作業を排除し、開発者の集中力を持続
- **アグレッシブな改善**: 変更のコストを下げることで、システムの継続的な進化を促進

### 達成基準

1. **迅速な再現性**: 新規ホストのセットアップが、リポジトリのcloneから30分以内に完了
2. **完全な可搬性**: LinuxとmacOSの間で、作業感に差異が感じられない
3. **高速な継続サイクル**: 軽微な設定変更から適用完了まで1分以内で完了し、集中力が途切れない
4. **体系的な知識管理**: 設計思想や決定背景がドキュメント化され、未来の自分が迅速に理解できる

## 概要

このリポジトリは、複数のホスト（Linux/macOS）にわたるシステム設定をNix Flakesを使って管理する個人用dotfilesです。NixOSとnix-darwinの両方に対応しており、Home Managerを使用してユーザー環境を統合的に管理します。

## 主な特徴

goal-modelで定義された4つの主要ゴールを技術的に実現する特徴群：

### 1. 変更の容易性と拡張性
- **高速ビルド**: 分散ビルドとキャッシュ利用により、軽微な設定変更を1分以内で適用
- **自動化**: pre-commit hooks、CI/CD、タスクランナーによる反復作業の効率化
- **モジュラー設計**: 再利用可能なコンポーネント構造で影響範囲を限定

### 2. 再現性とポータビリティ
- **Nix Flakes**: 依存関係を固定した宣言的なシステム設定
- **クロスプラットフォーム**: NixOS（Linux）とnix-darwin（macOS）の統一管理
- **Home Manager**: ユーザー環境とdotfilesの統合管理
- **SOPS**: 暗号化された秘密情報の安全な管理と自動復号

### 3. 信頼性の確保
- **ロールバック機能**: Git + Nixによる安全な設定変更とロールバック
- **CI/CD**: GitHub Actionsによる事前ビルドとテスト
- **副作用の排除**: impermanenceによるクリーンな環境維持

### 4. 進化と知識の管理
- **問題・改善管理**: GitHub Issuesによるアイデアとタスクの体系的管理
- **更新通知**: 使用アプリケーションの更新情報の自動通知
- **文書化**: 設計思想と決定背景の体系的記録

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

## 現在の状況と課題

goal-modelで定義された達成基準に対する現在の進捗状況：

### 達成済み
- ✅ **分散ビルドとキャッシュ**: 全ての対象ホストで動作し、ビルド時間を大幅短縮
- ✅ **SOPS暗号化**: 機密情報の安全な管理と自動復号が実現
- ✅ **CI/CD**: GitHub Actionsでビルド確認、Cachixでバイナリキャッシュ
- ✅ **Garbage Collection**: 週次の自動実行で容量問題を回避

### 部分的達成
- 🔄 **軽微な設定変更1分以内**: 通常は達成できるが、Emacsビルドがボトルネック
- 🔄 **pre-commit hooks**: 設定済みだが、具体的な動作範囲の把握が不足
- 🔄 **文書化**: ゴールモデルは作成済み、詳細な設計思想の記録が課題

### 未達成・課題
- ❌ **30分セットアップ**: 新規ホストでの再現性検証が未実施
- ❌ **flake自動更新**: 手動実行のままで自動化が未完了
- ❌ **nur-packages CI**: 独自パッケージリポジトリのCI未構築

## 開発

### コード品質管理

- **フォーマッター**: nixfmt、biome、shfmt、stylua、yamlfmt、terraform fmt
- **Pre-commitフック**: nil (Nix linter)、shellcheck、treefmt
- **CI/CD**: GitHub Actionsによる全プラットフォームビルド検証

## ライセンス

個人用設定のため、参考程度にご利用ください。

[![Ask DeepWiki](https://deepwiki.com/badge.svg)](https://deepwiki.com/Yus314/dotfiles)
