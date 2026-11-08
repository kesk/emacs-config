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

  (defun my/tabspaces-new-scratch-workspace ()
    "Open a new workspace whose only buffer is *scratch*.
The tab is named \"*scratch*\", or \"*scratch*<N>\" if that is taken."
    (interactive)
    (let* ((tab-bar-new-tab-choice (lambda () (get-buffer-create "*scratch*")))
           (existing (tabspaces--list-tabspaces))
           (name "*scratch*")
           (n 1))
      (while (member name existing)
        (setq name (format "*scratch*<%d>" (cl-incf n))))
      (tab-new)
      (tab-rename name)
      (delete-other-windows)
      (switch-to-buffer "*scratch*")))

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
    "pK" '(tabspaces-kill-buffers-close-workspace :which-key "close workspace & kill buffers")
    "pp" '(tabspaces-open-or-create-project-and-workspace :which-key "switch project")
    "pt" '(tabspaces-switch-or-create-workspace :which-key "switch workspace")
    "pr" '(tabspaces-rename-workspace :which-key "rename")
    "ps" '(my/tabspaces-new-scratch-workspace :which-key "new scratch workspace")

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
    "tt" '(toggle-theme :which-key "theme")
    ;; These repeat: after the first press, plain +, - or 0 keeps adjusting.
    "t+" '(text-scale-adjust :which-key "font larger")
    "t-" '(text-scale-adjust :which-key "font smaller")
    "t0" '(text-scale-adjust :which-key "font reset")
    "tg" '(:ignore t :which-key "font (all buffers)")
    "tg+" '(global-text-scale-adjust :which-key "font larger")
    "tg-" '(global-text-scale-adjust :which-key "font smaller")
    "tg0" '(global-text-scale-adjust :which-key "font reset")

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
  :hook
  ;; Line numbers sit between the text and org-modern's fringe bracket.
  (org-mode . (lambda () (display-line-numbers-mode -1)))
  ;; A little air between lines, in prose buffers only.
  (org-mode . (lambda () (setq-local line-spacing 0.2)))
  (org-mode . my/org-inhibit-angle-pairing)
  :init
  (setq org-directory "~/org/")
  ;; Off: org-modern skips its fringe bracket on src blocks under org-indent-mode.
  (setq org-startup-indented nil)
  (setq org-hide-emphasis-markers t)

  ;; Org gives < and > paren syntax (for timestamps), so `electric-pair-mode'
  ;; turned <cl into <cl> and org-tempo's <cl TAB no longer expanded cleanly.
  (defun my/org-inhibit-angle-pairing ()
    "Keep `electric-pair-mode' from pairing < in this Org buffer."
    (let ((inhibit electric-pair-inhibit-predicate))
      (setq-local electric-pair-inhibit-predicate
                  (lambda (char)
                    (or (eq char ?<) (funcall inhibit char))))))
  (setq calendar-week-start-day 1) ;; Monday as first day of week
  :config
  ;; You can add more Org-mode specific configurations here later
  (require 'org-tempo)
  ;; <cl TAB / <el TAB insert a src block with the language filled in
  (add-to-list 'org-structure-template-alist '("cl" . "src clojure"))
  (add-to-list 'org-structure-template-alist '("el" . "src emacs-lisp"))

  ;; Agenda setup
  (setq org-agenda-files '("~/org/"))

  ;; Babel: evaluate Clojure blocks through the running CIDER REPL
  (setq org-babel-clojure-backend 'cider)
  ;; Evaluation still asks for confirmation.  A presentation that should run
  ;; without prompting opts in with a file-local
  ;; `org-confirm-babel-evaluate: nil', which Emacs asks about on opening.
  (org-babel-do-load-languages
   'org-babel-load-languages
   '((emacs-lisp . t)
     (clojure . t)))

  (defun my/org-insert-current-date-inactive ()
    "Insert an inactive Org timestamp for today at point."
    (interactive)
    (org-insert-time-stamp (current-time) nil t))

  (defun my/org-babel-remove-all-results ()
    "Remove the results of every source block in the current buffer."
    (interactive)
    (org-babel-remove-result-one-or-many t))

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
    "." '(org-time-stamp :which-key "timestamp")
    ;; Mirrors the "e" eval prefix under cider-mode-map
    "e" '(:ignore t :which-key "eval")
    "ee" '(org-babel-execute-src-block :which-key "eval block")
    "eb" '(org-babel-execute-buffer :which-key "eval buffer")
    "es" '(org-babel-execute-subtree :which-key "eval subtree")
    "ek" '(org-babel-remove-result-one-or-many :which-key "remove result")
    "eK" '(my/org-babel-remove-all-results :which-key "remove all results")
    "ev" '(org-babel-expand-src-block :which-key "view expanded block")
    "'" '(org-edit-special :which-key "edit block")
    "i" '(org-insert-structure-template :which-key "insert block")))

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
   org-modern-star 'replace  ; ◉○◈◇✳ per level (org-modern-replace-stars)
   org-modern-hide-stars "·" ; a dot per leading star, to show the depth
   org-modern-table t        ; draw tables with thin lines like the org-modern screenshots
   org-modern-list '((43 . "➤") (45 . "–") (42 . "•"))
   org-modern-todo-faces
   '(("TODO" :inverse-video t :inherit org-todo)
     ("PROJ" :inverse-video t :inherit org-todo)
     ("STRT" :inverse-video t :inherit org-todo)
     ("WAIT" :inverse-video t :inherit org-todo)
     ("HOLD" :inverse-video t :inherit org-todo)
     ("KILL" :inverse-video t :inherit org-todo)
     ("WORK" :inverse-video t :inherit org-todo)))

  ;; Otherwise Clojure blocks use clojure-mode (a cider dependency), which looks
  ;; different from .clj files and gives the / in :foo/bar the `default' face.
  (with-eval-after-load 'org-src
    (add-to-list 'org-src-lang-modes '("clojure" . clojure-ts)))

  (custom-set-faces
   '(org-level-1 ((t (:inherit outline-1 :height 1.4))))
   '(org-level-2 ((t (:inherit outline-2 :height 1.3))))
   '(org-level-3 ((t (:inherit outline-3 :height 1.2))))
   '(org-level-4 ((t (:inherit outline-4 :height 1.1))))
   '(org-level-5 ((t (:inherit outline-5 :height 1.0))))))

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

;;; 2.2.2 DSLIDE (Presentations from Org files)
;; Each heading is a slide; src blocks on a slide run as steps when
;; stepping forward, so Clojure demos evaluate live in CIDER.
(use-package dslide
  :after org
  :commands (dslide-deck-start dslide-deck-develop dslide-deck-present)
  :init
  (my/local-leader-def
    :keymaps 'org-mode-map
    "p"  '(:ignore t :which-key "present")
    "pp" '(dslide-deck-start :which-key "start presentation")
    "pd" '(dslide-deck-develop :which-key "develop (with preview)")
    "pP" '(dslide-deck-present :which-key "present (new frame + notes)"))
  :config
  (setq dslide-breadcrumb-separator " › ")

  (defun my/dslide-present-frame-parameters ()
    "Place the presentation frame maximized on another monitor, if any.
With a single monitor, return nil so dslide opens an ordinary frame."
    (let* ((current (alist-get 'geometry (frame-monitor-attributes)))
           (other (seq-find (lambda (monitor)
                              (not (equal (alist-get 'geometry monitor) current)))
                            (display-monitor-attributes-list))))
      (append
       my/dslide-frame-padding
       (when other
         (pcase-let ((`(,x ,y . ,_) (alist-get 'workarea other)))
           ;; (+ N) allows negative positions, for a monitor left of or above
           ;; the main one
           `((left . (+ ,x)) (top . (+ ,y)) (fullscreen . maximized)))))))
  (setq dslide-present-frame-parameters #'my/dslide-present-frame-parameters)

  ;; Padding around the slides, as in the org-modern screenshots.
  ;; `dslide-deck-present' gets it from the frame parameters above, since it
  ;; makes a frame of its own.  The other modes reuse the current frame, so
  ;; pad it on start and put the old values back on stop.
  (defvar my/dslide-frame-padding
    '((internal-border-width . 20) (right-divider-width . 20))
    "Frame parameters that pad the frame a presentation runs in.")
  (defvar my/dslide-saved-frame-padding nil
    "The (FRAME . PARAMETERS) that were in effect before padding FRAME.")
  (defun my/dslide-pad-frame ()
    "Pad the selected frame for the presentation, remembering its old values."
    (unless my/dslide-saved-frame-padding
      (let ((frame (selected-frame)))
        (setq my/dslide-saved-frame-padding
              (cons frame (mapcar (lambda (param)
                                    (cons (car param)
                                          (frame-parameter frame (car param))))
                                  my/dslide-frame-padding)))
        (modify-frame-parameters frame my/dslide-frame-padding))))
  (defun my/dslide-unpad-frame ()
    "Restore the padding `my/dslide-pad-frame' changed."
    (pcase-let ((`(,frame . ,params) my/dslide-saved-frame-padding))
      (when (frame-live-p frame)
        (modify-frame-parameters frame params)))
    (setq my/dslide-saved-frame-padding nil))
  (dolist (hook '(dslide-start-hook dslide-develop-hook))
    (add-hook hook #'my/dslide-pad-frame))
  (add-hook 'dslide-stop-hook #'my/dslide-unpad-frame)

  (defun my/dslide-enlarge-text ()
    "Scale up text in the slide buffer."
    (with-current-buffer (oref dslide--deck slide-buffer)
      (text-scale-set 2)))
  ;; `dslide-deck-present' runs its own hook instead of `dslide-start-hook'
  (dolist (hook '(dslide-start-hook dslide-present-hook))
    (add-hook hook #'my/dslide-enlarge-text))

  ;; dslide hides the cursor by setting `cursor-type', but Evil resets it
  ;; from its per-state cursor specs after every command.  Make those specs
  ;; empty in the slide buffer only; the base buffer (notes) keeps its cursor.
  (defun my/dslide-hide-evil-cursor ()
    "Hide the Evil cursor in the slide buffer."
    (with-current-buffer (oref dslide--deck slide-buffer)
      (dolist (var '(evil-default-cursor
                     evil-normal-state-cursor
                     evil-motion-state-cursor))
        (set (make-local-variable var) '(nil)))
      (evil-refresh-cursor)))
  (dolist (hook '(dslide-start-hook dslide-present-hook dslide-develop-hook))
    (add-hook hook #'my/dslide-hide-evil-cursor))

  ;; `global-hl-line-mode' skips buffers where its variable is locally nil.
  ;; org-indent's virtual indentation is a text property shared with the base
  ;; buffer, and dslide's hidden drawers strip it from the line after them, so
  ;; a slide's first list item ended up less indented than the rest.  An
  ;; overlay (local to the slide buffer, and taking precedence over text
  ;; properties) blanks it on slides while the notes keep it.  Only when
  ;; org-indent is on, though: org-modern draws its src-block fringe bracket
  ;; with `line-prefix' too, and the overlay would hide it.
  (defun my/dslide-disable-editing-chrome ()
    "Turn off line highlighting, line numbers, linting and org-indent on slides."
    (with-current-buffer (oref dslide--deck slide-buffer)
      (setq-local global-hl-line-mode nil)
      (global-hl-line-unhighlight)
      (display-line-numbers-mode -1)
      (flycheck-mode -1)
      (when (bound-and-true-p org-indent-mode)
        (without-restriction
          (let ((overlay (make-overlay (point-min) (point-max) nil nil t)))
            (overlay-put overlay 'line-prefix "")
            (overlay-put overlay 'wrap-prefix ""))))))
  (dolist (hook '(dslide-start-hook dslide-present-hook dslide-develop-hook))
    (add-hook hook #'my/dslide-disable-editing-chrome))

  ;; Evil's state maps shadow dslide's arrow keys, so rebind them per state.
  ;; Evil only picks up minor-mode state bindings on a keymap refresh, which
  ;; doesn't happen when dslide-mode turns on in the new slide buffer.  The
  ;; base buffer is refreshed too, so the deck can be driven from the notes
  ;; window when presenting with `dslide-deck-present'.
  (defun my/dslide-refresh-evil-keymaps ()
    "Activate dslide's Evil bindings in the slide and base buffers."
    (dolist (buffer (list (oref dslide--deck slide-buffer)
                          (oref dslide--deck base-buffer)))
      (with-current-buffer buffer
        (evil-normalize-keymaps))))
  (dolist (hook '(dslide-start-hook dslide-present-hook dslide-develop-hook))
    (add-hook hook #'my/dslide-refresh-evil-keymaps))

  ;; dslide only looks for the slide buffer on the selected frame, and its
  ;; contents view assumes the slide window is selected.  Driven from the notes
  ;; window, <up> would display the slide buffer there instead of opening the
  ;; contents, and <down> would stop the deck instead of leaving the contents.
  (defun my/dslide-call-in-slide-window (command &rest args)
    "Call COMMAND with the slide window selected, on whichever frame it is."
    (let* ((slide-buffer (and (dslide-live-p) (oref dslide--deck slide-buffer)))
           (window (and slide-buffer (get-buffer-window slide-buffer t))))
      (if (or (null window) (eq window (selected-window)))
          (apply command args)
        ;; Stepping from the notes moves the buffer's point, not the window's
        (set-window-point window (with-current-buffer slide-buffer (point)))
        (with-selected-window window
          (apply command args)
          ;; `post-command-hook' will run in the notes buffer, so it won't
          ;; reach the highlight's buffer-local hook
          (when (dslide--contents-active-p)
            (dslide--contents-hl-line))))))
  (defun my/dslide-call-in-contents-window (command &rest args)
    "Call COMMAND in the slide window if the contents view is showing."
    (if (and (dslide-live-p)
             (with-current-buffer (oref dslide--deck slide-buffer)
               (dslide--contents-active-p)))
        (apply #'my/dslide-call-in-slide-window command args)
      (apply command args)))
  ;; Opening the contents scrolls up unconditionally, which signals an error
  ;; when the window is already at the top, as it is on the first slide.
  (defun my/dslide-ignore-beginning-of-buffer (command &rest args)
    "Call COMMAND, ignoring a `beginning-of-buffer' error."
    (ignore-error beginning-of-buffer
      (apply command args)))
  (advice-add 'dslide-display-contents :around
              #'my/dslide-ignore-beginning-of-buffer)
  (advice-add 'dslide-deck-start :around #'my/dslide-call-in-slide-window)
  ;; On a slide, stepping and stopping work from the notes as they are
  (dolist (command '(dslide-deck-forward dslide-deck-backward dslide-deck-stop))
    (advice-add command :around #'my/dslide-call-in-contents-window))

  (general-define-key
   :states '(normal motion)
   :keymaps 'dslide-mode-map
   "<right>" #'dslide-deck-forward
   "<left>"  #'dslide-deck-backward
   "<up>"    #'dslide-deck-start
   "<down>"  #'dslide-deck-stop
   "q"       #'dslide-deck-stop))

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
;; Update default-frame-alist in place rather than setq'ing it: early-init.el
;; already put the no-toolbar/menu-bar/scroll-bar settings there, and
;; replacing the list would bring those back on every frame created after
;; startup.  `alist-get' also keeps `SPC f R' from piling up duplicates.
(setq initial-frame-alist '((width . 150) (height . 60)))
(setf (alist-get 'width default-frame-alist) 150)
(setf (alist-get 'height default-frame-alist) 60)

;; A little padding around the frame and between side-by-side windows.  This
;; also updates `default-frame-alist', so new frames get it too.
;; Presentations pad more (see `my/dslide-frame-padding').  Colour the border
;; and dividers like the background so they read as empty space, not lines.
(modify-all-frames-parameters
 '((internal-border-width . 10)
   (right-divider-width . 10)))

(defun my/blend-window-dividers (&rest _)
  "Colour the window dividers and frame border like the default background."
  (let ((bg (face-attribute 'default :background)))
    (dolist (face '(window-divider
                    window-divider-first-pixel
                    window-divider-last-pixel))
      (face-spec-reset-face face)
      (set-face-foreground face bg))
    (set-face-background 'internal-border bg)))
;; Re-run on every theme switch, e.g. when macOS flips light/dark.
(add-hook 'enable-theme-functions #'my/blend-window-dividers)

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


;;; 3.5 GOTO-ADDRESS (Clickable URLs & e-mail addresses)
(use-package goto-addr
  :ensure nil
  :init
  (defun my/goto-address-repl-setup ()
    "Enable `goto-address-mode' in a way that also catches REPL output.

`cider-repl--emit-output' puts `(syntax-table (1))' -- punctuation
syntax -- on every character of program output, so unbalanced parens
in output don't break sexp navigation (CIDER issue #3102), and
`cider-repl-mode' sets `parse-sexp-lookup-properties' so it takes
effect.  A side effect is that no output character is a word
constituent, and `goto-address-url-regexp' begins with `\\<', which
can only match before one.  URLs in output therefore never match,
while URLs on the input line -- ordinary buffer text -- do.

Dropping the anchor buffer-locally fixes it.  `goto-address-mail-regexp'
has no such anchor and already works.  The cost is that a URL glued to
a preceding word now matches too, which is harmless in output."
    (interactive)
    ;; `goto-address-mode' is autoloaded but the regexp variable is not, so a
    ;; REPL buffer created before any prog/text buffer would read a void var.
    (require 'goto-addr)
    (setq-local goto-address-url-regexp
                (if (string-prefix-p "\\<" goto-address-url-regexp)
                    (substring goto-address-url-regexp 2)
                  goto-address-url-regexp))
    (goto-address-mode 1))
  ;; `cider-repl-mode' derives from `fundamental-mode', so neither hook below
  ;; reaches it.  It gets the unrestricted variant on purpose: the buffer is
  ;; mostly program output, not code, so URLs there are rarely in a comment.
  :hook ((prog-mode . goto-address-prog-mode)
         (text-mode . goto-address-mode)
         (cider-repl-mode . my/goto-address-repl-setup)))


;;; 4. THEME
(use-package doom-themes
  :config
  ;; Global settings (defaults)
  (setq doom-themes-enable-bold t    ; if nil, bold is universally disabled
        doom-themes-enable-italic t) ; if nil, italics is universally disabled

  (defun my/apply-system-appearance (appearance)
    "Enable the gruvbox variant matching the macOS APPEARANCE.
A nil APPEARANCE, as on builds without appearance support, means dark."
    (let* ((light (eq appearance 'light))
           (theme (if light 'doom-gruvbox-light 'doom-gruvbox))
           (other (if light 'doom-gruvbox 'doom-gruvbox-light)))
      (unless (custom-theme-enabled-p theme)
        (mapc #'disable-theme custom-enabled-themes)
        ;; Load without enabling: `toggle-theme' only finds variants among
        ;; themes that are already loaded.  This must come before the active
        ;; theme, since loading a doom theme overwrites the palette that
        ;; `doom-color' reads.
        (unless (custom-theme-p other)
          (load-theme other t t))
        (load-theme theme t))))

  ;; doom-gruvbox's docstrings are nearly the text colour, and the light
  ;; variant's match its strings.  Use a muted aqua instead, the one hue the
  ;; dark variant's syntax colours leave free.
  (custom-set-faces
   '(font-lock-doc-face ((((background dark)) (:foreground "#689d6a"))
                         (t (:foreground "#427b58")))))

  ;; Pick the right variant during init rather than waiting for the hook,
  ;; which first runs after startup and would flash the wrong theme.
  (my/apply-system-appearance (bound-and-true-p ns-system-appearance))
  ;; emacs-plus only; other builds simply don't follow the system.
  (when (boundp 'ns-system-appearance-change-functions)
    (add-hook 'ns-system-appearance-change-functions #'my/apply-system-appearance))

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
  ;; Offline grammar sources.  `treesit-install-language-grammar' skips its
  ;; git clone when an entry's URL is an existing directory and compiles from
  ;; <dir>/src with cc, so grammar checkouts dropped under this directory make
  ;; the same alist install without network.  See OFFLINE.md.
  (defvar my/treesit-source-dir
    (or (getenv "EMACS_TS_SRC") (locate-user-emacs-file "ts-src"))
    "Directory holding local tree-sitter grammar source checkouts.
Each checkout is looked up by its upstream repository name (the last path
component of the entry's URL), so `tsx' and `typescript' share one
`tree-sitter-typescript' directory as they do upstream.")

  (defun my/treesit-use-local-sources ()
    "Repoint `treesit-language-source-alist' at checkouts in `my/treesit-source-dir'.
Only entries with a matching directory are rewritten; the rest keep their
URL, so this is a no-op on a machine without local sources.  Idempotent."
    (when (file-directory-p my/treesit-source-dir)
      (setq treesit-language-source-alist
            (mapcar
             (lambda (entry)
               ;; Entries are variable length -- (LANG URL) up to
               ;; (LANG URL REVISION SOURCE-DIR CC C++) -- hence `nth'.
               (let* ((lang (nth 0 entry))
                      (url (nth 1 entry))
                      (source-dir (nth 3 entry))
                      (rest (nthcdr 4 entry))
                      (dir (and (stringp url)
                                (seq-find
                                 #'file-directory-p
                                 (list (expand-file-name (file-name-nondirectory url)
                                                         my/treesit-source-dir)
                                       (expand-file-name (format "tree-sitter-%s" lang)
                                                         my/treesit-source-dir))))))
                 (if (not dir)
                     entry
                   ;; REVISION is dropped on purpose: with a local directory,
                   ;; a non-nil revision makes treesit run `git checkout' in
                   ;; it, which fails on a plain copied-in source tree.
                   (append (list lang dir nil source-dir) rest))))
             treesit-language-source-alist))))

  (defun my/treesit-install-all-grammars ()
    "Install all tree-sitter grammars in `treesit-language-source-alist'.
Local sources under `my/treesit-source-dir' are picked up first, so this
works after unpacking them into a running session."
    (interactive)
    (my/treesit-use-local-sources)
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
  (my/treesit-use-local-sources)

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
  ;; `set-auto-mode' checks the shebang before the file name, and clojure-mode
  ;; (a cider dependency) autoloads these interpreters onto itself, so a
  ;; babashka script would otherwise open in clojure-mode despite `:mode'.
  :interpreter ("bb" "clj" "clojure" ("nbb" . clojure-ts-clojurescript-mode))
  :config
  (setopt clojure-ts-toplevel-inside-comment-form t)

  ;; Tonsky indent style
  (setopt clojure-ts-indent-style 'fixed)

  (add-hook 'clojure-ts-mode-hook #'my/lisp-syntax-setup)

  (defun my/clojure-ts-fix-keyword-delimiter ()
    "Stop the / in namespaced keywords from covering the background.
clojure-ts-mode gives it the `default' face, which carries a background and so
hides anything beneath it, such as an Org source block's."
    (when (treesit-ready-p 'clojure t)
      (setq-local treesit-font-lock-settings
                  (append treesit-font-lock-settings
                          (treesit-font-lock-rules
                           :language 'clojure
                           :feature 'keyword
                           :override t
                           '((kwd_lit delimiter: _ @font-lock-delimiter-face)))))))
  (add-hook 'clojure-ts-mode-hook #'my/clojure-ts-fix-keyword-delimiter)

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
    "u" '(cider-jack-in-universal :which-key "jack in universal")
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

  ;; Babashka >= 1.13 embeds real nREPL plus a *subset* of cider-nrepl
  ;; (inspector, info, complete, eldoc, test, stacktrace...) and now reports
  ;; a `clojure' entry ("1.12.6-SCI") in `describe'.  That makes
  ;; `cider-runtime-clojure-p' true, so `cider--connected-hook' takes the JVM
  ;; init path, which unconditionally sends `cider/init-debugger' -- an op bb
  ;; does not provide.  CIDER 2.0 turns any unsupported namespaced op into a
  ;; `user-error' at send time, which aborts the rest of the connect callback
  ;; (capabilities, `cider-repl-init-function', enabling `cider-mode' in open
  ;; buffers).  Guard the debugger init the same way CIDER already guards
  ;; `cider/out-subscribe'.
  (define-advice cider--debug-init-connection
      (:around (orig-fn &rest args) my/skip-without-debugger-op)
    "Only initialize the debugger on connections that actually provide it."
    (if (cider-nrepl-op-supported-p "cider/init-debugger")
        (apply orig-fn args)
      (message "CIDER: no debugger middleware on this REPL (%s); skipping init"
               (cider-runtime))))

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

;;; 6.2 SYSTEMD (Unit files)
;; Stock Emacs has no mode for systemd units.  The package's autoloads
;; register `systemd-mode' for .service/.timer/.socket/etc. and drop-in
;; .conf files, so it can stay deferred until one is opened.
(use-package systemd
  :defer t)



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
