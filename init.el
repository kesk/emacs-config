;;; init.el --- Main Initialization File  -*- lexical-binding: t; -*-

;;; 1. PACKAGE MANAGER SETUP
(require 'package)
(setq package-archives '(("melpa" . "https://melpa.org/packages/")
                         ("org" . "https://orgmode.org/elpa/")
                         ("elpa" . "https://elpa.gnu.org/packages/")))

(package-initialize)
(unless package-archive-contents
  (package-refresh-contents))

;; Initialize use-package on non-Linux platforms
(unless (package-installed-p 'use-package)
  (package-install 'use-package))

(require 'use-package)
(setq use-package-always-ensure t)

;;; Separate custom-file to keep init.el clean
(setq custom-file (expand-file-name "custom.el" user-emacs-directory))
(when (file-exists-p custom-file)
  (load custom-file))

;;; 2. EVIL MODE (Vim Keybindings)
(use-package evil
  :init
  (setq evil-want-integration t) ;; This is optional since it's already set to t by default.
  (setq evil-want-keybinding nil)
  :config
  (evil-mode 1))

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
  :after evil
  :config
  (evil-snipe-mode +1))

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
  (define-key evil-motion-state-map (kbd "C-d") 'evil-scroll-down))

;; Universal Argument Map
(global-set-key (kbd "C-S-u") 'universal-argument)

;;; 2.0.5 PERSPECTIVE (Workspaces)
(use-package perspective
  :bind
  ("C-x C-b" . persp-list-buffers)         ; or use a nicer switcher, see below
  :init
  (persp-mode)
  :custom
  (persp-mode-prefix-key (kbd "C-c p")))

(use-package persp-projectile
  :after perspective)

;;; 2.0.6 MAGIT (Git Client)
(use-package magit
  :commands (magit-status magit-get-current-branch)
  :custom
  (magit-display-buffer-function #'magit-display-buffer-same-window-except-diff-v1))

;;; 2.0.7 GIT GUTTER (Diff indicators)
(use-package git-gutter
  :config
  (global-git-gutter-mode +1))

(use-package git-gutter-fringe
  :config
  (define-fringe-bitmap 'git-gutter-fr:added [224] nil nil '(center repeated))
  (define-fringe-bitmap 'git-gutter-fr:modified [224] nil nil '(center repeated))
  (define-fringe-bitmap 'git-gutter-fr:deleted [128 192 224 240] nil nil 'bottom))

;;; 2.0.8 GENERAL (Keybindings & Leader Key)
(use-package general
  :after evil
  :config
  (general-create-definer my-leader-def
    :states '(normal visual insert emacs)
    :prefix "SPC"
    :non-normal-prefix "C-SPC"
    :global-prefix "C-SPC")

  (general-create-definer my-local-leader-def
    :states '(normal visual insert emacs)
    :prefix "ö"
    :non-normal-prefix "C-ö"
    :global-prefix "C-ö")

  (my-leader-def
    "f"  '(:ignore t :which-key "files")
    "ff" '(find-file :which-key "find file")
    "fc" '((lambda () (interactive) (find-file user-init-file)) :which-key "open init.el")
    "fR" '((lambda () (interactive) (load-file user-init-file)) :which-key "reload init.el")
    "fd" '(diff-buffer-with-file :which-key "diff with file")
    "fr" '(consult-recent-file :which-key "recent files")
    "/" '(consult-line :which-key "search buffer")
    "SPC" '(projectile-find-file :which-key "find project file") ; Bind SPC SPC here
    
    "s"  '(:ignore t :which-key "search")
    "sl" '(consult-line :which-key "search line")

    "b"  '(:ignore t :which-key "buffer")
    "bb" '(consult-buffer :which-key "switch buffer")
    "bk" '(kill-current-buffer :which-key "kill buffer")

    "g"  '(:ignore t :which-key "git")
    "gg" '(magit-status :which-key "magit status")
    "gG" '(magit-status-here :which-key "magit status here")
    "gd" '(magit-diff-buffer-file :which-key "diff with file")
    "gj" '(git-gutter:next-hunk :which-key "next change")
    "gk" '(git-gutter:previous-hunk :which-key "previous change")

    "p" '(:ignore t :which-key "project")
    "pp" '(projectile-persp-switch-project :which-key "switch project")
    "pk" '(persp-kill :which-key "kill current perspective")
    "pt" '(persp-switch :which-key "switch perspective")
    
    "TAB" '(persp-switch :which-key "switch perspective")))

;;; 2.1 WHICH-KEY (Keybinding Helper)
(use-package which-key
  :init (which-key-mode)
  :diminish which-key-mode
  :config
  (setq which-key-idle-delay 0.3) ;; Pop up after 0.3 seconds
  (setq which-key-separator "  ") ;; Add more spacing between columns
  (which-key-setup-side-window-bottom))

;;; 2.2 COMPLETION FRAMEWORK (Vertico + Consult + Marginalia)
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
  (setq consult-project-function (lambda (_) (projectile-project-root)))
  ;; Use consult-buffer to show buffers from current perspective by default
  (consult-customize consult--source-buffer :hidden t :default nil)
  (add-to-list 'consult-buffer-sources persp-consult-source))
  

(use-package marginalia
  :after vertico
  :init
  (marginalia-mode))

;;; 3. BASIC UI & DEFAULTS
;; macOS keybindings
(setq mac-command-modifier 'meta)
(setq mac-option-modifier nil)
(setq mac-right-option-modifier 'super)

;; Set initial frame size (width x height)
(setq initial-frame-alist '((width . 150) (height . 60)))
(setq default-frame-alist '((width . 150) (height . 60)))

(set-face-attribute 'default nil :family "Fira Code" :height 120 :weight 'normal)
(set-face-attribute 'fixed-pitch nil :family "Fira Code" :height 120 :weight 'normal)

;;; Ligature support for Fira Code
(use-package ligature
  :config
  (ligature-set-ligatures 'prog-mode '("www" "**" "***" "**/" "*>" "*/" "\\\\" "\\\\\\" "{-" "::"
                                       ":::" ":=" "!!" "!=" "!==" "-}" "----" "-->" "->" "->>"
                                       "-<" "-<<" "-~" "#{" "#[" "##" "###" "####" "#(" "#?" "#_"
                                       "#_(" ".-" ".=" ".." "..<" "..." "?=" "??" ";;" "/*" "/**"
                                       "/=" "/==" "/>" "//" "///" "&&" "||" "||=" "|=" "|>" "^=" "$>"
                                       "++" "+++" "+>" "=:=" "==" "===" "==>" "=>" "=>>" "<="
                                       "=<<" "=/=" ">-" ">=" ">=>" ">>" ">>-" ">>=" ">>>" "<*"
                                       "<*>" "<|" "<|>" "<$" "<$>" "<!--" "<-" "<--" "<->" "<+"
                                       "<+>" "<=" "<==" "<=>" "<=<" "<>" "<<" "<<-" "<<=" "<<<"
                                       "<~" "<~~" "</" "</>" "~@" "~-" "~>" "~~" "~~>" "%%"))
  (global-ligature-mode t))

(setq-default indent-tabs-mode nil) ; Prefer spaces for indentation

(setq ring-bell-function 'ignore)       ; Silent bell
(global-display-line-numbers-mode t)    ; Line numbers
(column-number-mode t)                  ; Show column number in mode line

;; Font handling (optional - uncomment and adjust if you have a preferred font)
;; (set-face-attribute 'default nil :font "JetBrains Mono" :height 140)

;; Backup files handling - keep directory clean
(setq backup-directory-alist `(("." . ,(expand-file-name ".tmp/backups/" user-emacs-directory))))
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
  :init (doom-modeline-mode 1)
  :config
  (setq doom-modeline-height 15        ;; You can adjust this
        doom-modeline-buffer-file-name-style 'file
        doom-modeline-major-mode-icon t
        doom-modeline-hud nil))

;;; 6. LANGUAGE MODES
(use-package tree-sitter
  :ensure t
  :init
  (global-tree-sitter-mode))

(use-package tree-sitter-langs
  :after tree-sitter
  :ensure t
  :config)
  ;; You may need to install the grammar for Clojure
  ;; M-x tree-sitter-install-grammar RET clojure RET
  

(use-package clojure-ts-mode
  :after tree-sitter-langs
  :mode ("\\.clj\\'" "\\.cljs\\'" "\\.cljc\\'" "\\.edn\\'")
  :config
  (setq tree-sitter-hl-default-modes '(clojure-ts-mode))

  (my-local-leader-def
   :keymaps 'clojure-ts-mode-map
   "j" '(cider-jack-in :which-key "jack in REPL")
   "c" '(cider-connect :which-key "connect to REPL")))

(use-package parinfer-rust-mode
  :after clojure-ts-mode
  :hook ((clojure-ts-mode . parinfer-rust-mode)
         (emacs-lisp-mode . parinfer-rust-mode))
  :config
  ;; Enable evil-local-mode to ensure Evil works correctly with Parinfer
  (add-hook 'parinfer-rust-mode-hook (lambda ()
                                       (evil-local-mode 1))))

(use-package cider
  :after clojure-ts-mode
  :config
  (setq cider-repl-display-help-banner nil) ; clean up the REPL
  (setq cider-repl-pop-to-buffer-on-connect nil) ; keep focus in source file
  
  ;; Configure REPL window to be at the bottom with height 15
  (add-to-list 'display-buffer-alist
               '("\\*cider-repl"
                 (display-buffer-reuse-window display-buffer-in-side-window)
                 (side . bottom)
                 (window-height . 15))))
  ;; CIDER can take a moment to start, you might want to adjust idle timers
  ;; (setq cider-prompt-for-switch-to-repl t)
