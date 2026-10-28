{
  description = "issue-talk - Hands-free GitHub Issue inbox for iOS";

  nixConfig = {
    extra-substituters = [
      "https://nix-community.cachix.org"
      "https://cache.numtide.com"
    ];
    extra-trusted-public-keys = [
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      "niks3.numtide.com-1:DTx8wZduET09hRmMtKdQDxNNthLQETkc/yaX7M4qK0g="
    ];
  };

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    git-hooks = {
      url = "github:cachix/git-hooks.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    markdown-formatter = {
      url = "github:i9wa4/markdown-formatter";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        flake-parts.follows = "flake-parts";
        git-hooks.follows = "git-hooks";
        treefmt-nix.follows = "treefmt-nix";
      };
    };
  };

  outputs =
    inputs@{ flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [
        "aarch64-darwin"
        "x86_64-linux"
      ];
      imports = [
        inputs.git-hooks.flakeModule
        inputs.treefmt-nix.flakeModule
      ];

      perSystem =
        {
          config,
          pkgs,
          system,
          ...
        }:
        let
          workflowFiles = "^\\.github/workflows/.*\\.(yml|yaml)$";
          markdownFormatter = "${inputs.markdown-formatter.packages.${system}.default}/bin/mdfmt";
          rumdlConfig = pkgs.writeText "rumdl.toml" ''
            [MD013]
            code-blocks = false
            headings = false
            reflow = true
          '';
          # nix develop also sets NIX_BUILD_TOP; only a builder runs underneath it.
          inNixBuild = ''[ -n "''${NIX_BUILD_TOP:-}" ] && [[ "$PWD/" == "$NIX_BUILD_TOP/"* ]]'';
          pinactRun = pkgs.writeShellScript "pinact-run" ''
            if ${inNixBuild}; then
              exec ${pkgs.pinact}/bin/pinact run --fix=false --no-api "$@"
            fi
            exec ${pkgs.pinact}/bin/pinact run "$@"
          '';
          zizmorRun = pkgs.writeShellScript "zizmor-run" ''
            if ${inNixBuild}; then
              exec ${pkgs.zizmor}/bin/zizmor --offline "$@"
            fi
            exec ${pkgs.zizmor}/bin/zizmor "$@"
          '';
          treefmtRun = pkgs.writeShellScript "treefmt-run" ''
            # treefmt-nix checks formatting separately inside the sandbox.
            if ${inNixBuild}; then
              exit 0
            fi
            exec ${pkgs.nix}/bin/nix fmt "$@"
          '';
          commonTools =
            with pkgs;
            [
              gh
              pre-commit
              python3
              swift-format
            ]
            ++ pkgs.lib.optionals pkgs.stdenv.hostPlatform.isDarwin [ pkgs.swiftlint ];
        in
        {
          devShells = {
            default = pkgs.mkShellNoCC {
              packages = commonTools ++ config.pre-commit.settings.enabledPackages;
              shellHook = ''
                ${config.pre-commit.installationScript}
              '';
            };
            ci = pkgs.mkShellNoCC {
              packages = [
                pkgs.gitleaks
                pkgs.python3
              ];
            };
            broker = pkgs.mkShellNoCC {
              packages = [
                pkgs.python3
                pkgs.python3Packages.gunicorn
              ];
            };
          };

          treefmt = {
            projectRootFile = "flake.nix";
            programs = {
              nixfmt.enable = true;
              shfmt = {
                enable = true;
                indent_size = 2;
              };
            };
            settings = {
              formatter = {
                python = {
                  command = "${pkgs.ruff}/bin/ruff";
                  options = [ "format" ];
                  includes = [ "*.py" ];
                };
                swift = {
                  command = "${pkgs.swift-format}/bin/swift-format";
                  options = [
                    "format"
                    "--in-place"
                  ];
                  includes = [ "*.swift" ];
                };
                rumdl = {
                  command = "${pkgs.rumdl}/bin/rumdl";
                  options = [
                    "fmt"
                    "--config"
                    "${rumdlConfig}"
                  ];
                  includes = [ "*.md" ];
                };
              };
              global.excludes = [
                ".direnv"
                ".git"
                "*.lock"
              ];
            };
          };

          pre-commit = {
            check.enable = true;
            settings.hooks = {
              end-of-file-fixer.enable = true;
              # Preserve the exact upstream bytes, including whitespace inside JS templates.
              trim-trailing-whitespace = {
                enable = true;
                excludes = [ "^IssueTalk/Resources/Renderer/mermaid\\.min\\.js$" ];
              };
              # Pinned offline renderer; its hash and license are verified separately.
              check-added-large-files = {
                enable = true;
                excludes = [ "^IssueTalk/Resources/Renderer/mermaid\\.min\\.js$" ];
              };
              detect-private-keys.enable = true;
              check-merge-conflicts.enable = true;
              check-json.enable = true;
              check-yaml.enable = true;
              gitleaks = {
                enable = true;
                pass_filenames = false;
              };
              actionlint.enable = true;
              ghalint = {
                enable = true;
                entry = "${pkgs.ghalint}/bin/ghalint run";
                files = workflowFiles;
              };
              pinact = {
                enable = true;
                entry = "${pinactRun}";
                files = workflowFiles;
              };
              zizmor = {
                enable = true;
                entry = "${zizmorRun}";
                files = workflowFiles;
              };
              statix.enable = true;
              deadnix.enable = true;
              rumdl-check = {
                enable = true;
                entry = "${pkgs.rumdl}/bin/rumdl check --config ${rumdlConfig}";
                types = [ "markdown" ];
              };
              markdown-formatter = {
                enable = true;
                name = "markdown-formatter (all tracked markdown)";
                entry = "${markdownFormatter} --write";
                types = [ "markdown" ];
              };
              shellcheck.enable = true;
              ruff-check = {
                enable = true;
                entry = "${pkgs.ruff}/bin/ruff check --fix";
                types = [ "python" ];
              };
              renderer-integrity = {
                enable = true;
                name = "pinned offline Mermaid asset";
                entry = "${pkgs.python3}/bin/python scripts/check_renderer.py";
                pass_filenames = false;
                always_run = true;
              };
              treefmt = {
                enable = true;
                entry = "${treefmtRun}";
                pass_filenames = false;
                always_run = true;
              };
              swiftlint = {
                enable = pkgs.stdenv.hostPlatform.isDarwin;
                entry = "${pkgs.writeShellScript "swiftlint-hook" ''
                  # Xcode's SourceKit is outside the Nix build sandbox.
                  if ${inNixBuild}; then
                    exec ${pkgs.swiftlint}/bin/swiftlint lint --strict --no-cache --disable-sourcekit "$@"
                  fi
                  export XCODE_DEFAULT_TOOLCHAIN_OVERRIDE="$(/usr/bin/xcode-select -p)/Toolchains/XcodeDefault.xctoolchain"
                  exec ${pkgs.swiftlint}/bin/swiftlint lint --strict --no-cache "$@"
                ''}";
                types = [ "swift" ];
                pass_filenames = false;
              };
            };
          };
        };
    };
}
