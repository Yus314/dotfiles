{ unstable, ... }:
{
  programs.vivaldi = {
    enable = false;

    package = unstable.vivaldi;
    commandLineArgs = [
      "--enable-features=UseOzonePlatfor"
      "--ozone-platform=x11"
    ];
  };
}
