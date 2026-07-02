{ config, lib, pkgs, ... }:

{
  options.my.c-dev = {
    extraPackages = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = [];
      description = "Additional packages to install for C development.";
    };
  };

  config = {
    home.packages = with pkgs; [
      # gcc and clang both provide bin/cpp and bin/cc; give gcc priority so
      # buildEnv resolves the collision while keeping gcc/g++ and clang/clang++.
      (lib.hiPrio gcc)
      clang
      gnumake
      cmake
      lldb
      clang-tools   # clangd, clang-format, clang-tidy
      bear          # generate compile_commands.json
      pkg-config
    ]
    # gdb and valgrind don't build on aarch64-darwin
    ++ lib.optionals pkgs.stdenv.isLinux [
      gdb
      valgrind
    ]
    ++ config.my.c-dev.extraPackages;
  };
}
