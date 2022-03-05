(setq inhibit-startup-message t)

(package-initialize)

(if (display-graphic-p)
  (tool-bar-mode 0))
(menu-bar-mode t)

(set-frame-size-according-to-resolution)

(if (display-graphic-p)
  (x-focus-frame nil))

(add-to-list 'load-path "/usr/local/share/emacs/site-lisp")
(add-to-list 'load-path "/usr/local/share/emacs/24.5/site-lisp")

(setq package-archives
  '(("gnu"   . "http://elpa.gnu.org/packages/")
     ("melpa" . "http://melpa.org/packages/")
   ))

(modify-frame-parameters
  (selected-frame)
  '((font . "-*-monaco-*-*-*-*-16-*-*-*-*-*-*")))

(add-hook
  'after-make-frame-functions
    (lambda (frame)
      (modify-frame-parameters
        frame
        '((font . "-*-monaco-*-*-*-*-16-*-*-*-*-*-*"))
      )))

(setq scroll-step 1)

(when (fboundp 'electric-indent-mode) (electric-indent-mode -1))
(setq-default indent-tabs-mode nil)
(setq-default tab-always-indent t)

(setq-default tab-width 2)
(setq standard-indent   2)
(setq sh-basic-offset   2)
(setq sh-indentation    2)

(if (display-graphic-p)
  (mouse-wheel-mode t))

(setq make-backup-files nil)

  (line-number-mode t)
(column-number-mode t)

(add-to-list 'interpreter-mode-alist '("bash"   . shell-script-mode))
(add-to-list 'interpreter-mode-alist '("python" . python-mode))

(setq default-major-mode 'text-mode)

(setq next-line-add-newline nil)
(setq require-final-newline nil)
