{ sources ? import ./nix/sources.nix
, nixpkgs ? sources.nixpkgs
, pkgs ? import nixpkgs { config = { }; }
, lib ? pkgs.lib
, cargo ? pkgs.cargo
, nix ? pkgs.nix
, makeWrapper ? pkgs.makeWrapper
, darwin ? pkgs.darwin
, stdenv ? pkgs.stdenv
, defaultCrateOverrides ? pkgs.defaultCrateOverrides
, release ? true
}:
let
  cargoNix = import ./crate2nix/Cargo.nix { inherit pkgs release; };
  withoutTemplates = name: type:
    let
      baseName = builtins.baseNameOf (builtins.toString name);
    in
      !(baseName == "templates" && type == "directory");
  crate2nix = cargoNix.rootCrate.build.override {
    testCrateFlags = [
      "--skip nix_integration_tests"
    ];
    crateOverrides = defaultCrateOverrides // {
      crate2nix = { src, ... }: {
        src =
          if release
          then src
          else
            lib.cleanSourceWith {
              filter = withoutTemplates;
              inherit src;
            };
        dontFixup = !release;
      };
      cssparser-macros = attrs: assert builtins.trace "cssparser" true;{
        buildInputs = lib.optionals stdenv.isDarwin [ darwin.apple_sdk.frameworks.Security ];
      };
    } // (
      let
        addLibiconvOverride = prev: {
          buildInputs = (prev.buildInputs or [ ]) ++ (with pkgs; lib.optional stdenv.isDarwin libiconv);
        };
        addLibiconvToAll = libs: lib.genAttrs libs (_: addLibiconvOverride);
      in
        addLibiconvToAll [
            "anyhow"
            "bitflags"
            "crate2nix"
            "crossbeam-utils"
            "libc"
            "log"
            "memchr"
            "pest_derive"
            "proc-macro-error"
            "proc-macro-error-attr"
            "proc-macro2"
            "ryu"
            "serde"
            "serde_derive"
            "serde_json"
            "structopt-derive"
            "syn"
            "typenum"
        ]
    );
  };
  set_templates = if release then "" else "--set TEMPLATES_DIR ${./crate2nix/templates}";
in
pkgs.symlinkJoin {
  name = crate2nix.name;
  paths = [ crate2nix ];
  buildInputs = [ makeWrapper cargo ];
  meta = {
    description = "Nix build file generator for rust crates.";
    longDescription = ''
      Crate2nix generates nix files from Cargo.toml/lock files
      so that you can build every crate individually in a nix sandbox.
    '';
    homepage = https://github.com/kolloch/crate2nix;
    license = lib.licenses.asl20;
    maintainers = [
      {
        github = "kolloch";
        githubId = 339354;
        name = "Peter Kolloch";
      }
      lib.maintainers.andir
    ];
    platforms = lib.platforms.all;
  };
  postBuild = ''
    # Fallback to built dependencies for cargo and nix-prefetch-url
    wrapProgram $out/bin/crate2nix ${set_templates}\
       --suffix PATH ":" ${lib.makeBinPath [ cargo nix pkgs.nix-prefetch-git ]}
    rm -rf $out/lib $out/bin/crate2nix.d
    mkdir -p \
      $out/share/bash-completion/completions \
      $out/share/zsh/vendor-completions
    $out/bin/crate2nix completions -s 'bash' -o $out/share/bash-completion/completions
    $out/bin/crate2nix completions -s 'zsh' -o $out/share/zsh/vendor-completions
  '';
}
