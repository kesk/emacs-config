;;; init.el --- Main Initialization File  -*- lexical-binding: t; -*-

;;; 1. PACKAGE MANAGER SETUP
(require 'package)
(setq package-archives '(("melpa" . "https://melpa.org/packages/")
                         ("melpa-stable" . "https://stable.melpa.org/packages/")
                         ("org" . "https://orgmode.org/elpa/")
                         ("elpa" . "https://elpa.gnu.org/packages/")))
;; melpa-stable is only consulted for packages that explicitly `:pin' to it.
;; MELPA's date-based versions (e.g. 20260415.1809) always sort above stable's
;; semantic versions (e.g. 2.0.1), so adding the archive does not change which
;; version any unpinned package resolves to.

;;; 1.0.5 OFFLINE / AIR-GAPPED OPERATION
;; Set EMACS_OFFLINE (to anything) to promise this Emacs never reaches the
;; network for packages.  Two things change: the archive refresh below is
;; skipped, and `:ensure' stops trying to install, so every `use-package' form
;; loads whatever is already on disk instead.  Missing packages are then logged
;; as "Error (use-package): Cannot load X" and startup continues; deferred forms
;; (`:hook', `:commands', `:bind') fail later at first use rather than at boot.
;;
;; Without this, an unreachable network means one DNS timeout per package, and
;; `package-refresh-contents' below blocks startup on all four archives.
(defvar my/offline (and (getenv "EMACS_OFFLINE") t)
  "Non-nil when package operations must not touch the network.
Set from the EMACS_OFFLINE environment variable at startup.")

(package-initialize)
(unless (or my/offline package-archive-contents)
  (package-refresh-contents))

;; Performance tracking
(setq use-package-compute-statistics t)

(require 'use-package)
(setq use-package-always-ensure (not my/offline))

;;; 1.1 NATIVE COMPILATION
;; `native-comp-jit-compilation' is off (see early-init.el), so nothing is
;; compiled during startup.  Native code is produced here instead, explicitly
;; and out-of-process.
;;
;; The subprocess matters: compiling inside this Emacs would install .eln files
;; while this same Emacs lazily loads them, which is the race the JIT setting
;; exists to avoid.  A separate batch process shares no such state.
(defun my/native-compile-packages (&rest _)
  "Natively compile installed packages in a separate Emacs process.
Runs asynchronously; progress and errors land in *native-compile*.
Attached to `package-upgrade-all' so a bulk upgrade refreshes native code
without having to remember this step."
  (interactive)
  (let ((emacs (expand-file-name invocation-name invocation-directory)))
    (make-process
     :name "my-native-compile"
     :buffer "*native-compile*"
     :command (list emacs "--batch" "--eval"
                    (format "(progn (native-compile-async %S 'recursively) \
(while (or (bound-and-true-p comp-files-queue) \
(and (fboundp 'comp--async-runnings) (> (comp--async-runnings) 0))) \
(sleep-for 2)) (message \"done\"))"
                            package-user-dir))
     :noquery t
     :sentinel
     (lambda (_proc event)
       ;; `start-process' failures are easy to miss, so say something either way.
       (message "my/native-compile-packages: %s" (string-trim event))))
    (message "Native-compiling packages in the background (see *native-compile*)")))

(advice-add 'package-upgrade-all :after #'my/native-compile-packages)

;;; Distinct C-i and TAB
;; This allows C-i to be bound separately from TAB (useful for Evil mode)
(defun my/distinguish-gui-tab ()
  (define-key input-decode-map [?\C-i] [C-i]))

(add-hook 'tty-setup-hook 'my/distinguish-gui-tab)
(my/distinguish-gui-tab)

;; Reset GC after startup (gcmh will take over, but let's be safe)
(add-hook 'emacs-startup-hook
          (lambda ()
            (message "Emacs loaded in %s with %d garbage collections."
                     (format "%.2f seconds"
                             (float-time
                              (time-subtract after-init-time before-init-time)))
                     gcs-done)))

;;; 1.0.5 ESSENTIALS
(use-package no-littering
  :config
  (no-littering-theme-backups))
(recentf-mode 1)
(global-auto-revert-mode 1)
(delete-selection-mode 1)

;; Disable electric-pair-mode in Lisps (conflicts with Parinfer)
(electric-pair-mode 1)
(defun my/disable-electric-pair-in-lisps ()
  (electric-pair-local-mode -1))

(add-hook 'emacs-lisp-mode-hook #'my/disable-electric-pair-in-lisps)
(add-hook 'clojure-mode-hook #'my/disable-electric-pair-in-lisps)
(add-hook 'clojure-ts-mode-hook #'my/disable-electric-pair-in-lisps)
(add-hook 'lisp-data-mode-hook #'my/disable-electric-pair-in-lisps)

(defun my/lisp-syntax-setup ()
  "Common syntax settings for Lisp-like modes."
  (modify-syntax-entry ?- "w")
  (modify-syntax-entry ?? "w")
  (modify-syntax-entry ?! "w")
  (modify-syntax-entry ?> "w")
  (modify-syntax-entry ?< "w")
  (modify-syntax-entry ?: "w")
  (modify-syntax-entry ?/ "w")
  (modify-syntax-entry ?. "w")
  (modify-syntax-entry ?* "w"))

(add-hook 'emacs-lisp-mode-hook #'my/lisp-syntax-setup)

(use-package exec-path-from-shell
  :if (memq window-system '(mac ns))
  :config
  (add-to-list 'exec-path-from-shell-variables "GEMINI_API_KEY")
  (exec-path-from-shell-initialize))

;;; Separate custom-file to keep init.el clean
(setq custom-file (expand-file-name "custom.el" user-emacs-directory))
(when (file-exists-p custom-file)
  (load custom-file))

(let ((secrets-file (expand-file-name "secrets.el" user-emacs-directory)))
  (when (file-exists-p secrets-file)
    (load secrets-file)))

;;; 1.1 PERFORMANCE
(use-package gcmh
  :init
  (setq gcmh-idle-delay 'auto
        gcmh-auto-idle-delay-factor 10
        gcmh-high-cons-threshold (* 128 1024 1024))
  (gcmh-mode 1))

;;; 2. EVIL MODE (Vim Keybindings)
(use-package evil
  :init
  (setq evil-want-integration t) ;; This is optional since it's already set to t by default.
  (setq evil-want-keybinding nil)
  (setq evil-undo-system 'undo-fu)
  :config
  (evil-mode 1)
  ;; Custom motion for next closing square bracket
  (evil-define-motion evil-next-close-square (count)
    "Go to COUNT next unmatched \"]\"."
    :jump t
    :type exclusive
    (forward-char)
    (evil-up-paren ?\[ ?\] (or count 1))
    (backward-char))
  (evil-define-motion evil-previous-open-square (count)
    "Go to COUNT previous unmatched \"[\"."
    :jump t
    :type exclusive
    (evil-up-paren ?\[ ?\] (- (or count 1)))))

(use-package undo-fu
  :config
  (global-unset-key (kbd "C-z"))) ;; Unset C-z to avoid accidental suspend/undo confusion

(use-package vundo
  :commands (vundo)
  :config
  ;; Better looking tree characters
  (setq vundo-glyph-alist vundo-unicode-symbols)
  (setq vundo-compact-display t))

(use-package evil-collection
  :after evil
  :config
  (evil-collection-init))

(use-package avy
  :bind (("M-s" . avy-goto-char-2)
         ("M-g M-g" . avy-goto-line))
  :config
  (setq avy-background nil))

(use-package evil-snipe
  :after (evil evil-collection)
  :config
  (evil-snipe-mode +1)
  (evil-snipe-override-mode +1)
  (setq evil-snipe-scope 'visible)

  ;; Disable snipe in Magit buffers (buffer-local)
  (add-hook 'magit-mode-hook #'turn-off-evil-snipe-override-mode))

(use-package evil-surround
  :after evil
  :config
  (global-evil-surround-mode 1))

;;; 2.0.2 PROJECTILE
(use-package projectile
  :init
  (projectile-mode +1)
  :config
  ;; Ensure Projectile is initialized before other things that depend on it
  (setq projectile-project-search-path '("~/Developer/"))) ; Customize as needed


;;; 2.0.3 EVIL CUSTOMIZATION (C-u scrolling)
(with-eval-after-load 'evil-maps
  (define-key evil-motion-state-map (kbd "C-u") 'evil-scroll-up)
  (define-key evil-motion-state-map (kbd "C-d") 'evil-scroll-down)
  ;; Bind the distinct <C-i> key (set up in input-decode-map) to jump forward
  (define-key evil-motion-state-map (kbd "<C-i>") 'evil-jump-forward))

;; Universal Argument Map
(global-set-key (kbd "C-S-u") 'universal-argument)

;;; 2.0.5 TABSPACES (Workspaces)
;; Was a local fork carrying a session-restore patch; upstream implemented an
;; equivalent (and more robust) placeholder cleanup, so we track MELPA again.
;; One gap remains, patched by `my/tabspaces-cleanup-placeholder' below.
;; Note upstream development moved to https://codeberg.org/mclear-tools/tabspaces
(use-package tabspaces
  :hook (after-init . tabspaces-mode)
  :commands (tabspaces-switch-or-create-workspace
             tabspaces-open-or-create-project-and-workspace)
  :custom
  (tabspaces-use-filtered-buffers-as-default t)
  (tabspaces-default-tab "Default")
  (tabspaces-remove-to-default t)
  (tabspaces-include-buffers '("*scratch*"))
  ;; Session management
  (tabspaces-session t)
  (tabspaces-session-auto-restore t)
  (tabspaces-session-project-session-store nil)
  :config
  ;; `tabspaces-restore-session' switches to "*tabspaces--placeholder*" before
  ;; selecting each workspace, so the tab that was current when restore began
  ;; ends up holding it.  Upstream's cleanup only sweeps tabs named in
  ;; `tabspaces--session-list', which never includes that pre-existing tab, so
  ;; the placeholder survives there.  Upstream then kills the placeholder
  ;; buffer, leaving the tab pointing at a dead buffer -- which `tab-bar'
  ;; renders as " *Old buffer *tabspaces--placeholder**" (see tab-bar.el,
  ;; `tab-bar-select-tab').  Sweep every tab rather than just the session's.
  (defconst my/tabspaces-placeholder-regexp "tabspaces--placeholder"
    "Match tabs and buffers left behind by a tabspaces session restore.")

  (defun my/tabspaces-cleanup-placeholder (&rest _)
    "Close tabs and kill buffers left over by a tabspaces session restore."
    (dolist (name (tabspaces--list-tabspaces))
      (when (and name
                 (string-match-p my/tabspaces-placeholder-regexp name)
                 ;; `tab-bar' refuses to close the last tab; don't try.
                 (> (length (tab-bar-tabs)) 1))
        (tab-bar-close-tab-by-name name)))
    (dolist (buf (buffer-list))
      (when (string-match-p my/tabspaces-placeholder-regexp (buffer-name buf))
        (kill-buffer buf))))

  ;; Covers the direct, --safe, and deferred-daemon restore paths, which all
  ;; funnel through `tabspaces-restore-session'.
  (advice-add 'tabspaces-restore-session :after #'my/tabspaces-cleanup-placeholder)

  ;; Filter Buffers for Consult
  (with-eval-after-load 'consult
    ;; Hide full buffer list (still available with "b" prefix)
    (consult-customize consult-source-buffer :hidden t :default nil)
    ;; Set consult-workspace buffer list
    (defvar consult--source-workspace
      (list :name     "Workspace Buffers"
            :narrow   ?w
            :history  'buffer-name-history
            :category 'buffer
            :state    #'consult--buffer-state
            :default  t
            :items    (lambda () (consult--buffer-query
                                  :predicate #'tabspaces--local-buffer-p
                                  :sort 'visibility
                                  :as #'buffer-name)))

      "Workspace buffer candidate source for `consult-buffer'.")
    (add-to-list 'consult-buffer-sources 'consult--source-workspace)))

;;; 2.0.5.5 EDIFF
(use-package ediff
  :config
  (setq ediff-window-setup-function 'ediff-setup-windows-plain)
  (setq ediff-split-window-function 'split-window-horizontally)
  ;; Suppress the "Delete variant?" prompt after quitting
  (setq ediff-keep-variants nil)

  (defun my/ediff-cleanup-mess ()
    "Kill Ediff-specific temporary buffers upon quitting Ediff."
    (dolist (buf (buffer-list))
      (let ((buffer-name (buffer-name buf)))
        (when (and buffer-name
                   (or (member buffer-name '("*ediff-errors*" "*ediff-diff*" "*Ediff Registry*" "*ediff-fine-diff*" "*Ediff Control Panel*"))
                       (string-match-p "^FILE=" buffer-name)))
          (when (buffer-live-p buf)
            (kill-buffer buf))))))

  ;; Restore window layout when quitting ediff
  (add-hook 'ediff-quit-hook #'winner-undo)
  (add-hook 'ediff-quit-hook #'my/ediff-cleanup-mess))

;;; 2.0.6 MAGIT (Git Client)
(use-package magit
  :commands (magit-status magit-get-current-branch)
  :custom
  (magit-display-buffer-function #'magit-display-buffer-traditional))

;;; 2.0.7 GIT GUTTER (Diff indicators)
(use-package git-gutter
  :config
  (global-git-gutter-mode +1)
  (setq git-gutter:update-interval 0.5))

(use-package git-gutter-fringe
  :config
  (define-fringe-bitmap 'git-gutter-fr:added [240 240 240 240 240 240 240 240 240 240 240 240 240 240 240 240] nil nil 'center)
  (define-fringe-bitmap 'git-gutter-fr:modified [240 240 240 240 240 240 240 240 240 240 240 240 240 240 240 240] nil nil 'center)
  (define-fringe-bitmap 'git-gutter-fr:deleted [128 192 224 240 240 224 192 128] nil nil 'center))

;;; 2.0.7.5 WS-BUTLER (Clean whitespace only on changed lines)
(use-package ws-butler
  :config
  (ws-butler-global-mode 1))

;;; 2.0.8 GENERAL (Keybindings & Leader Key)
(use-package general
  :after (evil evil-collection)
  :config
  ;; Explicitly unbind SPC in motion state to allow using it as a leader key
  (define-key evil-motion-state-map " " nil)

  ;; evil-collection rebinds SPC to `image-scroll-up' directly in
  ;; `image-mode-map', which takes precedence over the motion-state unbind
  ;; above — undo it so the leader key works in image-mode too.
  (with-eval-after-load 'image-mode
    (evil-collection-define-key 'normal 'image-mode-map (kbd "SPC") nil))

  (general-create-definer my/leader-def
    :states '(normal visual insert emacs motion)
    :prefix "SPC"
    :non-normal-prefix "s-SPC"
    :global-prefix "s-SPC")

  (general-create-definer my/local-leader-def
    :states '(normal visual insert emacs motion)
    :prefix "ö"
    :non-normal-prefix "s-ö"
    :global-prefix "s-ö")

  (my/leader-def
    "/" '(consult-line :which-key "search buffer")
    "SPC" '(projectile-find-file :which-key "find project file") ; Bind SPC SPC here
    "TAB" '(tabspaces-switch-or-create-workspace :which-key "switch workspace")

    "c"  '(:ignore t :which-key "code")
    "cr" '(my/copy-with-reference :which-key "copy with reference")

    "a"  '(:ignore t :which-key "ai")
    "aa" '(gptel :which-key "gptel (chat)")
    "as" '(gptel-send :which-key "gptel (send)")
    "am" '(gptel-menu :which-key "gptel (menu)")

    "b"  '(:ignore t :which-key "buffer")
    "bb" '(consult-buffer :which-key "switch buffer")
    "bB" '(ibuffer :which-key "list all buffers (ibuffer)")
    "bd" '(kill-current-buffer :which-key "kill buffer")
    "bk" '(kill-current-buffer :which-key "kill buffer")
    "bn" '(evil-buffer-new :which-key "new buffer")
    "br" '(revert-buffer :which-key "revert buffer")
    "bs" '(save-buffer :which-key "save")

    "e"  '(:ignore t :which-key "errors")
    "eb" '(flycheck-buffer :which-key "check buffer")
    "ed" '(flycheck-disable-mode :which-key "disable Flycheck")
    "el" '(flycheck-list-errors :which-key "list errors")
    "en" '(flycheck-next-error :which-key "next error")
    "ep" '(flycheck-previous-error :which-key "previous error")

    "f"  '(:ignore t :which-key "files")
    "fc" '((lambda () (interactive) (find-file user-init-file)) :which-key "open init.el")
    "fd" '((lambda () (interactive) (ediff-current-file)) :which-key "ediff current file")
    "ff" '(find-file :which-key "find file")
    "fn" '(my/native-compile-packages :which-key "native-compile packages")
    "fR" '((lambda () (interactive) (load-file user-init-file)) :which-key "reload init.el")
    "fr" '(consult-recent-file :which-key "recent files")

    "g"  '(:ignore t :which-key "git")
    "gd" '(magit-diff-buffer-file :which-key "diff with file")
    "gg" '(magit-status :which-key "magit status")
    "gG" '(magit-status-here :which-key "magit status here")
    "gn" '(git-gutter:next-hunk :which-key "next change")
    "gp" '(git-gutter:previous-hunk :which-key "previous change")

    "n" '(:ignore t :which-key "narrow/widen")
    "nd" '(narrow-to-defun :which-key "narrow to defun")
    "nr" '(narrow-to-region :which-key "narrow to region")
    "nw" '(widen :which-key "widen")

    "o" '(:ignore t :which-key "org")
    "oa" '(org-agenda :which-key "open agenda")
    "on" '((lambda () (interactive) (find-file-other-window (expand-file-name "notes.org" org-directory))) :which-key "open main notes file")
    "ot" '(org-todo-list :which-key "open todo list")

    "p" '(:ignore t :which-key "project")
    "pk" '(tabspaces-close-workspace :which-key "close workspace")
    "pp" '(tabspaces-open-or-create-project-and-workspace :which-key "switch project")
    "pt" '(tabspaces-switch-or-create-workspace :which-key "switch workspace")
    "pr" '(tabspaces-rename-workspace :which-key "rename")

    "q" '(:ignore t :which-key "quit")
    "qq" 'kill-emacs
    "qr" 'restart-emacs

    "s"  '(:ignore t :which-key "search")
    "sl" '(consult-line :which-key "search line")
    "sp" '(consult-ripgrep :which-key "search project")
    "ss" '(consult-line :which-key "search line")
    "sg" '(rgrep :which-key "grep")

    "t" '(:ignore t :which-key "toggle")
    "tF" '(toggle-frame-fullscreen :which-key "fullscreen")
    "tf" '(toggle-frame-maximized :which-key "maximize")

    "v" '(vundo :which-key "visual undo")

    "w" '(:ignore t :which-key "window")
    "wh" '(evil-window-left :which-key "window left")
    "wj" '(evil-window-down :which-key "window down")
    "wk" '(evil-window-up :which-key "window up")
    "wl" '(evil-window-right :which-key "window right")
    "wc" '(evil-window-delete :which-key "close window")
    "wd" '(delete-window :which-key "delete window")
    "wo" '(delete-other-windows :which-key "delete other windows")
    "ws" '(split-window-below :which-key "split horizontal")
    "wv" '(split-window-right :which-key "split vertical")
    "w=" '(balance-windows :which-key "balance windows")

    "u" 'universal-argument)

  ;; Custom keybindings
  (general-define-key
   :states '(normal visual insert emacs)
   "C-SPC" 'completion-at-point))

;;; 2.1 WHICH-KEY (Keybinding Helper)
(use-package which-key
  :init (which-key-mode)
  :diminish which-key-mode
  :config
  (setq which-key-idle-delay 0.3) ;; Pop up after 0.3 seconds
  (setq which-key-separator " -> ") ;; Add more spacing between columns
  (which-key-setup-side-window-bottom))

;;; 2.1.5 HELPFUL (Better Help Buffers)
(use-package helpful
  :init
  (setq-default evil-lookup-func #'helpful-at-point)
  :bind
  (("C-h f" . helpful-callable)
   ("C-h v" . helpful-variable)
   ("C-h k" . helpful-key)
   ("C-h x" . helpful-command)
   ("C-h d" . helpful-at-point)
   ("C-h F" . helpful-function)))

;;; 2.2 ORG-MODE
(use-package org
  :init
  (setq org-directory "~/org/")
  (setq org-startup-indented t)
  (setq org-hide-emphasis-markers t)
  (setq calendar-week-start-day 1) ;; Monday as first day of week
  :config
  ;; You can add more Org-mode specific configurations here later
  (require 'org-tempo)

  ;; Agenda setup
  (setq org-agenda-files '("~/org/"))

  (defun my/org-insert-current-date-inactive ()
    "Insert an inactive Org timestamp for today at point."
    (interactive)
    (org-insert-time-stamp (current-time) nil t))

  ;; Local leader bindings for Org
  (my/local-leader-def
    :keymaps 'org-mode-map
    "t" '(:ignore t :which-key "toggle")
    "tt" '(org-todo :which-key "todo state")
    "tc" '(org-toggle-checkbox :which-key "checkbox")
    "d" '(:ignore t :which-key "date")
    "dd" '(org-deadline :which-key "deadline")
    "ds" '(org-schedule :which-key "schedule")
    "di" '(my/org-insert-current-date-inactive :which-key "insert inactive")
    "." '(org-time-stamp :which-key "timestamp")))

(use-package org-modern
  :hook
  (org-mode . org-modern-mode)
  (org-agenda-finalize . org-modern-agenda)
  :config
  (setq
   ;; Edit settings
   org-auto-align-tags nil
   org-tags-column 0
   org-catch-invisible-edits 'show-and-error
   org-special-ctrl-a/e t
   org-insert-heading-respect-content t

   ;; Org Modern settings
   org-modern-star nil       ; Let org-superstar handle the stars
   org-modern-hide-stars nil ; Let org-superstar handle hiding
   org-modern-table nil      ; keep standard table looking (or set to t)
   org-modern-list '((43 . "➤") (45 . "–") (42 . "•"))
   org-modern-todo-faces
   '(("TODO" :inverse-video t :inherit org-todo)
     ("PROJ" :inverse-video t :inherit org-todo)
     ("STRT" :inverse-video t :inherit org-todo)
     ("WAIT" :inverse-video t :inherit org-todo)
     ("HOLD" :inverse-video t :inherit org-todo)
     ("KILL" :inverse-video t :inherit org-todo)
     ("WORK" :inverse-video t :inherit org-todo)))

  (custom-set-faces
   '(org-level-1 ((t (:inherit outline-1 :height 1.4))))
   '(org-level-2 ((t (:inherit outline-2 :height 1.3))))
   '(org-level-3 ((t (:inherit outline-3 :height 1.2))))
   '(org-level-4 ((t (:inherit outline-4 :height 1.1))))
   '(org-level-5 ((t (:inherit outline-5 :height 1.0))))))

(use-package org-superstar
  :after org
  :hook (org-mode . org-superstar-mode)
  :config
  (setq org-superstar-headline-bullets-list '("◉" "○" "◈" "◇" "✳"))
  (setq org-superstar-special-todo-items t))

(use-package org-appear
  :hook (org-mode . org-appear-mode))

;;; 2.2.1 VERB (REST Client)
(use-package verb
  :after org
  :config
  (define-key org-mode-map (kbd "C-c C-r") verb-command-map)
  (my/local-leader-def
    :keymaps 'org-mode-map
    "r"     '(:ignore t :which-key "verb")
    "r RET" '(verb-send-request-on-point-no-window :which-key "send (silent)")
    "re"    '(verb-export-request-on-point :which-key "export")
    "rf"    '(verb-send-request-on-point :which-key "send (here)")
    "rk"    '(verb-kill-all-response-buffers :which-key "kill responses")
    "rr"    '(verb-send-request-on-point-display :which-key "send (switch)")
    "rs"    '(verb-send-request-on-point-other-window :which-key "send (stay)")
    "rv"    '(verb-set-var :which-key "set var")
    "rx"    '(verb-show-vars :which-key "show vars"))

  (my/local-leader-def
    :keymaps 'verb-response-body-mode-map
    "h" '(verb-toggle-show-headers :which-key "toggle headers")
    "f" '(verb-re-send-request :which-key "re-send")
    "k" '(verb-kill-response-buffer-and-window :which-key "kill")
    "h" '(verb-toggle-show-headers :which-key "toggle headers")
    "s" '(verb-show-request :which-key "show request")
    "w" '(verb-re-send-request-eww :which-key "re-send (eww)")))

;;; 2.3 COMPLETION FRAMEWORK (Vertico + Consult + Marginalia)
(use-package orderless
  :init
  ;; Configure a custom style that prioritizes initial matches
  ;; and falls back to char-wise matching.
  (setq completion-styles '(orderless basic))
  (setq completion-category-defaults nil)
  (setq completion-category-overrides '((file (styles partial-completion)))))

(use-package vertico
  :init
  (vertico-mode)
  ;; Load extensions
  (setq vertico-cycle t)
  :bind (:map vertico-map
              ("C-j" . vertico-next)
              ("C-k" . vertico-previous)))

;;; EVIL MULTIEDIT
(use-package evil-multiedit
  :after evil
  :config
  (evil-multiedit-default-keybinds)
  (setq evil-multiedit-follow-matches t)

  ;; Disable parinfer completely during multiedit to avoid conflicts
  (add-hook 'evil-multiedit-mode-hook
            (lambda ()
              (if evil-multiedit-mode
                  (when (bound-and-true-p parinfer-rust-mode)
                    (parinfer-rust-mode -1)
                    (setq-local my/parinfer-was-enabled t))
                (when (bound-and-true-p my/parinfer-was-enabled)
                  (parinfer-rust-mode 1)
                  (kill-local-variable 'my/parinfer-was-enabled))))))

;;; EXPAND REGION
(use-package expreg
  :bind (("M-k" . expreg-expand)
         ("M-j" . expreg-contract)))

;;; 2.3 CORFU (Auto-completion)
(use-package corfu
  :init
  (global-corfu-mode)
  :custom
  (corfu-auto t)                 ;; Enable auto completion
  (corfu-cycle t)                ;; Enable cycling for `corfu-next/previous'
  (corfu-preselect 'prompt)      ;; Always preselect the prompt
  (corfu-quit-no-match 'separator)

  :bind
  (:map corfu-map
        ("TAB" . corfu-next)
        ([tab] . corfu-next)
        ("S-TAB" . corfu-previous)
        ([backtab] . corfu-previous)
        ("S-SPC" . corfu-insert-separator)))

;; Enable rich annotations using the Marginalia package
(use-package marginalia
  :after vertico
  :init
  (marginalia-mode))

(use-package embark
  :bind
  (("M-o" . embark-act)         ;; Changed to M-o as requested
   ("C-h B" . embark-bindings))

  :init
  ;; Optionally replace the key help with a completing-read interface
  (setq prefix-help-command #'embark-prefix-help-command)

  :config
  ;; Hide the mode line of the Embark live/completions buffers
  (add-to-list 'display-buffer-alist
               '("\\`\\*Embark Collect \\(Live\\|Completions\\)\\*"
                 nil
                 (window-parameters (mode-line-format . none)))))

;; Consult users will also want the embark-consult package.
(use-package embark-consult
  :hook
  (embark-collect-mode . consult-preview-at-point-mode))

;; Configure directory extension.
(use-package vertico-directory
  :after vertico
  :ensure nil
  ;; More convenient directory navigation commands
  :bind (:map vertico-map
              ("RET" . vertico-directory-enter)
              ("DEL" . vertico-directory-delete-char)
              ("M-DEL" . vertico-directory-delete-word))
  ;; Tidy shadowed file names
  :hook (rfn-eshadow-update-overlay . vertico-directory-tidy))

(use-package consult
  :after vertico
  :bind (("C-x b" . consult-buffer)
         ("C-x 4 b" . consult-buffer-other-window)
         ("C-x 5 b" . consult-buffer-other-frame)
         ("C-x r b" . consult-bookmark)
         ("M-y" . consult-yank-pop))
  :hook (completion-list-mode . consult-preview-at-point-mode)
  :config
  (setq consult-project-function (lambda (_) (projectile-project-root))))

(use-package wgrep
  :config
  (setq wgrep-auto-save-buffer t))

(use-package ibuffer
  :ensure nil
  :config
  (setq ibuffer-show-empty-groups nil
        ibuffer-display-empty-groups nil))

(use-package ibuffer-projectile
  :after ibuffer
  :hook ((ibuffer . (lambda ()
                      (ibuffer-projectile-set-filter-groups)
                      (unless (eq ibuffer-sorting-mode 'alphabetic)
                        (ibuffer-do-sort-by-alphabetic))))))

(use-package dired
  :ensure nil
  :config
  (setq dired-listing-switches "-agho --group-directories-first")
  (when (eq system-type 'darwin)
    (let ((gls (executable-find "gls")))
      (if gls
          (setq insert-directory-program gls)
        ;; If gls is not found, remove --group-directories-first from switches
        (setq dired-listing-switches "-agho"))))
  (setq dired-dwim-target t)
  (setq dired-kill-when-opening-new-dired-buffer t) ; Reuse same buffer
  (general-define-key
   :states 'normal
   :keymaps 'dired-mode-map
   "h" 'dired-up-directory
   "l" 'dired-find-file))

(use-package dired-hide-dotfiles
  :hook (dired-mode . dired-hide-dotfiles-mode)
  :config
  (general-define-key
   :states 'normal
   :keymaps 'dired-mode-map
   "." 'dired-hide-dotfiles-mode))

(use-package nerd-icons-dired
  :hook
  (dired-mode . nerd-icons-dired-mode))

;;; 2.4 AI (gptel)
(use-package gptel
  :ensure t
  :commands (gptel gptel-send gptel-menu)
  :config
  (setq gptel-model 'gemini-2.0-flash
        gptel-backend (gptel-make-gemini "Gemini"
                        :key (lambda () (or (bound-and-true-p GEMINI_API_KEY)
                                            (getenv "GEMINI_API_KEY")))
                        :stream t)))

(use-package llm-tool-collection
  :load-path "/Users/seb/Developer/llm-tool-collection"
  :after gptel
  :config
  (mapcar (apply-partially #'apply #'gptel-make-tool)
          (llm-tool-collection-get-all)))

;;; 3. BASIC UI & DEFAULTS
(setq initial-scratch-message nil)
(setq initial-major-mode 'fundamental-mode)

;; macOS keybindings
(setq mac-command-modifier 'meta)
(setq mac-option-modifier nil)
(setq mac-right-option-modifier 'super)

;; Bind Cmd+1 through Cmd+9 (M-1..M-9) to switch workspaces (tabs)
(dotimes (i 9)
  (global-set-key (kbd (format "M-%d" (+ i 1)))
                  `(lambda () (interactive) (tab-bar-select-tab ,(+ i 1)))))

;; Set initial frame size (width x height)
(setq initial-frame-alist '((width . 150) (height . 60)))
(setq default-frame-alist '((width . 150) (height . 60)))

(defun my/center-frame ()
  "Center the current frame."
  (interactive)
  (let* ((width (frame-pixel-width))
         (height (frame-pixel-height))
         (screen-width (display-pixel-width))
         (screen-height (display-pixel-height))
         (left (max 0 (/ (- screen-width width) 2)))
         (top (max 0 (/ (- screen-height height) 2))))
    (set-frame-position (selected-frame) left top)))

;; Center the frame after startup
(add-hook 'window-setup-hook #'my/center-frame)

(set-face-attribute 'default nil :family "Fira Code" :height 120 :weight 'normal)
(set-face-attribute 'fixed-pitch nil :family "Fira Code" :height 120 :weight 'normal)

;;; Ligature support for Fira Code
(use-package ligature
  :config
  (ligature-set-ligatures 't '("www" "**" "***" "**/" "*>" "*/" "\\\\" "\\\\\\" "{-" "::"
                               ":::" ":=" "!!" "!=" "!==" "-}" "----" "-->" "->" "->>"
                               "-<" "-<<" "-~" "#{" "#[" "##" "###" "####" "#(" "#?" "#_"
                               "#_(" ".-" ".=" ".." "..<" "..." "?=" "??" ";;" "/*" "/**"
                               "/=" "/==" "/>" "//" "///" "&&" "||" "||=" "|=" "|>" "^=" "$>"
                               "++" "+++" "+>" "=:=" "==" "===" "==>" "=>" "=>>" "<="
                               "=<<" "=/=" ">-" ">=" ">=>" ">>" ">>-" ">>=" ">>>" "<*"
                               "<*>" "<|" "<|>" "<$" "<$>" "<!--" "<-" "<--" "<->" "<+"
                               "<+>" "<=" "<==" "<=>" "<=<" "<>" "<<" "<<-" "<<=" "<<<"
                               "<~" "<~~" "</" "</>" "~@" "~-" "~>" "~~" "~~>" "%%"))
  (global-ligature-mode 1))

(setq-default indent-tabs-mode nil) ; Prefer spaces for indentation
(setq-default fill-column 90)      ; Set wrap column to 90
(add-hook 'text-mode-hook 'visual-line-mode)
(add-hook 'text-mode-hook 'turn-on-auto-fill)

(setq ring-bell-function 'ignore)       ; Silent bell
(global-display-line-numbers-mode t)    ; Line numbers
(column-number-mode t)                  ; Show column number in mode line
(global-hl-line-mode +1)                ; Highlight current line
(winner-mode +1)                        ; Window layout undo/redo

;; Remember history and cursor position
(savehist-mode 1)
(save-place-mode 1)

;; Smooth scrolling
(setq scroll-conservatively 101
      scroll-margin 5)
;; (pixel-scroll-precision-mode +1)

;; Font handling (optional - uncomment and adjust if you have a preferred font)
;; (set-face-attribute 'default nil :font "JetBrains Mono" :height 140)

;; Backup files handling - keep directory clean
(setq make-backup-files t               ; backup of a file the first time it is saved.
      backup-by-copying t               ; don't clobber symlinks
      version-control t                 ; version numbers for backup files
      delete-old-versions t             ; delete excess backup files silently
      kept-old-versions 6               ; oldest versions to keep when a new numbered backup is made (default: 2)
      kept-new-versions 9               ; newest versions to keep when a new numbered backup is made (default: 2)
      auto-save-default t               ; auto-save every buffer that visits a file
      auto-save-timeout 20              ; number of seconds idle time before auto-save (default: 30)
      auto-save-interval 200)           ; number of keystrokes between auto-saves (default: 300)


;;; 4. THEME
(use-package doom-themes
  :config
  ;; Global settings (defaults)
  (setq doom-themes-enable-bold t    ; if nil, bold is universally disabled
        doom-themes-enable-italic t) ; if nil, italics is universally disabled
  (load-theme 'doom-one t)

  ;; Enable flashing mode-line on errors
  (doom-themes-visual-bell-config)

  ;; Corrects (and improves) org-mode's native fontification.
  (doom-themes-org-config))

;;; 5. MODELINE
(use-package doom-modeline
  :init
  (doom-modeline-mode 1)
  :config
  (setq doom-modeline-height 15        ;; You can adjust this
        doom-modeline-buffer-file-name-style 'file
        doom-modeline-major-mode-icon t
        doom-modeline-hud nil))

;;; 5.1 LINTING (Flycheck)
(use-package flycheck
  :init (global-flycheck-mode)
  :config
  ;; Use the built-in clj-kondo checker if available
  (setq flycheck-check-syntax-automatically '(save mode-enabled idle-change))
  (setq flycheck-emacs-lisp-load-path 'inherit))

(use-package flycheck-clj-kondo
  :after flycheck
  :config
  (require 'flycheck-clj-kondo))

;;; 5.2 EMACS LISP CONFIG
(add-hook 'emacs-lisp-mode-hook #'my/lisp-syntax-setup)

;;; 6. LANGUAGE MODES
(use-package treesit
  :ensure nil
  :preface
  (defun my/treesit-install-all-grammars ()
    "Install all tree-sitter grammars in `treesit-language-source-alist'."
    (interactive)
    (mapc #'treesit-install-language-grammar (mapcar #'car treesit-language-source-alist)))

  :config
  (setq treesit-language-source-alist
        '((bash "https://github.com/tree-sitter/tree-sitter-bash")
          (c "https://github.com/tree-sitter/tree-sitter-c")
          (cpp "https://github.com/tree-sitter/tree-sitter-cpp")
          (clojure "https://github.com/sogaiu/tree-sitter-clojure")
          (css "https://github.com/tree-sitter/tree-sitter-css")
          (dockerfile "https://github.com/camdencheek/tree-sitter-dockerfile")
          (elisp "https://github.com/Wilfred/tree-sitter-elisp")
          (go "https://github.com/tree-sitter/tree-sitter-go")
          (go-mod "https://github.com/camdencheek/tree-sitter-go-mod")
          (html "https://github.com/tree-sitter/tree-sitter-html")
          (javascript "https://github.com/tree-sitter/tree-sitter-javascript" "master" "src")
          (json "https://github.com/tree-sitter/tree-sitter-json")
          (make "https://github.com/alemuller/tree-sitter-make")
          (markdown "https://github.com/ikatyang/tree-sitter-markdown")
          (python "https://github.com/tree-sitter/tree-sitter-python")
          (toml "https://github.com/tree-sitter/tree-sitter-toml")
          (tsx "https://github.com/tree-sitter/tree-sitter-typescript" "master" "tsx/src")
          (typescript "https://github.com/tree-sitter/tree-sitter-typescript" "master" "typescript/src")
          (yaml "https://github.com/ikatyang/tree-sitter-yaml")))

  (add-to-list 'auto-mode-alist '("\\(?:Dockerfile\\|Containerfile\\)\\(?:\\..*\\)?\\'" . dockerfile-ts-mode)))

(use-package treesit-fold
  :vc (:url "https://github.com/emacs-tree-sitter/treesit-fold" :branch "master")
  :after treesit
  :hook (prog-mode . treesit-fold-mode))

;; Was a local fork carrying a namespaced-map indentation fix; upstream merged
;; the equivalent change, so we track MELPA again.
(use-package clojure-ts-mode
  :after treesit
  :mode ("\\.clj\\'" "\\.cljs\\'" "\\.cljc\\'" "\\.edn\\'")
  :config
  (setopt clojure-ts-toplevel-inside-comment-form t)

  ;; Tonsky indent style
  (setopt clojure-ts-indent-style 'fixed)

  (add-hook 'clojure-ts-mode-hook #'my/lisp-syntax-setup)

  (general-define-key
   :states '(normal visual insert emacs)
   :keymaps 'clojure-ts-mode-map
   "TAB" 'clojure-ts-align
   "M-t" 'transpose-sexps
   "M-r" 'raise-sexp)

  (defun my/find-containing-seq-node (POINT)
    (let* ((seq-lit '("list_lit" "vec_lit" "map_lit"))
           (current (treesit-node-at POINT)))
      (while (not (or (eq nil current)
                      (and (member (treesit-node-type current) seq-lit)
                           (< (treesit-node-start current) POINT (1- (treesit-node-end current))))))
        (setq current (treesit-node-parent current)))
      current))

  (defun my/previous-seq-start ()
    (interactive)
    (when-let ((node (my/find-containing-seq-node (point))))
      (goto-char (treesit-node-start node))))

  (defun my/next-seq-end ()
    (interactive)
    (when-let ((node (my/find-containing-seq-node (point))))
      (goto-char (1- (treesit-node-end node)))))

  (add-hook 'clojure-ts-mode-hook
            (lambda ()
              (evil-define-key* '(normal visual motion) 'local
                (kbd "(") 'my/previous-seq-start
                (kbd ")") 'my/next-seq-end)))

  (defvar my/treesit-clojure-lit-pattern "sym_lit\\|kwd_lit\\|bool_lit\\|num_lit\\|str_lit"
    "Tree-sitter pattern matching Clojure literals (symbols, keywords, booleans, numbers, strings).")

  (defun my/clojure-jump-next-lit-start ()
    "Jump to the start of the next literal node (symbol, keyword, etc.) in the syntax tree."
    (interactive)
    (when-let ((match (treesit-search-forward (treesit-node-at (point)) my/treesit-clojure-lit-pattern)))
      (if (< (point) (treesit-node-start match))
          (goto-char (treesit-node-start match))
        (treesit-search-forward-goto
         (treesit-node-at (point))
         my/treesit-clojure-lit-pattern t))))

  (defun my/clojure-jump-next-lit-end ()
    "Jump to the end of the next literal node in the syntax tree.
If already inside a literal, jump to its end."
    (interactive)
    (when-let ((match (treesit-search-forward (treesit-node-at (point)) my/treesit-clojure-lit-pattern)))
      (if (< (1+ (point)) (treesit-node-end match))
          (goto-char (1- (treesit-node-end match)))
        (treesit-search-forward-goto
         (treesit-node-at (point))
         my/treesit-clojure-lit-pattern)
        (forward-char -1))))

  (defun my/clojure-jump-prev-lit ()
    "Jump to the start of the previous literal node in the syntax tree."
    (interactive)
    (when-let ((match (treesit-search-forward (treesit-node-at (point)) my/treesit-clojure-lit-pattern t)))
      (if (> (point) (treesit-node-start match))
          (goto-char (treesit-node-start match))
        (treesit-search-forward-goto
         (treesit-node-at (point))
         my/treesit-clojure-lit-pattern t t))))

  (general-define-key
   :states '(normal visual)
   :keymaps 'clojure-ts-mode-map
   "W" #'my/clojure-jump-next-lit-start
   "E" #'my/clojure-jump-next-lit-end
   "B" #'my/clojure-jump-prev-lit)

  (defun my/find-parent-form (POINT)
    (let ((current (treesit-node-at POINT)))
      (while (not (or (eq nil current)
                      (and (member (treesit-node-type current) '("list_lit" "vec_lit" "map_lit"))
                           (> POINT (treesit-node-start current)))))
        (setq current (treesit-node-parent current)))
      current))

  (defun my/insert-at-form-start ()
    (interactive)
    (when-let ((closest (my/find-parent-form (point))))
      (goto-char (treesit-node-start closest))
      (forward-char)
      (evil-insert-state)))

  (defun my/insert-at-form-end ()
    (interactive)
    (when-let ((closest (my/find-parent-form (point))))
      (goto-char (treesit-node-end closest))
      (backward-char)
      (evil-insert-state)))

  (general-define-key
   :states 'normal
   :keymaps 'clojure-ts-mode-map
   "A" #'my/insert-at-form-end
   "I" #'my/insert-at-form-start)

  (my/local-leader-def
    :keymaps 'clojure-ts-mode-map
    "j" '(cider-jack-in :which-key "jack in REPL")
    "c" '(cider-connect :which-key "connect to REPL")

    "R" '(:ignore t :which-key "refactor")
    "Ra" '(clojure-ts-add-arity :which-key "add arity")

    "Rt" '(:ignore t :which-key "threading")
    "RtF" '(clojure-ts-thread-first-all :which-key "thread first all")
    "Rtf" '(clojure-ts-thread-first :which-key "thread first")
    "RtL" '(clojure-ts-thread-last-all :which-key "thread last all")
    "Rtl" '(clojure-ts-thread-last :which-key "thread last")
    "RtU" '(clojure-ts-unwind-all :which-key "unwind all")
    "Rtu" '(clojure-ts-unwind :which-key "unwind")

    "Rc" '(:ignore t :which-key "cycle")
    "Rcp" '(clojure-ts-cycle-privacy :which-key "cycle privacy")
    "Rcc" '(clojure-ts-cycle-conditional :which-key "cycle if/if-not")
    "Rcn" '(clojure-ts-cycle-not :which-key "cycle not")
    "Rck" '(clojure-ts-cycle-keyword-string :which-key "cycle keyword/string")

    "a" '(clojure-ts-align :which-key "align")

    "p" 'parinfer-rust-switch-mode))

(use-package parinfer-rust-mode
  :hook ((clojure-ts-mode . parinfer-rust-mode)
         (emacs-lisp-mode . parinfer-rust-mode))
  :config)
  ;; Enable evil-local-mode to ensure Evil works correctly with Parinfer
  ;; (add-hook 'parinfer-rust-mode-hook (lambda ()
  ;;                                      (evil-local-mode 1)))

(use-package cider
  ;; Pinned to stable releases rather than MELPA master snapshots: CIDER has an
  ;; active release cadence and the 2.x line landed some breaking renames, so
  ;; tracking master here buys churn rather than fixes. Unpinning means jumping
  ;; to whatever `master' is that day (2.1.0-snapshot at time of writing).
  :pin "melpa-stable"
  :after clojure-ts-mode
  :hook (cider-stacktrace-mode . visual-line-mode)
  :config
  ;; Fix for Tree-sitter freezes in clojure-ts-mode:
  ;; CIDER's eldoc calls clojure-find-ns (from clojure-mode), which uses
  ;; clojure-forward-logical-sexp. When Tree-sitter is active, this can
  ;; trigger expensive or infinite loops on invalid syntax.
  (with-eval-after-load 'clojure-mode
    (advice-add 'clojure-find-ns :around
                (lambda (orig-fun &rest args)
                  (if (derived-mode-p 'clojure-ts-mode)
                      (clojure-ts-find-ns)
                    (apply orig-fun args)))))
  (setq cider-repl-display-help-banner nil ; clean up the REPL
        cider-repl-pop-to-buffer-on-connect nil ; keep focus in source file
        cider-clojure-cli-global-aliases ":dev:test")

  ;; Make 'K' look up documentation in CIDER
  (with-eval-after-load 'evil
    (add-hook 'cider-mode-hook (lambda () (setq-local evil-lookup-func #'cider-doc))))

  ;; `cider-macrostep-mode' (CIDER 2.0) drives inline macro stepping from
  ;; single-key bindings -- e/RET expand, a expand-all, c collapse, n/p jump
  ;; between expandable operators, q quit. They live in a plain minor-mode
  ;; keymap, and Evil's state maps go through `emulation-mode-map-alists',
  ;; which outranks `minor-mode-map-alist' -- so in normal state `e' would run
  ;; `evil-forward-word-end' instead. evil-collection has no cider-macrostep
  ;; support as of 2.0.1, hence the manual override.
  (with-eval-after-load 'cider-macrostep
    (evil-make-overriding-map cider-macrostep-mode-map 'normal)
    (add-hook 'cider-macrostep-mode-hook #'evil-normalize-keymaps))

  ;; Configure REPL window to be at the bottom with height 15
  (add-to-list 'display-buffer-alist
               '("\\*cider-repl"
                 (display-buffer-reuse-window display-buffer-in-side-window)
                 (side . bottom)
                 (window-height . 12)
                 (dedicated . t)))

  (defun my/cider-run-start ()
    "Run (user/start) in the current CIDER REPL."
    (interactive)
    (cider-interactive-eval "(user/start)"))

  (defun my/cider-run-stop ()
    "Run (user/stop) in the current CIDER REPL."
    (interactive)
    (cider-interactive-eval "(user/stop)"))

  (defun my/cider-run-go ()
    "Run (user/go) in the current CIDER REPL."
    (interactive)
    (cider-interactive-eval "(user/go)"))

  (defun my/cider-run-reset ()
    "Run (user/reset) in the current CIDER REPL."
    (interactive)
    (cider-interactive-eval "(user/reset)"))

  (defun my/cider-run-reload-all-ns ()
    "Run (user/reload-all-ns) in the current CIDER REPL."
    (interactive)
    (cider-interactive-eval "(user/reload-all-ns)"))

  (defun my/cider-inspect-tapped ()
    (interactive)
    (cider-interactive-eval "user/tapped")
    (cider-inspect-last-result))

  (defun my/cider-reset-tapped ()
    (interactive)
    (cider-interactive-eval "(user/reset-tapped)"))

  (my/local-leader-def
    :keymaps 'cider-mode-map
    "x"  '(:ignore t :which-key "system")
    "xs" '(my/cider-run-start :which-key "start")
    "xt" '(my/cider-run-stop :which-key "stop")
    "xx" '(my/cider-run-go :which-key "go")
    "xe" '(my/cider-run-reset :which-key "reset")
    "xr" '(my/cider-run-reload-all-ns :which-key "reload all namespaces")
    "e" '(:ignore t :which-key "eval")
    "ee" '(cider-eval-sexp-at-point :which-key "eval sexp at point")
    "ed" '(cider-eval-defun-at-point :which-key "eval defun at point")
    "ep" '(cider-eval-sexp-up-to-point :which-key "eval sexp up to point")
    "eP" '(cider-eval-defun-up-to-point :which-key "eval defun up to point")
    "ec" '(cider-pprint-eval-defun-to-comment :which-key "eval defun to comment")
    "ek" '(cider-kill-last-result :which-key "copy last result")

    "h" '(:ignore t :which-key "help")
    "hd" '(cider-clojuredocs :which-key "clojure docs")

    "r" '(:ignore t :which-key "REPL")
    "r!" '(cider-interrupt :which-key "interrupt")
    "ra" '(cider-apropos :which-key "apropos")
    "rb" '(cider-switch-to-repl-buffer :which-key "switch to REPL buffer")
    "rc" '(cider-repl-clear-buffer :which-key "clear REPL buffer")
    "rd" '(cider-debug-defun-at-point :which-key "debug defun at point")
    "ri" '(cider-inspect-last-result :which-key "inspect last result")
    "rl" '((lambda () (interactive) (cider-load-file (buffer-file-name))) :which-key "load current file")
    "rm" '(cider-macroexpand-1 :which-key "macroexpand 1")
    "rM" '(cider-macroexpand-all :which-key "macroexpand all")
    "rn" '(cider-repl-set-ns :which-key "set REPL ns to current")
    "rq" '(cider-quit :which-key "quit CIDER")
    "rr" '(cider-ns-reload :which-key "reload namespace")
    "rR" '(cider-ns-reload-all :which-key "reload all namespaces")
    "rt" '(my/cider-inspect-tapped :which-key "inspect tapped values")
    "rT" '(my/cider-reset-tapped :which-key "empty tapped values")
    "ru" '(cider-undef :which-key "undef")
    "rU" '(cider-undef-all :which-key "undef all"))

  (my/local-leader-def
    :keymaps 'cider-repl-mode-map
    "x"  '(:ignore t :which-key "system")
    "xs" '(my/cider-run-start :which-key "start")
    "xt" '(my/cider-run-stop :which-key "stop")
    "xx" '(my/cider-run-go :which-key "go")
    "xe" '(my/cider-run-reset :which-key "reset")
    "xr" '(my/cider-run-reload-all-ns :which-key "reload all namespaces")
    "q" '(cider-quit :which-key "quit")
    "c" '(cider-repl-clear-buffer :which-key "clear"))

  (my/local-leader-def
    :keymaps 'cider-inspector-mode-map
    "a" '(cider-inspector-set-max-atom-length :which-key "max atom length")
    "c" '(cider-inspector-set-max-coll-size :which-key "max coll size")
    "d" '(cider-inspector-def-current-val :which-key "def current val")
    "g" '(cider-inspector-refresh :which-key "refresh")
    "l" '(cider-inspector-pop :which-key "pop")
    "o" '(cider-inspector-open-thing-at-point :which-key "open thing at point")
    "p" '(cider-inspector-toggle-pretty-print :which-key "toggle pretty print")
    "q" '(cider-popup-buffer-quit-function :which-key "quit")
    "s" '(cider-inspector-toggle-sort-maps :which-key "toggle sort maps")
    "t" '(cider-inspector-tap-current-val :which-key "tap current val")
    "v" '(cider-inspector-toggle-view-mode :which-key "toggle view mode")
    "y" '(cider-inspector-display-analytics :which-key "display analytics"))

  (general-define-key
   :states '(normal visual)
   :keymaps 'cider-mode-map
   "gd" 'cider-find-var)

  (general-define-key
   :states '(normal visual)
   :keymaps 'cider-repl-mode-map
   "öq" 'cider-quit)

  (general-define-key
   :states '(normal insert)
   :keymaps 'cider-repl-mode-map
   "C-j" #'cider-repl-next-input
   "C-k" #'cider-repl-previous-input))

;;; 6.1 MARKDOWN MODE
(use-package markdown-mode
  :mode ("\\.md\\'" "\\.markdown\\'")
  :init (setq markdown-command "markdown")
  :config
  (setq markdown-header-scaling t)

  (my/local-leader-def
    :keymaps 'markdown-mode-map
    "i" '(:ignore t :which-key "insert")
    "il" '(markdown-insert-link :which-key "link")
    "ii" '(markdown-insert-image :which-key "image")
    "it" '(markdown-insert-table :which-key "table")
    "ic" '(markdown-insert-code :which-key "code")

    "t" '(:ignore t :which-key "toggle")
    "ti" '(markdown-toggle-inline-images :which-key "inline images")
    "tI" '(markdown-toggle-url-hiding :which-key "url hiding")

    "p" '(:ignore t :which-key "preview")
    "pp" '(markdown-preview :which-key "preview")
    "pe" '(markdown-export :which-key "export")))



;;; 7. CUSTOM COMMANDS
(defun my/copy-with-reference (start end)
  "Copy the selected region with file path and line numbers.
Each line in the content is prefixed with its line number."
  (interactive "r")
  (let* ((project-root (ignore-errors (projectile-project-root)))
         (file-path (if (buffer-file-name)
                        (if project-root
                            (file-relative-name (buffer-file-name) project-root)
                          (buffer-file-name))
                      (buffer-name)))
         (line-start (line-number-at-pos start))
         (line-end (let ((end-line (line-number-at-pos end)))
                     (if (and (> end start)
                              (eq (char-before end) ?\n))
                         (1- end-line)
                       end-line)))
         (content (buffer-substring-no-properties start end))
         (lines (let ((l (split-string content "\n")))
                  (if (and l (string= "" (car (last l))))
                      (butlast l)
                    l)))
         (current-line line-start)
         (numbered-content
          (mapconcat (lambda (line)
                       (let ((formatted (format "%4d | %s" current-line line)))
                         (setq current-line (1+ current-line))
                         formatted))
                     lines
                     "\n"))
         (formatted-text (format "From: %s lines %d-%d\n\n%s"
                                 file-path line-start line-end numbered-content)))
    (kill-new formatted-text)
    (deactivate-mark)
    (message "Copied with reference: %s lines %d-%d" file-path line-start line-end)))

;;; init.el ends here
