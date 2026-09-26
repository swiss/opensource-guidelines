{
  pkgs,
  lib,
  config,
  ...
}:

let
  # open-govpress (https://gitlab.com/swiss-armed-forces/cyber-command/cea/open-govpress)
  # is the CLI used to render these .adoc documents to PDF. It ships as a
  # generic dynamically-linked Linux binary (electron-builder's tar.gz
  # target), which cannot execute directly on NixOS -- there is no
  # /lib64/ld-linux-x86-64.so.2 and no FHS layout for it to find its shared
  # libraries in. Wrapping it in an FHS environment (the same trick nixpkgs
  # itself uses for Chrome/Electron/AppImage binaries) lets the unmodified
  # upstream tarball run as-is, with no patchelf/rebuild step.
  #
  # The build is fetched from a GitHub Release rather than committed to the
  # repo: at ~112MiB it clears GitHub's 100MB hard limit on regular git
  # objects, and this repo is a fork, which GitHub's LFS policy blocks from
  # uploading *new* LFS objects at all -- release assets hit neither limit.
  govpressVersion = "0.0.15";
  govpressUrl = "https://github.com/736-c41-2c1-e464fc974/opensource-guidelines/releases/download/open-govpress-v${govpressVersion}/open-govpress-${govpressVersion}-linux-x64.tar.gz";
  govpressSha256 = "e676d20f57c7376b24e448e01d9783bd31c9b45ee4126e0865b46890d4171ff5";

  govpressFHS = pkgs.buildFHSEnv {
    name = "open-govpress-fhs";
    targetPkgs =
      pkgs: with pkgs; [
        glib
        nss
        nspr
        atk
        at-spi2-atk
        at-spi2-core
        cups
        dbus
        libdrm
        gtk3
        pango
        cairo
        xorg.libX11
        xorg.libXcomposite
        xorg.libXdamage
        xorg.libXext
        xorg.libXfixes
        xorg.libXrandr
        xorg.libxcb
        xorg.libxshmfence
        libxkbcommon
        mesa
        libGL
        alsa-lib
        expat
        libgbm
        systemd
      ];
  };

  # A deliberately small bundle: the editor counterpart of the git hooks, so
  # that the things the hooks reject are visible while typing rather than at
  # commit time. Every entry below pairs with a hook in git-hooks.hooks, except
  # direnv (which is how the shell gets loaded at all) and AsciiDoc (which is
  # what this repository is written in).
  #
  # nixpkgs carries all of these, so none of them need the
  # extensionsFromVscodeMarketplace escape hatch and its pinned sha256.
  vscodeWithExtensions = pkgs.vscode-with-extensions.override {
    vscodeExtensions = with pkgs.vscode-extensions; [
      # Syntax highlighting and live preview for the 15 documents in docs/.
      asciidoctor.asciidoctor-vscode

      # Loads this devenv automatically, instead of requiring `devenv shell`.
      mkhl.direnv

      # Honours .editorconfig while typing -> editorconfig-checker hook.
      editorconfig.editorconfig

      # devenv.nix itself. Set nix.formatterPath to nixfmt to match the hook.
      jnoortheen.nix-ide

      # Inline shellcheck for tools/*.sh. Note the hook runs it as
      # `-x -o all`, which is stricter than this extension's default, so a
      # clean editor does not guarantee a clean commit.
      timonwong.shellcheck

      # The workflows and publiccode.yml -> yamllint hook.
      redhat.vscode-yaml

      # Schema validation and expression completion for the workflows in
      # .github/workflows/. CI is the publishing pipeline here, so those two
      # files carry more weight than their size suggests.
      github.vscode-github-actions
    ];
  };
in
{
  env = {
    DO_NOT_TRACK = 1;

    # Interactive devenvs get the editor; CI does not. The lint workflow runs
    # `devenv shell`, and without this it would pull the whole VS Code closure
    # on every push just to run the hooks.
    cicd = lib.mkDefault false;
  };

  dotenv = {
    enable = true;
    disableHint = true;
  };

  # https://devenv.sh/packages/
  packages =
    with pkgs;
    [
      git
      gh
      curl

      # document creation / verification
      #
      # Used ad hoc throughout this repo's Markdown -> AsciiDoc migration to
      # render and sanity-check every converted .adoc file; kept here so that
      # workflow doesn't depend on remembering `nix-shell -p asciidoctor`.
      asciidoctor-with-extensions # asciidoctor-pdf, asciidoctor-reducer, asciidoctor-diagram
      pandoc

      # headless rendering
      xvfb-run
    ]
    #
    # Interactive devenvs only: these are never needed to render or to lint,
    # and CI should not pay for them. Enter CI/CD mode with
    # `devenv --option env.cicd:bool true ...`.
    #
    ++ lib.optionals (!config.env.cicd) [
      vscodeWithExtensions
    ];

  # https://devenv.sh/git-hooks/
  #
  # Recommended by git-hooks.nix, and much faster than the Python pre-commit on
  # a repository this small, where process startup dominates.
  git-hooks.package = pkgs.prek;

  git-hooks.hooks = {
    # Line endings and whitespace. The .adoc sources came through a
    # Word -> Markdown -> AsciiDoc migration, which is exactly the kind of
    # pipeline that reintroduces CRLF one file at a time.
    dos2unix = {
      enable = true;
      entry = "${lib.getExe pkgs.dos2unix}";
      args = [ "--info=c" ];
    };

    trim-trailing-whitespace.enable = true;
    end-of-file-fixer.enable = true;

    # The workflow invokes tools/*.sh directly (`run: tools/site-index.sh`), so
    # a dropped exec bit breaks the Pages deploy rather than anything local.
    check-executables-have-shebangs.enable = true;
    check-shebang-scripts-are-executable = {
      enable = true;
      # .envrc is sourced by direnv, never executed. Its shebang is there to
      # get shell highlighting and the shellcheck directive on line 2, so
      # marking it executable would be wrong in the way this hook warns about.
      excludes = [ "^\\.envrc$" ];
    };

    check-symlinks.enable = true;

    editorconfig-checker.enable = true;

    nixfmt.enable = true;

    # devenv.lock is JSON, but identify classifies files by extension and does
    # not know `.lock`, so it has to be named explicitly to be checked at all.
    check-json = {
      enable = true;
      files = "(\\.json|devenv\\.lock)$";
      types = [ "file" ];
    };

    # truthy check-keys is off because GitHub Actions' `on:` trigger key is
    # read as the YAML 1.1 boolean `true`; every workflow file would fail.
    yamllint = {
      enable = true;
      settings = {
        strict = true;
        configData = "{ extends: default, rules: { document-start: disable, line-length: {max: 165}, truthy: {check-keys: false} } }";
      };
    };

    ripsecrets.enable = true;

    shellcheck = {
      enable = true;
      args = [
        "-x"
        "-o"
        "all"
      ];
    };

    # git-hooks.nix has no AsciiDoc linter of any kind -- the closest it ships
    # are the prose linters (vale, proselint), which check style rather than
    # syntax and would drown in false positives on four non-English languages.
    # See the script for what this does and does not catch.
    check-asciidoc = {
      enable = true;
      entry = "${config.devenv.root}/tools/check-asciidoc.sh";
      files = "\\.adoc$";
      types = [ "file" ];
    };
  };

  # Print the output of the git hooks that `devenv test` runs, otherwise a
  # failing hook only reports that it failed.
  tasks."devenv:git-hooks:run".showOutput = true;

  enterShell = ''
    (
      set -euo pipefail
      cd '${config.devenv.root}'

      if tty -s; then
        devenv-help
      fi
    )
  '';

  scripts.devenv-help = {
    description = "Print this help";
    exec = ''
      set -euo pipefail
      cd '${config.devenv.root}'

      echo
      echo "Helper scripts provided by the devenv:"
      echo
      sed -e 's| |XXXXXX|g' -e 's|=| |' <<EOF | column -t | sed -e 's|^|- |' -e 's|XXXXXX| |g'
      ${lib.generators.toKeyValue { } (lib.mapAttrs (name: value: value.description) config.scripts)}
      EOF
      echo
    '';
  };

  scripts.lint = {
    description = "Run all git hooks over every file (lint [prek args...])";
    exec = ''
      (
        set -euo pipefail
        cd '${config.devenv.root}'

        prek run "''${@:---all-files}"
      )
    '';
  };

  # The only way in: `open-govpress render <file.adoc>... -o out.pdf`.
  #
  # The wrapper only passes down what has to come from Nix -- store paths and
  # the pinned release -- because shell inside a Nix string is invisible to
  # shellcheck and editorconfig-checker. The logic lives in the script, where
  # the hooks can see it.
  scripts.open-govpress = {
    description = "Render .adoc documents (open-govpress render <file>... -o out.pdf)";
    exec = ''
      GOVPRESS_VERSION='${govpressVersion}' \
      GOVPRESS_URL='${govpressUrl}' \
      GOVPRESS_SHA256='${govpressSha256}' \
      GOVPRESS_FHS='${lib.getExe govpressFHS}' \
      GOVPRESS_XVFB_RUN='${lib.getExe pkgs.xvfb-run}' \
      GOVPRESS_CURL='${lib.getExe pkgs.curl}' \
      GOVPRESS_SHA256SUM='${pkgs.coreutils}/bin/sha256sum' \
        exec '${config.devenv.root}/tools/open-govpress.sh' "''${@}"
    '';
  };

  scripts.render-docs = {
    description = "Render every .adoc document in every language into build/ (render-docs [lang...])";
    exec = ''
      exec '${config.devenv.root}/tools/render-docs.sh' "''${@}"
    '';
  };
}
