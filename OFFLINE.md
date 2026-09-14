# Running this config offline / air-gapped

This config only needs the network at *install* time. Nothing phones home
during normal use, so the job is to carry the installed state over and stop
Emacs from trying to fetch anything.

## 1. Start Emacs with `EMACS_OFFLINE` set

```sh
EMACS_OFFLINE=1 emacs
```

This sets `my/offline` in `init.el`, which skips `package-refresh-contents`
and turns off `use-package-always-ensure`. Without it, every package that
isn't already installed costs a DNS timeout at startup.

The variable has to be in the environment Emacs *inherits*. Launching from a
shell is fine; a GUI Emacs started from a desktop launcher won't see a shell
export.

## 2. What to carry over

Everything in `.gitignore` is exactly what a fresh clone lacks, so a clone
alone is not a working config. Copy the whole directory, including:

| Path | Why |
|---|---|
| `elpa/` | all packages, including `elpa/treesit-fold` which is a `:vc` git checkout no archive can supply |
| `tree-sitter/` | compiled grammars — see section 4 |
| `parinfer-rust/` | already contains both the darwin and linux libraries, nothing to do |
| `~/Developer/llm-tool-collection` | sibling checkout pulled in via `:load-path`; its `use-package` form fails at startup if missing |
| `eln-cache/` | optional — regenerating it needs no network |

If the target has an internal ELPA mirror, point `package-archives` at it
but **keep the archive names** from `init.el` (`melpa`, `melpa-stable`,
`elpa`). `cider` is pinned to `"melpa-stable"` *by name*; a mirror that
exposes its packages under any other name silently fails to supply it.

## 3. Check what the machine can actually supply

```sh
emacs --batch -l scripts/check-packages.el init.el
```

No network, installs nothing. Reports every package as installed / built-in /
in-archive / MISSING, then a separate section for tree-sitter grammars:
whether each library loads, whether its source entry is a local directory or
a remote URL, and whether a C compiler is present.

Grammars get their own section because they are shared libraries, not
packages — a clean package report says nothing about them.

## 4. Tree-sitter grammars

### Only two matter

`treesit-language-source-alist` in `init.el` lists 19 languages, but only
two are wired to a major mode:

- **`clojure`** — `clojure-ts-mode` is the Clojure major mode
- **`dockerfile`** — `dockerfile-ts-mode` via `auto-mode-alist`

The other 17 are aspirational. The `*` marker in the check script's output
shows which is which. Nothing breaks if the unmarked ones are absent.

### Two ways to get them onto the box

They are alternatives — pick one.

| | Copy | Needs on the box |
|---|---|---|
| **Compiled library** | `libtree-sitter-clojure.so` into `tree-sitter/` | nothing — but it must be built *for Linux*, so a `.dylib` from a Mac is useless |
| **Source** | ~90 KB of C per grammar | a C compiler |

Copying a compiled library needs no config change at all: Emacs finds it by
filename and never consults `treesit-language-source-alist`. The rest of
this section is about building from source.

### Where the source comes from

The GitHub URLs already in `init.el`:

- <https://github.com/sogaiu/tree-sitter-clojure>
- <https://github.com/camdencheek/tree-sitter-dockerfile>

What makes offline builds possible is that these repos ship a
**pre-generated `src/parser.c`** — the output of the `tree-sitter` CLI,
checked in. So the target needs neither Node nor the CLI, only `cc`.

The complete payload for `clojure` is two files:

```
tree-sitter-clojure/src/parser.c
tree-sitter-clojure/src/tree_sitter/parser.h
```

`dockerfile` additionally has `src/scanner.c` and two extra headers
(`alloc.h`, `array.h`). Verified: a directory stripped to exactly these files
compiles and produces a working parser.

### Making the bundle on a connected machine

```sh
mkdir ts-src && cd ts-src
git clone --depth 1 https://github.com/sogaiu/tree-sitter-clojure
git clone --depth 1 https://github.com/camdencheek/tree-sitter-dockerfile
rm -rf */.git
```

Copying the whole clones (~1.4 MB each) is fine; pruning to `src/` is
optional. Removing `.git` is not optional — see gotchas.

### Installing on the air-gapped box

Unpack so you have `~/.config/emacs/ts-src/tree-sitter-clojure/` etc., then
evaluate once in Emacs — no config change needed:

```elisp
(setq treesit-language-source-alist
      '((clojure    "~/.config/emacs/ts-src/tree-sitter-clojure")
        (dockerfile "~/.config/emacs/ts-src/tree-sitter-dockerfile")))
(treesit-install-language-grammar 'clojure)
(treesit-install-language-grammar 'dockerfile)
```

Emacs 30 treats a URL that resolves to an existing directory as a local
source: it skips `git clone` entirely and compiles from `<dir>/src/` with
`cc`. The libraries land in `~/.config/emacs/tree-sitter/`. The alist is
only consulted while installing — once the `.so` exists, this is permanent.

Then confirm:

```sh
emacs --batch -l scripts/check-packages.el init.el
```

The `clojure *` and `dockerfile *` rows should read `loadable`. Trust an
actual `.clj` buffer over the report, though: a library built against a
newer glibc than the target's fails at parser creation, not at load.

### Without Emacs at all

The same thing the installer does internally:

```sh
cd tree-sitter-clojure/src
cc -fPIC -shared -I. parser.c -o ~/.config/emacs/tree-sitter/libtree-sitter-clojure.so
```

Add `scanner.c` after `parser.c` for grammars that have one.

### Gotchas

- **No revision with a local directory.** An entry like
  `(clojure "/local/dir" "master")` makes treesit run
  `git -C /local/dir checkout master`, which fails on a plain copied-in
  source tree. Leave the revision out (or `nil`). The `javascript`, `tsx`
  and `typescript` entries in `init.el` carry `"master"` — drop it if you
  ever build those locally.
- **`scanner.cc` needs `c++`.** A C-only toolchain builds grammars with a
  `scanner.c` or none; a C++ scanner needs `c++`/`g++` too. Neither of the
  two required grammars has one.
- **The build leaves artifacts in `src/`.** treesit compiles in place, so
  `parser.o` and the library end up next to `parser.c`. Harmless, but don't
  bundle a directory you have already built in — you'd ship stale `.o`
  files for the wrong platform.
- **Grammar ABI.** Emacs 30.2 accepts tree-sitter ABI 13–15. Anything
  recent is fine; the check script's `loadable` verdict is the test.
