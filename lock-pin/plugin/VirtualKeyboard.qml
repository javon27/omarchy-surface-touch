import QtQuick
import qs.Commons
import qs.Ui

// Touch keyboard for the lock screen. Defaults to a numeric PIN pad, with a
// toggle to a full QWERTY layout for typing the real account password.
// Typed characters go straight into `target` (the password TextInput) via
// insert()/remove() -- nothing here is logged, stored, or sent anywhere else.
Item {
  id: root

  property var target: null
  property string mode: "numeric"   // "numeric" | "full"
  property bool shift: false
  property bool symbols: false

  readonly property var numericRows: [
    ["1","2","3"],
    ["4","5","6"],
    ["7","8","9"]
  ]
  readonly property var letterRows: [
    ["1","2","3","4","5","6","7","8","9","0"],
    ["q","w","e","r","t","y","u","i","o","p"],
    ["a","s","d","f","g","h","j","k","l"],
    ["z","x","c","v","b","n","m"]
  ]
  readonly property var symbolRows: [
    ["1","2","3","4","5","6","7","8","9","0"],
    ["!","@","#","$","%","^","&","*","(",")"],
    ["-","_","=","+","[","]","{","}",";",":"],
    [",",".","/","?","\"","'","<",">","\\","|"]
  ]
  readonly property var fullRows: symbols ? symbolRows : letterRows

  function typeChar(ch) {
    if (!target) return
    var c = (root.mode === "full" && !symbols && shift) ? ch.toUpperCase() : ch
    target.insert(target.cursorPosition, c)
    if (root.mode === "full" && !symbols && shift) shift = false
  }

  function backspace() {
    if (!target) return
    var pos = target.cursorPosition
    if (pos > 0) target.remove(pos - 1, pos)
  }

  function submit() {
    if (target) target.accepted()
  }

  implicitHeight: column.implicitHeight

  Column {
    id: column
    width: parent.width
    spacing: 10

    // Numeric pad
    Column {
      anchors.horizontalCenter: parent.horizontalCenter
      spacing: 10
      visible: root.mode === "numeric"

      Repeater {
        model: root.numericRows
        delegate: Row {
          anchors.horizontalCenter: parent.horizontalCenter
          spacing: 10
          Repeater {
            model: modelData
            delegate: Key { width: 64; height: 56; label: modelData; onTapped: root.typeChar(modelData) }
          }
        }
      }

      Row {
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: 10
        Key { width: 64; height: 48; label: "ABC"; onTapped: root.mode = "full" }
        Key { width: 64; height: 48; label: "0"; onTapped: root.typeChar("0") }
        Key { width: 64; height: 48; label: "⌫"; onTapped: root.backspace() }
      }

      Key {
        anchors.horizontalCenter: parent.horizontalCenter
        width: 3 * 64 + 2 * 10
        height: 48
        label: "Enter"
        onTapped: root.submit()
      }
    }

    // Full QWERTY
    Column {
      width: parent.width
      spacing: 8
      visible: root.mode === "full"

      Repeater {
        model: root.fullRows
        delegate: Row {
          anchors.horizontalCenter: parent.horizontalCenter
          spacing: 6
          Repeater {
            model: modelData
            delegate: Key {
              width: 40
              height: 44
              label: (root.mode === "full" && !root.symbols && root.shift) ? modelData.toUpperCase() : modelData
              onTapped: root.typeChar(modelData)
            }
          }
        }
      }

      Row {
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: 6

        Key { width: 60; height: 44; label: "⇧"; highlighted: root.shift; visible: !root.symbols; onTapped: root.shift = !root.shift }
        Key { width: 60; height: 44; label: root.symbols ? "ABC" : "!#123"; highlighted: root.symbols; onTapped: root.symbols = !root.symbols }
        Key { width: 180; height: 44; label: ""; onTapped: root.typeChar(" ") }
        Key { width: 60; height: 44; label: "⌫"; onTapped: root.backspace() }
        Key { width: 60; height: 44; label: "123"; onTapped: root.mode = "numeric" }
        Key { width: 70; height: 44; label: "Enter"; onTapped: root.submit() }
      }
    }
  }
}
