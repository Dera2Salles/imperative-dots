import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

Row {
    id: statusMonitors
    spacing: barWindow.s(4)

    property var theme: mocha
    property var barWindow: null

    // --- State Variables ---
    property int cpuPercent: 0
    property int ramPercent: 0
    property var cavaValues: []
    property string netRx: "0K"
    property string netTx: "0K"

    // ==========================================
    // DATA FETCHING LOGIC
    // ==========================================

    // --- CPU & RAM ---
    Process {
        id: sysmonPoller
        command: ["bash", "-c", "~/.config/hypr/scripts/quickshell/watchers/sysmon_fetch.sh"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    let data = JSON.parse(this.text.trim());
                    statusMonitors.cpuPercent = data.cpu;
                    statusMonitors.ramPercent = data.ram;
                } catch(e) {}
            }
        }
    }

    Timer {
        interval: 2000; running: true; repeat: true; triggeredOnStart: true
        onTriggered: { sysmonPoller.running = false; sysmonPoller.running = true; }
    }

    // --- CAVA ---
    Process {
        id: cavaDaemon
        command: ["bash", "-c", "~/.config/hypr/scripts/quickshell/watchers/cava_daemon.sh"]
        running: true
    }

    Process {
        id: cavaReader
        command: ["cat", "/tmp/qs_cava"]
        stdout: StdioCollector {
            onStreamFinished: {
                let txt = this.text.trim();
                if (txt !== "") {
                    let vals = txt.split(";").filter(s => s !== "").map(Number);
                    statusMonitors.cavaValues = vals;
                }
            }
        }
    }

    Timer {
        interval: 40; running: true; repeat: true
        onTriggered: { cavaReader.running = false; cavaReader.running = true; }
    }

    // --- NETWORK SPEED ---
    Process {
        id: speedPoller
        command: ["bash", "-c", "~/.config/hypr/scripts/quickshell/watchers/speed_fetch.sh"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    let data = JSON.parse(this.text.trim());
                    statusMonitors.netRx = data.rx;
                    statusMonitors.netTx = data.tx;
                } catch(e) {}
            }
        }
    }

    Timer {
        interval: 1000; running: true; repeat: true; triggeredOnStart: true
        onTriggered: { speedPoller.running = false; speedPoller.running = true; }
    }

    // ==========================================
    // UI COMPONENTS (PILLS)
    // ==========================================

    // -------- CPU + RAM Monitor Pill --------
    Rectangle {
        id: sysmonPill
        height: barWindow.barHeight
        width: sysmonRow.width + barWindow.s(24)
        radius: barWindow.s(14)
        border.color: Qt.rgba(theme.text.r, theme.text.g, theme.text.b, 0.08)
        border.width: 1
        color: Qt.rgba(theme.base.r, theme.base.g, theme.base.b, 0.75)
        clip: true

        property bool isHovered: sysmonMouse.containsMouse
        Behavior on color { ColorAnimation { duration: 200 } }
        scale: isHovered ? 1.03 : 1.0
        Behavior on scale { NumberAnimation { duration: 250; easing.type: Easing.OutExpo } }

        property bool initAnimTrigger: false
        Timer { running: statusMonitors.visible && !parent.initAnimTrigger; interval: 60; onTriggered: parent.initAnimTrigger = true }
        opacity: initAnimTrigger ? 1 : 0
        transform: Translate { y: sysmonPill.initAnimTrigger ? 0 : barWindow.s(15); Behavior on y { NumberAnimation { duration: 500; easing.type: Easing.OutBack } } }
        Behavior on opacity { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }

        Row {
            id: sysmonRow
            anchors.centerIn: parent
            spacing: barWindow.s(10)

            // CPU
            Column {
                spacing: barWindow.s(2)
                anchors.verticalCenter: parent.verticalCenter
                Text {
                    text: "CPU"; font.family: "JetBrains Mono"; font.pixelSize: barWindow.s(9); font.weight: Font.Bold
                    color: theme.overlay1; anchors.horizontalCenter: parent.horizontalCenter
                }
                Rectangle {
                    width: barWindow.s(44); height: barWindow.s(5); radius: barWindow.s(3)
                    color: Qt.rgba(theme.surface1.r, theme.surface1.g, theme.surface1.b, 0.8)
                    Rectangle {
                        width: parent.width * (statusMonitors.cpuPercent / 100); height: parent.height; radius: parent.radius
                        color: statusMonitors.cpuPercent >= 85 ? theme.red : (statusMonitors.cpuPercent >= 60 ? theme.peach : theme.sky)
                        Behavior on width { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }
                    }
                }
                Text {
                    text: statusMonitors.cpuPercent + "%"; font.family: "JetBrains Mono"; font.pixelSize: barWindow.s(10); font.weight: Font.Black
                    color: statusMonitors.cpuPercent >= 85 ? theme.red : (statusMonitors.cpuPercent >= 60 ? theme.peach : theme.text)
                    anchors.horizontalCenter: parent.horizontalCenter
                }
            }

            Rectangle { width: 1; height: barWindow.s(28); anchors.verticalCenter: parent.verticalCenter; color: Qt.rgba(theme.text.r, theme.text.g, theme.text.b, 0.1) }

            // RAM
            Column {
                spacing: barWindow.s(2)
                anchors.verticalCenter: parent.verticalCenter
                Text {
                    text: "RAM"; font.family: "JetBrains Mono"; font.pixelSize: barWindow.s(9); font.weight: Font.Bold
                    color: theme.overlay1; anchors.horizontalCenter: parent.horizontalCenter
                }
                Rectangle {
                    width: barWindow.s(44); height: barWindow.s(5); radius: barWindow.s(3)
                    color: Qt.rgba(theme.surface1.r, theme.surface1.g, theme.surface1.b, 0.8)
                    Rectangle {
                        width: parent.width * (statusMonitors.ramPercent / 100); height: parent.height; radius: parent.radius
                        color: statusMonitors.ramPercent >= 85 ? theme.red : (statusMonitors.ramPercent >= 60 ? theme.peach : theme.mauve)
                        Behavior on width { NumberAnimation { duration: 600; easing.type: Easing.OutCubic } }
                    }
                }
                Text {
                    text: statusMonitors.ramPercent + "%"; font.family: "JetBrains Mono"; font.pixelSize: barWindow.s(10); font.weight: Font.Black
                    color: statusMonitors.ramPercent >= 85 ? theme.red : (statusMonitors.ramPercent >= 60 ? theme.peach : theme.text)
                    anchors.horizontalCenter: parent.horizontalCenter
                }
            }
        }
        MouseArea { id: sysmonMouse; anchors.fill: parent; hoverEnabled: true }
    }

    // -------- Mini Cava Visualizer Pill --------
    Rectangle {
        id: cavaPill
        height: barWindow.barHeight
        radius: barWindow.s(14)
        border.color: Qt.rgba(theme.text.r, theme.text.g, theme.text.b, 0.08)
        border.width: 1
        color: Qt.rgba(theme.base.r, theme.base.g, theme.base.b, 0.75)
        clip: true

        property int barCount: statusMonitors.cavaValues.length > 0 ? statusMonitors.cavaValues.length : 12
        property int barW: barWindow.s(3)
        property int barGap: barWindow.s(2)
        property int innerH: barWindow.s(28)

        width: barCount * (barW + barGap) - barGap + barWindow.s(24)

        property bool initAnimTrigger: false
        Timer { running: statusMonitors.visible && !parent.initAnimTrigger; interval: 30; onTriggered: parent.initAnimTrigger = true }
        opacity: initAnimTrigger ? 1 : 0
        transform: Translate { y: cavaPill.initAnimTrigger ? 0 : barWindow.s(15); Behavior on y { NumberAnimation { duration: 500; easing.type: Easing.OutBack } } }
        Behavior on opacity { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }

        Row {
            anchors.centerIn: parent
            spacing: cavaPill.barGap
            Repeater {
                model: cavaPill.barCount
                delegate: Item {
                    width: cavaPill.barW; height: cavaPill.innerH
                    property real rawVal: (index < statusMonitors.cavaValues.length) ? statusMonitors.cavaValues[index] : 0
                    property real barHeight: Math.max(barWindow.s(2), (rawVal / 100) * cavaPill.innerH)
                    Behavior on barHeight { NumberAnimation { duration: 80; easing.type: Easing.OutCubic } }

                    Rectangle {
                        width: parent.width; height: parent.barHeight; anchors.bottom: parent.bottom; radius: barWindow.s(2)
                        color: {
                            let t = parent.rawVal / 100;
                            return Qt.rgba(theme.mauve.r * t + theme.teal.r * (1 - t), theme.mauve.g * t + theme.teal.g * (1 - t), theme.mauve.b * t + theme.teal.b * (1 - t), 1.0);
                        }
                    }
                }
            }
        }
    }

    // -------- Network Speed Pill --------
    Rectangle {
        id: speedPill
        height: barWindow.barHeight
        radius: barWindow.s(14)
        border.color: Qt.rgba(theme.text.r, theme.text.g, theme.text.b, 0.08)
        border.width: 1
        color: Qt.rgba(theme.base.r, theme.base.g, theme.base.b, 0.75)
        clip: true
        width: speedLayoutRow.width + barWindow.s(24)

        property bool initAnimTrigger: false
        Timer { running: statusMonitors.visible && !parent.initAnimTrigger; interval: 75; onTriggered: parent.initAnimTrigger = true }
        opacity: initAnimTrigger ? 1 : 0
        transform: Translate { y: speedPill.initAnimTrigger ? 0 : barWindow.s(15); Behavior on y { NumberAnimation { duration: 500; easing.type: Easing.OutBack } } }
        Behavior on opacity { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }

        Row {
            id: speedLayoutRow; anchors.centerIn: parent; spacing: barWindow.s(8)
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "󰖩"; font.family: "Iosevka Nerd Font"; font.pixelSize: barWindow.s(18); color: theme.blue
            }
            Column {
                anchors.verticalCenter: parent.verticalCenter; spacing: 0
                Row {
                    spacing: barWindow.s(3)
                    Text { text: "▼"; font.pixelSize: barWindow.s(8); anchors.verticalCenter: parent.verticalCenter; color: theme.teal; font.family: "Iosevka Nerd Font" }
                    Text { text: statusMonitors.netRx; font.family: "JetBrains Mono"; anchors.verticalCenter: parent.verticalCenter; font.pixelSize: barWindow.s(10); font.weight: Font.ExtraBold; color: theme.text }
                }
                Row {
                    spacing: barWindow.s(3)
                    Text { text: "▲"; font.pixelSize: barWindow.s(8); anchors.verticalCenter: parent.verticalCenter; color: theme.mauve; font.family: "Iosevka Nerd Font" }
                    Text { text: statusMonitors.netTx; font.family: "JetBrains Mono"; anchors.verticalCenter: parent.verticalCenter; font.pixelSize: barWindow.s(10); font.weight: Font.ExtraBold; color: theme.text }
                }
            }
        }
    }
}
