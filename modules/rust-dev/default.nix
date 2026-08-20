{ config, lib, pkgs, ... }:

{
  options.my.rust-dev = {
    extraPackages = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = [];
      description = "Additional packages to install for Rust development.";
    };
  };

  config = {
    home.packages = with pkgs; [
      rustc
      cargo
      clippy
      rustfmt
      rust-analyzer
      cargo-edit
      cargo-watch
    ]
    ++ lib.optional pkgs.stdenv.isLinux mold
    ++ config.my.rust-dev.extraPackages;

    home.sessionPath = [ "$HOME/.cargo/bin" ];

    # On darwin, `cc` resolves to nix's GCC rather than Apple's clang: modules/c-dev
    # installs both gcc and clang, which collide on bin/cc, and gcc holds hiPrio to
    # break the tie. Nix GCC has no macOS SDK on its search path, so it fails to link
    # -liconv (which rustc passes on every *-apple-darwin target) and cannot compile
    # any crate reaching for Apple frameworks — aws-lc-sys, pulled in by
    # reqwest → rustls, trips over both (missing CoreServices/CoreServices.h and
    # "NEON and crypto extensions should be statically available"). Adding libiconv
    # only clears the link error; the framework failures need a compiler that knows
    # the SDK. Pin cargo to Apple's clang instead of depending on PATH order.
    home.file = lib.mkMerge [
      (lib.mkIf pkgs.stdenv.isDarwin {
        ".cargo/config.toml".text = ''
          [target.aarch64-apple-darwin]
          linker = "/usr/bin/cc"

          [env]
          CC = "/usr/bin/cc"
          CXX = "/usr/bin/c++"
        '';
      })

      # mold links noticeably faster than bfd/gold; gcc (our cc) supports
      # -fuse-ld=mold since gcc 12, so this stays a plain rustflag rather
      # than swapping the linker binary itself.
      (lib.mkIf pkgs.stdenv.isLinux {
        ".cargo/config.toml".text = ''
          [target.'cfg(target_os = "linux")']
          rustflags = ["-C", "link-arg=-fuse-ld=mold"]
        '';
      })
    ];
  };
}
