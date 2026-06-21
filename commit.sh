#!/usr/bin/env bash
#
# commit.sh — stage everything and commit using COMMIT_MSG.txt verbatim.
#
# Why this exists: pasting a long commit message onto `git commit -m "..."`
# lets the shell try to execute parts of it — backticks run as commands, * and ?
# glob, 200...299 and $(...) cause parse errors. Reading the message from a file
# with `git commit -F` avoids all of that. This script does exactly that, plus a
# few safety checks, and works no matter which directory you run it from.
#
# Usage:
#   ./commit.sh            # stage all, commit from COMMIT_MSG.txt (no push)
#   ./commit.sh --push     # ...and push to the current branch's upstream
#   ./commit.sh --push origin master   # ...and push to a specific remote/branch
#
set -euo pipefail

# Resolve this script's own directory so COMMIT_MSG.txt is found regardless of CWD.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MSG_FILE="$SCRIPT_DIR/COMMIT_MSG.txt"

# 1. Must have the message file.
if [[ ! -f "$MSG_FILE" ]]; then
  echo "error: COMMIT_MSG.txt not found next to this script ($SCRIPT_DIR)." >&2
  echo "       Run this script from inside the drop folder where COMMIT_MSG.txt lives." >&2
  exit 1
fi

# 2. Must be inside a git repo. Operate from the repo root.
if ! REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null)"; then
  echo "error: not inside a git repository." >&2
  echo "       Move this drop's files into your repo (or run from your repo), then re-run." >&2
  exit 1
fi
cd "$REPO_ROOT"

# 3. Stage everything.
git add -A

# 4. Nothing to commit? Say so and stop (not an error).
if git diff --cached --quiet; then
  echo "Nothing staged to commit — working tree matches HEAD. Done."
  exit 0
fi

echo "Files to be committed:"
git diff --cached --name-status
echo

# 5. Commit using the file verbatim (no shell parsing of the message).
git commit -F "$MSG_FILE"
echo "Committed using COMMIT_MSG.txt."

# 6. Optional push.
if [[ "${1:-}" == "--push" ]]; then
  shift
  if [[ $# -ge 2 ]]; then
    REMOTE="$1"; BRANCH="$2"
    echo "Pushing to $REMOTE $BRANCH ..."
    git push "$REMOTE" "$BRANCH"
  else
    BRANCH="$(git rev-parse --abbrev-ref HEAD)"
    echo "Pushing current branch ($BRANCH) to its upstream ..."
    # Fall back to setting upstream on origin if none is configured.
    if ! git push 2>/dev/null; then
      echo "No upstream set; pushing to origin/$BRANCH and setting it as upstream."
      git push -u origin "$BRANCH"
    fi
  fi
  echo "Push complete."
else
  echo "Not pushing (run with --push to push). e.g.: ./commit.sh --push origin master"
fi
