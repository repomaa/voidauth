{
  description = "VoidAuth - Single Sign-On for Your Self-Hosted Universe";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
  };

  outputs =
    inputs@{
      self,
      flake-parts,
      ...
    }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      imports = [
        ./nix/flake-module.nix
      ];

      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];

      perSystem =
        {
          pkgs,
          ...
        }:
        {
          # Formatter for nix files
          formatter = pkgs.nixfmt;
        };

      flake.nixosModules.voidauth =
        {
          config,
          lib,
          pkgs,
          ...
        }:
        import ./nix/module.nix {
          inherit config lib pkgs;
          voidauthPackage = self.packages.${pkgs.stdenv.hostPlatform.system}.voidauth;
        };
    };
}
