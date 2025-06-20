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
    age = {
      keyFile = "/Users/kaki/.config/sops/age/keys.txt";
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
