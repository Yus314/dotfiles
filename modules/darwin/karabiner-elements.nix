# modules/karabiner-elements.nix

{
  config,
  lib,
  pkgs,
  ...
}:

let
  # cfgは config.services.karabiner-elements への短いエイリアス
  cfg = config.services.karabiner-elements;
in
{
  # ====================================================================
  # 1. オプションの定義
  # ここで、あなたが望む services.karabiner-elements = { ... } の形を定義します
  # ====================================================================
  options.services.karabiner-elements = {
    enable = lib.mkEnableOption "Karabiner-Elements configuration managed by Home Manager";

    useGoku = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Whether to use Goku to generate the configuration from an EDN file.";
    };

    gokuConfigPath = lib.mkOption {
      type = lib.types.path;
      description = "Path to the karabiner.edn file used by Goku.";
      # 例: gokuConfigPath = ./karabiner.edn;
    };

    # 関連パッケージのオプション
    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.karabiner-elements;
      description = "The Karabiner-Elements package to install.";
    };
    gokuPackage = lib.mkOption {
      type = lib.types.package;
      default = pkgs.goku;
      description = "The Goku package to use for building the configuration.";
    };
  };

  # ====================================================================
  # 2. 設定の実現 (オプションが有効な場合に実行されるロジック)
  # ====================================================================
  config = lib.mkIf cfg.enable {
    # 必要なパッケージをインストールリストに追加
    home.packages = [ cfg.gokuPackage ]; # Karabiner本体はnix-darwinのsystem.applicationsで管理推奨

    # Gokuを使用する場合のロジック
    # lib.mkIf を使って useGoku が true の場合のみ実行
    config = lib.mkIf cfg.useGoku rec {
      # Home Managerで、ビルドしたファイルをホームディレクトリの適切な場所に配置
      # EDNファイルから karabiner.json をビルドするDerivation
      karabinerJson = pkgs.stdenv.mkDerivation rec {
        pname = "karabiner-config-from-goku";
        version = "local";
        src = cfg.gokuConfigPath; # ユーザーが指定したEDNファイルパスを使用
        nativeBuildInputs = [ cfg.gokuPackage ];

        buildPhase = ''
          export HOME=$(mktemp -d)
          mkdir -p $HOME/.config/karabiner
          cp ${src} $HOME/.config/karabiner/karabiner.edn
          goku
        '';
        installPhase = ''
          local generated_json="$HOME/.config/karabiner/karabiner.json"
          mkdir -p $out
          cp "$generated_json" $out/karabiner.json
        '';
      };
      home.file.".config/karabiner/assets/complex_modifications/karabiner.json" = {
        source = "${karabinerJson}/karabiner.json";
        # この設定により、gokuConfigPathで指定したEDNファイルが変更されると、
        # 自動的にJSONが再ビルドされ、シンボリックリンクが更新される
      };
    };
  };
}
