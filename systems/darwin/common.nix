{specialArgs,lib,...}:let
  inherit (specialArgs) username;
in{
  imports = [../common.nix];
  system.stateVersion = 6;

    users = {
    users.${username} = {
      home = "/Users/${username}";
      uid = lib.mkDefault 501;
    };
    knownUsers = [ username ];
  };
}
