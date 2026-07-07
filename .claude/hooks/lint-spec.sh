#!/bin/bash
# PostToolUse hook. Claude Code runs this after every Write/Edit and
# pipes the tool payload in on stdin. If the written file is a route
# spec, the Prolog linter gets the final say: exit 2 from this script
# blocks the edit and feeds stderr back to the model, so a turn cannot
# end with a spec the linter rejects.
payload=$(cat)
file=$(printf '%s' "$payload" | python3 -c \
  'import json,sys; print(json.load(sys.stdin).get("tool_input",{}).get("file_path",""))' \
  2>/dev/null)

case "$file" in
  */examples/*.json) ;;
  *) exit 0 ;;
esac

cd "${CLAUDE_PROJECT_DIR:-.}" || exit 0

report=$(swipl driver.pl "$file" 2>&1)
if [ $? -ne 0 ]; then
  {
    echo "Route spec rejected by the linter:"
    printf '%s\n' "$report"
    echo "Fix the warnings in $file and write it again."
  } >&2
  exit 2
fi
exit 0
