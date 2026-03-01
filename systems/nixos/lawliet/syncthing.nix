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

  # 他ホストのデバイスID
  # 取得方法: syncthing --device-id
  watariDeviceId = "3XNHQ5T-LBTQ3PJ-EXYZUJA-SSUF3B7-GX3XCCU-ADNBUPR-KRDYYJF-JBUIDAG";
  ryukDeviceId = "6SK3K4H-L25FKU2-FB4RELG-GZ6HGJ4-77YJUYB-JGZ6H65-53DK2IK-RN572QS";
  remDeviceId = "BIJF4JD-CUBPXFO-7NLGBYO-55HYH2K-7IV4RI7-ZGH75BB-YJ3SYJK-XBIEGQC";

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

    settings = {
      # グローバルオプション
      options = {
        localAnnounceEnabled = true;
        relaysEnabled = true;
        urAccepted = -1;
        limitBandwidthInLan = false;
      };

      # デバイス設定
      devices = lib.mkIf isConfigured {
        "android-mole" = {
          id = androidDeviceId;
          name = "Android MoLe";
          autoAcceptFolders = false;
        };
        "watari" = {
          id = watariDeviceId;
          name = "watari (macOS)";
        };
        "ryuk" = {
          id = ryukDeviceId;
          name = "ryuk (lab-main)";
        };
        "rem" = {
          id = remDeviceId;
          name = "rem (lab-sub)";
        };
      };

      # フォルダ設定
      folders = lib.mkIf isConfigured {
        "mole-ledger-${moleProfileUuid}" = {
          path = "/home/${user}/ledger/${profileName}";
          type = "sendreceive";
          devices = [ "android-mole" ];
          versioning = {
            type = "staggered";
            params = {
              cleanInterval = "3600";
              maxAge = "31536000";
            };
          };
        };
        "org-tasks" = {
          path = "/home/${user}/org";
          type = "sendreceive";
          devices = [
            "android-mole"
            "watari"
            "ryuk"
            "rem"
          ];
          fsWatcherEnabled = true;
          fsWatcherDelayS = 2;
          rescanIntervalS = 300;
          versioning = {
            type = "staggered";
            params = {
              cleanInterval = "3600";
              maxAge = "2592000";
            };
          };
        };
        "org-knowledge" = {
          path = "/home/${user}/org-knowledge";
          type = "sendreceive";
          devices = [
            "watari"
            "ryuk"
            "rem"
          ];
          fsWatcherEnabled = true;
          fsWatcherDelayS = 10;
          rescanIntervalS = 3600;
          versioning = {
            type = "staggered";
            params = {
              cleanInterval = "3600";
              maxAge = "2592000";
            };
          };
        };
        "obsidian-vault" = {
          path = "/home/${user}/obsidian-vault";
          type = "sendreceive";
          devices = [
            "android-mole"
            "watari"
            "ryuk"
            "rem"
          ];
          ignorePerms = true;
          fsWatcherEnabled = true;
          fsWatcherDelayS = 5;
          rescanIntervalS = 1800;
          versioning = {
            type = "staggered";
            params = {
              cleanInterval = "3600";
              maxAge = "2592000";
            };
          };
        };
      };
    };
  };

  # org同期ディレクトリと.stignore作成
  system.activationScripts.syncthing-org-setup = lib.stringAfter [ "users" ] ''
        mkdir -p /home/${user}/org/inbox
        mkdir -p /home/${user}/org-knowledge/zk
        mkdir -p /home/${user}/org-knowledge/archive
        chown -R ${user}:${group} /home/${user}/org /home/${user}/org-knowledge

        cat > /home/${user}/org/.stignore << 'STEOF'
    // Emacs temp files
    .#*
    *.tmp
    *~
    // macOS metadata
    .DS_Store
    ._*
    // Org internal
    .org-id-locations
    STEOF

        cat > /home/${user}/org-knowledge/.stignore << 'STEOF'
    // Emacs temp files
    .#*
    *.tmp
    *~
    // macOS metadata
    .DS_Store
    ._*
    // Org internal
    .org-id-locations
    // org-roam DB (SQLite + WAL/SHM) - ローカル生成
    org-roam.db
    org-roam.db-wal
    org-roam.db-shm
    STEOF

        chown ${user}:${group} /home/${user}/org/.stignore /home/${user}/org-knowledge/.stignore
  '';

  # Obsidian vault同期ディレクトリと.stignore作成
  system.activationScripts.syncthing-obsidian-setup = lib.stringAfter [ "users" ] ''
        mkdir -p /home/${user}/obsidian-vault
        chown ${user}:${group} /home/${user}/obsidian-vault

        STIGNORE="/home/${user}/obsidian-vault/.stignore"
        STIGNORE_NEW="$STIGNORE.new"
        cat > "$STIGNORE_NEW" << 'STEOF'
    // Obsidian workspace (device-specific)
    .obsidian/workspace.json
    .obsidian/workspace-mobile.json
    .obsidian/workspace-cache.json
    // Trash (削除は全端末に反映、ゴミ箱は端末ローカル)
    .trash/
    // macOS metadata
    .DS_Store
    ._*
    // Editor temp files
    .#*
    *.tmp
    *~
    *.swp
    *.swo
    *.bak
    STEOF
        # 内容が同じなら上書きしない (mtime 変更による不要な同期を防止)
        if ! cmp -s "$STIGNORE_NEW" "$STIGNORE" 2>/dev/null; then
          mv "$STIGNORE_NEW" "$STIGNORE"
        else
          rm -f "$STIGNORE_NEW"
        fi
        chown ${user}:${group} "$STIGNORE"
  '';

  # MoLe同期ディレクトリとファイルの作成
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
