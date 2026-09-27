// Builds commands for bounded file reads and checked atomic writes. The byte
// limits are enforced by the subprocess before data reaches a QML collector.

var readScript =
  "export LC_ALL=C\n" +
  "path=$1\n" +
  "limit=$2\n" +
  "[[ $limit =~ ^[1-9][0-9]*$ ]] || exit 64\n" +
  "[[ -f $path ]] || exit 66\n" +
  "size=$(stat -Lc %s -- \"$path\" 2>/dev/null) || exit 66\n" +
  "(( size <= limit )) || exit 65\n" +
  "head -c \"$limit\" -- \"$path\" 2>/dev/null"

var writeScript =
  "export LC_ALL=C\n" +
  "target=$1\n" +
  "payload=$2\n" +
  "limit=$3\n" +
  "[[ $limit =~ ^[1-9][0-9]*$ ]] || exit 64\n" +
  "(( ${#payload} <= limit )) || exit 65\n" +
  "directory=${target%/*}\n" +
  "[[ -n $directory && -d $directory && ! -L $directory ]] || exit 66\n" +
  "umask 077\n" +
  "temporary=$(mktemp --tmpdir=\"$directory\" .sgruendel-fzf-state.XXXXXX) || exit 73\n" +
  "trap 'rm -f -- \"$temporary\"' EXIT\n" +
  "chmod 600 -- \"$temporary\" || exit 73\n" +
  "printf '%s' \"$payload\" > \"$temporary\" || exit 74\n" +
  "mv -fT -- \"$temporary\" \"$target\" || exit 74\n" +
  "trap - EXIT"

var prepareDirectoryScript =
  "directory=$1\n" +
  "[[ -n $directory && ! -L $directory ]] || exit 73\n" +
  "if [[ -e $directory ]]; then\n" +
  "  [[ -d $directory ]] || exit 73\n" +
  "  chmod 700 -- \"$directory\" || exit 73\n" +
  "else\n" +
  "  mkdir -m 700 -- \"$directory\" || exit 73\n" +
  "fi\n" +
  "[[ -d $directory && ! -L $directory ]] || exit 73"

function normalizedLimit(maxBytes) {
  var value = Math.floor(Number(maxBytes))
  return isFinite(value) && value > 0 ? value : 1
}

function readCommand(path, maxBytes) {
  return ["bash", "-c", readScript, "bash", String(path), String(normalizedLimit(maxBytes))]
}

function writeCommand(path, text, maxBytes) {
  return ["bash", "-c", writeScript, "bash", String(path), String(text), String(normalizedLimit(maxBytes))]
}

function prepareDirectoryCommand(path) {
  return ["bash", "-c", prepareDirectoryScript, "bash", String(path)]
}

if (typeof module !== "undefined") {
  module.exports = {
    readScript: readScript,
    writeScript: writeScript,
    prepareDirectoryScript: prepareDirectoryScript,
    readCommand: readCommand,
    writeCommand: writeCommand,
    prepareDirectoryCommand: prepareDirectoryCommand
  }
}
