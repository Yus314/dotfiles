{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.kimi-cli;
  tomlFormat = pkgs.formats.toml { };
  jsonFormat = pkgs.formats.json { };
in
{
  options.programs.kimi-cli = {
    enable = lib.mkEnableOption "Kimi Code CLI - AI-powered terminal agent by Moonshot AI";

    package = lib.mkOption {
      type = lib.types.package;
      description = "The kimi-cli package to install.";
    };

    settings = lib.mkOption {
      type = tomlFormat.type;
      default = { };
      description = ''
        Configuration written to {file}`~/.kimi/config.toml`.
        When empty (default), config.toml is not managed by this module,
        allowing external tools like sops.templates to manage it.
        See https://moonshotai.github.io/kimi-cli/en/configuration/config-files.html
      '';
    };

    mcpServers = lib.mkOption {
      type = lib.types.attrsOf jsonFormat.type;
      default = { };
      description = ''
        MCP server definitions written to {file}`~/.kimi/mcp.json`.
        Same format as Claude Code MCP servers:
        `{ serverName = { command = "..."; args = [...]; env = {...}; }; }`
      '';
    };

    custom-instructions = lib.mkOption {
      type = lib.types.lines;
      default = "";
      description = ''
        Content for {file}`~/.kimi/AGENTS.md`, injected into the agent's system prompt.
        See https://moonshotai.github.io/kimi-cli/en/customization/agents.html
      '';
    };

    skills = lib.mkOption {
      type = lib.types.either (lib.types.attrsOf (lib.types.either lib.types.lines lib.types.path)) lib.types.path;
      default = { };
      description = ''
        Custom skills. Attribute set of skill name to content (string or path).
        Creates {file}`~/.kimi/skills/<name>/SKILL.md`.
        Or a path to a directory containing skill folders.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = !lib.isPath cfg.skills || lib.pathIsDirectory cfg.skills;
        message = "`programs.kimi-cli.skills` must be a directory when set to a path";
      }
    ];

    home.packages = [ cfg.package ];

    home.file = lib.mkMerge [
      (lib.mkIf (cfg.settings != { }) {
        ".kimi/config.toml".source = tomlFormat.generate "kimi-config.toml" cfg.settings;
      })

      (lib.mkIf (cfg.mcpServers != { }) {
        ".kimi/mcp.json".text = builtins.toJSON { mcpServers = cfg.mcpServers; };
      })

      (lib.mkIf (cfg.custom-instructions != "") {
        ".kimi/AGENTS.md".text = cfg.custom-instructions;
      })

      (lib.mkIf (lib.isPath cfg.skills) {
        ".kimi/skills" = {
          source = cfg.skills;
          recursive = true;
        };
      })

      (lib.mkIf (builtins.isAttrs cfg.skills && cfg.skills != { }) (
        lib.mapAttrs' (
          name: content:
          if lib.isPath content && lib.pathIsDirectory content then
            lib.nameValuePair ".kimi/skills/${name}" {
              source = content;
              recursive = true;
            }
          else
            lib.nameValuePair ".kimi/skills/${name}/SKILL.md" (
              if lib.isPath content then { source = content; } else { text = content; }
            )
        ) (if builtins.isAttrs cfg.skills then cfg.skills else { })
      ))
    ];
  };
}
