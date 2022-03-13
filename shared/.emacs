(setq inhibit-startup-message t)
(menu-bar-mode t)

(add-to-list 'load-path "/usr/share/emacs/site-lisp")
(add-to-list 'load-path "/usr/share/emacs/27.2/site-lisp")
(add-to-list 'load-path "/usr/share/emacs/26.3/site-lisp")
(add-to-list 'load-path "/usr/local/share/emacs/site-lisp")

(setq package-archives
  '(("gnu"   . "http://elpa.gnu.org/packages/")
     ("melpa" . "http://melpa.org/packages/")
   ))
(package-initialize)

(when (fboundp 'electric-indent-mode) (electric-indent-mode -1))
(setq-default indent-tabs-mode nil)
(setq-default tab-always-indent t)

(setq-default tab-width 2)
(setq standard-indent   2)
(setq sh-basic-offset   2)
(setq sh-indentation    2)

(setq make-backup-files nil)

  (line-number-mode t)
(column-number-mode t)

(add-to-list 'interpreter-mode-alist '("bash"   . shell-script-mode))
(add-to-list 'interpreter-mode-alist '("python" . python-mode))

(setq default-major-mode 'text-mode)

(setq next-line-add-newline nil)
(setq require-final-newline nil)
