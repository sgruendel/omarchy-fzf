import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import qs.Commons
import qs.Ui
import "BoundedFile.js" as BoundedFile
import "LastFieldState.js" as LastFieldState
import "SearchCommand.js" as SearchCommand
import "UserDirs.js" as UserDirs

Item {
  id: root

  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  property var shell: null
  property var manifest: null

  property bool opened: false
  property var dirs: []
  property int activeIndex: -1
  property int selectedIndex: 0
  property int searchGen: 0
  property bool searching: false
  property string searchError: ""
  property string dirsError: ""
  property bool dirsLoaded: false
  property bool lastFieldLoaded: false
  property string lastFieldPath: ""
  property string pendingLastFieldState: ""
  property bool stateDirReady: false

  readonly property int maxUserDirsBytes: 65536
  readonly property int maxStateBytes: 8192
  readonly property int maxDirectoryEntries: 64
  readonly property int maxPathLength: 4096
  readonly property int maxSearchOutputBytes: 262144
  readonly property int maxSearchErrorChars: 8192

  readonly property string stateHome: Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state"
  readonly property string stateDir: stateHome + "/sgruendel.fzf"
  readonly property string statePath: stateDir + "/state.json"
  readonly property string configHome: Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config"
  readonly property string userDirsPath: configHome + "/user-dirs.dirs"

  // Shares the [menu] surface tokens — themes that style the menu also
  // style this overlay.
  property color background: Color.menu.background
  property color foreground: Color.menu.text
  property color border: Color.menu.border
  property var borderSpec: Border.surfaceSpec("menu", "border", border, Math.max(1, Style.space(2)))
  property color scrim: Color.menu.scrim
  property color selectedBackground: Color.menu.selectedBackground
  property color selectedText: Color.menu.selectedText
  readonly property int cornerRadius: Style.cornerRadius
  property string fontFamily: Style.font.menuFamily
  property int contentMargin: Style.spacing.panelPadding
  property int fieldHeight: Math.max(Style.space(34), Style.font.title + Style.spacing.controlPaddingY * 2)
  property int shortcutHeight: Math.max(Style.space(34), Style.font.caption + Style.spacing.controlPaddingY * 2)
  property int contentSpacing: Style.spacing.md
  property int cardWidth: Math.min(Style.space(560), panel.width - Style.gapsOut * 2)
  property int cardHeight: Math.min(Style.space(500), panel.height - Style.gapsOut * 2)
  property int maxResults: 200

  Component.onCompleted: {
    userDirsProc.running = true
    lastFieldReadProc.running = true
  }

  function resetSearch(clearActive) {
    debounce.stop()
    root.searchGen++
    if (searchProc.running) searchProc.running = false
    if (clearActive) root.activeIndex = -1
    root.selectedIndex = 0
    root.searching = false
    root.searchError = ""
    resultModel.clear()
  }

  function open(payloadJson) {
    root.resetSearch(true)
    root.opened = true
    for (var i = 0; i < fieldsRepeater.count; i++) {
      var field = fieldsRepeater.itemAt(i)
      if (field) field.clearText()
    }
    root.focusPreferredField()
  }

  function close() {
    root.opened = false
    root.resetSearch(true)
  }

  function dismiss() {
    if (root.shell && typeof root.shell.hide === "function")
      root.shell.hide((root.manifest && root.manifest.id) || "sgruendel.fzf")
    else
      root.close()
  }

  function toggle() {
    if (root.opened) root.dismiss()
    else root.open("{}")
  }

  function loadUserDirs(raw) {
    var parsed = UserDirs.parseUserDirs(
      raw, Quickshell.env("HOME"), root.maxDirectoryEntries, root.maxPathLength)
    root.resetSearch(true)
    root.dirs = parsed
    root.dirsLoaded = true
    root.dirsError = parsed.length === 0 ? "No searchable XDG user directories found" : ""
    root.focusPreferredField()
  }

  function failUserDirs(reason) {
    root.resetSearch(true)
    root.dirs = []
    root.dirsLoaded = true
    root.dirsError = reason || ("Could not read " + root.userDirsPath)
  }

  function loadLastField(raw) {
    root.lastFieldPath = LastFieldState.parse(raw)
    root.lastFieldLoaded = true
    root.focusPreferredField()
  }

  function focusPreferredField() {
    if (!root.opened || !root.dirsLoaded || !root.lastFieldLoaded) return
    Qt.callLater(function() {
      if (!root.opened) return
      var index = LastFieldState.preferredIndex(root.dirs, root.lastFieldPath)
      var field = index >= 0 ? fieldsRepeater.itemAt(index) : null
      if (field) field.focusInput()
    })
  }

  function rememberField(index) {
    if (!root.lastFieldLoaded || index < 0 || index >= root.dirs.length) return
    var path = root.dirs[index].path
    if (path === root.lastFieldPath && root.pendingLastFieldState === "") return

    var serialized = LastFieldState.serialize(path)
    if (serialized === "") return
    root.lastFieldPath = path
    root.pendingLastFieldState = serialized

    if (root.stateDirReady) {
      root.flushLastFieldState()
    } else if (!stateDirProc.running) {
      stateDirProc.running = true
    }
  }

  function flushLastFieldState() {
    if (root.pendingLastFieldState === "" || stateWriteProc.running) return
    stateWriteProc.payload = root.pendingLastFieldState
    root.pendingLastFieldState = ""
    stateWriteProc.command = BoundedFile.writeCommand(
      root.statePath, stateWriteProc.payload, root.maxStateBytes)
    stateWriteProc.running = true
  }

  function onQueryChanged(index, text) {
    if (text === "") {
      if (root.activeIndex === index) root.resetSearch(true)
      return
    }

    // Invalidate and remove the previous result set immediately. Waiting for
    // the debounce would leave stale rows actionable under the new query.
    root.searchGen++
    if (searchProc.running) searchProc.running = false
    root.activeIndex = index
    root.selectedIndex = 0
    root.searching = true
    root.searchError = ""
    resultModel.clear()
    debounce.restart()
  }

  function onFieldFocused(index) {
    root.rememberField(index)
    // Focusing another field abandons the previous search: clear the text of
    // every other field so a stale query cannot resurrect its results.
    for (var i = 0; i < fieldsRepeater.count; i++) {
      if (i === index) continue
      var field = fieldsRepeater.itemAt(i)
      if (field && field.text !== "") field.clearText()
    }
    if (root.activeIndex !== index) {
      root.resetSearch(true)
    }
  }

  function runSearch() {
    if (root.activeIndex < 0 || root.activeIndex >= root.dirs.length) return
    var field = fieldsRepeater.itemAt(root.activeIndex)
    var query = field ? field.text : ""
    if (query === "") return
    var dirPath = root.dirs[root.activeIndex].path
    // Set pendingGen only after exec(): stopping the previous process may
    // flush its collector synchronously, and that stale output must still
    // fail the generation check.
    searchProc.errorText = ""
    searchProc.exec(SearchCommand.command(
      query, dirPath, root.maxResults, root.maxSearchOutputBytes))
    searchProc.pendingGen = root.searchGen
  }

  function applyResults(gen, raw) {
    if (gen !== root.searchGen) return
    root.searching = false
    root.searchError = ""
    resultModel.clear()
    var lines = String(raw || "").split("\0")
    for (var i = 0; i < lines.length && resultModel.count < root.maxResults; i++) {
      if (lines[i] === "") continue
      // Every command result is NUL-terminated. Ignore a trailing fragment if
      // a future command implementation ever reaches its byte cap mid-record.
      if (i === lines.length - 1 && raw && raw.charAt(raw.length - 1) !== "\0") continue
      resultModel.append({ path: lines[i] })
    }
    if (root.selectedIndex >= resultModel.count) root.selectedIndex = Math.max(0, resultModel.count - 1)
    Qt.callLater(function() {
      if (resultModel.count > 0) resultList.positionViewAtIndex(root.selectedIndex, ListView.Contain)
    })
  }

  function finishSearch(gen, exitCode, stdoutText, stderrText) {
    if (gen !== root.searchGen) return
    if (exitCode === 0) {
      root.applyResults(gen, stdoutText)
      return
    }

    root.searching = false
    resultModel.clear()
    var detail = String(stderrText || "").trim()
    root.searchError = detail !== "" ? detail : "Search failed (exit " + exitCode + ")"
  }

  function select(delta, wrap) {
    if (resultModel.count === 0) return
    if (wrap) {
      root.selectedIndex = (root.selectedIndex + delta + resultModel.count) % resultModel.count
    } else {
      root.selectedIndex = Math.max(0, Math.min(resultModel.count - 1, root.selectedIndex + delta))
    }
    resultList.positionViewAtIndex(root.selectedIndex, ListView.Contain)
  }

  function activateIndex(index) {
    if (root.activeIndex < 0 || root.activeIndex >= root.dirs.length) return
    if (index < 0 || index >= resultModel.count) return
    var fullPath = root.dirs[root.activeIndex].path + "/" + resultModel.get(index).path
    root.dismiss()
    Quickshell.execDetached(["xdg-open", fullPath])
  }

  ListModel { id: resultModel }

  // Both readers cap regular-file input before it reaches the collectors.
  Process {
    id: userDirsProc
    command: BoundedFile.readCommand(root.userDirsPath, root.maxUserDirsBytes)
    stdout: StdioCollector { id: userDirsStdout; waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode === 0) root.loadUserDirs(userDirsStdout.text)
      else if (exitCode === 65) root.failUserDirs("XDG user directories file is too large")
      else root.failUserDirs()
    }
  }

  Process {
    id: lastFieldReadProc
    command: BoundedFile.readCommand(root.statePath, root.maxStateBytes)
    stdout: StdioCollector { id: lastFieldReadStdout; waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode === 0) root.loadLastField(lastFieldReadStdout.text)
      else {
        if (exitCode === 65)
          console.warn("sgruendel.fzf: state file exceeds byte limit", root.statePath)
        root.loadLastField("")
      }
    }
  }

  Process {
    id: stateDirProc
    command: BoundedFile.prepareDirectoryCommand(root.stateDir)
    running: false
    onExited: function(exitCode) {
      if (exitCode === 0) {
        root.stateDirReady = true
        root.flushLastFieldState()
      } else {
        console.warn("sgruendel.fzf: could not create state directory", root.stateDir)
      }
    }
  }

  Process {
    id: stateWriteProc
    property string payload: ""
    running: false
    onExited: function(exitCode) {
      if (exitCode !== 0) {
        console.warn("sgruendel.fzf: state write failed with exit", exitCode)
        // Let a later focus retry the same path without immediately spinning.
        root.lastFieldPath = ""
      }
      stateWriteProc.payload = ""
      root.flushLastFieldState()
    }
  }

  Timer {
    id: debounce
    interval: 150
    onTriggered: root.runSearch()
  }

  Process {
    id: searchProc
    property int pendingGen: 0
    property string errorText: ""
    stdout: StdioCollector {
      id: searchStdout
      waitForEnd: true
    }
    stderr: SplitParser {
      // Empty markers emit arbitrary chunks instead of buffering whole lines.
      splitMarker: ""
      onRead: function(data) {
        var remaining = root.maxSearchErrorChars - searchProc.errorText.length
        if (remaining > 0)
          searchProc.errorText += String(data || "").slice(0, remaining)
      }
    }
    onExited: function(exitCode) {
      root.finishSearch(searchProc.pendingGen, exitCode, searchStdout.text, searchProc.errorText)
    }
  }

  PanelWindow {
    id: panel
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "sgruendel-fzf"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    Rectangle {
      anchors.fill: parent
      color: root.scrim
    }

    MouseArea {
      anchors.fill: parent
      onClicked: root.dismiss()
    }

    BorderSurface {
      id: card
      width: root.cardWidth
      height: root.cardHeight
      radius: root.cornerRadius
      anchors.centerIn: parent
      color: root.background
      borderSpec: root.borderSpec
      padding: root.contentMargin

      MouseArea { anchors.fill: parent; onClicked: {} }

      Item {
        anchors.fill: parent
        anchors.topMargin: card.contentTopInset
        anchors.rightMargin: card.contentRightInset
        anchors.bottomMargin: card.contentBottomInset
        anchors.leftMargin: card.contentLeftInset

        Column {
          id: fieldsColumn
          anchors.top: parent.top
          anchors.left: parent.left
          anchors.right: parent.right
          spacing: Style.space(4)

          Repeater {
            id: fieldsRepeater
            model: root.dirs

            delegate: Rectangle {
              id: fieldRow

              required property int index
              required property var modelData

              property alias text: input.text

              function clearText() { input.text = "" }
              function focusInput() { input.forceActiveFocus() }

              visible: root.activeIndex === -1 || root.activeIndex === index
              width: parent.width
              height: visible ? root.fieldHeight : 0
              radius: root.cornerRadius
              color: input.activeFocus
                ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.08)
                : "transparent"

              Text {
                id: dirLabel
                anchors.left: parent.left
                anchors.leftMargin: Style.spacing.controlPaddingX
                anchors.verticalCenter: parent.verticalCenter
                width: Style.space(110)
                text: fieldRow.modelData.name
                textFormat: Text.PlainText
                color: root.foreground
                opacity: input.activeFocus || input.text !== "" ? 1 : 0.58
                font.family: root.fontFamily
                font.pixelSize: Style.font.title
                elide: Text.ElideRight
              }

              TextInput {
                id: input
                anchors.left: dirLabel.right
                anchors.leftMargin: Style.space(8)
                anchors.right: parent.right
                anchors.rightMargin: Style.spacing.controlPaddingX
                anchors.verticalCenter: parent.verticalCenter
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.title
                clip: true
                cursorVisible: activeFocus

                onTextChanged: root.onQueryChanged(fieldRow.index, text)
                onActiveFocusChanged: if (activeFocus) root.onFieldFocused(fieldRow.index)

                Keys.onPressed: function(event) {
                  var control = (event.modifiers & Qt.ControlModifier) !== 0
                  if (event.key === Qt.Key_Escape) {
                    if (input.text !== "") input.text = ""
                    else root.dismiss()
                    event.accepted = true
                  } else if (event.key === Qt.Key_Up || (control && event.key === Qt.Key_K)) {
                    root.select(-1, true)
                    event.accepted = true
                  } else if (event.key === Qt.Key_Down || (control && event.key === Qt.Key_J)) {
                    root.select(1, true)
                    event.accepted = true
                  } else if (event.key === Qt.Key_PageUp || (control && event.key === Qt.Key_U)) {
                    root.select(-10, false)
                    event.accepted = true
                  } else if (event.key === Qt.Key_PageDown || (control && event.key === Qt.Key_D)) {
                    root.select(10, false)
                    event.accepted = true
                  } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                    root.activateIndex(root.selectedIndex)
                    event.accepted = true
                  } else if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
                    var step = (event.key === Qt.Key_Backtab) ? -1 : 1
                    var next = (fieldRow.index + step + fieldsRepeater.count) % fieldsRepeater.count
                    var field = fieldsRepeater.itemAt(next)
                    if (field) field.focusInput()
                    event.accepted = true
                  }
                }

                Text {
                  anchors.fill: parent
                  visible: input.text === ""
                  text: "Search " + fieldRow.modelData.name + "…"
                  textFormat: Text.PlainText
                  color: root.foreground
                  opacity: 0.38
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.title
                  verticalAlignment: Text.AlignVCenter
                  elide: Text.ElideRight
                }
              }
            }
          }

          Text {
            visible: root.dirs.length === 0
            width: parent.width
            height: visible ? root.fieldHeight : 0
            text: root.dirsError || "No searchable XDG user directories found"
            textFormat: Text.PlainText
            color: root.foreground
            opacity: 0.7
            font.family: root.fontFamily
            font.pixelSize: Style.font.title
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            wrapMode: Text.WordWrap
          }
        }

        Item {
          anchors.top: fieldsColumn.bottom
          anchors.topMargin: root.contentSpacing
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.bottom: shortcuts.top
          anchors.bottomMargin: root.contentSpacing
          visible: root.activeIndex !== -1

          ListView {
            id: resultList
            anchors.fill: parent
            model: resultModel
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            delegate: Rectangle {
              required property int index
              required property string path

              readonly property bool hasCursor: index === root.selectedIndex

              width: resultList.width
              height: Math.max(Style.space(28), Style.font.body + Style.spacing.controlPaddingY * 2)
              radius: root.cornerRadius
              color: hasCursor ? root.selectedBackground : "transparent"

              Text {
                anchors.left: parent.left
                anchors.leftMargin: Style.spacing.controlPaddingX
                anchors.right: parent.right
                anchors.rightMargin: Style.spacing.controlPaddingX
                anchors.verticalCenter: parent.verticalCenter
                text: parent.path.replace(/\n/g, "↵").replace(/\r/g, "↵").replace(/\t/g, "⇥")
                textFormat: Text.PlainText
                color: parent.hasCursor ? root.selectedText : root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                elide: Text.ElideMiddle
              }

              MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onContainsMouseChanged: if (containsMouse) root.selectedIndex = index
                onClicked: {
                  root.selectedIndex = index
                  root.activateIndex(index)
                }
              }
            }
          }

          Text {
            anchors.centerIn: parent
            width: parent.width - Style.spacing.controlPaddingX * 2
            visible: root.activeIndex !== -1 && resultModel.count === 0
            text: root.searching ? "Searching…" : (root.searchError || "No matches")
            textFormat: Text.PlainText
            color: root.foreground
            opacity: 0.7
            font.family: root.fontFamily
            font.pixelSize: Style.font.title
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
          }
        }

        Item {
          id: shortcuts
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          height: root.shortcutHeight

          Rectangle {
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: Math.max(1, Style.space(1))
            color: root.border
            opacity: 0.6
          }

          Row {
            anchors.centerIn: parent
            spacing: Style.space(12)

            Repeater {
              model: root.activeIndex === -1
                ? [
                    { keys: "Tab ⇧Tab", action: "Directory" },
                    { keys: "Esc", action: "Close" }
                  ]
                : [
                    { keys: "↑ ↓  C-j C-k", action: "Navigate" },
                    { keys: "PgUp PgDn  C-u C-d", action: "Page" },
                    { keys: "Enter", action: "Open" },
                    { keys: "Esc", action: "Clear" }
                  ]

              delegate: Row {
                id: shortcut

                required property var modelData

                height: keycap.height
                spacing: Style.space(4)

                Rectangle {
                  id: keycap
                  width: keyText.implicitWidth + Style.space(8)
                  height: Math.max(Style.space(20), Style.font.caption + Style.space(6))
                  radius: Math.min(root.cornerRadius, height / 2)
                  color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.08)

                  Text {
                    id: keyText
                    anchors.centerIn: parent
                    text: shortcut.modelData.keys
                    textFormat: Text.PlainText
                    color: root.foreground
                    opacity: 0.85
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                  }
                }

                Text {
                  height: keycap.height
                  text: shortcut.modelData.action
                  textFormat: Text.PlainText
                  color: root.foreground
                  opacity: 0.58
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  verticalAlignment: Text.AlignVCenter
                }
              }
            }
          }
        }
      }
    }
  }
}
