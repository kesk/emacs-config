# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A personal Emacs configuration (Evil-mode based, `use-package` driven). There is no
build system, package manifest, or test suite — it's dotfiles. "Correctness" means
"Emacs starts cleanly and the new config does what it says," validated by reloading
Emacs, not by running a test command.

## Validating changes

- Reload config in a running Emacs: `SPC f R` (bound to `load-file user-init-file`).
- Open the config from inside Emacs: `SPC f c`.
- From the shell, a clean-start sanity check: `emacs -Q -l early-init.el -l init.el --eval '(message "ok")'`
  (note: this will hit the network for any package not yet installed, since
  `package.el` auto-refreshes archive contents).
- Startup time and GC count are logged to the `*Messages*` buffer on every boot
  (see the `emacs-startup-hook` in `init.el`) — useful for checking a change didn't
  regress startup performance.
- There is no flycheck/byte-compile CI step; lean on `M-x checkdoc` / loading the file
  interactively to catch errors.

## File layout

- `early-init.el` — runs before package/UI init. GC threshold deferral, frame-alist
  tweaks to avoid flicker, and a macOS/`libgccjit` native-comp PATH fix. Keep this file
  minimal; anything that doesn't need to run before the package system should go in
  `init.el` instead.
- `init.el` — everything else. One file, organized under numbered comment-header
  sections (`;;; 1. PACKAGE MANAGER SETUP`, `;;; 2. EVIL MODE`, `;;; 4. THEME`, etc.).
  Sub-numbers (`2.0.5`, `2.0.7.5`) exist because sections were inserted between
  existing ones over time — when adding a new package, slot it into the matching
  numbered section (or add a new top-level number) rather than appending to the end.
- `custom.el` — managed by Emacs's Customize system (`custom-set-variables` /
  `custom-set-faces`), loaded explicitly from `init.el`. Gitignored; treat it as
  machine-local state, not something to hand-edit for feature changes.
- `secrets.el` — gitignored, holds API keys (e.g. `GEMINI_API_KEY`) loaded via
  `setq`. Never write secrets into `init.el` or any tracked file.
- `var/` — runtime/session state managed by `no-littering` (recentf, savehist,
  save-place, projectile cache, tabspaces session, etc.). Gitignored, not meant to be
  edited by hand.
- `snippets/`, `tree-sitter/`, `parinfer-rust/`, `elpa/`, `eln-cache/`, `transient/` —
  generated/downloaded artifacts (yasnippet snippets, compiled tree-sitter grammars,
  ELPA packages, native-comp cache). Not hand-maintained.

## Architecture notes specific to this config

**Leader keys.** Two `general.el` definers set up in the `GENERAL` section:
`my/leader-def` on `SPC` (global commands, namespaced like `SPC f` file, `SPC g` git,
`SPC b` buffer, `SPC o` org, `SPC p` project/workspace) and `my/local-leader-def` on
`ö` (mode-local commands, e.g. Clojure refactors under `cider-mode-map` /
`clojure-ts-mode-map`). When adding a new command, follow the existing
`"<key>" '(command :which-key "label")` convention and put it under the right
namespace rather than inventing a new top-level prefix.

**Workspaces.** `tabspaces` provides project-scoped workspaces/tabs, with
session persistence into `var/tabspaces-session.eld`. `projectile` is the underlying
project-root provider (`projectile-project-search-path` is `~/Developer/`) and is
relied on elsewhere (e.g. `consult-project-function`, `my/copy-with-reference`).

**Local sibling-repo packages.** One package is pulled via `:load-path` from a
sibling checkout under `~/Developer/`: `llm-tool-collection`
(`~/Developer/llm-tool-collection`), which is not published to MELPA. It is a local
development dependency — if the checkout is missing on a machine, its `use-package`
form will fail at startup. `treesit-fold` instead uses `:vc` to pull a specific
GitHub branch directly (no local checkout needed).

`tabspaces` and `clojure-ts-mode` were previously local patched forks, but upstream
absorbed the equivalent changes in both cases, so they now come from MELPA like
everything else. Note that `tabspaces` development has moved from GitHub to
<https://codeberg.org/mclear-tools/tabspaces>.

**Package pinning.** Nothing is pinned except `cider`, which uses `:pin
"melpa-stable"` to track tagged releases (2.x) rather than MELPA's master snapshots.
The `melpa-stable` archive is only consulted for packages that explicitly `:pin` to
it — MELPA's date-based versions always sort above stable's semantic versions, so
unpinned packages resolve to MELPA regardless. Note that `package-upgrade-all` can
delete a package whose name is also built into Emacs (this has happened with
`transient`) without reinstalling it; check `ls elpa/ | grep transient` after bulk
upgrades.

**Lisp editing stack.** `electric-pair-mode` is globally on but explicitly disabled
in Lisp-like modes (`emacs-lisp-mode`, `clojure-ts-mode`, `lisp-data-mode`) because it
conflicts with `parinfer-rust-mode`, which is hooked into both `emacs-lisp-mode` and
`clojure-ts-mode` for structural paren editing. `my/lisp-syntax-setup` widens the
symbol syntax class for `-?!><:/.* ` so Evil word-motions treat e.g. `my/foo!` as one
word. `evil-multiedit` temporarily disables `parinfer-rust-mode` for the duration of a
multiedit session (see the hook in the `EVIL MULTIEDIT` section) to avoid the two
fighting over buffer edits.

**Clojure/CIDER workflow.** `clojure-ts-mode` (tree-sitter based; the legacy
`clojure-mode`/`tree-sitter` packages were removed in favor of built-in `treesit`,
see commit `56e2e6c`) is the active major mode. Several custom tree-sitter node
helpers exist for the Clojure grammar (`my/find-containing-seq-node`,
`my/find-parent-form`, the `my/clojure-jump-*-lit*` family) backing custom Evil motions
(`(`/`)`, `W`/`E`/`B`, `A`/`I` are rebound in `clojure-ts-mode-map` to jump by
form/literal rather than Emacs's default sexp motions). CIDER's REPL helpers
(`my/cider-run-start/stop/go/reset/reload-all-ns`) assume a Clojure REPL exposing a
`user/start`, `user/stop`, `user/go`, `user/reset`, `user/reload-all-ns` API (the
common Integrant/Stuart Sierra reloaded-workflow convention) — these are config-side
glue, not guaranteed to exist in every Clojure project opened.

**AI integration.** `gptel` is configured with Gemini as the backend
(`gptel-make-gemini`, model `gemini-2.0-flash`), reading the API key from
`secrets.el`/`GEMINI_API_KEY`. `llm-tool-collection` registers a set of tool
functions into `gptel` via `gptel-make-tool` for tool-calling.

## Conventions to follow when editing `init.el`

- Wrap each package in its own `(use-package ... )` form; configuration for that
  package belongs in its `:init`/`:config`, not scattered elsewhere in the file.
- Custom interactive commands are prefixed `my/` (e.g. `my/copy-with-reference`,
  `my/center-frame`) — keep using that prefix for new ones to avoid colliding with
  package-provided names.
- When a new keybinding belongs to a specific mode rather than globally, bind it
  with `general-define-key :keymaps '<mode>-map` or under `my/local-leader-def`
  scoped to that mode, mirroring the existing Clojure/CIDER/Markdown/Org sections —
  don't add mode-specific bindings to the global `my/leader-def` block.
