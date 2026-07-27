#!/usr/bin/env bash
set -euo pipefail

EXIT_CODE_SUCCESS=0
EXIT_CODE_ERROR=1
TIMESTAMP_FORMAT='+%Y%m%d-%H%M'
TASK_ROOT_FOLDER_NAME='.tasks'
ERROR_MESSAGE_REPO_NOT_FOUND='gitリポジトリが見つかりません。'
ERROR_MESSAGE_EMPTY_ID='IDが空になりました。英数字で指定してください。'
ERROR_MESSAGE_INVALID_TYPE='指示の種類は feature/fix/change/research/other のいずれかで指定してください。'
ERROR_MESSAGE_UNEXPECTED='処理でエラーが発生しました。'
LOG_MESSAGE_BRANCH_CREATED='ブランチを作成しました: %s'
LOG_MESSAGE_TASK_CREATED='タスクディレクトリを作成しました: %s'

#
# スクリプト配置ディレクトリからgitリポジトリのルートを取得する。
#
get_repo_root() {
  local script_directory

  script_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  git -C "${script_directory}" rev-parse --show-toplevel 2>/dev/null || true
}

#
# 指示内容IDを仕様に沿った形式へ正規化する。
#
normalize_instruction_id() {
  local raw_id="$1"

  printf '%s' "${raw_id}" |
    tr '[:upper:]' '[:lower:]' |
    sed -E 's/[^a-z0-9-]+/-/g; s/^-+//; s/-+$//'
}

#
# 指示種別が仕様の選択肢に含まれているかを検証する。
#
validate_instruction_type() {
  local instruction_type="$1"

  case "${instruction_type}" in
    feature | fix | change | research | other) return 0 ;;
    *) return 1 ;;
  esac
}

#
# 指示種別とIDからブランチを作成する。
#
create_branch() {
  local repo_root="$1"
  local instruction_type="$2"
  local normalized_id="$3"

  local branch_name
  branch_name="${instruction_type}/${normalized_id}"
  git -C "${repo_root}" checkout -b "${branch_name}" >/dev/null
  printf '%s\n' "${branch_name}"
}

#
# タイムスタンプ付きのタスクディレクトリを作成する。
#
create_task_directory() {
  local repo_root="$1"
  local normalized_id="$2"

  local timestamp
  local task_directory
  timestamp="$(date "${TIMESTAMP_FORMAT}")"
  task_directory="${repo_root}/${TASK_ROOT_FOLDER_NAME}/${timestamp}_${normalized_id}"
  mkdir -p "${task_directory}"
  printf '%s\n' "${task_directory}"
}

#
# スクリプトのメイン処理を実行する。
#
main() {
  local instruction_type="${1:-}"
  local raw_id="${2:-}"
  local repo_root
  local normalized_id
  local branch_name
  local task_directory
  trap 'printf "%s\n" "${ERROR_MESSAGE_UNEXPECTED}" >&2; exit "${EXIT_CODE_ERROR}"' ERR

  # gitリポジトリ内での実行であることを確認する。
  repo_root="$(get_repo_root)"
  if [[ -z "${repo_root}" ]]; then
    printf '%s\n' "${ERROR_MESSAGE_REPO_NOT_FOUND}" >&2
    exit "${EXIT_CODE_ERROR}"
  fi

  # 指示種別の入力値を検証する。
  if ! validate_instruction_type "${instruction_type}"; then
    printf '%s\n' "${ERROR_MESSAGE_INVALID_TYPE}" >&2
    exit "${EXIT_CODE_ERROR}"
  fi

  # 指示内容IDを正規化し、空なら失敗として終了する。
  normalized_id="$(normalize_instruction_id "${raw_id}")"
  if [[ -z "${normalized_id}" ]]; then
    printf '%s\n' "${ERROR_MESSAGE_EMPTY_ID}" >&2
    exit "${EXIT_CODE_ERROR}"
  fi

  # ブランチとタスクディレクトリを順に作成する。
  branch_name="$(create_branch "${repo_root}" "${instruction_type}" "${normalized_id}")"
  task_directory="$(create_task_directory "${repo_root}" "${normalized_id}")"

  # 作成結果を標準出力へ表示する。
  printf "${LOG_MESSAGE_BRANCH_CREATED}\n" "${branch_name}"
  printf "${LOG_MESSAGE_TASK_CREATED}\n" "${task_directory}"
  exit "${EXIT_CODE_SUCCESS}"
}

main "$@"
