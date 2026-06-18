#!/usr/bin/env bash
: <<DOCXX
Add description
Author: morgan@morganism.dev
Date: Thu 18 Jun 2026 07:11:27 BST
DOCXX

#!/usr/bin/env bash

# ---- Guard: must be sourced ----
# Bash: $BASH_SOURCE != $0 when sourced
# Zsh:  $ZSH_EVAL_CONTEXT contains ":file" when sourced
if [[ -n "$BASH_VERSION" ]]; then
  if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    echo "ERROR: This script must be sourced, not executed."
    echo "Use:  source aws-profile-select.sh"
    return 1 2>/dev/null || exit 1
  fi
elif [[ -n "$ZSH_VERSION" ]]; then
  case $ZSH_EVAL_CONTEXT in
    *:file) ;;
    *)
      echo "ERROR: This script must be sourced, not executed."
      echo "Use:  source aws-profile-select.sh"
      return 1 2>/dev/null || exit 1
      ;;
  esac
fi
# --------------------------------

# Extract profiles
mapfile -t PROFILES < <(grep '^\[' ~/.aws/credentials | sed 's/[][]//g')

if [[ ${#PROFILES[@]} -eq 0 ]]; then
  echo "No AWS profiles found."
  return 1
fi

echo "Select AWS profile:"
for i in "${!PROFILES[@]}"; do
  printf "  %d) %s\n" "$((i+1))" "${PROFILES[$i]}"
done

echo
read -n1 -p "Press a number (1-${#PROFILES[@]}): " KEY
echo

if [[ ! "$KEY" =~ ^[0-9]+$ ]]; then
  echo "Invalid selection"
  return 1
fi

INDEX=$((KEY-1))

if [[ $INDEX -lt 0 || $INDEX -ge ${#PROFILES[@]} ]]; then
  echo "Selection out of range"
  return 1
fi

export AWS_PROFILE="${PROFILES[$INDEX]}"
echo "AWS_PROFILE set to: $AWS_PROFILE"
