;;; init.el --- Main Initialization File  -*- lexical-binding: t; -*-

;;; 1. PACKAGE MANAGER SETUP
(require 'package)
(setq package-archives '(("melpa" . "https://melpa.org/packages/")
                         ("org" . "https://orgmode.org/elpa/")
                         ("elpa" . "https://elpa.gnu.org/packages/")))

(package-initialize)
(unless package-archive-contents
  (package-refresh-contents))

;;; Distinct C-i and TAB
;; This allows C-i to be bound separately from TAB (useful for Evil mode)
(defun my/distinguish-gui-tab ()
  (define-key input-decode-map [?\C-i] [C-i]))

(add-hook 'tty-setup-hook 'my/distinguish-gui-tab)
(my/distinguish-gui-tab)

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
  (setq evil-undo-system 'undo-fu)
  :config
  (evil-mode 1))

(use-package undo-fu
  :config
  (global-unset-key (kbd "C-z"))) ;; Unset C-z to avoid accidental suspend/undo confusion

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

;;; 2.0.5 PERSPECTIVE (Workspaces)
(use-package perspective
  :bind
  ("C-x C-b" . persp-list-buffers)         ; or use a nicer switcher, see below
  :init
  (persp-mode)
  :custom
  (persp-mode-prefix-key (kbd "C-c p"))
  :config
  ;; Switch to perspective by index (1-9) using CMD+n (M-n)
  (dotimes (i 9)
    (let ((n (+ 1 i)))
      (global-set-key (kbd (format "M-%d" n))
                      (lambda () (interactive)
                        (let ((names (sort (persp-names) #'string<)))
                          (if (> n (length names))
                              (message "No perspective %d" n)
                            (persp-switch (nth (1- n) names)))))))))

(use-package persp-projectile
  :after perspective)

;;; 2.0.5.5 EDIFF
(use-package ediff
  :config
  (setq ediff-window-setup-function 'ediff-setup-windows-plain)
  (setq ediff-split-window-function 'split-window-horizontally)
  ;; Suppress the "Delete variant?" prompt after quitting
  (setq ediff-keep-variants nil))

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
    :non-normal-prefix "s-SPC"
    :global-prefix "s-SPC")

  (general-create-definer my-local-leader-def
    :states '(normal visual insert emacs)
    :prefix "ö"
    :non-normal-prefix "s-ö"
    :global-prefix "s-ö")

  (my-leader-def
    "f"  '(:ignore t :which-key "files")
    "ff" '(find-file :which-key "find file")
    "fc" '((lambda () (interactive) (find-file user-init-file)) :which-key "open init.el")
    "fR" '((lambda () (interactive) (load-file user-init-file)) :which-key "reload init.el")
    "fd" '((lambda () (interactive) (ediff-current-file)) :which-key "ediff current file")
    "fr" '(consult-recent-file :which-key "recent files")
    "/" '(consult-line :which-key "search buffer")
    "SPC" '(projectile-find-file :which-key "find project file") ; Bind SPC SPC here

    "e"  '(:ignore t :which-key "errors")
    "el" '(flycheck-list-errors :which-key "list errors")
    "en" '(flycheck-next-error :which-key "next error")
    "ep" '(flycheck-previous-error :which-key "previous error")
    "eb" '(flycheck-buffer :which-key "check buffer")
    "ed" '(flycheck-disable-mode :which-key "disable Flycheck")
    
    "s"  '(:ignore t :which-key "search")
    "sl" '(consult-line :which-key "search line")

    "b"  '(:ignore t :which-key "buffer")
    "bb" '(consult-buffer :which-key "switch buffer")
    "bB" '(ibuffer :which-key "list all buffers (ibuffer)")
    "bk" '(kill-current-buffer :which-key "kill buffer")
    "bd" '(kill-current-buffer :which-key "kill buffer")
    "br" '(revert-buffer :which-key "revert buffer")

    "g"  '(:ignore t :which-key "git")
    "gg" '(magit-status :which-key "magit status")
    "gG" '(magit-status-here :which-key "magit status here")
    "gd" '(magit-diff-buffer-file :which-key "diff with file")
    "gj" '(git-gutter:next-hunk :which-key "next change")
    "gk" '(git-gutter:previous-hunk :which-key "previous change")

    "p" '(:ignore t :which-key "project")
    "pp" '(projectile-persp-switch-project :which-key "switch project")
    "pk" '((lambda () (interactive) (persp-kill (persp-current-name))) :which-key "kill current perspective")
    "pt" '(persp-switch :which-key "switch perspective")
    
    "o" '(:ignore t :which-key "org")
    "on" '((lambda () (interactive) (find-file-other-window (expand-file-name "notes.org" org-directory))) :which-key "open main notes file")
    "oa" '(org-agenda :which-key "open agenda")
    "ot" '(org-agenda-list :which-key "open todo list")

    "TAB" '(persp-switch :which-key "switch perspective")

    "t" '(:ignore t :which-key "toggle")
    "tf" '(toggle-frame-maximized :which-key "maximize")
    "tF" '(toggle-frame-fullscreen :which-key "fullscreen"))

  ;; Custom keybindings
  (general-define-key
   :states '(normal visual insert emacs)
   "C-SPC" 'corfu-completion-at-point))

;;; 2.1 WHICH-KEY (Keybinding Helper)
(use-package which-key
  :init (which-key-mode)
  :diminish which-key-mode
  :config
  (setq which-key-idle-delay 0.3) ;; Pop up after 0.3 seconds
  (setq which-key-separator " -> ") ;; Add more spacing between columns
  (setq which-key-sorting-type 'which-key-key-order)
  ;(setq which-key-sorting-type 'which-key-description-order) ;; Sort by description
  (which-key-setup-side-window-bottom))

;;; 2.2 ORG-MODE
(use-package org
  :init
  (setq org-directory "~/org/")
  (setq org-startup-indented t)
  :config
  ;; You can add more Org-mode specific configurations here later
  (require 'org-tempo)
    
  ;; Agenda setup
  (setq org-agenda-files '("~/org/"))
  
  ;; Local leader bindings for Org
  (my-local-leader-def
    :keymaps 'org-mode-map
    "t" '(org-todo :which-key "todo state")
    "d" '(org-deadline :which-key "deadline")
    "s" '(org-schedule :which-key "schedule")
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
  (global-ligature-mode t))

(setq-default indent-tabs-mode nil) ; Prefer spaces for indentation

(setq ring-bell-function 'ignore)       ; Silent bell
(global-display-line-numbers-mode t)    ; Line numbers
(column-number-mode t)                  ; Show column number in mode line
(global-hl-line-mode +1)                ; Highlight current line

;; Smooth scrolling
(setq scroll-conservatively 101
      scroll-margin 5)
;; (pixel-scroll-precision-mode +1)

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

;; TRAMP persistency file
(setq tramp-persistency-file-name (expand-file-name "tramp" (expand-file-name ".tmp/" user-emacs-directory)))


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

;;; 5.1 LINTING (Flycheck)
(use-package flycheck
  :init (global-flycheck-mode)
  :config
  ;; Use the built-in clj-kondo checker if available
  (setq flycheck-check-syntax-automatically '(save mode-enabled))
  (setq flycheck-emacs-lisp-load-path 'inherit))

(use-package flycheck-clj-kondo
  :after flycheck
  :config
  (require 'flycheck-clj-kondo))

;;; 5.2 EMACS LISP CONFIG
(add-hook 'emacs-lisp-mode-hook
          (lambda ()
            (setq-local evil-lookup-func (lambda () (describe-symbol (symbol-at-point))))))

;;; 6. LANGUAGE MODES
(use-package tree-sitter
  :init
  (global-tree-sitter-mode))

(use-package tree-sitter-langs
  :after tree-sitter
  :config)
  ;; You may need to install the grammar for Clojure
  ;; M-x tree-sitter-install-grammar RET clojure RET
  

(use-package clojure-ts-mode
  :after tree-sitter-langs
  :mode ("\\.clj\\'" "\\.cljs\\'" "\\.cljc\\'" "\\.edn\\'")
  :config
  (setopt tree-sitter-hl-default-modes '(clojure-ts-mode)
          clojure-toplevel-inside-comment-form t)

  ;; Tonsky indent style
  (setopt clojure-ts-indent-style 'fixed)

  (defun my-clojure-syntax-hook ()
    (modify-syntax-entry ?- "w") ; Treat hyphen as part of word
    (modify-syntax-entry ?? "w") ; Treat question mark as part of word (corrected)
    (modify-syntax-entry ?! "w") ; Treat exclamation mark as part of word
    (modify-syntax-entry ?> "w") ; Treat greater than as part of word
    (modify-syntax-entry ?< "w") ; Treat less than as part of word
    (modify-syntax-entry ?: "w") ; Treat colon as part of word (for keywords)
    (modify-syntax-entry ?/ "w") ; Treat slash as part of word (for qualified symbols/namespaces)
    (modify-syntax-entry ?. "w") ; Treat dot as part of word (for interop)
    (modify-syntax-entry ?* "w"))
  (add-hook 'clojure-ts-mode-hook 'my-clojure-syntax-hook)

  (general-define-key
   :states '(normal visual insert emacs)
   :keymaps 'clojure-ts-mode-map
   "TAB" 'clojure-ts-align)

  (my-local-leader-def
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
    
    "a" '(clojure-ts-align :which-key "align")))

(use-package parinfer-rust-mode
  :hook ((clojure-ts-mode . parinfer-rust-mode)
         (emacs-lisp-mode . parinfer-rust-mode))
  :config)
  ;; Enable evil-local-mode to ensure Evil works correctly with Parinfer
  ;; (add-hook 'parinfer-rust-mode-hook (lambda ()
  ;;                                      (evil-local-mode 1)))

(use-package cider
  :after clojure-ts-mode
  :config
  (setq cider-repl-display-help-banner nil ; clean up the REPL
        cider-repl-pop-to-buffer-on-connect nil ; keep focus in source file
        cider-clojure-cli-global-aliases ":dev:test")
  
  ;; Make 'K' look up documentation in CIDER
  (with-eval-after-load 'evil
    (add-hook 'cider-mode-hook (lambda () (setq-local evil-lookup-func #'cider-doc))))

  ;; Configure REPL window to be at the bottom with height 15
  (add-to-list 'display-buffer-alist
               '("\\*cider-repl"
                 (display-buffer-reuse-window display-buffer-in-side-window)
                 (side . bottom)
                 (window-height . 12)))

  (my-local-leader-def
    :keymaps 'cider-mode-map
    "e" '(:ignore t :which-key "eval")
    "ee" '(cider-eval-sexp-at-point :which-key "eval sexp at point")
    "ed" '(cider-eval-defun-at-point :which-key "eval defun at point")
    "ep" '(cider-eval-sexp-up-to-point :which-key "eval sexp up to point")
    "eP" '(cider-eval-defun-up-to-point :which-key "eval defun up to point")
    "ec" '(cider-eval-defun-to-comment :which-key "eval defun to comment")

    "r" '(:ignore t :which-key "REPL")
    "r!" '(cider-interrupt :which-key "interrupt")
    "ra" '(cider-apropos :which-key "apropos")
    "ri" '(cider-inspect :which-key "inspect")
    "rr" '(cider-ns-reload :which-key "reload namespace")
    "rR" '(cider-ns-reload-all :which-key "reload all namespaces")
    "rl" '((lambda () (interactive) (cider-load-file (buffer-file-name))) :which-key "load current file")
    "rb" '(cider-switch-to-repl-buffer :which-key "switch to REPL buffer")
    "rq" '(cider-quit :which-key "quit CIDER")
    "ru" '(cider-undef :which-key "undef")
    "rU" '(cider-undef-all :which-key "undef all")
    "rd" '(cider-debug-defun-at-point :which-key "debug defun at point")
    "rm" '(cider-macroexpand-1 :which-key "macroexpand 1")
    "rM" '(cider-macroexpand-all :which-key "macroexpand all"))

  (general-define-key
   :states '(normal visual)
   :keymaps 'cider-mode-map
   "gd" 'cider-find-var)

  (general-define-key
   :states '(normal visual)
   :keymaps 'cider-repl-mode-map
   "öq" 'cider-quit))


;;; init.el ends here
