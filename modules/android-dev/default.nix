{ config, lib, pkgs, ... }:

{
  options.my.android-dev = {
    extraPackages = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = [];
      description = "Additional packages to install for Android development.";
    };
  };

  config = {
    home.packages = with pkgs; [
      android-tools   # adb, fastboot
      jdk17           # JDK for Gradle builds (Android Studio bundles its own JBR)
      gradle
      kotlin
      kotlin-language-server
      ktlint
      scrcpy          # mirror/control an Android device over adb
    ] ++ config.my.android-dev.extraPackages;
  };
}
