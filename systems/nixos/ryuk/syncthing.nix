# Syncthing - ryuk (lab-main) 設定
{
  config,
  lib,
  pkgs,
  ...
}:
let
  user = "kaki";
  group = "users";

  # デバイスID（各ホストで syncthing --device-id で取得）
  lawlietDeviceId = "5DKI3TB-RHCDNPG-KQFLPIA-NPQNV45-UEPFADB-RQKZBG4-RT6KU6K-P6BX3AP";
  watariDeviceId = "3XNHQ5T-LBTQ3PJ-EXYZUJA-SSUF3B7-GX3XCCU-ADNBUPR-KRDYYJF-JBUIDAG";
  remDeviceId = "BIJF4JD-CUBPXFO-7NLGBYO-55HYH2K-7IV4RI7-ZGH75BB-YJ3SYJK-XBIEGQC";
  androidDeviceId = "UWBK2PL-5L6CQUN-PMJF2TQ-5OBPRFT-ZFDRPTK-OXSGBQH-WWU2Y65-7WRVIAF";
in
{
  services.syncthing = {
    enable = true;
    inherit user group;
    dataDir = "/home/${user}";
    configDir = "/home/${user}/.config/syncthing";
    openDefaultPorts = true;
    guiAddress = "127.0.0.1:8384";
    overrideDevices = true;
    overrideFolders = true;
    settings = {
      options = {
        localAnnounceEnabled = true;
        relaysEnabled = true;
        urAccepted = -1;
      };
      devices = {
        "lawliet" = {
          id = lawlietDeviceId;
        };
        "watari" = {
          id = watariDeviceId;
        };
        "rem" = {
          id = remDeviceId;
        };
        "android-mole" = {
          id = androidDeviceId;
        };
      };
      folders = {
        "org-tasks" = {
          path = "/home/${user}/org";
          type = "sendreceive";
          devices = [
            "lawliet"
            "watari"
            "rem"
            "android-mole"
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
            "lawliet"
            "watari"
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
}
