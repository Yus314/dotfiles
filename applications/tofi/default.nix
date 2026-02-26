# ./tofi.nix
# Tofi ランチャーの設定
{
  config,
  lib,
  pkgs,
  ...
}:

{
  programs.tofi = {
    enable = true;
    settings = {
      # フォント
      font = "Bizin Gothic Discord NF"; # 更新: 指定された値
      # フォントサイズ
      font-size = 18;
      # テキストの色
      text-color = "#FFFFFF";
      # プロンプトの背景色 (RGBA)
      prompt-background = "#00000000";
      # プロンプト背景のパディング
      prompt-background-padding = 0;
      # プロンプト背景の角丸半径
      prompt-background-corner-radius = 0;
      # プレースホルダーのテキスト色 (RGBA)
      placeholder-color = "#FFFFFFA8";
      # プレースホルダーの背景色 (RGBA)
      placeholder-background = "#00000000";
      # プレースホルダー背景のパディング
      placeholder-background-padding = 0;
      # プレースホルダー背景の角丸半径
      placeholder-background-corner-radius = 0;
      # 入力フィールドの背景色 (RGBA)
      input-background = "#00000000";
      # 入力フィールド背景のパディング
      input-background-padding = 0;
      # 入力フィールド背景の角丸半径
      input-background-corner-radius = 0;
      # デフォルトの結果項目の背景色 (RGBA)
      default-result-background = "#00000000";
      # デフォルトの結果項目のパディング (縦, 横) - Nixでは文字列で指定
      default-result-background-padding = "4, 10";
      # デフォルトの結果項目の角丸半径
      default-result-background-corner-radius = 0;
      # 選択された結果項目のテキスト色
      selection-color = "#000000";
      # 選択された結果項目の背景色
      selection-background = "#CCEEFF";
      # 選択された結果項目のパディング (縦, 横) - Nixでは文字列で指定
      selection-background-padding = "4, 10";
      # 選択された結果項目の角丸半径
      selection-background-corner-radius = 8;
      # 選択された結果項目内の一致したテキストの色 (RGBA)
      selection-match-color = "#00000000";
      # テキストカーソルのスタイル (block, bar, underline)
      text-cursor-style = "bar";
      # プロンプトのテキスト
      prompt-text = "run: ";
      # プレースホルダーのテキスト
      placeholder-text = "...";
      # 結果リスト項目間のスペース
      result-spacing = 8; # 更新: 指定された値
      # 幅（ピクセル）
      width = 1290; # 更新: 指定された値
      # 高さ（ピクセル）
      height = 480; # 更新: 指定された値
      # 背景色 (RGBA)
      background-color = "#1B1D1EBF"; # 更新: 指定された値
      # アウトライン（外枠線）の幅
      outline-width = 0;
      # アウトライン（外枠線）の色
      outline-color = "#080800";
      # ボーダー（枠線）の幅
      border-width = 3; # 更新: 指定された値
      # ボーダー（枠線）の色
      border-color = "#cceeff";
      # 角丸半径
      corner-radius = 24;
      # ディスプレイのスケーリング設定に従うか
      scale = true;
      # ランチャーの表示位置 (center, top, bottom, left, right, top-left など)
      anchor = "top";
    };
  };

  home.activation.tofiDrunCacheRefresh = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    apps_dir="${config.home.profileDirectory}/share/applications"
    state_dir="${config.xdg.stateHome}/tofi"
    hash_file="$state_dir/desktop-hash"
    cache_file="${config.xdg.cacheHome}/tofi-drun"

    if [ -d "$apps_dir" ]; then
      $DRY_RUN_CMD ${pkgs.coreutils}/bin/mkdir -p "$state_dir"
      new_hash="$(
        ${pkgs.findutils}/bin/find "$apps_dir" -type f -name '*.desktop' -print0 \
          | ${pkgs.coreutils}/bin/sort -z \
          | ${pkgs.findutils}/bin/xargs -0 -r ${pkgs.coreutils}/bin/stat -c '%n %s %Y' \
          | ${pkgs.coreutils}/bin/sha256sum \
          | ${pkgs.coreutils}/bin/cut -d' ' -f1
      )"
      old_hash=""
      if [ -f "$hash_file" ]; then
        old_hash="$(${pkgs.coreutils}/bin/cat "$hash_file")"
      fi
      if [ "$new_hash" != "$old_hash" ]; then
        $DRY_RUN_CMD ${pkgs.coreutils}/bin/rm -f "$cache_file"
        $DRY_RUN_CMD ${pkgs.coreutils}/bin/printf '%s\n' "$new_hash" > "$hash_file"
      fi
    fi
  '';

  xdg.desktopEntries.wlogout = {
    name = "wlogout";
    type = "Application";
    exec = "wlogout";
    terminal = false;
  };
}
