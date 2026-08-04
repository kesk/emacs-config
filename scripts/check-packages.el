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
;; copied in by hand.  So must the compiled tree-sitter grammars in
;; tree-sitter/, which are not packages at all.

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

(package-initialize)
(my/check-packages-report
 (or (car command-line-args-left)
     (expand-file-name "init.el" user-emacs-directory)))

;;; check-packages.el ends here
