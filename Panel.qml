import QtQuick
import qs.Commons
import qs.Ui

Panel {
  id: root
  moduleName: "josh2c.protonpass"

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰌆"
    onPressed: root.toggle()
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    contentWidth: panel.fittedContentWidth(Style.space(280))
    contentHeight: panel.fittedContentHeight(content.implicitHeight, Style.space(180))

    Column {
      id: content
      width: panel.contentWidth
      spacing: Style.space(10)

      PanelHero {
        width: parent.width
        title: "Proton Pass"
        meta: "Plugin scaffold ready"
        foreground: root.foreground
        fontFamily: root.fontFamily
        iconComponent: Component {
          Text {
            text: "󰌆"
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.display
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
          }
        }
      }
    }
  }
}
