#!/bin/bash

# Distro Version Info:
release_info="$(cat /etc/*-release)"
ubuntu="$(grep 'ID=ubuntu' <<< "$release_info")"
kali="$(grep 'ID=kali' <<< "$release_info")"
debian="$(grep 'ID=debian' <<< "$release_info")"
arch="$(grep 'ID=arch' <<< "$release_info")"
version_id="$(grep 'VERSION_ID' <<< "$release_info" | awk -F '"' '{print $2}' | cut -d'.' -f1)"
VERSION="$(grep 'VERSION=' <<< "$release_info" | awk -F '(' '{print $2}' | cut -d')' -f1 | tr [:upper:] [:lower:] | awk '{print $1}' | awk 'NF>0')"

# Set $USER if unset:
if [[ -z "${USER}" ]]; then
  USER="$(id -un)"
fi

# FUNCTIONS:
proxy_check() {
  if [ -n "$(grep interactive <<< "${@}")" ]; then
    echo -e '\n[INFO] This script cannot be run on a proxied network without modifying'
    echo -e '[INFO] $http_proxy, $https_proxy, and setting up both apt and docker proxy config files.'
    echo -e '[INFO] It is MANDATORY to run this script from a non-proxied, external ISP without prior config modification.'
    echo -e '\nARE YOU BEHIND A PROXY???'
    read -p '[yes/no] ' proxy
  elif [ -n "$http_proxy" -o -n "$http_proxy" ]; then
    proxy='yes'
  else
    proxy='no'
  fi
  if [[ $proxy = yes ]]; then
    echo -e '\nGet your ass out from behind a proxy and try again later.\n'
    exit
  fi
}
error_check() {
  if [[ $? -ne 0 ]]; then
    echo -e "\n[ERROR] ${@}"
    exit
  fi
}
not_supported() {
  echo -e '\n[ERROR] This script can currently only run on supported Debian-based distos...and Arch.'
  exit 1
}
distro_check_active() {
  echo -e '\nSelect your Linux distribution:\n'
  echo '1) Kali'
  echo '2) Debian'
  echo '3) Ubuntu'
  echo '4) Arch'
  echo
  read -p 'Distro Number: ' DISTRO
}
distro_check_passive() {
  # FIND IF SUPPORTED:
  if [[ -n $kali ]]; then
    DISTRO=1
    DISTRO_NAME='kali'
    if [[ $version_id -lt 2018 ]]; then
      not_supported
    fi
  elif [[ -n $debian ]]; then
    DISTRO=2
    DISTRO_NAME='debian'
    if [[ $version_id -lt 8 ]]; then
      not_supported
    fi
  elif [[ -n $ubuntu ]]; then
    DISTRO=3
    DISTRO_NAME='ubuntu'
    if [[ $version_id -lt 16 ]]; then
      not_supported
    fi
  elif [[ -n $arch ]]; then
    DISTRO=4
    DISTRO_NAME='arch'
  fi
}
pkg_manager_config() {
  # CONFIGURE PACKAGE MANAGER:
  if command -v apt-get &> /dev/null; then
    # Determine if Debian-based distro:
    if [[ $USER != 'root' ]]; then
      PKG_MANAGER='sudo apt-get'
    else
      PKG_MANAGER='apt-get'
    fi
    # Variable to store the command used to update the package cache:
    UPDATE_PKG_CACHE="${PKG_MANAGER} update"
    # PKG_INSTALL="${PKG_MANAGER} --yes --no-install-recommends install"
    PKG_INSTALL="${PKG_MANAGER} --yes install"
  elif command -v pacman &> /dev/null; then
    if [[ $USER != 'root' ]]; then
      PKG_MANAGER='sudo pacman'
    else
      PKG_MANAGER='pacman'
    fi
    UPDATE_PKG_CACHE="${PKG_MANAGER} -Sy"
    PKG_INSTALL="${PKG_MANAGER} -S"
  else
    not_supported
  fi
}

###################################################################
# START:
###################################################################

# Check that the user is not behind a proxy:
proxy_check

# INSTALL DOCKER:
if [[ -n $(command -v docker) ]]; then
  echo -e 'Do you wish to reinstall Docker?'
  read -p '[yes/no] ' docker
else
  docker='yes'
fi

if [[ $docker = no ]]; then
  echo -e '\nBye.'
  exit
else
  if [[ ${@} = --interactive ]]; then
    distro_check_active
  else
    distro_check_passive
  fi

  # CONFIGURE PACKAGE MANAGER:
  pkg_manager_config

  if [ "$DISTRO" != "1" -a "$USER" = "root" ]; then
    echo -e '\n[ERROR] This script should be run by a non-root user except on Kali Linux.'
    exit 1
  fi

  # INSTALL DEPENDENCIES:
  echo -e '\n[INFO] Updating the package cache...'
  ${UPDATE_PKG_CACHE}
  echo -e '\n[INFO] Installing Docker dependencies...'
  ${PKG_INSTALL} sudo apt-transport-https ca-certificates curl software-properties-common

  # DOWNLOAD DOCKER GPG KEY:
  echo -e '\n[INFO] Adding Docker GPG key...'
  if [[ $DISTRO -eq 3 ]]; then
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
  elif [[ $DISTRO -eq 4 ]]; then
    echo 'No need...you use Arch, btw.'
  else
    curl -fsSL https://download.docker.com/linux/debian/gpg | sudo apt-key add -
  fi
  error_check 'Problem adding Docker GPG key.'

  # REMOVE UNOFFICIAL PACKAGES:
  if [[ $DISTRO -ne 4 ]]; then
    echo -e '\n[INFO] Removing any existing unofficial Docker repositories...'
    ${PKG_MANAGER} remove --silent --yes docker docker-engine docker.io >/dev/null 2>&1
  fi

  # ADDING OFFICIAL REPOS:
  echo -e '\n[INFO] Adding Official Docker repository...'
  if [[ $DISTRO -eq 1 ]]; then
    echo 'deb https://download.docker.com/linux/debian stretch stable' | sudo tee /etc/apt/sources.list.d/docker.list
  elif [[ $DISTRO -eq 2 ]]; then
    # sudo add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/debian $(lsb_release -cs) stable"
    sudo add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/debian ${VERSION} stable"
  elif [[ $DISTRO -eq 4 ]]; then
    echo 'No need...you use Arch, btw.'
  else
    # sudo add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
    sudo add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu ${VERSION} stable"
  fi
  error_check 'Error adding Docker repository'

  # INSTALL DOCKER:
  echo -e '\n[INFO] Updating the package cache...'
  ${UPDATE_PKG_CACHE}
  echo -e '\n[INFO] Installing docker-ce...'
  if [[ $DISTRO -ne 4 ]]; then
    ${PKG_INSTALL} docker-ce
  else
    ${PKG_INSTALL} docker
  fi
  error_check 'Error installing Docker'

  # INSTALL DOCKER-COMPOSE:
  if [[ -n $(echo $* | grep 'with-compose') ]]; then
    echo -e '\n[INFO] Installing docker-compose...'
    ${PKG_INSTALL} docker-compose
    error_check 'Error installing Docker Compose'
  fi

  # ADD NON-ROOT DOCKER USER:
  if [[ -n $(echo $* | grep 'interactive') ]]; then
    if [[ $LOGNAME != root ]]; then
      echo -e "\nDocker can be run by normal users without having to use 'sudo'."
      echo "You should first look into security implications of this functionality."
      echo "You can always do this later as root by running the following command:"
      echo "usermod -aG docker ${LOGNAME}"
      echo -e '\nDo you wish to add the current user to the docker group?'
      read -p '[yes/no] ' dockeruser
    else
      dockeruser=yes
    fi
  fi
  if [[ $dockeruser = yes ]]; then
    sudo groupadd docker 2>/dev/null
    sudo usermod -aG docker "${LOGNAME}"
    echo -e "\n[INFO] You will need to run su - ${LOGNAME} to inherit docker group privileges."
  fi

  # ENABLE DOCKER:
  if [[ -n $(echo $* | grep 'interactive') ]]; then
    echo -e '\nDo you want Docker to start on boot?'
    read -p '[yes/no] ' enable
  else
    enable=yes
  fi
  if [[ $enable = yes ]]; then
    echo -e '\n[INFO] Enabling Docker to start on boot...'
    sudo systemctl enable docker
  fi
  # START DOCKER
  echo -e '\n[INFO] Starting Docker...'
  sudo systemctl start docker
fi

# FINISH
error_check 'Something went wrong.'
if [[ $LOGNAME != root ]]; then
  echo -e "\n[INFO] You may need to run su - ${USER} to inherit docker group privileges."
fi
echo -e '\n[SUCCESS] Installation Complete.'
