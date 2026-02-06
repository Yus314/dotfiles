# Syncthing - システムレベル設定
# ベストプラクティス: Pure評価モードで動作、sops-nixによるシークレット管理対応
{
  config,
  lib,
  pkgs,
  ...
}:
let
  user = "kaki";
  group = "users";

  # ======================================
  # 設定項目（環境に合わせて変更）
  # ======================================

  # Android端末のSyncthing デバイスID
  # 取得方法: Syncthing → 左上メニュー → デバイスIDを表示
  androidDeviceId = "UWBK2PL-5L6CQUN-PMJF2TQ-5OBPRFT-ZFDRPTK-OXSGBQH-WWU2Y65-7WRVIAF";

  # MoLeプロファイルUUID
  # 取得方法: MoLeアプリ → プロファイル設定 → UUID表示
  # または: /storage/emulated/0/Documents/MoLe/ 内のディレクトリ名
  moleProfileUuid = "54759836-a16e-4485-a015-ac4280535bb4";

  # プロファイル名（ディレクトリ名として使用）
  profileName = "personal";

  # デバイスIDが設定されているかチェック
  isConfigured = !lib.hasPrefix "XXXXXXX" androidDeviceId;
in
{
  services.syncthing = {
    enable = true;

    # ユーザー/グループ設定（重要: 未指定だとsyncthing:syncthingになる）
    inherit user group;

    # ディレクトリ設定
    dataDir = "/home/${user}";
    configDir = "/home/${user}/.config/syncthing";

    # ファイアウォール自動設定
    # 22000/TCP+UDP: 同期トラフィック
    # 21027/UDP: デバイス検出
    openDefaultPorts = true;

    # GUI設定（ローカルのみ）
    guiAddress = "127.0.0.1:8384";

    # 宣言的設定モード
    # true = Nix設定にないデバイス/フォルダは削除される
    overrideDevices = true;
    overrideFolders = true;

    # 将来的にsops-nixで証明書管理する場合:
    # key = config.sops.secrets.syncthing_key.path;
    # cert = config.sops.secrets.syncthing_cert.path;

    settings = {
      # グローバルオプション
      options = {
        # LAN内デバイス自動検出
        localAnnounceEnabled = true;
        # リレーサーバー使用（NAT越え用）
        # プライバシー重視の場合は false に
        relaysEnabled = true;
        # 使用状況レポート拒否
        urAccepted = -1;
        # LAN内帯域制限なし
        limitBandwidthInLan = false;
      };

      # デバイス設定
      devices = lib.mkIf isConfigured {
        "android-mole" = {
          id = androidDeviceId;
          name = "Android MoLe";
          # 自動フォルダ承認は無効（セキュリティ）
          autoAcceptFolders = false;
        };
      };

      # フォルダ設定
      folders = lib.mkIf isConfigured {
        "mole-ledger-${moleProfileUuid}" = {
          # PC側の同期パス
          path = "/home/${user}/ledger/${profileName}";
          # 双方向同期
          type = "sendreceive";
          # 共有先デバイス
          devices = [ "android-mole" ];
          # バージョン管理（削除ファイル履歴）
          versioning = {
            type = "staggered";
            params = {
              # クリーンアップ間隔（秒）
              cleanInterval = "3600";
              # 最大保持期間（秒）= 1年
              maxAge = "31536000";
            };
          };
        };
      };
    };
  };

  # 同期ディレクトリとファイルの作成
  system.activationScripts.syncthing-mole-setup = lib.stringAfter [ "users" ] ''
        # ディレクトリ作成
        mkdir -p /home/${user}/ledger/${profileName}
        chown -R ${user}:${group} /home/${user}/ledger

        # .stignoreファイル作成（MoLe IPCディレクトリを除外）
        cat > /home/${user}/ledger/${profileName}/.stignore << 'EOF'
    // MoLe IPC files (do not sync)
    requests/
    responses/
    audit.log

    // Temporary files
    *.tmp
    *.swp
    *~

    // Lock files
    *.lock
    .#*
    *.bak
    EOF
        chown ${user}:${group} /home/${user}/ledger/${profileName}/.stignore

        # journal.ledgerテンプレート作成（存在しない場合のみ）
        if [ ! -f /home/${user}/ledger/${profileName}/journal.ledger ]; then
          cat > /home/${user}/ledger/${profileName}/journal.ledger.template << 'EOF'
    ; MoLe Journal Template
    ; Copy this to journal.ledger and customize

    ; Include mobile transactions from MoLe app
    include mobile.journal

    ; Your accounts and transactions below
    ; account assets:bank:checking
    ; account expenses:food
    EOF
          chown ${user}:${group} /home/${user}/ledger/${profileName}/journal.ledger.template
        fi
  '';
}
