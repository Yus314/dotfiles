{ unstable, ... }:
{
  programs.vivaldi = {
    enable = true;

    package = unstable.vivaldi;
    commandLineArgs = [
      "--enable-features=UseOzonePlatfor"
      "--ozone-platform=x11"
    ];
  };
}
