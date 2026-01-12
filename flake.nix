{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    haskell-flake.url = "github:srid/haskell-flake";
  };
  outputs =
    inputs@{
      self,
      nixpkgs,
      flake-parts,
      ...
    }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = nixpkgs.lib.systems.flakeExposed;
      imports = [ inputs.haskell-flake.flakeModule ];

      perSystem =
        { self', pkgs, ... }:
        {

          # Typically, you just want a single project named "default". But
          # multiple projects are also possible, each using different GHC version.
          haskellProjects.default = {
            # The base package set representing a specific GHC version.
            # By default, this is pkgs.haskellPackages.
            # You may also create your own. See https://community.flake.parts/haskell-flake/package-set
            # basePackages = pkgs.haskellPackages;

            # Extra package information. See https://community.flake.parts/haskell-flake/dependency
            #
            # Note that local packages are automatically included in `packages`
            # (defined by `defaults.packages` option).
            #
            packages = {
              cabal-hoogle = {
                source = pkgs.fetchFromGitHub {
                  owner = "YourFin";
                  repo = "cabal-hoogle";
                  rev = "fc857f3e42ba3f8e2f456ec4e453ca63d0d8f43a";
                  hash = "sha256-D9Pi88sSWs4EfZT1QtnjcjvD13D2xH4ZPDS6Dl/EmrI=";
                };
              };
              # aeson.source = "1.5.0.0";      # Override aeson to a custom version from Hackage
              # shower.source = inputs.shower; # Override shower to a custom source path
            };
            settings = {
              cabal-hoogle = {
                check = false;
                broken = false;
              };
              #  aeson = {
              #    check = false;
              #  };
              #  relude = {
              #    haddock = false;
              #    broken = false;
              #  };
            };

            devShell = {
              enable = true;

              mkShellArgs = {
                nativeBuildInputs = with pkgs; [
                  just
                  nushell
                  fzf
                  curl
                  tree-sitter
                ];
                shellHook = ''
                  export CABAL_DIR=$(pwd)/.cabal
                  export CABAL_CONFIG=$(pwd)/.cabal/config
                '';
              };
              # Programs you want to make available in the shell.
              # Default programs can be disabled by setting to 'null'
              # tools = hp: { fourmolu = hp.fourmolu; ghcid = null; };
              tools =
                hp: with pkgs; {
                  fourmolu = hp.fourmolu;
                  hpack = hp.hpack;
                  cabal-hoogle = hp.cabal-hoogle;
                };

              # Check that haskell-language-server works
              # hlsCheck.enable = true; # Requires sandbox to be disabled
            };
          };

          # haskell-flake doesn't set the default package, but you can do it here.
          packages.default = self'.packages.example;
        };
    };
}
