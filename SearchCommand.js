// Builds the headless fd/fzf pipeline used by the overlay. User fzf options
// are cleared because options that change the output protocol (for example,
// --print-query or --print0) would otherwise turn non-path data into results.

var searchScript =
  "export LC_ALL=C\n" +
  "emit_bounded_results() {\n" +
  "  local max_results=$1 max_bytes=$2 count=0 total=0 result size\n" +
  "  while IFS= read -r -d '' result; do\n" +
  "    size=${#result}\n" +
  "    if (( count >= max_results || total + size + 1 > max_bytes )); then break; fi\n" +
  "    printf '%s\\0' \"$result\"\n" +
  "    count=$((count + 1))\n" +
  "    total=$((total + size + 1))\n" +
  "  done\n" +
  "}\n" +
  "if [[ ! $3 =~ ^[1-9][0-9]*$ || ! $4 =~ ^[1-9][0-9]*$ ]]; then\n" +
  "  printf 'Invalid search output limit\\n' >&2\n" +
  "  exit 64\n" +
  "fi\n" +
  "if ! cd -- \"$2\" 2>/dev/null; then\n" +
  "  printf 'Directory is not available: %s\\n' \"$2\" >&2\n" +
  "  exit 66\n" +
  "fi\n" +
  "if ! command -v fd >/dev/null 2>&1; then\n" +
  "  printf 'Required command not found: fd\\n' >&2\n" +
  "  exit 127\n" +
  "fi\n" +
  "if ! command -v fzf >/dev/null 2>&1; then\n" +
  "  printf 'Required command not found: fzf\\n' >&2\n" +
  "  exit 127\n" +
  "fi\n" +
  "fd --type f --hidden --exclude .git --print0 --strip-cwd-prefix | " +
    "env FZF_DEFAULT_OPTS= FZF_DEFAULT_OPTS_FILE= " +
    "fzf --scheme=path --read0 --print0 --filter=\"$1\" | " +
    "emit_bounded_results \"$3\" \"$4\"\n" +
  "statuses=(\"${PIPESTATUS[@]}\")\n" +
  "if (( statuses[0] != 0 && statuses[0] != 141 )); then exit \"${statuses[0]}\"; fi\n" +
  "if (( statuses[1] != 0 && statuses[1] != 1 && statuses[1] != 141 )); then exit \"${statuses[1]}\"; fi\n" +
  "exit \"${statuses[2]}\""

function command(query, directory, maxResults, maxOutputBytes) {
  return [
    "bash", "-c", searchScript, "bash", String(query), String(directory),
    String(maxResults), String(maxOutputBytes)
  ]
}

if (typeof module !== "undefined") {
  module.exports = {
    searchScript: searchScript,
    command: command
  }
}
