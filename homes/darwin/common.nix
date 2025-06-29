{
  pkgs,
  inputs,
  specialArgs,
  ...
}:
let
  inherit (specialArgs) username;
in
{
  imports = [
    inputs.home-manager.darwinModules.home-manager
  ];
  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = false;
    users.${username} = {
      imports = [
        ../common.nix
        ../../modules/nix
      ];
      home = {
        inherit username;
      };
      programs.nix.target.user = true;
      #home.file.".gnupg/gpg-agent.conf".text = ''

      #pinentry-program ${pkgs.pinentry_mac}/Applications/pinentry-mac.app/Contents/MacOS/pinentry-mac
      # default-cache-ttl 34560000
      #  max-cache-ttl 34560000
      #'';
    };
    extraSpecialArgs = {
      inherit inputs;
    };
  };
}
