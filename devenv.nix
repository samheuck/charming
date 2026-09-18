{
  pkgs,
  lib,
  ...
}:
let
  my-packages-lib = with pkgs; [
    pkg-config
    gobject-introspection
    glib-networking
    xdotool
    udev
  ];
  my-packages = with pkgs; [
    dioxus-cli
    wasm-bindgen-cli
    wasm-pack
    trunk
    leptosfmt
    at-spi2-atk
    atkmm
    cairo
    gdk-pixbuf
    glib
    gtk3
    harfbuzz
    librsvg
    libsoup_3
    pango
    webkitgtk_4_1
    openssl
  ];

  # The `v8` crate's build script downloads this prebuilt static library with
  # python or curl unless RUSTY_V8_ARCHIVE points at a local file. Fetching it
  # here keeps the download pinned and out of cargo's hands. The build script
  # does not verify the archive matches the crate, so the version must track
  # the `v8` entry in Cargo.lock (enterShell warns when it drifts).
  rustyV8Version = "145.0.0";
  rustyV8Hashes = {
    aarch64-linux = "09jzmb66qk1q1cxkkri93ri58jyx6vlfygcn5l62nl91r5iaz270";
    x86_64-linux = "1hfap9v4x9jgm356sipx3n5f21xf9dwr7ffpabvl3lbq1hy7a5bj";
  };
  librustyV8 = pkgs.fetchurl {
    url = "https://github.com/denoland/rusty_v8/releases/download/v${rustyV8Version}/librusty_v8_release_${pkgs.stdenv.hostPlatform.rust.rustcTarget}.a.gz";
    sha256 = rustyV8Hashes.${pkgs.stdenv.hostPlatform.system};
  };
in
{
  packages = my-packages-lib ++ my-packages;

  env.RUSTY_V8_ARCHIVE = "${librustyV8}";

  enterShell = ''
    # Nix puts every package's include path into NIX_CFLAGS_COMPILE (~70 KB) and the
    # cc-wrapper forwards it on link commands too. gcc then packs all options into
    # one COLLECT_GCC_OPTIONS env string that exceeds Linux's 128 KiB per-string
    # limit, failing doctest links with "cannot execute collect2: Argument list too
    # long". Nothing in this workspace compiles C, so the include paths are unused.
    unset NIX_CFLAGS_COMPILE NIX_CFLAGS_COMPILE_FOR_BUILD

    lockedV8=$(grep -A1 '^name = "v8"$' "$DEVENV_ROOT/Cargo.lock" | sed -n 's/^version = "\(.*\)"$/\1/p')
    if [ "$lockedV8" != "${rustyV8Version}" ]; then
      echo "warning: Cargo.lock has v8 $lockedV8 but devenv.nix pins librusty_v8 ${rustyV8Version}; update rustyV8Version and its hashes"
    fi

    export GIO_MODULE_DIR=${pkgs.glib-networking.out}/lib/gio/modules/
    export LD_LIBRARY_PATH="$LD_LIBRARY_PATH:${lib.makeLibraryPath my-packages-lib}"
    export XDG_DATA_DIRS=${pkgs.gsettings-desktop-schemas}/share/gsettings-schemas/${pkgs.gsettings-desktop-schemas.name}:${pkgs.gtk3}/share/gsettings-schemas/${pkgs.gtk3.name}:$XDG_DATA_DIRS;
  '';

  enterTest = ''
    # Building and testing
    cargo build --verbose
    cargo run --bin generate_images img_test
    cargo test --verbose

    # Linting and formatting
    cargo fmt --check
    cargo clippy --all-targets --all-features

    # Build dioxus desktop example
    cd $DEVENV_ROOT/examples/dioxus-desktop-demo
    dx build

    # Build wasm examples 
    cd $DEVENV_ROOT/examples/dioxus-web-demo
    dx build
    cd $DEVENV_ROOT/examples/leptos-demo
    trunk build
    cd $DEVENV_ROOT/examples/sycamore-demo
    trunk build
    cd $DEVENV_ROOT/examples/yew-demo
    trunk build
  '';

  languages.rust = {
    enable = true;
    channel = "stable";
    version = "1.88.0";
    targets = [ "wasm32-unknown-unknown" ];
  };

  git-hooks.hooks = {
    nixfmt-rfc-style.enable = true;
    taplo.enable = true;
    rustfmt.enable = true;
    clippy = {
      enable = true;
      settings = {
        allFeatures = true;
        offline = false;
        denyWarnings = true;
        extraArgs = "--all-targets";
      };
    };
  };
}
