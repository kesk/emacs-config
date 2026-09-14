;;; check-packages.el --- Report which init.el packages a machine can supply  -*- lexical-binding: t; -*-

;; Written for air-gapped/offline setup: answers "if I start Emacs with this
;; init.el here, which packages are actually available?" without installing
;; anything or touching the network.

;;; Usage:
;;
;;   emacs --batch -l scripts/check-packages.el
;;   emacs --batch -l scripts/check-packages.el /path/to/other/init.el
;;
;; With no argument it reads init.el from `user-emacs-directory', so run it
;; against a checkout with an explicit path:
;;
;;   emacs --batch -l ~/Developer/emacs-config/scripts/check-packages.el \
;;                    ~/Developer/emacs-config/init.el
;;
;; Each package is reported as one of:
;;
;;   installed <version>   present in `package-user-dir' (or a site/distro dir)
;;   built-in              shipped with this Emacs, no package needed
;;   in archive: <names>   not installed, but an archive offers it
;;   MISSING               neither installed nor offered by any known archive
;;
;; A `!!' line flags a package whose `:pin' names an archive that cannot
;; supply it -- the case that silently breaks `cider' when a local mirror
;; exposes its packages under a different archive name than "melpa-stable".
;;
;;; Interpreting the output:
;;
;; "in archive"/"MISSING" are judged from the *cached* archive metadata in
;; elpa/archives.  On a machine that has never refreshed, that cache is empty
;; and everything uninstalled reads as MISSING even if a mirror carries it.
;; Point `package-archives' at the mirror, run `package-refresh-contents' once,
;; then re-run this.
;;
;; This checks presence, not version: an ancient distro-supplied `evil' reports
;; "installed" exactly like a current one.
;;
;; Packages that no archive can ever supply -- the `:vc' checkout, the
;; `:load-path' sibling repo -- are listed separately at the end; those must be
;; copied in by hand.
;;
;;; Tree-sitter grammars:
;;
;; Grammars are shared libraries rather than packages, so package.el knows
;; nothing about them and a clean package report says nothing about grammar
;; availability.  The second half of the report covers them separately: whether
;; each library actually loads, whether a local source checkout exists for it
;; (installable offline via init.el's `my/treesit-use-local-sources' fallback)
;; or only a remote URL (needs the network), and whether a C compiler is present
;; to build from source.  The source directory is `EMACS_TS_SRC' or ts-src/
;; next to the init file, matching init.el.

;;; Code:

(require 'package)
(require 'cl-lib)

(defun my/check-packages--scan (init-file)
  "Return (WANTED . MANUAL) parsed from INIT-FILE.
WANTED is a list of (SYMBOL . PINNED-ARCHIVE) for packages resolved through
`package.el'.  MANUAL is a list of (NAME . REASON) for forms that bypass the
archives entirely."
  (let (wanted manual)
    (with-temp-buffer
      (insert-file-contents init-file)
      (goto-char (point-min))
      (while (re-search-forward "^(use-package \\([^ \n)]+\\)" nil t)
        (let* ((name (match-string 1))
               (start (match-beginning 0))
               ;; A form ends at the next top-level sexp or section header.
               (end (or (save-excursion
                          (and (re-search-forward "^(\\|^;;; " nil t)
                               (match-beginning 0)))
                        (point-max)))
               (body (buffer-substring start end)))
          (cond
           ((string-match ":ensure nil" body) (push (cons name "built-in") manual))
           ((string-match ":load-path" body)  (push (cons name "local checkout") manual))
           ((string-match ":vc " body)        (push (cons name "git checkout (:vc)") manual))
           (t (push (cons (intern name)
                          (when (string-match ":pin \"\\([^\"]+\\)\"" body)
                            (match-string 1 body)))
                    wanted))))))
    (cons (nreverse wanted) (nreverse manual))))

(defun my/check-packages-report (init-file)
  "Print an availability report for the packages INIT-FILE asks for."
  (let* ((scan (my/check-packages--scan init-file))
         (wanted (car scan))
         (manual (cdr scan))
         (installed 0) (available 0) (missing '()))
    (princ (format "Reading %s\n\n" init-file))
    (princ (format "%-26s %s\n" "PACKAGE" "STATUS"))
    (dolist (entry wanted)
      (let* ((pkg (car entry))
             (pin (cdr entry))
             (desc (cadr (assq pkg package-alist)))
             (builtin (and (not desc) (package-built-in-p pkg)))
             (offers (mapcar #'package-desc-archive
                             (cdr (assq pkg package-archive-contents)))))
        (cond
         (desc
          (cl-incf installed)
          (princ (format "%-26s installed %s\n" pkg
                         (package-version-join (package-desc-version desc)))))
         (builtin
          (cl-incf installed)
          (princ (format "%-26s built-in\n" pkg)))
         (offers
          (cl-incf available)
          (princ (format "%-26s in archive: %s\n" pkg (string-join offers ","))))
         (t
          (push pkg missing)
          (princ (format "%-26s MISSING\n" pkg))))
        ;; A pin naming an archive that cannot supply the package resolves to
        ;; nothing at all -- worth shouting about, it is silent otherwise.
        (when (and pin (not desc) (not (member pin offers)))
          (princ (format "%-26s   !! pinned to \"%s\", which is not among %s\n"
                         "" pin (if offers (string-join offers ",") "(no archive)"))))))
    (princ (format "\n%d packages wanted: %d present, %d installable from archives, %d missing\n"
                   (length wanted) installed available (length missing)))
    (when missing
      (princ (format "missing: %s\n"
                     (mapconcat #'symbol-name (nreverse missing) " "))))
    (princ "\nNot archive-sourced (copy these in by hand):\n")
    (dolist (m manual)
      (princ (format "  %-24s %s\n" (car m) (cdr m))))))


(defun my/check-packages--grammar-alist (init-file)
  "Read the `treesit-language-source-alist' literal out of INIT-FILE.
Returns nil if the form is absent or unreadable."
  (with-temp-buffer
    (insert-file-contents init-file)
    (goto-char (point-min))
    ;; Anchor on the `setq', not a bare mention: the name also appears in the
    ;; `my/treesit-install-all-grammars' docstring, where it is followed by a
    ;; quote character and would otherwise match first.
    (when (re-search-forward "(setq[ \t\n]+treesit-language-source-alist[ \t\n]*'" nil t)
      (ignore-errors (read (current-buffer))))))

(defun my/check-packages-grammar-report (init-file)
  "Print a tree-sitter grammar report for INIT-FILE.
Grammars are shared libraries, not packages, so `package.el' knows nothing
about them and the package report above cannot speak for them."
  (princ "\nTREE-SITTER GRAMMARS\n")
  (if (not (require 'treesit nil t))
      (princ "  this Emacs was built without tree-sitter support\n")
    (let* ((alist (my/check-packages--grammar-alist init-file))
           (cfg-dir (file-name-directory (expand-file-name init-file)))
           (grammar-dir (expand-file-name "tree-sitter" cfg-dir))
           ;; Mirror `my/treesit-source-dir' in init.el: the fallback there
           ;; rewrites URL entries to these checkouts at startup, which the
           ;; literal alist read from the file cannot show.
           (source-dir (or (getenv "EMACS_TS_SRC")
                           (expand-file-name "ts-src" cfg-dir)))
           (init-text (with-temp-buffer
                        (insert-file-contents init-file)
                        (buffer-string)))
           (cc (seq-find #'executable-find '("cc" "gcc" "c99")))
           (c++ (seq-find #'executable-find '("c++" "g++")))
           (missing '()) (remote 0))
      ;; Look where this config keeps its grammars, not just where a default
      ;; `user-emacs-directory' would put them.
      (add-to-list 'treesit-extra-load-path (file-name-as-directory grammar-dir))
      (princ (format "  libraries in: %s\n" grammar-dir))
      (princ (format "  sources in  : %s%s\n" source-dir
                     (if (file-directory-p source-dir) "" "  (absent)")))
      (princ (format "  C compiler  : %s\n"
                     (or cc "NONE -- cannot build grammars from source")))
      (princ (format "  C++ compiler: %s\n"
                     (or c++ "none -- needed only for scanner.cc grammars")))
      (if (null alist)
          (princ "\n  no treesit-language-source-alist found in this init.el\n")
        (princ (format "\n  %-16s %-10s %s\n" "LANGUAGE" "LIBRARY" "SOURCE"))
        (dolist (entry alist)
          (let* ((lang (car entry))
                 (url (cadr entry))
                 (used (string-match-p (format "\\_<%s-ts-mode\\_>" lang) init-text))
                 (have (treesit-language-available-p lang))
                 (local (and (stringp url)
                             (or (file-accessible-directory-p (expand-file-name url))
                                 (seq-find #'file-directory-p
                                           (list (expand-file-name
                                                  (file-name-nondirectory url) source-dir)
                                                 (expand-file-name
                                                  (format "tree-sitter-%s" lang) source-dir)))))))
            (unless have (push (cons lang used) missing))
            (unless (or local (not (stringp url))) (cl-incf remote))
            (princ (format "  %-16s %-10s %s\n"
                           (format "%s%s" lang (if used " *" ""))
                           (if have "loadable" "MISSING")
                           (cond (local "local source (offline OK)")
                                 ((stringp url) "remote URL (NEEDS NETWORK)")
                                 (t "unknown"))))))
        (princ "\n  * = actually wired to a major mode in this init.el;\n")
        (princ "      unmarked languages are aspirational and cost nothing if absent.\n")
        (let ((needed (seq-filter #'cdr missing)))
          (princ (format "\n  %d/%d grammars loadable; %d missing (%d of them wired to a mode)\n"
                         (- (length alist) (length missing)) (length alist)
                         (length missing) (length needed)))
          (when needed
            (princ (format "  wired but MISSING: %s\n"
                           (mapconcat (lambda (m) (symbol-name (car m))) needed " "))))
          (when (> remote 0)
            (princ (format "\n  %d source entries have no local checkout, so installing them\n" remote))
            (princ "  needs the network.  To build offline, unpack the grammar source as\n")
            (princ (format "  %s/<upstream-repo-name>/src/parser.c\n" source-dir))
            (princ "  and init.el's fallback picks it up (see OFFLINE.md).\n")))))))

(package-initialize)
(let ((init (or (car command-line-args-left)
                (expand-file-name "init.el" user-emacs-directory))))
  (my/check-packages-report init)
  (my/check-packages-grammar-report init))

;;; check-packages.el ends here
