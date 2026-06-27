#!/usr/bin/env bash
#
# LAB 2 - bash helper (read side of lab2_menu.py)
#   - Show all files in a specific folder
#   - Show the installed Java version
#   - Print Log.txt
#
set -euo pipefail

show_files() {
  read -rp "Folder to list: " folder
  [ -z "$folder" ] && { echo "No folder given."; return 1; }
  ls -la "$folder"
}

show_java() {
  if command -v java >/dev/null 2>&1; then
    java -version
  else
    echo "Java not installed."
  fi
}

print_log() {
  if [ -f Log.txt ]; then
    cat Log.txt
  else
    echo "Log.txt not found in $(pwd)."
  fi
}

while true; do
  cat <<'MENU'

===== LAB 2 HELPER =====
1) Show all files in a folder
2) Show Java version
3) Print Log.txt
4) Exit
MENU
  read -rp "Choose [1-4]: " choice
  case "$choice" in
    1) show_files ;;
    2) show_java ;;
    3) print_log ;;
    4) echo "Bye."; exit 0 ;;
    *) echo "Invalid choice." ;;
  esac
done
