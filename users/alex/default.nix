{ pkgs, ... }:

{

  # This value determines the home Manager release that your
  # configuration is compatible with. This helps avoid breakage
  # when a new home Manager release introduces backwards
  # incompatible changes.
  #
  # You can update home Manager without changing this value. See
  # the home Manager release notes for a list of state version
  # changes in each release.
  home.stateVersion = "24.11";

  programs = import ./programs;

  # link the configuration file in current directory to the specified location in home directory
  # home.file.".config/i3/wallpaper.jpg".source = ./wallpaper.jpg;

  # link all files in `./scripts` to `~/.config/i3/scripts`
  # home.file.".config/i3/scripts" = {
  #   source = ./scripts;
  #   recursive = true;   # link recursively
  #   executable = true;  # make all files executable
  # };

  # encode the file content in nix configuration file directly
  # home.file.".xxx".text = ''
  #     xxx
  # '';

  # set cursor size and dpi for 4k monitor
  # xresources.properties = {
  #  "Xcursor.size" = 16;
  #  "Xft.dpi" = 172;
  # };

  # Packages that should be installed to the user profile.
  home.packages = with pkgs; [
    oh-my-zsh
    zsh-autosuggestions
    zsh-syntax-highlighting
  ];

  home.sessionVariables = {
    EDITOR = "emacs";
    LANG = "es_ES.UTF-8";
    LC_ALL = "es_ES.UTF-8";
    PAGER = "less";
  };

  home.shellAliases = {
    l = "ls";
    la = "ls -A";
    ll = "ls -lh";
    lla = "la -lhA";
  };
}
