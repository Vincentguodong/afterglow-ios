#!/usr/bin/env bash
# Double-click on macOS to open the project and installation guide.
set -u
project_root="$(cd "$(dirname "$0")" && pwd)"
bash "$project_root/Scripts/install-free.sh" --open
result=$?
if [[ -t 0 ]]; then
  printf '\n按回车键关闭此窗口…'
  read -r _ || true
fi
exit "$result"
