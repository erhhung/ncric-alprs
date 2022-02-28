# This user-data cloud-init script bootstraps a Ubuntu 20.04 server.
# It is appended to the host-specific "boot.tftpl" script template.

script="user-data"
exec > >(tee /var/log/$script.log | logger -t $script ) 2>&1
echo "[$(date '+%Y-%m-%d %H:%M:%S')] ===== BEGIN ${script^^} ====="
set -xeo pipefail

# run <func> [user]
run() {
  local func=$1 user=$2
  echo "[${user:-root}] $func"
  if [ $user ]; then
    export -f $func
    su $user -c "bash -c 'cd \$HOME; $func'"
  else
    $func
  fi
}

set_hostname() (
  hostname="alprs${ENV}-${HOST,,}"
  echo $hostname > /etc/hostname
  hostname $hostname
)

apt_install() {
  apt-get update
  apt-get dist-upgrade -y
  apt-get install -y figlet emacs-nox most unzip net-tools
}

motd_banner() (
  cd /etc/update-motd.d
  [ -f 11-help-text ] && exit
  cat <<EOF > 11-help-text
#!/bin/sh
figlet -f small "${HOST^^}" | sed '\$d'
EOF
  chmod -x 10-help-text 5* 8* 9*
  chmod +x 11-help-text 90* *reboot*
)

custom_prompt() (
  cd /etc/profile.d
  [ -f custom_prompt.sh ] && exit
  cat <<'EOF' > custom_prompt.sh
#!/bin/bash
export PROMPT_COMMAND='PS1="\[\033[1;36m\]\u\[\033[1;31m\]@\[\033[1;32m\]\h:\[\033[1;35m\]\w\[\033[1;31m\]$\[\033[0m\] "'
EOF
  chmod +x custom_prompt.sh
)

root_dotfiles() {
  cd /home/$USER
  /usr/bin/cp -f .bash_aliases .bashrc .emacs $HOME/
}

install_awscli() (
  cd /tmp
  curl -so awscliv2.zip https://awscli.amazonaws.com/awscli-exe-linux-aarch64.zip
  unzip -q awscliv2.zip
  ./aws/install
  rm -rf /tmp/aws*
)

bash_aliases() (
  [ -f .bash_aliases ] && exit
  cat <<'EOF' > .bash_aliases
# Emacs -*-Shell-Script-*- Mode

export LSCOLORS=GxFxCxDxBxegedabagaced
export EDITOR="/usr/bin/emacs"
export PAGER="/usr/bin/most"

# cd $OLDPWD only works in Bash
alias cdd='cd - > /dev/null'
# print cwd in shell escaped form
alias pwd='printf "%q\n" "$(builtin pwd)/"'
alias ls='ls --color=auto'
alias ll='ls -alF'
alias lt='ls -ltr'
alias la='ls -A'
alias s='screen'
alias du0='_diskusage . 0'
alias du1='_diskusage . 1'
alias sudo='sudo -E '
alias l=less
alias mud='most /var/log/user-data.log'

alias ag='sudo apt-get '
alias agu='ag update'
alias agi='ag install'
alias agd='ag dist-upgrade -y'
alias agr='ag autoremove -y --purge'

alias myip='printf "public: %s\n local: %s\n" "$(_instmeta public-ipv4)" "$(_instmeta local-ipv4)"'
alias myid='_instmeta instance-id'
alias myaz='_instmeta placement/availability-zone'
alias mytype='_instmeta instance-type'
alias myhost='_instmeta local-hostname'

# my instance metadata
# _instmeta <rel_path>
_instmeta() {
  echo $(curl -s "http://169.254.169.254/latest/meta-data/$1")
}

__touch_date() {
  local d=$(date '+%Y%m%d%H%M.00')
  if [ "$1" != '-t' ]; then
    echo "$d"
    return
  fi
  if [ "$1" == "-t" ]; then
    if [[ ! "$2" =~ ^[0-9]{0,12}$ ]]; then
      echo >&2 'Custom time must be all digits!'
      return 1
    fi
    if [ $((${#2} % 2)) -eq 1 ]; then
      echo >&2 'Even number of digits required!'
      return 1
    fi
    local n=$((12 - ${#2}))
    echo "${d:0:$n}$2.00"
  fi
}

_touch() {
  local d; d=$(__touch_date "$@") || return $?
  [ "$1" == '-t' ] && shift 2
  touch -cht "$d" "$@"
}
alias t='_touch'

touchall() {
  local d fargs=()
  if [ "$1" == '-d' ]; then
    fargs=(-type d); shift
  fi
  d=$(__touch_date "$@") || return $?
  [ "$d" ] && shift 2
  find "${@:-.}" "${fargs[@]}" -exec touch -cht "$d" "{}" \;
}
alias ta='touchall'
alias tad='touchall -d'

# show TCP4 ports currently in LISTENING state
listening() {
  netstat -ant | grep LISTEN | grep -E 'tcp4?' | sort -V
}
# show disk usage (please use du0/du1 aliases)
_diskusage() {
  local path="${1:-.}" depth=${2:-1}
  du -d $depth -x -h "$path" 2> >(grep -v 'Permission denied') | sort -h
}

# delete files and/or dirs older than x days
# rmold [--confirm] <days> [path] [findopts]
rmold() {
  if [ -z "$1" ]; then
    echo 'rmold [--confirm] <days> [path] [find_opts]'
    echo 'Performs dry run unless --confirm specified'
    return
  fi

  local conf=$1
  [ "$conf" == '--confirm' ] && shift

  local days=$1; shift
  if ! [ ${days:-0} -eq ${days:-1} 2> /dev/null ]; then
    echo >&2 'Days must be an integer!'
    return 1
  fi

  if [[ "$conf" == '--confirm' ]]; then
    find "$@" ! -path . -maxdepth 1 -mtime "+$days" -exec rm -rf "{}" \;
  else
    find "$@" ! -path . -maxdepth 1 -mtime "+$days" -printf "%T@ [%TD %TH:%TM] %s %p\n" 2> /dev/null \
      | sort -n | awk '{ hum[1]=" B";
      hum[1024**4]="TB"; hum[1024**3]="GB";
      hum[1024**2]="MB"; hum[1024   ]="KB";
      for (x = 1024**4; x > 0; x /= 1024) {
        if ($4 >= x) {
          printf $2" "$3"  %3.f %s  %s\n", $4/x, hum[x], $5; break;
        }
      }}';
  fi
}
EOF
)

add_dotemacs() (
  [ -f .emacs ] && exit
  cat <<'EOF' > .emacs
;; ===== Disable Startup Message =====
(setq inhibit-startup-message t)

;; Added by Package.el. This must come before configurations of
;; installed packages. Don't delete this line. If you don't want
;; it, just comment it out by adding a semicolon to the start of
;; the line. You may delete these explanatory comments.
(package-initialize)

;; ===== Hide Menu and Tool Bars =====
(if (display-graphic-p)
  (tool-bar-mode 0))
(menu-bar-mode t)

;; ===== Set Window Size Based On Resolution =====
(defun set-frame-size-according-to-resolution ()
  (interactive)
  (if window-system
  (progn
    ;; use 120 char wide window for largeish displays,
    ;; smaller 80 column windows for smaller displays.
    ;; pick whatever numbers make sense for you
    (if (> (x-display-pixel-width) 1280)
           (add-to-list 'default-frame-alist (cons 'width 140))
           (add-to-list 'default-frame-alist (cons 'width 80)))
    ;; for the height, subtract a couple hundred pixels
    ;; from the screen height (for panels, menubars and
    ;; whatnot), then divide by the height of a char to
    ;; get the height we want
    (add-to-list 'default-frame-alist
         (cons 'height (/ (- (x-display-pixel-height) 220)
                             (frame-char-height))))
    )))

(set-frame-size-according-to-resolution)

;; ===== Launch Window In Front =====
(if (display-graphic-p)
  (x-focus-frame nil))

;; ===== Set Local site-lisp Path =====
(add-to-list 'load-path "/usr/local/share/emacs/site-lisp")
(add-to-list 'load-path "/usr/local/share/emacs/24.5/site-lisp")

;; ===== Set ELPA archives =====
(setq package-archives '(("gnu"   . "http://elpa.gnu.org/packages/")
                         ("melpa" . "http://melpa.org/packages/")
                        ))

;; ===== Load Theme =====
(if (boundp 'custom-theme-load-path)
  (progn
    (add-to-list 'custom-theme-load-path "~/.emacs.d/elpa/dracula-theme-20200124.1953")
  ))

;(if (display-graphic-p)
;; https://draculatheme.com/emacs/
;  (load-theme 'dracula t)
;)

;; ===== Set Fonts =====
(modify-frame-parameters
  (selected-frame)
  '((font . "-*-monaco-*-*-*-*-16-*-*-*-*-*-*")))

(add-hook 'after-make-frame-functions
          (lambda (frame)
            (modify-frame-parameters
              frame
              '((font . "-*-monaco-*-*-*-*-16-*-*-*-*-*-*"))
              )))

;; ===== Set Colors =====
;; Set cursor and mouse-pointer colors
;(set-cursor-color "red")
;(set-mouse-color "goldenrod")
;; Set region background color
;(set-face-background 'region "blue")
;; Set Emacs background color
;(set-background-color "black")

;; ===== Set Highlight Current Line Minor Mode =====
;; In every buffer, the line which contains the cursor
;; will be fully highlighted
;(global-hl-line-mode t)

;; ===== Line By Line Scrolling =====
;; This makes the buffer scroll by only a single line when the up
;; or down cursor keys push the cursor (tool-bar-mode) outside the
;; buffer. The standard emacs behaviour is to reposition the cursor
;; in the center of screen, but this can make scrolling confusing
(setq scroll-step 1)

;; ===== Turn Off Tab Character =====
;; Emacs normally uses both tabs and spaces to indent lines. If you
;; prefer, all indentation can be made from spaces only. To request
;; this, set `indent-tabs-mode' to `nil'. This is a per-buffer variable;
;; altering the variable affects only the current buffer, but it can be
;; disabled for all buffers.
;; Use (setq ...) to set value locally to a buffer
;; Use (setq-default ...) to set value globally
(setq-default indent-tabs-mode nil)

;; ===== Disable Auto-Indentation of New Lines =====
(when (fboundp 'electric-indent-mode) (electric-indent-mode -1))

;; ===== Make Tab Key Do Indent First Then Completion =====
(setq-default tab-always-indent t)

;; ===== Set Default Tab Width =====
(setq-default tab-width 2)
(setq standard-indent   2)
(setq sh-basic-offset   2)
(setq sh-indentation    2)

;; ===== Support Wheel Mouse Scrolling =====
(if (display-graphic-p)
  (mouse-wheel-mode t))

;; ===== Prevent Emacs From Making Backup Files =====
(setq make-backup-files nil)

;; ===== Write Backup Files in Designated Folder =====
;; Enable backup files
;(setq make-backup-files t)
;; Enable versioning with default values
;(setq version-control t)
;; Save all backup file in this directory
;(setq backup-directory-alist (quote ((".*" . "~/.emacs.d/backups/"))))

;; ===== Show Line+Column Numbers on Mode Line =====
  (line-number-mode t)
(column-number-mode t)

;; ===== Define Auto-Loading of Scripting Major Modes =====
(add-to-list 'interpreter-mode-alist '("bash"   . shell-script-mode))
(add-to-list 'interpreter-mode-alist '("python" . python-mode))

;; ===== Make Text Mode The Default Mode For New Buffers =====
(setq default-major-mode 'text-mode)

;; ===== Prevent Emacs From Inserting a NewLine at EOF =====
(setq next-line-add-newline nil)
(setq require-final-newline nil)
EOF
)

install_certbot() {
  snap install core
  snap refresh core
  snap install --classic certbot
  ln -s /snap/bin/certbot /usr/bin/certbot
}

generate_cert() (
  cd /tmp
  curl -sLo cert.sh http://exampleconfig.com/static/raw/openssl/centos7/etc/pki/tls/certs/make-dummy-cert
  myFQDN=$(curl -s http://169.254.169.254/latest/meta-data/local-hostname)
  ed -s cert.sh <<EOF
6,11d
6i
	echo California
	echo Walnut Creek
	echo MaiVERIC, Inc.
	echo ALPR
	echo $myFQDN
	echo root@$myFQDN
.
22d
w
q
EOF
  chmod +x cert.sh
  ./cert.sh server.pem
  openssl storeutl -keys  server.pem | sed '1d;$d' > server.key
  openssl storeutl -certs server.pem | sed '1d;$d' > server.crt
  rm server.pem cert.sh
  chmod 400 server.key
)

run bash_aliases $USER
run add_dotemacs $USER
run set_hostname
run apt_install
run motd_banner
run custom_prompt
run root_dotfiles
run install_awscli
