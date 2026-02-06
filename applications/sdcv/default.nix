{
  config,
  pkgs,
  lib,
  ...
}:

let
  # 1. ソースの定義: GitHubリポジトリ全体を取得
  sdcv-repo = pkgs.fetchFromGitHub {
    owner = "chenyanming";
    repo = "sdcv_dictionaries";
    rev = "main";
    # 以下のハッシュはダミーです。初回エラー時に表示される正しいハッシュに書き換えてください
    hash = "sha256-4hjbrdjLpNLWOaw8T6jUF/CRZRvJjp4Gws5hFKXUIgM=";
  };
in
{
  # 2. sdcv のインストール
  home.packages = [ pkgs.sdcv ];

  # 3. フォルダごと配置
  # "stardict-kojien6-2.4.2" フォルダの中身（.ifo, .idx, .dict.dz 等）をすべて利用可能にします
  home.file.".stardict/dic/kojien6".source = "${sdcv-repo}/stardict-kojien6-2.4.2";
  home.file.".stardict/dic/jmdict-en-ja".source = "${sdcv-repo}/stardict-jmdict-en-ja-2.4.2";
}
