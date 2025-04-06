{
  buildNpmPackage,
  cairo,
  cmake,
  fetchFromGitHub,
  fetchNpmDeps,
  lib,
  nodejs,
  pango,
  pixman,
  pkg-config,
  ...
}:

buildNpmPackage rec {
  pname = "overleaf";
  version = "5.3.3";

  src = fetchFromGitHub {
    owner = "overleaf";
    repo = "overleaf";
    rev = "84413c991dedc28e8a51974d44e6dede3d344bec";
    hash = "sha256-93h6mh62Aprc1rTqw/CKQQz4BX1FQ+DOnACF+xv7pLA=";
  };

  patches = [ ./update-nan.patch ];

  npmDeps = fetchNpmDeps {
    inherit
      gitDepsLockfiles
      src
      patches
      ;
    name =
      let
        name = "${pname}-${version}";
      in
      "${name}-npm-deps";
    hash = "sha256-nItYjIJQw0PXnpEo54sv+3gYqS8MAJ0SoK0g5h5ol+U=";
  };

  gitDepsLockfiles = import ./lockfiles;

  buildInputs = [
    cairo
    pango
    pixman
  ];

  nativeBuildInputs = [
    cmake
    pkg-config
  ];

  npmWorkspace = "services/web";
  npmBuildScript = "webpack:production";

  installPhase = ''
    # This is in the official Dockerfile. It lets the history-v1 service find
    # the configuration needed to start.
    cp server-ce/config/production.json services/history-v1/config/
    cp server-ce/config/custom-environment-variables.json services/history-v1/config/

    mkdir -p $out/share
    cp -r {server-ce,services,libraries,node_modules} $out/share

    ${lib.concatMapStringsSep "\n"
      (app: ''
        main=$(node -e "console.log(require('$out/share/services/${app}/package.json').main || 'app.js')")
        # Overleaf assumes that process.argv[1] is a path to a script when
        # looking for the settings file, so we use the package directory here.
        makeWrapper ${nodejs}/bin/node $out/bin/overleaf-${app} \
          --add-flags "share/services/${app}/$main" \
          --chdir $out
      '')
      [
        "chat"
        "clsi"
        "contacts"
        "docstore"
        "document-updater"
        "filestore"
        "history-v1"
        "notifications"
        "project-history"
        "real-time"
        "web"
      ]
    }
  '';

  makeCacheWritable = true;
  dontUseCmakeConfigure = true;
  env.CYPRESS_INSTALL_BINARY = "0";

  passthru.updateScript = ./update.sh;

  meta = with lib; {
    description = "A web-based collaborative LaTeX editor";
    homepage = "https://github.com/overleaf/overleaf";
    license = licenses.agpl3Only;
    maintainers = [ ];
    mainProgram = "overleaf";
    platforms = platforms.unix;
  };
}
