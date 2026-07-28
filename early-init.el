;;; early-init.el --- Early Initialization  -*- lexical-binding: t; -*-

;; Defer garbage collection during startup for faster boot
(setq gc-cons-threshold most-positive-fixnum)

;; Prefer newer version of files (source or byte-compiled)
(setq load-prefer-newer t)

;; Disable GUI elements early to avoid flickering and save resources
(push '(menu-bar-lines . 0) default-frame-alist)
(push '(tool-bar-lines . 0) default-frame-alist)
(push '(vertical-scroll-bars . nil) default-frame-alist)

;; Disable startup screen
(setq inhibit-startup-screen t)
(setq inhibit-startup-message t)
(setq inhibit-startup-echo-area-message "seb")

;; Fix for native compilation on macOS (libgccjit)
(when (eq system-type 'darwin)
  (setenv "PATH" (concat "/opt/homebrew/bin:" (getenv "PATH")))
  (add-to-list 'exec-path "/opt/homebrew/bin")
  (setq native-comp-driver-options '("-B/opt/homebrew/bin/" "-Wl,-w")))

;; Do not natively compile on demand.  With JIT enabled, every file lacking an
;; up-to-date .eln queues an async compile at startup, and those subprocesses
;; install .eln files while the main process is busy loading .eln files.  A file
;; swapped underneath a load yields a half-read data blob and a hard crash
;; (SIGSEGV inside load_comp_unit, usually in `read0' parsing the blob).  That
;; window is widest right after a bulk `package-upgrade-all', which is exactly
;; when it bit -- twice.
;;
;; Existing .eln files are still used, and anything without one falls back to
;; byte-code.  To (re)generate native code, compile offline instead, with no
;; Emacs concurrently loading the output:
;;
;;   emacs --batch --eval '(native-compile-async "~/.config/emacs/elpa" (quote recursively))'
(setq native-comp-jit-compilation nil)

(provide 'early-init)
;;; early-init.el ends here
