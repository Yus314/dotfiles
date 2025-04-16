# ./tofi.nix
# Tofi ランチャーの設定
{ pkgs, ... }:

{
  programs.tofi = {
    enable = true;
    settings = {
      # フォント
      font = "Fira Code"; # 更新: 指定された値
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
      anchor = "center";
      # 削除: num-results = 5;
      # 削除: padding-left = "35%";
      # 削除: padding-top = "35%";
    };
  };
}
