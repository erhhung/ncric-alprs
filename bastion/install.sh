# This user-data cloud-init script is a continuation
# of the bastion host's "boot.sh" script.

install_node() (
  hash node 2> /dev/null && exit
  yum install -y gcc-c++ make
  curl -sL https://rpm.nodesource.com/setup_14.x | bash -
  yum install -y nodejs
  node -v && npm -v
)

install_delta() (
  cd /tmp
  hash delta 2> /dev/null && exit
  wget -q https://github.com/dandavison/delta/releases/download/0.12.0/delta-0.12.0-x86_64-unknown-linux-gnu.tar.gz
  tar xzvf delta-0.12.0-x86_64-unknown-linux-gnu.tar.gz -C /usr/bin --strip 1 delta-0.12.0-x86_64-unknown-linux-gnu/delta
  rm -f delta-*.tar.gz
)

add_gitconfig() (
  [ -f .gitconfig ] && exit
  cat <<'EOF' > .gitconfig
[core]
abbrev = 8
pager = delta

[color]
ui = auto

[gc]
autoDetach = false

[alias]
st = status
# show current branch
cb = rev-parse --abbrev-ref HEAD
# show root path of this project
root = rev-parse --show-toplevel
# show HEAD commit hash
hash = rev-parse --short HEAD
# show HEAD commit log
head = log --name-status -n 1 HEAD~1..HEAD
# list tracked remotes
lsr = remote -v
# list local branches
lsb = !git branch --no-color | colrm 1 2
# list remote branches
lsrb = !git ls-remote --heads origin | colrm 1 59
# remove local branch
rmb = branch -d
# remove remote branch
rmrb = push origin -d
# show commit history
hist = log --graph --date=short --pretty=format:\"%>|(6)%C(white)┃ %C(yellow)%h %C(brightcyan)%ad %C(white)┃ %Creset%s%C(brightred bold)%d %C(blue italic)[%an]\"
# edit commit history
ehist = "!f() { \
  git rebase -i ${1:-HEAD~1}; \
}; f"
# fetch plus submodules
up = "!f() { \
  git pull --rebase --prune \"$@\" && \
  git submodule update --init --recursive; \
}; f"
co = checkout
# create new branch
cob = checkout -b
# switch to branch only if it exists
coif = "!f() { \
  b=$(git ls-remote -h origin ${1:-%}); \
  [ -n \"$b\" ] && git checkout $1; \
}; f"
# add *existing* files and commit
cm = !git add -A && git commit -m
touch = commit --allow-empty -m
save = !git cm "SAVED"
wipe = !git cm "WIPED" -q && git reset HEAD~1 --hard
wip = commit -am "WIP"
# amend previous commit [w/ message]
amend = "!f() { \
  a() { git commit --amend \"$@\"; }; \
  [ -n \"$1\" ] && a -m \"$1\"; \
  [ -z \"$1\" ] && a -C HEAD; \
}; f"
undo = reset HEAD~1 --mixed
# debug git command
db = !GIT_TRACE=1 git
dt = difftool
mt = mergetool

[push]
default = simple

[pull]
rebase = true

[branch]
autosetuprebase = always

[filter "lfs"]
required = true
clean = git-lfs clean -- %f
smudge = git-lfs smudge -- %f
process = git-lfs filter-process

[url "https://"]
  insteadOf = git://
[url "https://github.com/"]
  insteadOf = git@github.com:

[pager]
diff = delta
log = delta
reflog = delta
show = delta

[interactive]
diffFilter = delta --color-only

[delta]
features = side-by-side line-numbers decorations
syntax-theme = Monokai Extended Bright
whitespace-error-style = 22 reverse
plus-style = "syntax #012800"
minus-style = "syntax #340001"
navigate = true

[delta "decorations"]
commit-decoration-style = bold yellow box ul
file-style = bold yellow ul
file-decoration-style = none

[merge]
tool = delta
conflictStyle = diff3

[diff]
tool = delta
colorMoved = default
EOF
)

clone_repo() (
  git clone https://github.com/openlattice/astrometrics.git
  cd astrometrics
  git co master
  git up
)

build_webapp() {
  cd astrometrics
  npm i && npm run build:prod
}

run install_node
run install_delta
run add_gitconfig $USER
run clone_repo    $USER
run build_webapp  $USER
