{pkgs,inputs,specialArgs,...}:
let
  inherit (specialArgs) username;
  in{
imports = [
            inputs.home-manager.darwinModules.home-manager
];
    home-manager = {
      useGlobalPkgs = true;
      useUserPackages = true;
    users.${username} = {
      imports = [
	../common.nix
      ];
      home = {
	inherit username;
        stateVersion = "25.05";
      };
      home.file.".gnupg/gpg-agent.conf".text = ''
        pinentry-program ${pkgs.pinentry_mac}/Applications/pinentry-mac.app/Contents/MacOS/pinentry-mac
        default-cache-ttl 34560000
        max-cache-ttl 34560000
      '';

      nixpkgs.config.allowUnfree = true;
    };
          extraSpecialArgs = {
      inherit inputs;
    };
  };
}
