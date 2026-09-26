# Kaggle の認証情報

watari の Home Manager に Kaggle CLI を追加する。新しい Personal API Token
を SOPS で暗号化して保存し、sops-nix が `~/.kaggle/access_token` に展開する。
ディレクトリは `0700`、トークンの実体は `0600`。他のホストには配布しない。
環境変数への常時 export や Nix の生成ファイルへの平文埋め込みは行わない。

## 登録・更新

dotfiles のルートで次を実行し、非表示の入力欄にトークンだけを貼り付ける。
コマンドの引数やチャットにトークンを貼り付けない。

```sh
nix shell github:NixOS/nixpkgs/6201e203d09599479a3b3450ed24fa81537ebc4e#sops -c python3 applications/kaggle/register_token.py
```

保存済みのファイルから登録する場合は、同じコマンドの末尾に
`--from-file /absolute/path/to/token` を加える。ファイルの内容はトークン単体とする。
Legacy の `kaggle.json` はこの登録処理の対象外。

macOS のクリップボードにトークンがある場合は、`--from-clipboard` を加える。
クリップボードの内容は表示せず、`KGAT_` で始まるトークンだけを受け付ける。
登録処理はクリップボードを変更しない。

登録処理は標準入力経由で SOPS に値を渡し、復号して一致を確認してから暗号文だけを
`applications/kaggle/secrets.yaml` に保存する。更新時も同じコマンドを使う。
元の入力ファイルがある場合は、その保管・削除を別途管理する。

初回は新しいモジュールと暗号文を Git に追加してから通常の構成反映を行う。
Git ベースの flake では未追跡のファイルを参照できない。

```sh
git add applications/kaggle .sops.yaml .gitignore
sudo darwin-rebuild switch --flake .#watari
```

`homes/darwin/watari/default.nix` の Kaggle import も変更に含める。
`secrets.yaml` が存在しない段階では CLI とディレクトリだけが設定される。
登録後は構成反映が必要で、登録コマンド単独では利用中の認証情報は更新されない。

## 利用上の境界

- `KAGGLE_API_TOKEN` や `KAGGLE_CONFIG_DIR` を別途設定すると、認証元が変わる場合がある。
- `0600` は同じユーザーで動くコードからの読み取りを防がない。
- Notebook、提出アーカイブ、ログ、リプレイ取得処理にはトークンを含めない。
- 漏えい時は Kaggle の設定画面で失効・再発行する。暗号文の更新だけでは失効しない。
- Kaggriculture の公開リプレイ取得・ローカル評価には、このトークンは不要。

認証の仕様: [Kaggle CLI](https://github.com/Kaggle/kaggle-cli/blob/main/docs/README.md)
