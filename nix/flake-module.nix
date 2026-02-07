{ self, ... }:
{
  perSystem =
    {
      config,
      pkgs,
      ...
    }:
    {
      packages = {
        voidauth = pkgs.callPackage ./package.nix {
          # Pass the flake source
          src = self;
        };
        default = config.packages.voidauth;
      };

      devShells.default = pkgs.mkShell {
        name = "voidauth-dev";

        buildInputs = with pkgs; [
          nodejs_24
          esbuild
          git
          pkg-config
          pixman
          cairo
          pango
          libpng
          sqlite
          vips
          libwebp
          libxml2
          prefetch-npm-deps
        ];

        shellHook = ''
          echo "VoidAuth Development Environment (Node.js $(node --version))"
        '';

        ESBUILD_BINARY_PATH = "${pkgs.esbuild}/bin/esbuild";
      };
    };
}
