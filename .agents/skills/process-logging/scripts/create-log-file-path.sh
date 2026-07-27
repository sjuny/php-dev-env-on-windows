#!/usr/bin/env bash
set -euo pipefail

EXIT_CODE_SUCCESS=0
EXIT_CODE_ERROR=1
TASKS_ROOT_FOLDER_NAME='.tasks'
NO_TASK_FOLDER_OUTPUT='no-task-folder'
TIMESTAMP_FORMAT='+%Y%m%d-%H%M'
LOG_FILE_NAME_FORMAT='process-log_%s.md'
ERROR_MESSAGE_NOT_GIT_WORKSPACE='gitのワークスペース内で実行してください。'
ERROR_MESSAGE_TASKS_ROOT_NOT_FOUND='.tasksディレクトリが存在しません。'
ERROR_MESSAGE_BRANCH_NAME_NOT_FOUND='現在のgitブランチ名を取得できません。'
ERROR_MESSAGE_TASK_DIRECTORY_NOT_FOUND='対象のタスクディレクトリが見つかりません（ブランチ末尾: %s）。'
FIND_MAX_DEPTH=1

#
# エラーメッセージを標準エラーへ、固定トークンを標準出力へ出力して終了する。
#
exit_with_task_folder_error() {
  local error_message="$1"

  # 呼び出し側が機械判定しやすいように固定トークンを返す。
  printf '%s\n' "${error_message}" >&2
  printf '%s\n' "${NO_TASK_FOLDER_OUTPUT}"
  exit "${EXIT_CODE_ERROR}"
}

#
# Gitワークスペースのルートパスを取得する。
#
get_workspace_root() {
  git rev-parse --show-toplevel 2>/dev/null || true
}

#
# .tasksディレクトリのルートパスを取得する。
#
get_tasks_root() {
  local workspace_root="$1"
  printf '%s/%s\n' "${workspace_root}" "${TASKS_ROOT_FOLDER_NAME}"
}

#
# 現在のGitブランチ名を取得する。
#
get_branch_name() {
  git rev-parse --abbrev-ref HEAD 2>/dev/null || true
}

#
# ブランチ名末尾を含むタスクディレクトリを1件取得する。
#
find_task_directory() {
  local tasks_root="$1"
  local branch_suffix="$2"

  find "${tasks_root}" -maxdepth "${FIND_MAX_DEPTH}" -type d -name "*${branch_suffix}*" -print -quit
}

#
# ログファイルパスを組み立てる。
#
build_log_file_path() {
  local task_directory="$1"
  local timestamp="$2"
  local log_file_name

  log_file_name="$(printf "${LOG_FILE_NAME_FORMAT}" "${timestamp}")"
  printf '%s/%s\n' "${task_directory}" "${log_file_name}"
}

#
# スクリプトのメイン処理を実行する。
#
main() {
  local workspace_root
  local tasks_root
  local branch_name
  local branch_suffix
  local task_directory
  local timestamp
  local log_file_path
  local error_message

  # Gitワークスペースのルートパスを取得し、取得不可なら終了する。
  workspace_root="$(get_workspace_root)"
  if [[ -z "${workspace_root}" ]]; then
    exit_with_task_folder_error "${ERROR_MESSAGE_NOT_GIT_WORKSPACE}"
  fi

  # .tasksディレクトリを取得し、存在しない場合は終了する。
  tasks_root="$(get_tasks_root "${workspace_root}")"
  if [[ ! -d "${tasks_root}" ]]; then
    exit_with_task_folder_error "${ERROR_MESSAGE_TASKS_ROOT_NOT_FOUND}"
  fi

  # 現在のGitブランチ名を取得し、取得不可なら終了する。
  branch_name="$(get_branch_name)"
  if [[ -z "${branch_name}" ]]; then
    exit_with_task_folder_error "${ERROR_MESSAGE_BRANCH_NAME_NOT_FOUND}"
  fi

  # ブランチ末尾をキーにタスクディレクトリを探索し、未検出なら終了する。
  branch_suffix="${branch_name##*/}"
  task_directory="$(find_task_directory "${tasks_root}" "${branch_suffix}")"
  if [[ -z "${task_directory}" ]]; then
    error_message="$(printf "${ERROR_MESSAGE_TASK_DIRECTORY_NOT_FOUND}" "${branch_suffix}")"
    exit_with_task_folder_error "${error_message}"
  fi

  # ログファイルパスを作成して標準出力へ返す。
  timestamp="$(date "${TIMESTAMP_FORMAT}")"
  log_file_path="$(build_log_file_path "${task_directory}" "${timestamp}")"
  printf '%s\n' "${log_file_path}"
  exit "${EXIT_CODE_SUCCESS}"
}

main
