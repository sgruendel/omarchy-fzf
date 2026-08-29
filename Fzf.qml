import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import qs.Commons
import qs.Ui
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
  property int contentSpacing: Style.spacing.md
  property int cardWidth: Math.min(Style.space(560), panel.width - Style.gapsOut * 2)
  property int cardHeight: Math.min(Style.space(500), panel.height - Style.gapsOut * 2)
  property int maxResults: 200

  function open(payloadJson) {
    root.opened = true
    root.activeIndex = -1
    root.selectedIndex = 0
    root.searching = false
    resultModel.clear()
    for (var i = 0; i < fieldsRepeater.count; i++) {
      var field = fieldsRepeater.itemAt(i)
      if (field) field.clearText()
    }
    Qt.callLater(function() {
      var first = fieldsRepeater.itemAt(0)
      if (first) first.focusInput()
    })
  }

  function close() {
    root.opened = false
  }

  function dismiss() {
    root.opened = false
    if (root.shell && typeof root.shell.hide === "function")
      root.shell.hide((root.manifest && root.manifest.id) || "sgruendel.fzf")
  }

  function toggle() {
    if (root.opened) root.dismiss()
    else root.open("{}")
  }

  function loadUserDirs(raw) {
    root.dirs = UserDirs.parseUserDirs(raw, Quickshell.env("HOME"))
  }

  function onQueryChanged(index, text) {
    if (text === "") {
      if (root.activeIndex === index) {
        root.activeIndex = -1
        root.selectedIndex = 0
        root.searching = false
        root.searchGen++
        resultModel.clear()
      }
      return
    }
    root.activeIndex = index
    root.selectedIndex = 0
    debounce.restart()
  }

  function onFieldFocused(index) {
    // Focusing another field abandons the previous search: clear the text of
    // every other field so a stale query cannot resurrect its results.
    for (var i = 0; i < fieldsRepeater.count; i++) {
      if (i === index) continue
      var field = fieldsRepeater.itemAt(i)
      if (field && field.text !== "") field.clearText()
    }
    if (root.activeIndex !== index) {
      root.activeIndex = -1
      root.searching = false
      root.searchGen++
      resultModel.clear()
    }
  }

  function runSearch() {
    if (root.activeIndex < 0 || root.activeIndex >= root.dirs.length) return
    var field = fieldsRepeater.itemAt(root.activeIndex)
    var query = field ? field.text : ""
    if (query === "") return
    root.searching = true
    root.searchGen++
    // Bump pendingGen only after exec(): stopping the previous process may
    // flush its collector synchronously, and that stale output must still
    // fail the generation check.
    searchProc.exec({
      command: ["sh", "-c",
        "fd --type f --hidden --exclude .git | fzf --filter=\"$1\" | head -" + root.maxResults,
        "sh", query],
      workingDirectory: root.dirs[root.activeIndex].path
    })
    searchProc.pendingGen = root.searchGen
  }

  function applyResults(gen, raw) {
    if (gen !== root.searchGen) return
    root.searching = false
    resultModel.clear()
    var lines = String(raw || "").split("\n")
    for (var i = 0; i < lines.length; i++) {
      if (lines[i] === "") continue
      resultModel.append({ path: lines[i] })
    }
    if (root.selectedIndex >= resultModel.count) root.selectedIndex = Math.max(0, resultModel.count - 1)
    Qt.callLater(function() {
      if (resultModel.count > 0) resultList.positionViewAtIndex(root.selectedIndex, ListView.Contain)
    })
  }

  function select(delta) {
    if (resultModel.count === 0) return
    root.selectedIndex = (root.selectedIndex + delta + resultModel.count) % resultModel.count
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

  FileView {
    path: Quickshell.env("HOME") + "/.config/user-dirs.dirs"
    watchChanges: true
    onLoaded: root.loadUserDirs(text())
  }

  Timer {
    id: debounce
    interval: 150
    onTriggered: root.runSearch()
  }

  Process {
    id: searchProc
    property int pendingGen: 0
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyResults(searchProc.pendingGen, text)
    }
    onExited: function(exitCode) {
      if (searchProc.pendingGen === root.searchGen) root.searching = false
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

      Column {
        anchors.fill: parent
        anchors.topMargin: card.contentTopInset
        anchors.rightMargin: card.contentRightInset
        anchors.bottomMargin: card.contentBottomInset
        anchors.leftMargin: card.contentLeftInset
        spacing: root.contentSpacing

        Column {
          id: fieldsColumn
          width: parent.width
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
                  if (event.key === Qt.Key_Escape) {
                    if (input.text !== "") input.text = ""
                    else root.dismiss()
                    event.accepted = true
                  } else if (event.key === Qt.Key_Up) {
                    root.select(-1)
                    event.accepted = true
                  } else if (event.key === Qt.Key_Down) {
                    root.select(1)
                    event.accepted = true
                  } else if (event.key === Qt.Key_PageUp) {
                    root.select(-10)
                    event.accepted = true
                  } else if (event.key === Qt.Key_PageDown) {
                    root.select(10)
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
        }

        Item {
          width: parent.width
          height: parent.height - fieldsColumn.implicitHeight - root.contentSpacing
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
                text: parent.path
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
            visible: root.activeIndex !== -1 && resultModel.count === 0
            text: root.searching ? "Searching…" : "No matches"
            color: root.foreground
            opacity: 0.7
            font.family: root.fontFamily
            font.pixelSize: Style.font.title
          }
        }
      }
    }
  }
}
