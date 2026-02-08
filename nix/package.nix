{
  lib,
  stdenv,
  buildNpmPackage,
  fetchNpmDeps,
  nodejs_24,
  makeWrapper,
  python3,
  pkg-config,
  sqlite,
  glib,
  vips,
  libwebp,
  pixman,
  cairo,
  pango,
  libpng,
  libxml2,
  src ? null,
}:

let
  nodejs = nodejs_24;
  finalSrc = if src != null then src else ./.;

  cleanSrc = lib.cleanSourceWith {
    src = finalSrc;
    filter =
      path: type:
      let
        base = baseNameOf path;
      in
      base != "dist"
      && base != ".git"
      && base != "result"
      && base != ".devenv"
      && base != ".env"
      && !lib.hasSuffix ".nix" base;
  };

  frontendNpmDeps = fetchNpmDeps {
    name = "voidauth-frontend-deps";
    src = cleanSrc + "/frontend";
    hash = "sha256-8RNtxaF1nRZnPVW8kRrZU1gSA7NyPxKKRqoz7575QtE=";
  };
in
buildNpmPackage {
  pname = "voidauth";
  version = (lib.importJSON (finalSrc + "/package.json")).version or finalSrc.lastModifiedDate;

  src = cleanSrc;
  npmDepsHash = "sha256-9m6FufdChJmxv6cFGCXv2q9GvEr0jGJek1sDJw+IhX4=";

  nativeBuildInputs = [
    nodejs
    python3
    pkg-config
    pixman
    cairo
    pango
    libpng
    makeWrapper
  ]
  ++ lib.optional stdenv.hostPlatform.isLinux glib;

  buildInputs = [
    vips
    libwebp
    libxml2
    sqlite
  ];

  preBuild = ''
    export HOME=$(mktemp -d)
    export npm_config_cache="$HOME/.npm-frontend"
    mkdir -p "$npm_config_cache"

    # Copy the prefetched cache
    cp -r ${frontendNpmDeps}/_cacache "$npm_config_cache/" 2>/dev/null || true

    pushd frontend
    cp ${frontendNpmDeps}/package-lock.json ./ 2>/dev/null || true
    npm ci --cache "$npm_config_cache" --offline --legacy-peer-deps
    npm rebuild

    # Patch esbuild to skip version check
    if [ -f node_modules/esbuild/install.js ]; then
      sed -i 's/validateBinaryVersion();/\/\/ validateBinaryVersion();/' node_modules/esbuild/install.js
    fi

    patchShebangs node_modules/
    popd
  '';

  buildPhase = ''
    runHook preBuild

    pushd frontend
    npm run build
    popd

    npm run server:build

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p $out/{bin,share/voidauth}

    cp dist/index.mjs $out/share/voidauth/
    cp -r migrations default_email_templates theme $out/share/voidauth/
    cp -r node_modules $out/share/voidauth/

    mkdir -p $out/share/voidauth/frontend
    cp -r frontend/dist/browser/* $out/share/voidauth/frontend/

    makeWrapper ${nodejs}/bin/node $out/bin/voidauth \
      --add-flags "$out/share/voidauth/index.mjs" \
      --set-default NODE_ENV production

    runHook postInstall
  '';

  dontNpmTest = true;
  npmPackFlags = [ "--ignore-scripts" ];
  npmRebuildFlags = [ "--ignore-scripts" ];

  meta = with lib; {
    description = "Single Sign-On for Your Self-Hosted Universe";
    homepage = "https://github.com/voidauth/voidauth";
    license = licenses.agpl3Plus;
    platforms = platforms.linux;
    mainProgram = "voidauth";
  };
}
