;;; early-init.el --- Early Initialization  -*- lexical-binding: t; -*-

;; Disable GUI elements early to avoid flickering
(push '(menu-bar-lines . 0) default-frame-alist)
(push '(tool-bar-lines . 0) default-frame-alist)
(push '(vertical-scroll-bars) default-frame-alist)

;; Disable startup screen
(setq inhibit-startup-screen t)
(setq inhibit-startup-message t)
(setq inhibit-startup-echo-area-message "seb") ; Replace with your user if needed

(provide 'early-init)
;;; early-init.el ends here
