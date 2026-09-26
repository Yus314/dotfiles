{
  config,
  lib,
  pkgs,
  ...
}:
let
  credentialDirectory = "${config.home.homeDirectory}/.kaggle";
  hasToken = builtins.pathExists ./secrets.yaml;
in
{
  home.packages = [ pkgs.kaggle ];

  # Bootstrap without a placeholder credential. Only encrypted data enters the
  # Nix store; sops-nix decrypts the token on the host that imports this module.
  sops.secrets = lib.optionalAttrs hasToken {
    kaggle-api-token = {
      sopsFile = ./secrets.yaml;
      key = "api_token";
      path = "${credentialDirectory}/access_token";
      mode = "0600";
    };
  };

  home.activation.kaggleCredentialDirectory =
    lib.hm.dag.entryBetween [ "sops-nix" ] [ "writeBoundary" ]
      ''
        run ${pkgs.coreutils}/bin/install -d -m 0700 ${lib.escapeShellArg credentialDirectory}
      '';
}
