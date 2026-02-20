{ pkgs, specialArgs, ... }:
let
  inherit (specialArgs) username;
in
{
  imports = [
    ../../applications/shkd
    ../../applications/yabai
  ];
  home-manager.users.${username} = {
    imports = [ ../desktop.nix ];
    home.file."Library/Application\ Support/AquaSKK/keymap.conf".source = ./keymap.conf;
    home.packages = [
      (pkgs.brewCasks.adobe-acrobat-pro.overrideAttrs (oldAttrs: {

        # 1. ハッシュ値の修正（必須）
        # 元の定義にはハッシュがないため、fetchurl を再定義して正しいハッシュを与えます
        src = pkgs.fetchurl {
          url = builtins.head oldAttrs.src.urls; # 元のURLを引き継ぐ
          hash = "sha256-QSZlKtYqypUYzAAHb+O4Zj1gKbO3Ncl0ykQyhhpFIZA="; # Updated hash from build error
        };
        unpackPhase = ''
          echo "--- Custom unpackPhase started ---"

          # ステップA: DMGファイルのマウント・展開
          # $src (ダウンロードしたdmg) を undmg コマンドでカレントディレクトリに展開します
          undmg $src

          # ステップB: 内部のPKGファイル特定
          # 展開されたファイルの中から .pkg で終わるファイルを探します
          pkgFile=$(find . -maxdepth 2 -name "*.pkg" | head -n 1)

          if [ -z "$pkgFile" ]; then
            echo "Error: .pkg file not found in the DMG image."
            ls -R # デバッグ用に中身を表示
            exit 1
          fi
          echo "Found installer package: $pkgFile"

          # ステップC: PKGの展開 (brew-nixの元のロジックをここで実行)
          # 見つけたPKGに対して xar を実行します
          xar -xf "$pkgFile"

          # ステップD: ペイロード(実際のアプリデータ)の抽出
          # application.pkg のみを展開（サンドボックスの容量制限対策）
          # support.pkg, automator.pkg, armagent.pkg などは不要
          if [ -f "application.pkg/Payload" ]; then
            echo "Extracting payload from: application.pkg/Payload"
            zcat "application.pkg/Payload" | cpio -i
          else
            echo "Error: application.pkg/Payload not found."
            ls -la *.pkg/ 2>/dev/null || ls -la
            exit 1
          fi
        '';
      }))
    ];
    programs.goku = {
      enable = true;
      configFile = ./karabiner.edn;
    };
  };
}
