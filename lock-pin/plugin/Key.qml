import QtQuick
import qs.Commons
import qs.Ui

Rectangle {
  id: root
  property string label: ""
  property bool highlighted: false
  signal tapped()

  width: 44
  height: 44
  radius: Style.cornerRadius
  color: area.pressed || highlighted ? Color.lock.selection : Color.lock.background
  border.width: 1
  border.color: Color.lock.borderActive

  Text {
    anchors.centerIn: parent
    text: root.label
    color: Color.lock.text
    font.family: Style.font.family
    font.pixelSize: Style.font.body
  }

  MouseArea {
    id: area
    anchors.fill: parent
    onClicked: root.tapped()
  }
}
