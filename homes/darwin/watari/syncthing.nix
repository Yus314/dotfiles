{
  pkgs,
  specialArgs,
  ...
}:
let
  inherit (specialArgs) username;
in
{
  home-manager.users.${username} = {
    home.packages = [ pkgs.syncthing ];

    services.syncthing = {
      enable = true;
      guiAddress = "127.0.0.1:8384";
      overrideDevices = true;
      overrideFolders = true;
      settings = {
        options = {
          localAnnounceEnabled = true;
          relaysEnabled = true;
          urAccepted = -1;
          limitBandwidthInLan = false;
        };
        devices = {
          "lawliet" = {
            # Lawliet's current Syncthing identity. Keep this paired with
            # systems/nixos/lawliet/syncthing.nix and qualify it against the
            # live `syncthing cli show system` value before rollout.
            id = "Q3KQM42-QOQX74N-WWFNOJJ-YVWL3HZ-RXPPYX5-UUFQQ25-RKHKDJP-6D2EJAR";
          };
          "android-mole" = {
            id = "UWBK2PL-5L6CQUN-PMJF2TQ-5OBPRFT-ZFDRPTK-OXSGBQH-WWU2Y65-7WRVIAF";
            autoAcceptFolders = false;
          };
        };
        folders = {
          "org-tasks" = {
            path = "/Users/${username}/org";
            type = "sendreceive";
            devices = [
              "lawliet"
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
            path = "/Users/${username}/org-knowledge";
            type = "sendreceive";
            devices = [ "lawliet" ];
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
          "weekly-report" = {
            path = "/Users/${username}/weekly-report";
            type = "sendreceive";
            devices = [
              "lawliet"
              "android-mole"
            ];
            ignorePerms = true;
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
            path = "/Users/${username}/obsidian-vault";
            type = "sendreceive";
            devices = [
              "lawliet"
              "android-mole"
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
          "hermes-session-archive-lawliet" = {
            path = "/Users/${username}/.local/share/hermes-session-archive/lawliet";
            type = "receiveonly";
            devices = [ "lawliet" ];
            fsWatcherEnabled = true;
            fsWatcherDelayS = 10;
            rescanIntervalS = 3600;
            versioning = {
              type = "staggered";
              params = {
                cleanInterval = "3600";
                maxAge = "31536000";
              };
            };
          };
          "hermes-session-archive-watari" = {
            path = "/Users/${username}/.local/share/hermes-session-archive/watari";
            type = "sendonly";
            devices = [ "lawliet" ];
            fsWatcherEnabled = true;
            fsWatcherDelayS = 10;
            rescanIntervalS = 3600;
            versioning = {
              type = "staggered";
              params = {
                cleanInterval = "3600";
                maxAge = "31536000";
              };
            };
          };
        };
      };
    };

    home.file = {
      "org/.stignore".text = ''
        // Emacs temp files
        .#*
        *.tmp
        *~
        // macOS metadata
        .DS_Store
        ._*
        // Org internal
        .org-id-locations
        // Hermes local backups (not live Orgzly data)
        .hermes-backups
        .hermes-backups/**
      '';
      "org-knowledge/.stignore".text = ''
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
      '';
      "obsidian-vault/.stignore".text = ''
        // Obsidian workspace (device-specific)
        .obsidian/workspace.json
        .obsidian/workspace-mobile.json
        .obsidian/workspace-cache.json
        // Nix-managed plugins (Home Manager)
        .obsidian/plugins/
        .obsidian/community-plugins.json
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
        // org-roam DB (SQLite + WAL/SHM) - ローカル生成
        org-roam.db
        org-roam.db-wal
        org-roam.db-shm
      '';
    };
  };
}
