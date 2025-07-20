{ inputs }:
{
  fcitx5-updated = final: prev: {
    fcitx5 = prev.fcitx5.overrideAttrs (oldAttrs: rec {
      version = "5.1.14";
      src = prev.fetchFromGitHub {
        owner = "fcitx";
        repo = "fcitx5";
        rev = version;
        hash = "sha256-wLJZyoWjf02+m8Kw+IcfbZY2NnjMGtCWur2+w141eS4=";
      };
    });
  };
}
