// The desktop's bar: workspaces, the focused window, the appliance's three
// environments, volume and clock. Run by hyprland.lua as
// `qs -p /usr/share/odimac/quickshell` (this file is shell.qml there). To use your own instead, start it
// from ~/.config/hypr/odimac.lua.
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Services.Pipewire

ShellRoot {
    id: root

    readonly property color bg: "#1e2030"
    readonly property color fg: "#cad3f5"
    readonly property color dim: "#6e738d"
    readonly property color accent: "#8aadf4"
    readonly property color raised: "#363a4f"
    readonly property string font: "DejaVu Sans"

    function mode(name) {
        Quickshell.execDetached(["systemd-cat", "-t", "odimac-mode", "/usr/lib/odimac/mode", name]);
    }

    // Keeps the default sink's volume readable.
    PwObjectTracker {
        objects: [Pipewire.defaultAudioSink]
    }

    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }

    component Pill: Rectangle {
        id: pill
        property alias text: label.text
        property bool active: false
        signal clicked()
        signal scrolled(int delta)

        implicitWidth: label.implicitWidth + 20
        implicitHeight: 22
        radius: 6
        color: active ? root.accent : (area.containsMouse ? root.raised : "transparent")

        Text {
            id: label
            anchors.centerIn: parent
            color: pill.active ? root.bg : root.fg
            font.family: root.font
            font.pixelSize: 12
        }
        MouseArea {
            id: area
            anchors.fill: parent
            hoverEnabled: true
            onClicked: pill.clicked()
            onWheel: wheel => pill.scrolled(wheel.angleDelta.y)
        }
    }

    Variants {
        model: Quickshell.screens

        PanelWindow {
            required property var modelData
            screen: modelData
            anchors {
                top: true
                left: true
                right: true
            }
            implicitHeight: 30
            color: root.bg

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 8
                anchors.rightMargin: 8
                spacing: 4

                Repeater {
                    model: Hyprland.workspaces
                    Pill {
                        required property var modelData
                        visible: modelData.id > 0 // not the special workspaces
                        text: modelData.name
                        active: modelData.focused
                        onClicked: Quickshell.execDetached(["hyprctl", "dispatch", "hl.dsp.focus({ workspace = " + modelData.id + " })"])
                    }
                }

                Text {
                    Layout.fillWidth: true
                    Layout.leftMargin: 12
                    text: Hyprland.activeToplevel?.title ?? ""
                    elide: Text.ElideRight
                    color: root.dim
                    font.family: root.font
                    font.pixelSize: 12
                }

                Pill {
                    text: "Mac display"
                    onClicked: root.mode("display")
                }
                Pill {
                    text: "Gaming"
                    onClicked: root.mode("game")
                }
                Pill {
                    text: "Desktop"
                    active: true
                }

                Pill {
                    readonly property var sink: Pipewire.defaultAudioSink
                    Layout.leftMargin: 12
                    visible: sink?.audio != null
                    text: sink?.audio?.muted ? "muted" : "vol " + Math.round((sink?.audio?.volume ?? 0) * 100) + "%"
                    onClicked: sink.audio.muted = !sink.audio.muted
                    onScrolled: delta => sink.audio.volume = Math.max(0, Math.min(1, sink.audio.volume + (delta > 0 ? 0.05 : -0.05)))
                }

                Text {
                    Layout.leftMargin: 8
                    text: Qt.formatDateTime(clock.date, "ddd d MMM  HH:mm")
                    color: root.fg
                    font.family: root.font
                    font.pixelSize: 12
                }
            }
        }
    }
}
