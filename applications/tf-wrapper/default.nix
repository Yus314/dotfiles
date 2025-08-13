{ config, pkgs, ... }:

{
  # tf-wrapperパッケージをインストール
  home.packages = with pkgs; [
    tf-wrapper
  ];

  # sops.nix設定 - フラット構造対応
  sops.secrets = {
    # OCI認証情報（フラットキー指定）
    "tf-wrapper-tenancy" = {
      sopsFile = ./secrets.yaml;
      path = "${config.xdg.configHome}/tf-wrapper/tenancy.txt";
      key = "tenancy_ocid";
    };

    "tf-wrapper-user" = {
      sopsFile = ./secrets.yaml;
      path = "${config.xdg.configHome}/tf-wrapper/user.txt";
      key = "user_ocid";
    };

    "tf-wrapper-fingerprint" = {
      sopsFile = ./secrets.yaml;
      path = "${config.xdg.configHome}/tf-wrapper/fingerprint.txt";
      key = "fingerprint";
    };

    # Terraformバックエンド設定（フラットキー指定）
    "tf-wrapper-backend-bucket" = {
      sopsFile = ./secrets.yaml;
      path = "${config.xdg.configHome}/tf-wrapper/backend-bucket.txt";
      key = "backend_bucket";
    };

    "tf-wrapper-backend-namespace" = {
      sopsFile = ./secrets.yaml;
      path = "${config.xdg.configHome}/tf-wrapper/backend-namespace.txt";
      key = "backend_namespace";
    };

    "tf-wrapper-backend-region" = {
      sopsFile = ./secrets.yaml;
      path = "${config.xdg.configHome}/tf-wrapper/backend-region.txt";
      key = "backend_region";
    };

    # OCI秘密鍵（フラットキー指定）
    "tf-wrapper-private-key" = {
      sopsFile = ./secrets.yaml;
      path = "${config.xdg.configHome}/tf-wrapper/private_key.pem";
      key = "private_key";
      mode = "0600";
    };
  };

  # 設定ディレクトリの作成
  xdg.configFile = {
    # プロファイル設定ファイル（将来の機能拡張用）
    "tf-wrapper/profiles.yaml".text = ''
      # tf-wrapper プロファイル設定
      # 将来的に複数のOCI環境をサポートする場合に使用
      profiles:
        default:
          description: "デフォルトOCI設定"
          config_files:
            - "oci.yaml"
            - "backend.yaml"
          private_key: "oci_private_key.pem"
    '';
  };
}
