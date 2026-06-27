#!/usr/bin/env python3
"""
LAB 2 - interactive python menu

  1. Create a few files in a specific folder
  2. Run Java installation
  3. Insert a resource (line) into Log.txt

Runs on a Linux agent. Option 2 needs sudo for the package manager.
"""
import os
import shutil
import subprocess
import sys
from pathlib import Path


def detect_pm() -> str:
    """Return the first available package manager: apt-get / dnf / yum."""
    for pm in ("apt-get", "dnf", "yum"):
        if shutil.which(pm):
            return pm
    return ""


def create_files() -> None:
    folder = input("Target folder: ").strip()
    if not folder:
        print("No folder given.")
        return
    count = input("How many files? ").strip()
    if not count.isdigit() or int(count) < 1:
        print("Enter a positive number.")
        return
    base = Path(folder).expanduser()
    base.mkdir(parents=True, exist_ok=True)
    for i in range(1, int(count) + 1):
        f = base / f"file{i}.txt"
        f.write_text(f"file {i}\n")
    print(f"Created {count} files in {base}")


def install_java() -> None:
    pm = detect_pm()
    if not pm:
        print("No supported package manager found.")
        return
    pkg = "default-jdk" if pm == "apt-get" else "java-latest-openjdk"
    print(f"Using {pm} to install {pkg} ...")
    if pm == "apt-get":
        subprocess.run(["sudo", "apt-get", "update", "-y"], check=False)
    subprocess.run(["sudo", pm, "install", "-y", pkg], check=False)
    print("Java install attempted. Verify with: java -version")


def insert_to_log() -> None:
    text = input("Resource/line to append to Log.txt: ").strip()
    if not text:
        print("Nothing to write.")
        return
    with open("Log.txt", "a", encoding="utf-8") as fh:
        fh.write(text + "\n")
    print(f"Appended to {os.path.abspath('Log.txt')}")


MENU = """
===== LAB 2 MENU =====
1) Create a few files in a specific folder
2) Run Java installation
3) Insert a resource into Log.txt
4) Exit
"""


def main() -> int:
    while True:
        print(MENU)
        choice = input("Choose [1-4]: ").strip()
        if choice == "1":
            create_files()
        elif choice == "2":
            install_java()
        elif choice == "3":
            insert_to_log()
        elif choice == "4":
            print("Bye.")
            return 0
        else:
            print("Invalid choice.")


if __name__ == "__main__":
    sys.exit(main())
