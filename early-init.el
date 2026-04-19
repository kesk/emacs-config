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

(provide 'early-init)
;;; early-init.el ends here
