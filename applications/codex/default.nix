{
  config,
  lib,
  ...
}:

{
  # sops.nix設定 - OpenAI API KEY
  sops.secrets = {
    "codex-openai-api-key" = {
      sopsFile = ./secrets.yaml;
      path = "${config.xdg.configHome}/codex/openai_api_key";
      key = "openai_api_key";
      mode = "0600";
    };
  };

  programs.codex = {
    enable = true;
    settings = {
      sandbox_mode = "workspace-write";
      approval_policy = "on-request";
      sandbox_workspace_write = {
        network_access = true;
      };
    };
  };

  # Fish shellでOPENAI_API_KEY環境変数を設定
  programs.fish.interactiveShellInit = lib.mkAfter ''
    # Load OpenAI API key for Codex CLI
    if test -f "${config.xdg.configHome}/codex/openai_api_key"
      set -gx OPENAI_API_KEY (cat "${config.xdg.configHome}/codex/openai_api_key")
    end
  '';
}
