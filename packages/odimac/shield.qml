// On the Mac display, an invisible layer over the receiver's window that
// takes the iMac's own pointer. The receiver passes every pointer position
// it is given on to the Mac as a touch, and the Mac moves its pointer there:
// with the iMac's pointer resting on the receiver, the Mac's pointer kept
// jumping back to that spot. Run by odimac-shield.service as
// `quickshell -p /usr/share/odimac/quickshell` (this file is shell.qml
// there), beside Omarchy's own shell.
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland

ShellRoot {
    id: root

    // The receiver's workspace is named; see hyprland.lua.
    readonly property bool onMacDisplay: (Hyprland.focusedWorkspace?.name ?? "") === "display"

    Variants {
        model: Quickshell.screens

        PanelWindow {
            required property var modelData
            screen: modelData
            visible: root.onMacDisplay
            color: "transparent"
            anchors {
                top: true
                bottom: true
                left: true
                right: true
            }
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "odimac-shield"

            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.AllButtons
                cursorShape: Qt.BlankCursor
                onWheel: wheel => wheel.accepted = true
            }
        }
    }
}
