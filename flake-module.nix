{
  self,
  inputs,
  lib,
  config,
  ...
}:
let
  inherit (builtins) attrValues pathExists;
  inherit (lib)
    filter
    last
    mapAttrs
    mkOption
    splitString
    types
    ;

  getDefaultPlatform =
    system: if (last (splitString "-" system)) == "linux" then "nixos" else "darwin";

  systemConfigurations =
    platform: hostname: attrs:
    if platform == "nixos" then
      { nixosConfigurations."${hostname}" = inputs.nixpkgs.lib.nixosSystem attrs; }
    else
      { darwinConfigurations."${hostname}" = inputs.nix-darwin.lib.darwinSystem attrs; };

  maybePath = path: if pathExists path then path else null;
in
{
  options.hosts = mkOption {
    default = { };
    type = types.attrsOf (
      types.submodule (
        { name, ... }:
        {
          options = {
            system = mkOption {
              default = "x86_64-linux";
              type = types.str;
            };
            platform = mkOption {
              default = getDefaultPlatform config.hosts.${name}.system;
              type = types.str;
            };
            modules = mkOption {
              default = [ ];
              type = types.listOf types.path;
            };
            username = mkOption {
              default = "kaki";
              type = types.str;
            };
            specialArgs = mkOption {
              default = { };
              type = types.attrs;
            };
          };
        }
      )
    );
  };

  config = rec {
    flake = lib.foldAttrs (host: acc: host // acc) { } (
      attrValues (
        mapAttrs (
          name: cfg:
          systemConfigurations cfg.platform name (
            {
              modules =
                filter (x: x != null) [
                  (maybePath ./systems/${cfg.platform}/${name})
                  (maybePath ./homes/${cfg.platform}/${name})
                ]
                ++ cfg.modules;
              specialArgs = {
                inherit self inputs;
                inherit (cfg) username;
              } // cfg.specialArgs;
            }
            // {
              inherit (cfg) system;
            }
          )
        ) config.hosts
      )
    );
  };
}
