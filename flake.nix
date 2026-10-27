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
      systems = [ "aarch64-darwin" ];
      imports = [
        inputs.git-hooks.flakeModule
        inputs.treefmt-nix.flakeModule
      ];

      perSystem =
        { config, pkgs, system, ... }:
        let
          workflowFiles = "^\\.github/workflows/.*\\.(yml|yaml)$";
          markdownFormatter = "${inputs.markdown-formatter.packages.${system}.default}/bin/mdfmt";
          commonTools = with pkgs; [
            gh
            swift-format
            swiftlint
          ];
          ciTools = with pkgs; [
            gitleaks
            actionlint
            ghalint
            pinact
            zizmor
          ];
        in
        {
          devShells = {
            default = pkgs.mkShell {
              packages = commonTools;
              shellHook = ''
                ${config.pre-commit.installationScript}
              '';
            };
            ci = pkgs.mkShell {
              packages = commonTools ++ ciTools;
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
                swift = {
                  command = "${pkgs.swift-format}/bin/swift-format";
                  options = [ "format" "--in-place" ];
                  includes = [ "*.swift" ];
                };
                markdown = {
                  command = markdownFormatter;
                  options = [ "--write" ];
                  includes = [ "*.md" ];
                };
              };
              global.excludes = [ ".direnv" ".git" "*.lock" ];
            };
          };

          pre-commit = {
            check.enable = true;
            settings.hooks = {
              end-of-file-fixer.enable = true;
              trim-trailing-whitespace.enable = true;
              check-added-large-files.enable = true;
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
                entry = "${pkgs.pinact}/bin/pinact run";
                files = workflowFiles;
              };
              zizmor = {
                enable = true;
                entry = "${pkgs.zizmor}/bin/zizmor";
                files = workflowFiles;
              };
              statix.enable = true;
              deadnix.enable = true;
              shellcheck.enable = true;
              swiftlint = {
                enable = true;
                entry = "${pkgs.swiftlint}/bin/swiftlint lint --strict";
                types = [ "swift" ];
                pass_filenames = false;
              };
            };
          };
        };
    };
}
