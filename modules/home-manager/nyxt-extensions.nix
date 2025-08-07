{
  config,
  lib,
  pkgs,
  ...
}:

with lib;

let
  cfg = config.programs.nyxt;
in
{
  options.programs.nyxt = {
    extensions = mkOption {
      type = types.attrsOf types.path;
      default = { };
      example = literalExpression ''
        {
          "my-extension" = ./my-extension;
          "nx-rbw" = pkgs.fetchFromGitHub {
            owner = "atlas-engineer";
            repo = "nx-rbw";
            rev = "main";
            sha256 = "...";
          };
        }
      '';
      description = ''
        Nyxt extensions to install. The attribute name is the extension name,
        and the value is the path to the extension directory.
        Extensions will be placed in ~/.local/share/nyxt/extensions/.
      '';
    };
  };

  config = mkIf (cfg.enable && cfg.extensions != { }) {
    xdg.dataFile = mkMerge (
      mapAttrsToList (name: path: {
        "nyxt/extensions/${name}".source = path;
      }) cfg.extensions
    );
  };
}
