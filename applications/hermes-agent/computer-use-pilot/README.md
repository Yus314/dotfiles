# Hermes computer-use read-only pilot

This is an experimental Niri/AT-SPI feasibility pilot, not a general desktop-control interface.

## Scope

The MCP broker exposes exactly `doctor`, `list_apps`, and `get_app_state`. It accepts only the bundled synthetic GTK target, verifies the target process identity before and after collection, and returns a bounded projection. It does not expose host application names, arbitrary text, screenshots, actions, pointer input, or keyboard input. MCP sampling is disabled.

The synthetic target is intentionally started manually; it is not a persistent user service. The AT-SPI launcher is declarative, but the Home Manager configuration should not be activated solely for this pilot until a recurring, non-sensitive GUI-only use case demonstrates user value.

## Verification

Run the focused tests:

```console
python3 -m unittest \
  applications/hermes-agent/scripts/test_computer_use_config.py \
  applications/hermes-agent/computer-use-pilot/test_readonly_broker.py -v
```

Build the candidate Home Manager generation without activating it:

```console
nix build --impure --no-link \
  '.#nixosConfigurations.lawliet.config.home-manager.users.kaki.home.activationPackage'
```

Start the synthetic target only during a smoke test:

```console
hermes-computer-use-synthetic-target
```

Then verify discovery with `hermes mcp test computer-use-linux`. Stop the synthetic target after the test.

## Rollback

For a committed source rollback, use `git revert <pilot-commit>` rather than resetting unrelated work. If a candidate was applied manually, stop `hermes-computer-use-atspi.service`, remove or disable only the `mcp_servers.computer-use-linux` entry, and restore the pre-pilot `~/.hermes/config.yaml` backup. Do not reset the whole Home Manager generation when unrelated changes are present.
