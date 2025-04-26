#!/bin/bash

# Default size threshold in MB
SIZE_LIMIT_MB=${1:-10}
SIZE_LIMIT_BYTES=$((SIZE_LIMIT_MB * 1024 * 1024))

# Function to check for large files in a given branch
check_large_git_files() {
  local branch="$1"
  echo "Branch: $branch"
  git ls-tree -r -l "$branch" | awk -v limit="$SIZE_LIMIT_BYTES" '$4 > limit {printf "%10d bytes\t%s\n", $4, $5}'
  echo ""
}

# Get all local branches
branches=$(git for-each-ref --format='%(refname:short)' refs/heads/)

# Iterate through each branch
for branch in $branches; do
  check_large_git_files "$branch"
done
