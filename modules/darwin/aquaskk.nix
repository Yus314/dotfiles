{
  config,
  lib,
  pkgs,
  ...
}:
let
  # オプションの名前をaquaskkに変更
  cfg = config.my.services.aquaskk;
  tracedPackage = builtins.trace "### AquaSKK package path is: ${cfg.package} ###" cfg.package;
in
{
  options = {
    # オプションの名前をaquaskkに変更
    my.services.aquaskk = {
      enable = lib.mkEnableOption "AquaSKK";
      # デフォルトパッケージをaquaskkに変更
      package = lib.mkPackageOption pkgs "aquaskk" { };
    };
  };

  config = lib.mkIf cfg.enable {
    # systemPackagesは念のため残しておく
    environment.systemPackages = [ cfg.package ];

    # activationScriptsは不要なので削除。代わりに、Nixの作法に則ったシンボリックリンクを作成する。
    # これにより、/etc/profiles/per-user/<username>/Library/Input Methods/AquaSKK.app のようなリンクが作られ、
    # システムがAquaSKKを認識できるようになる。
    system.activationScripts.extraActivation.text = ''
      # 変数を定義します
      # OLD: macOSが実際に参照するパス
      # NEW: Nixでビルドされたパッケージが格納されているパス
            echo "Copying AquaSKK to $OLD 1..."
      OLD="/Library/Input Methods/AquaSKK.app"
      NEW="${cfg.package}/Library/Input Methods/AquaSKK.app"

      echo "Copying AquaSKK to $OLD ..."

      # 既に古いバージョンのAquaSKK.appが存在するかどうかをチェック
      if [ -d "$OLD" ]; then
        # 存在する場合、Nixストアの新しいバージョンと差分があるかチェック
        if ! diff -rq "$NEW" "$OLD"; then
          # 差分があれば、古いものを一度削除してから新しいものをコピーする
          echo "Updating AquaSKK.app..."
          rm -rf "$OLD"
          cp -r "$NEW" "$OLD"
        else
          # 差分がなければ何もしない
          echo "AquaSKK.app is already up-to-date."
        fi
      else
        # そもそも存在しない場合は、単純にコピーする
        echo "Installing AquaSKK.app for the first time..."
        cp -r "$NEW" "$OLD"
      fi
    '';

    # userLaunchAgentsは不要なので削除

    # system.defaultsはAquaSKK用に完全に書き換え
    system.defaults.inputsources.AppleEnabledThirdPartyInputSources = [
      {
        # Info.plistから取得した正しいBundle ID
        "Bundle ID" = "jp.sourceforge.inputmethod.aquaskk";
        InputSourceKind = "Keyboard Input Method";
      }
      {
        "Bundle ID" = "jp.sourceforge.inputmethod.aquaskk";
        "Input Mode" = "jp.sourceforge.inputmethod.aquaskk.Hiragana";
        InputSourceKind = "Input Mode";
      }
      {
        "Bundle ID" = "jp.sourceforge.inputmethod.aquaskk";
        "Input Mode" = "jp.sourceforge.inputmethod.aquaskk.Katakana";
        InputSourceKind = "Input Mode";
      }
      {
        "Bundle ID" = "jp.sourceforge.inputmethod.aquaskk";
        "Input Mode" = "jp.sourceforge.inputmethod.aquaskk.Ascii";
        InputSourceKind = "Input Mode";
      }
      # 必要に応じて他の入力モード（全角英数など）もInfo.plistから追加
    ];
  };
}
