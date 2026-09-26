{ config, lib, ... }:
let
  upstreamDoctype = ''<!DOCTYPE plist PUBLIC "-//Apple Computer//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">'';
  liveDoctype = ''<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">'';

  serializeLikeLive =
    serviceConfig:
    builtins.replaceStrings [ upstreamDoctype ] [ liveDoctype ] (
      lib.generators.toPlist { escape = true; } serviceConfig
    )
    + "\n";

  kanataPlist = serializeLikeLive config.launchd.daemons.kanata-shingeta.serviceConfig;
  skhdPlist = serializeLikeLive config.launchd.user.agents.skhd.serviceConfig;
in
{
  assertions = [
    {
      assertion = lib.hasInfix liveDoctype kanataPlist && lib.hasSuffix "\n" kanataPlist;
      message = "Kanata launchd plist must use the qualified live XML identity";
    }
    {
      assertion = lib.hasInfix liveDoctype skhdPlist && lib.hasSuffix "\n" skhdPlist;
      message = "skhd launchd plist must use the qualified live XML identity";
    }
  ];

  # Keep serviceConfig as the policy source of truth. Only these two generated
  # plist files need the historical Apple DOCTYPE and terminal newline to avoid
  # a byte-only launchd reload during ordinary source convergence.
  environment.launchDaemons."local.kaki.kanata-shingeta.plist".text = lib.mkForce kanataPlist;
  environment.userLaunchAgents."org.nixos.skhd.plist".text = lib.mkForce skhdPlist;
}
