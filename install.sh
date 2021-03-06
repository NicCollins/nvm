#!/bin/bash

set -e

nvm_has() {
  type "$1" > /dev/null 2>&1
  return $?
}

if [ -z "$NVM_DIR" ]; then
  NVM_DIR="$HOME/.nvm"
fi

#
# Outputs the location to NVM depending on:
# * The availability of $NVM_SOURCE
# * The method used ("script" or "git" in the script, defaults to "git")
# NVM_SOURCE always takes precedence
#
nvm_source() {
  local NVM_METHOD
  NVM_METHOD="$1"
  if [ -z "$NVM_SOURCE" ]; then
    local NVM_SOURCE
  else
    echo "$NVM_SOURCE"
    return 0
  fi
  if [ "_$NVM_METHOD" = "_script" ]; then
    NVM_SOURCE="https://raw.githubusercontent.com/NicCollins/nvm/v0.21.0/nvm.sh"
  elif [ "_$NVM_METHOD" = "_script-nvm-exec" ]; then
    NVM_SOURCE="https://raw.githubusercontent.com/NicCollins/nvm/v0.21.0/nvm-exec"
  elif [ "_$NVM_METHOD" = "_git" ] || [ -z "$NVM_METHOD" ]; then
    NVM_SOURCE="https://github.com/NicCollins/nvm.git"
  else
    echo >&2 "Unexpected value \"$NVM_METHOD\" for \$NVM_METHOD"
    return 1
  fi
  echo "$NVM_SOURCE"
  return 0
}

nvm_download() {
  if nvm_has "curl"; then
    curl $*
  elif nvm_has "wget"; then
    # Emulate curl with wget
    ARGS=$(echo "$*" | sed -e 's/--progress-bar /--progress=bar /' \
                           -e 's/-L //' \
                           -e 's/-I /--server-response /' \
                           -e 's/-s /-q /' \
                           -e 's/-o /-O /' \
                           -e 's/-C - /-c /')
    wget $ARGS
  fi
}

install_nvm_from_git() {
  if [ -d "$NVM_DIR/.git" ]; then
    echo "=> nvm is already installed in $NVM_DIR, trying to update"
    printf "\r=> "
    cd "$NVM_DIR" && (git fetch 2> /dev/null || {
      echo >&2 "Failed to update nvm, run 'git fetch' in $NVM_DIR yourself." && exit 1
    })
  else
    # Cloning to $NVM_DIR
    echo "=> Downloading nvm from git to '$NVM_DIR'"
    printf "\r=> "
    mkdir -p "$NVM_DIR"
    git clone "$(nvm_source "git")" "$NVM_DIR"
  fi
  cd "$NVM_DIR" && git checkout v0.21.0 && git branch -D master >/dev/null 2>&1
  return
}

install_nvm_as_script() {
  local NVM_SOURCE
  NVM_SOURCE=$(nvm_source "script")
  local NVM_EXEC_SOURCE
  NVM_EXEC_SOURCE=$(nvm_source "script-nvm-exec")

  # Downloading to $NVM_DIR
  mkdir -p "$NVM_DIR"
  if [ -d "$NVM_DIR/nvm.sh" ]; then
    echo "=> nvm is already installed in $NVM_DIR, trying to update"
  else
    echo "=> Downloading nvm as script to '$NVM_DIR'"
  fi
  nvm_download -s "$NVM_SOURCE" -o "$NVM_DIR/nvm.sh" || {
    echo >&2 "Failed to download '$NVM_SOURCE'"
    return 1
  }
  nvm_download -s "$NVM_EXEC_SOURCE" -o "$NVM_DIR/nvm-exec" || {
    echo >&2 "Failed to download '$NVM_EXEC_SOURCE'"
    return 2
  }
  chmod a+x "$NVM_DIR/nvm-exec" || {
    echo >&2 "Failed to mark '$NVM_DIR/nvm-exec' as executable"
    return 3
  }
}

nvm_add_profile() {
  if ! grep -qc 'nvm.sh' "$1"; then
      echo "=> Appending source string to $1"
      printf "$2\n" >> "$1"
    else
      echo "=> Source string already in $1"
    fi
}

#
# Detect profile file if not specified as environment variable
# (eg: PROFILE=~/.myprofile)
# The echo'ed path is guaranteed to be an existing file
# Otherwise, an empty string is returned
#
nvm_detect_profile() {
  found=1
  if [ -f "$PROFILE" ]; then
    nvm_add_profile "$PROFILE" "$1"
    found=0
  else 
    if [ -f "$HOME/.bashrc" ]; then
      nvm_add_profile "$HOME/.bashrc" "$1"
      found=0
    fi
    if [ -f "$HOME/.bash_profile" ]; then
      nvm_add_profile "$HOME/.bash_profile" "$1"
      found=0
    fi
    if [ -f "$HOME/.zshrc" ]; then
      nvm_add_profile "$HOME/.zshrc" "$1"
      found=0
    fi
    if [ -f "$HOME/.profile" ]; then
      nvm_add_profile "$HOME/.profile" "$1"
      found=0
    fi
  fi
  return $found
}

nvm_do_install() {
  if [ -z "$METHOD" ]; then
    # Autodetect install method
    if nvm_has "git"; then
      install_nvm_from_git
    elif nvm_has "nvm_download"; then
      install_nvm_as_script
    else
      echo >&2 "You need git, curl, or wget to install nvm"
      exit 1
    fi
  elif [ "~$METHOD" = "~git" ]; then
    if ! nvm_has "git"; then
      echo >&2 "You need git to install nvm"
      exit 1
    fi
    install_nvm_from_git
  elif [ "~$METHOD" = "~script" ]; then
    if ! nvm_has "nvm_download"; then
      echo >&2 "You need curl or wget to install nvm"
      exit 1
    fi
    install_nvm_as_script
  fi

  echo "NVM Download Complete"

  local NVM_PROFILE
  
  SOURCE_STR="\nexport NVM_DIR=\"$NVM_DIR\"\n[ -s \"\$NVM_DIR/nvm.sh\" ] && . \"\$NVM_DIR/nvm.sh\"  # This loads nvm\nnvm use v0.10.32"
  
  nvm_detect_profile "$SOURCE_STR"
  NVM_PROFILE=$?

  if [ $NVM_PROFILE -gt "0" ] ; then
    echo "=> Profile not found. Tried Profile (as defined in \$PROFILE), ~/.bashrc, ~/.bash_profile, ~/.zshrc, and ~/.profile."
    echo "=> Create one of them and run this script again"
    echo "=> Create it (touch .bashrc) and run this script again"
    echo "   OR"
    echo "=> Append the following lines to the correct file yourself:"
    printf "$SOURCE_STR"
    echo
  fi

  echo "=> Close and reopen your terminal to start using nvm"
  nvm_reset
}

#
# Unsets the various functions defined
# during the execution of the install script
#
nvm_reset() {
  unset -f nvm_do_install nvm_has nvm_download install_nvm_as_script install_nvm_from_git nvm_reset nvm_detect_profile
}

[ "_$NVM_ENV" = "_testing" ] || nvm_do_install
