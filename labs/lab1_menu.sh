#!/usr/bin/env bash
#
# LAB 1 — interactive bash menu
#   1. Create a new directory in ~/Desktop/
#   2. Create a new user (by input)
#   3. Install curl & tcpdump
#
# Runs on a Linux agent. Options 2 & 3 need sudo.
set -euo pipefail

# Pick the available package manager: apt-get (Debian/Ubuntu) or dnf/yum (RHEL/CentOS).
detect_pm() {
  if   command -v apt-get >/dev/null 2>&1; then echo "apt-get"
  elif command -v dnf     >/dev/null 2>&1; then echo "dnf"
  elif command -v yum     >/dev/null 2>&1; then echo "yum"
  else echo ""
  fi
}

create_desktop_dir() {
  read -rp "New directory name: " name
  [ -z "$name" ] && { echo "No name given."; return 1; }
  local target="$HOME/Desktop/$name"
  mkdir -p "$target"
  echo "Created: $target"
}

create_user() {
  read -rp "New username: " user
  [ -z "$user" ] && { echo "No username given."; return 1; }
  sudo useradd -m "$user" && echo "User '$user' created." || echo "useradd failed (already exists?)."
}

install_tools() {
  local pm; pm="$(detect_pm)"
  [ -z "$pm" ] && { echo "No supported package manager found."; return 1; }
  echo "Using package manager: $pm"
  if [ "$pm" = "apt-get" ]; then sudo apt-get update -y; fi
  sudo "$pm" install -y curl tcpdump
  echo "Installed curl & tcpdump."
}

while true; do
  cat <<'MENU'

===== LAB 1 MENU =====
1) Create a new directory in ~/Desktop/
2) Create a new user (by input)
3) Install curl & tcpdump
4) Exit
MENU
  read -rp "Choose [1-4]: " choice
  case "$choice" in
    1) create_desktop_dir ;;
    2) create_user ;;
    3) install_tools ;;
    4) echo "Bye."; exit 0 ;;
    *) echo "Invalid choice." ;;
  esac
done
