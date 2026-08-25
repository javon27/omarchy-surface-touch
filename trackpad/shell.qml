import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Io

// Standalone virtual trackpad. Touch here moves the real cursor via
// relative mouse motion (same as the physical Type Cover trackpad), so
// every app handles it identically -- including click-and-drag text
// selection, which touch-to-pointer emulation can't do reliably.
// Toggled independently of the main omarchy-shell process.
ShellRoot {
  id: root

  property real gain: 2.2
  property real scrollGain: 3.0
  property int tapMaxDurationMs: 250
  property real tapMaxMovePx: 12
  property int doubleTapWindowMs: 300
  property real doubleTapMaxDistPx: 25

  property var touchState: ({})   // pointId -> {startX, startY, lastX, lastY, startTime, dragSelect}
  property var lastTap: null       // {time, x, y} of the most recent completed single-finger tap

  property real panelX: 80
  property real panelY: 80
  property real panelWidth: 420
  property real panelHeight: 240
  readonly property real minPanelWidth: 220
  readonly property real minPanelHeight: 160

  Process {
    id: injector
    running: true
    command: ["socat", "-", "UNIX-CONNECT:/run/trackpad.sock"]
    stdinEnabled: true
  }

  function send(cmd) {
    injector.write(cmd + "\n")
  }

  // Drag/resize with the real hardware trackpad/mouse pins the panel
  // directly to the actual absolute cursor position (polled from Hyprland)
  // rather than accumulating DragHandler's translation deltas, which
  // don't reliably track 1:1 for this panel. Touch keeps using translation
  // directly since that already works correctly.
  Timer {
    id: dragCursorPollTimer
    interval: 20
    repeat: true
    running: dragCursorPoll.mode !== ""
    onTriggered: cursorPosProc.running = true
  }

  QtObject {
    id: dragCursorPoll
    property string mode: ""   // "", "drag", "resize"
    property real grabDx: 0
    property real grabDy: 0
    property bool haveGrabOffset: false
  }

  Process {
    id: cursorPosProc
    command: ["hyprctl", "-j", "cursorpos"]
    stdout: StdioCollector {
      onStreamFinished: {
        if (dragCursorPoll.mode === "") return
        var pos
        try {
          pos = JSON.parse(text)
        } catch (e) {
          return
        }
        if (typeof pos.x !== "number" || typeof pos.y !== "number") return

        if (dragCursorPoll.mode === "drag") {
          if (!dragCursorPoll.haveGrabOffset) {
            dragCursorPoll.grabDx = pos.x - root.panelX
            dragCursorPoll.grabDy = pos.y - root.panelY
            dragCursorPoll.haveGrabOffset = true
          } else {
            root.panelX = Math.max(0, pos.x - dragCursorPoll.grabDx)
            root.panelY = Math.max(0, pos.y - dragCursorPoll.grabDy)
          }
        } else if (dragCursorPoll.mode === "resize") {
          if (!dragCursorPoll.haveGrabOffset) {
            dragCursorPoll.grabDx = pos.x - (root.panelX + root.panelWidth)
            dragCursorPoll.grabDy = pos.y - (root.panelY + root.panelHeight)
            dragCursorPoll.haveGrabOffset = true
          } else {
            root.panelWidth = Math.max(root.minPanelWidth, pos.x - dragCursorPoll.grabDx - root.panelX)
            root.panelHeight = Math.max(root.minPanelHeight, pos.y - dragCursorPoll.grabDy - root.panelY)
          }
        }
      }
    }
  }

  // If the injected cursor happens to be sitting over this panel's own
  // rectangle when a click fires, that click lands on our own surface --
  // Wayland gives the clicked surface an implicit pointer grab, which then
  // never gets released properly since this panel doesn't do anything
  // with a mouse click, leaving the cursor stuck. Check first and skip
  // the click entirely rather than let that happen.
  Process {
    id: clickSafetyProc
    property string pendingClick: ""
    command: ["hyprctl", "-j", "cursorpos"]
    stdout: StdioCollector {
      onStreamFinished: {
        if (clickSafetyProc.pendingClick === "") return
        var pos
        try {
          pos = JSON.parse(text)
        } catch (e) {
          clickSafetyProc.pendingClick = ""
          return
        }
        var overPanel = pos.x >= root.panelX && pos.x <= root.panelX + root.panelWidth &&
                         pos.y >= root.panelY && pos.y <= root.panelY + root.panelHeight
        if (!overPanel) {
          root.send(clickSafetyProc.pendingClick)
        }
        clickSafetyProc.pendingClick = ""
      }
    }
  }

  function sendClickSafely(cmd) {
    clickSafetyProc.pendingClick = cmd
    clickSafetyProc.running = true
  }

  function onPointsPressed(points) {
    var next = Object.assign({}, root.touchState)
    var isFirstFingerOfGesture = points.length === 1 && Object.keys(root.touchState).length === 0
    for (var i = 0; i < points.length; i++) {
      var p = points[i]
      var entry = { startX: p.x, startY: p.y, lastX: p.x, lastY: p.y, startTime: Date.now(), dragSelect: false }

      // Second tap of a double-tap, landing close to the first in time and
      // space: hold the left button down now so any drag that follows (tap
      // and a half) extends a selection, same as a real trackpad's
      // double-tap-drag. If it turns out to just be a plain double-tap
      // (released quickly with no drag), the down+up still lands as a
      // normal double-click.
      if (isFirstFingerOfGesture && root.lastTap) {
        var dt = Date.now() - root.lastTap.time
        var dist = Math.abs(p.x - root.lastTap.x) + Math.abs(p.y - root.lastTap.y)
        if (dt <= root.doubleTapWindowMs && dist <= root.doubleTapMaxDistPx) {
          entry.dragSelect = true
          root.send("DOWN left")
          root.lastTap = null
        }
      }

      next[p.pointId] = entry
    }
    root.touchState = next
  }

  function onPointsUpdated(points) {
    var ids = Object.keys(root.touchState)

    if (ids.length === 1) {
      var p = points[0]
      var st = root.touchState[p.pointId]
      if (!st) return
      var dx = p.x - st.lastX
      var dy = p.y - st.lastY
      if (dx !== 0 || dy !== 0) {
        root.send("MOVE " + Math.round(dx * root.gain) + " " + Math.round(dy * root.gain))
      }
      st.lastX = p.x
      st.lastY = p.y
      return
    }

    if (ids.length === 2 && points.length === 2) {
      // Two-finger drag scrolls instead of moving the cursor -- average
      // both fingers' motion so it doesn't matter which one moves more.
      var totalDx = 0, totalDy = 0, counted = 0
      for (var i = 0; i < points.length; i++) {
        var pt = points[i]
        var s = root.touchState[pt.pointId]
        if (!s) continue
        totalDx += pt.x - s.lastX
        totalDy += pt.y - s.lastY
        counted++
        s.lastX = pt.x
        s.lastY = pt.y
      }
      if (counted > 0) {
        var avgDx = totalDx / counted
        var avgDy = totalDy / counted
        if (avgDx !== 0 || avgDy !== 0) {
          root.send("SCROLL " + Math.round(avgDx * root.scrollGain) + " " + Math.round(avgDy * root.scrollGain))
        }
      }
    }
  }

  function onPointsReleased(points) {
    var ids = Object.keys(root.touchState)
    var fingerCount = ids.length
    var now = Date.now()

    var wasDragSelect = false
    for (var k = 0; k < ids.length; k++) {
      if (root.touchState[ids[k]].dragSelect) wasDragSelect = true
    }

    if (wasDragSelect) {
      root.send("UP left")
    } else if (fingerCount >= 1) {
      var allQuickTaps = true
      for (var i = 0; i < ids.length; i++) {
        var st = root.touchState[ids[i]]
        var moved = Math.abs(st.lastX - st.startX) + Math.abs(st.lastY - st.startY)
        if (now - st.startTime > root.tapMaxDurationMs || moved > root.tapMaxMovePx) {
          allQuickTaps = false
          break
        }
      }
      if (allQuickTaps) {
        if (fingerCount === 1) {
          root.sendClickSafely("CLICK left")
          var tapped = root.touchState[ids[0]]
          root.lastTap = { time: now, x: tapped.lastX, y: tapped.lastY }
        } else if (fingerCount === 2) {
          root.sendClickSafely("CLICK right")
        } else if (fingerCount === 3) {
          root.sendClickSafely("CLICK middle")
        }
      } else {
        // A real move/scroll, not a tap -- don't let a later tap chain
        // into a double-tap-drag against this one.
        root.lastTap = null
      }
    }

    // Clear released points from state.
    var next = Object.assign({}, root.touchState)
    for (var j = 0; j < points.length; j++) delete next[points[j].pointId]
    root.touchState = next
  }

  PanelWindow {
    id: panel

    // Floating: anchored only to top-left, with the actual position
    // controlled via margins so the drag handle can move it anywhere
    // on screen instead of being docked to an output edge.
    anchors { top: true; left: true }
    margins.left: root.panelX
    margins.top: root.panelY
    implicitWidth: root.panelWidth
    implicitHeight: root.panelHeight
    color: "transparent"

    WlrLayershell.namespace: "virtual-trackpad"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    Rectangle {
      anchors.fill: parent
      color: "#1a1b26"
      opacity: 0.92
      radius: 8
      border.width: 2
      border.color: "#565f89"

      Rectangle {
        id: dragHandle
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: 28
        radius: 8
        color: "#24283b"

        Text {
          anchors.centerIn: parent
          text: "⠿⠿ Trackpad"
          color: "#a9b1d6"
          font.pixelSize: 13
        }

        DragHandler {
          id: dragHandler
          target: null
          acceptedDevices: PointerDevice.TouchScreen | PointerDevice.TouchPad | PointerDevice.Stylus
          property real startPanelX: 0
          property real startPanelY: 0
          property bool usingCursorPoll: false
          onActiveChanged: {
            if (active) {
              startPanelX = root.panelX
              startPanelY = root.panelY
              usingCursorPoll = centroid.device && centroid.device.type !== PointerDevice.TouchScreen
              if (usingCursorPoll) {
                dragCursorPoll.grabDx = 0
                dragCursorPoll.grabDy = 0
                dragCursorPoll.haveGrabOffset = false
                dragCursorPoll.mode = "drag"
              }
            } else {
              usingCursorPoll = false
              if (dragCursorPoll.mode === "drag") dragCursorPoll.mode = ""
            }
          }
          onTranslationChanged: {
            if (!active || usingCursorPoll) return
            root.panelX = Math.max(0, startPanelX + translation.x)
            root.panelY = Math.max(0, startPanelY + translation.y)
          }
        }
      }

      Text {
        anchors.top: dragHandle.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.topMargin: 4
        anchors.leftMargin: 8
        anchors.rightMargin: 8
        text: "tap to click, double-tap+drag to select, two-finger scroll/tap for right-click"
        color: "#565f89"
        font.pixelSize: 10
        wrapMode: Text.WordWrap
        horizontalAlignment: Text.AlignHCenter
      }

      MultiPointTouchArea {
        // Real touch only -- a synthetic click (from the very cursor this
        // panel drives) or the hardware trackpad landing here would
        // otherwise get treated as a touch point too, feeding a bogus
        // point into the gesture state machine and leaving it stuck.
        mouseEnabled: false

        anchors.top: dragHandle.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.topMargin: 26
        anchors.bottomMargin: 18
        minimumTouchPoints: 1
        maximumTouchPoints: 3

        onPressed: function(points) { root.onPointsPressed(points) }
        onUpdated: function(points) { root.onPointsUpdated(points) }
        onReleased: function(points) { root.onPointsReleased(points) }
      }

      Text {
        id: resizeGrip
        width: 40
        height: 40
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        text: "⤡"
        color: "#565f89"
        font.pixelSize: 16
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter

        DragHandler {
          id: resizeHandler
          target: null
          acceptedDevices: PointerDevice.TouchScreen | PointerDevice.TouchPad | PointerDevice.Stylus
          property real startWidth: 0
          property real startHeight: 0
          property bool usingCursorPoll: false
          onActiveChanged: {
            if (active) {
              startWidth = root.panelWidth
              startHeight = root.panelHeight
              usingCursorPoll = centroid.device && centroid.device.type !== PointerDevice.TouchScreen
              if (usingCursorPoll) {
                dragCursorPoll.grabDx = 0
                dragCursorPoll.grabDy = 0
                dragCursorPoll.haveGrabOffset = false
                dragCursorPoll.mode = "resize"
              }
            } else {
              usingCursorPoll = false
              if (dragCursorPoll.mode === "resize") dragCursorPoll.mode = ""
            }
          }
          onTranslationChanged: {
            if (!active || usingCursorPoll) return
            root.panelWidth = Math.max(root.minPanelWidth, startWidth + translation.x)
            root.panelHeight = Math.max(root.minPanelHeight, startHeight + translation.y)
          }
        }
      }
    }
  }
}
