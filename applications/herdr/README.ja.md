# Herdr

AI エージェントの状態を一覧できるターミナルマルチプレクサー。
公式の [herdr-nix](https://github.com/herdrdev/herdr-nix) が配布するバイナリを
`flake.lock` で固定し、全ホスト共通の Home Manager 設定から導入する。
導入時のバージョンは **0.9.1**。

## 起動と設定

watari への反映はリポジトリルートで実行する。

```sh
nh darwin switch . -H watari
herdr
```

システムへの反映前でも、リポジトリルートから次のコマンドで起動できる。

```sh
nix run .#herdr
```

Ghostty の通常のシェルから起動すると、初回セットアップが開く。
設定は `~/.config/herdr/config.toml` に保存され、Herdr の Settings から変更できる。
Home Manager の `programs.herdr.settings` は一覧・通知の標準設定を管理する。
生成ファイルへのシンボリックリンクは作らず、activation で既存の書き込み可能な
設定ファイルへ統合する。キー設定・テーマ・その他の設定とコメントは保持する。
変更前の内容は同じディレクトリの `config.toml.backup-*` に保存する。
Herdr と activation が同時に設定を書き換えないよう、Settings の編集完了後に反映する。
Ghostty の配色に合わせる場合は、Settings のテーマで `terminal` を選択する。

キーバインドの設定は [`keybindings.toml`](./keybindings.toml) に保存する。
新しい端末では、このファイルの `[keys]` を既存の `config.toml` に統合する。
Home Manager はこの設定を自動適用・上書きしない。
適用後は `herdr config check` で検証し、`herdr server reload-config` で再読み込みする。

一覧は `ui.agent_panel_sort = "priority"` で応答待ちを優先し、
`ui.status_indicators = "symbols"` で状態を記号でも区別する。
背景タブの完了・入力待ちは `ui.toast.delivery = "herdr"`、
`ui.toast.delay_seconds = 1` で Herdr 内に通知する。
これらの値は Nix の `settings.ui` を変更して管理する。
Home Manager 反映後は実行中の Herdr で設定を再読み込みする。

既存の tmux 設定はそのまま利用できる。両方の既定 prefix が `Ctrl+b` のため、
最初は tmux の外で Herdr を起動する。

| 操作 | キー |
| --- | --- |
| 前・次のワークスペースへ移動 | `Ctrl+Alt+t/s` |
| 左・右のペインへ移動 | `Ctrl+Alt+d/n` |
| 上・下のペインへ移動 | `Ctrl+Alt+Shift+t/s` |
| 前・次のタブへ移動 | `Ctrl+Alt+i/u` |
| ペインの最大化・復帰 | `Ctrl+Alt+z` |
| 左右に分割 | `Ctrl+b` → `v` |
| 上下に分割 | `Ctrl+b` → `-` |
| タブを追加 | `Ctrl+b` → `c` |
| ワークスペースを追加 | `Ctrl+b` → `Shift+n` |
| ワークスペースを選択 | `Ctrl+b` → `w` |
| キー一覧 | `Ctrl+b` → `?` |
| プロセスを残して離脱 | `Ctrl+b` → `q` |

既定の `Ctrl+b` → `h/j/k/l`、`p/n`、`z` も併用できる。
ワークスペースは選択モードを開かずに直接切り替えられる。
OS 側の `Alt+t/s` と方向を揃え、Herdr 内では Ctrl を加える。
`Ctrl+b` → `w` の移動モードでは、`d/s/t/n` でペイン、上下矢印でワークスペースを選ぶ。
macOS の Ghostty では左 Option を Alt として使う。
`Alt` はウィンドウ管理、`Ctrl+Shift` は外側の端末、上記の `Ctrl+Alt` は Herdr に割り当てる。
ただし、`Ctrl+Alt+数字`、`Ctrl+Alt+Tab`、`Ctrl+Alt+f` は既存の WM 操作に使用している。

この文字キーの配置は Kanata の英数レイヤーを前提とする。
日本語レイヤーでは出力が変わるため、操作前に通常の入力切り替えで英数へ戻す。
Herdr の `switch_ascii_input_source_in_prefix` は Kanata のレイヤーを同期しないため、
この設定例では有効化しない。

再度、同じセッション名を指定して起動すると、そのセッションに接続する。
`herdr server stop` は内部のシェルやエージェントも終了するため、離脱には使わない。

## プロジェクトごとのウィンドウ

watari では Ghostty のウィンドウと Herdr のセッションをプロジェクトごとに分ける。

| プロジェクト | セッション | 外側のシェルからの接続 |
| --- | --- | --- |
| dotfiles | `dotfiles` | `herdr session attach dotfiles` |
| Kaggriculture | `default` | `herdr session attach default` |

各コマンドは別々の Ghostty ウィンドウで実行する。
引数なしの `herdr` は引き続き Kaggriculture の `default` に接続する。
Kaggriculture の既存の担当・自動化は `default` に残し、その中の workspace で切り替える。
dotfiles の会話は専用セッション内のタブで切り替える。

セッション間ではペイン、エージェント一覧、ソケット、保存された実行状態が独立する。
設定ファイルとファイルアクセス権限は共有する。
CLI で別セッションを操作するときは `herdr --session dotfiles ...` のように対象を明示する。
現在の通知は Herdr 内表示なので、隠れたウィンドウの完了・入力待ちはそのウィンドウで確認する。

## エージェント連携

Herdr 内のペインで `codex`、`claude`、`hermes` を起動すると、画面から状態を検出する。
Codex の公式連携は Home Manager の activation で導入・更新する。
`flake.lock` で固定した Herdr に付属する公式インストーラーを、書き込み可能な
Codex 設定の生成後に実行する。既存の設定と他のフックを保持しながら、
`herdr-agent-state.sh`、`hooks.json`、`features.hooks` を管理する。
連携スクリプトが使用する `python3` も Home Manager で低い優先度で導入する。
既存の Python 環境があればそちらを優先し、プロファイル内の実行ファイルの衝突を避ける。

通常は `nh darwin switch . -H watari` で反映する。
連携だけを先に反映する場合は、環境変数を読み込んだ通常のシェルで実行する。

```sh
nix run .#herdr -- integration install codex
herdr integration status
```

watari のシステム世代 346 で全体ビルドと通常の Home Manager activation を検証済み。
`herdrMutableConfig` と `herdrCodexIntegration` が実行され、適用前の Herdr/Codex 設定と
フックの内容が保持されることを確認した。設定再読み込み後も Herdr サーバーは継続し、
公式連携は `current (v8)`、設定検証は `config: ok` となった。

Claude Code や Hermes でもネイティブのセッション ID を使った復元を利用する場合は、
初回セットアップの Integrations 画面、または必要なエージェントのコマンドから追加する。

```sh
herdr integration install claude
herdr integration install hermes
```

連携のインストール後は対象エージェントを起動し直す。
Codex の初回起動で `Hooks need review` が出た場合は、`Review hooks` から
`SessionStart` の `herdr-agent-state.sh` を確認し、そのフックを信頼する。
通常画面からは `/hooks` でも確認できる。`herdr integration status` の
`current` はインストール状態であり、Codex 側の信頼確認の完了を意味しない。
実行中のエージェントや Herdr サーバーを activation から停止・再起動することはない。
Codex 以外の連携は各プロファイルの設定先を確認して手動で導入する。
Codex 連携は `CODEX_HOME`、Hermes 連携は `HERMES_HOME` の設定先を使う。
このリポジトリの Codex は XDG 配下の `~/.config/codex` を使用するため、
activation はそのパスを明示し、手動導入時は Home Manager の環境変数が
読み込まれた通常のシェルで実行する。
Hermes の独立したプロファイルを使う場合も、そのプロファイルの設定先を確認する。

Codex 連携の activation を削除しても、導入済みのフックは自動削除しない。
連携を止める場合は activation を削除したうえで
`herdr integration uninstall codex` を実行する。

## 会話の復元確認

通常の離脱は `Ctrl+b` → `q` を使う。サーバーを停止すると内部のプロセスは
終了するが、公式連携が会話 ID を報告済みのペインは、その会話を再開できる。
復元を試すときは専用の名前付きセッションを用意する。

```sh
herdr session attach herdr-check
```

その中で Codex と短い検証用の会話をし、入力待ちになったら離脱する。
Herdr の外のシェルで、検証用セッションだけを停止して再接続する。

```sh
herdr session stop herdr-check
herdr session attach herdr-check
```

元の会話が表示され、その続きを答えられることを確認する。
シェルだけが戻った場合は Codex のフックの信頼状態と会話 ID の報告を確認する。
名前付きセッションでもファイルや認証情報は共有されるため、試験はファイル編集を
伴わない会話にする。

2026-09-23 に Herdr 0.9.1、Codex 0.153.4、公式連携 v8 で検証済み。
初回のフック信頼確認後、検証用サーバーを停止・再接続して同じ会話 ID が復元され、
再提示していない合言葉を答えられることを確認した。

## 更新

```sh
nix flake update herdr-nix
nix build --no-link .#herdr
nh darwin switch . -H watari
```

バイナリは Nix で管理するため、更新には `herdr update` を使わない。
動作中のサーバーは以前のバイナリを使い続ける。実行中の作業を終えてから
`herdr server stop`、`herdr` の順で再起動する。

参照: [公式ドキュメント](https://herdr.dev/docs/)、
[キー操作](https://herdr.dev/docs/keyboard/)、
[エージェント連携](https://herdr.dev/docs/integrations/)。
