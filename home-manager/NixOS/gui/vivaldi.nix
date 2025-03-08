{ unstable, ... }:
{
  programs.vivaldi = {
    package = unstable.legacyPackages.x86_64-linux.vivaldi;
    enable = false;
  };
}
