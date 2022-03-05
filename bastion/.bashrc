# Emacs -*-Shell-Script-*- Mode

# not sure why Ctrl-L is broken
# after upgrading to Bash 4.4
bind -x '"\C-l": clear;'

# Source global definitions
if [ -f /etc/bashrc ]; then
  . /etc/bashrc
fi

# User specific aliases and functions
if [ -f $HOME/.bash_aliases ]; then
  . $HOME/.bash_aliases
fi
