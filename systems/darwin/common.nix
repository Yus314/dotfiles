{
  specialArgs,
  lib,
  inputs,
  config,
  ...
}:
let
  inherit (specialArgs) username;
in
{
  imports = [
    ../../modules/darwin
    ../common.nix
    inputs.sops-nix.darwinModules.sops
  ];
  system.stateVersion = 6;
  sops = {
    defaultSopsFile = ../../secrets/default.yaml;
    gnupg = {
      home = "/Users/kaki/.gnupg";
      sshKeyPaths = [ ];
    };
    secrets = {
      gh-token = { };
    };
    templates = {
      "gh-token" = {
        owner = "kaki";
        #group = "users";
        mode = "0440";
        content = ''
          	  access-tokens = github.com=${config.sops.placeholder."gh-token"}
          	'';
      };
    };
  };

  # distributed builds fail with the following error
  # fish: Unknown command: nix-store
  # see the workaround
  # https://github.com/NixOS/nix/issues/7508#issuecomment-2597403478
  programs.fish.shellInit = ''
    if test -e '/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.fish' && test -n "$SSH_CONNECTION"
      source '/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.fish'
    end
  '';

  # nix.extraOptions = ''
  #   !include ${config.sops.templates."gh-token".path}
  # '';
  users = {
    users.${username} = {
      home = "/Users/${username}";
      uid = lib.mkDefault 501;
    };
    knownUsers = [ username ];
  };
}
