import QtQuick
import QtQuick.Window
import QtQuick.Effects
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import "../"

Item {
    id: root
    focus: true

    // --- Responsive Scaling Logic ---
    Scaler {
        id: scaler
        currentWidth: Screen.width
    }
    
    function s(val) { 
        return scaler.s(val); 
    }

    property bool isLayoutDropdownOpen: false

    // -------------------------------------------------------------------------
    // KEYBOARD SHORTCUTS
    // -------------------------------------------------------------------------
    Keys.onEscapePressed: {
        if (langInput.activeFocus) {
            langInput.focus = false;
            event.accepted = true;
        } else if (wpDirInput.activeFocus) {
            wpDirInput.focus = false;
            event.accepted = true;
        } else if (root.isLayoutDropdownOpen) {
            root.isLayoutDropdownOpen = false;
            event.accepted = true;
        } else {
            closeSequence.start();
            event.accepted = true;
        }
    }
    
    Keys.onPressed: (event) => {
        if (root.isLayoutDropdownOpen) {
            if (event.key === Qt.Key_Tab || event.key === Qt.Key_Down) {
                layoutListView.incrementCurrentIndex();
                event.accepted = true;
            } else if (event.key === Qt.Key_Backtab || event.key === Qt.Key_Up) {
                layoutListView.decrementCurrentIndex();
                event.accepted = true;
            }
        }
    }

    Keys.onReturnPressed: (event) => root.handleRootEnter(event)
    Keys.onEnterPressed: (event) => root.handleRootEnter(event)

    function handleRootEnter(event) {
        if (root.isLayoutDropdownOpen) {
            if (layoutListView.currentIndex >= 0 && layoutListView.currentIndex < root.kbToggleModelArr.length) {
                root.setKbOptions = root.kbToggleModelArr[layoutListView.currentIndex].val;
            }
            root.isLayoutDropdownOpen = false;
            event.accepted = true;
            return;
        }
        
        if (!langInput.activeFocus && !wpDirInput.activeFocus) {
            root.saveAppSettings();
        }
        event.accepted = true;
    }

    MatugenColors { id: _theme }
    // -------------------------------------------------------------------------
    // COLORS
    // -------------------------------------------------------------------------
    readonly property color base: _theme.base
    readonly property color mantle: _theme.mantle
    readonly property color crust: _theme.crust
    readonly property color text: _theme.text
    readonly property color subtext0: _theme.subtext0
    readonly property color subtext1: _theme.subtext1
    readonly property color surface0: _theme.surface0
    readonly property color surface1: _theme.surface1
    readonly property color surface2: _theme.surface2
    readonly property color overlay0: _theme.overlay0
    readonly property color mauve: _theme.mauve
    readonly property color pink: _theme.pink
    readonly property color blue: _theme.blue
    readonly property color sapphire: _theme.sapphire
    readonly property color green: _theme.green
    readonly property color peach: _theme.peach
    readonly property color yellow: _theme.yellow
    readonly property color red: _theme.red

    // -------------------------------------------------------------------------
    // SSOT GLOBAL SETTINGS & UPDATES
    // -------------------------------------------------------------------------
    property int initialWorkspaceCount: 8 
    
    property real setUiScale: 1.0
    property bool setOpenGuideAtStartup: true
    property bool setTopbarHelpIcon: true
    property int setWorkspaceCount: 8
    property string setWallpaperDir: {
        const dir = Quickshell.env("WALLPAPER_DIR")
        return (dir && dir !== "") 
        ? dir 
        : Quickshell.env("HOME") + "/Pictures/Wallpapers"
    }
    property string setLanguage: ""
    property string setKbOptions: "grp:alt_shift_toggle"

    property var kbToggleModelArr: [
        { label: "Alt + Shift", val: "grp:alt_shift_toggle" },
        { label: "Win + Space", val: "grp:win_space_toggle" },
        { label: "Caps Lock", val: "grp:caps_toggle" },
        { label: "Ctrl + Shift", val: "grp:ctrl_shift_toggle" },
        { label: "Ctrl + Alt", val: "grp:ctrl_alt_toggle" },
        { label: "Right Alt", val: "grp:toggle" },
        { label: "No Toggle", val: "" }
    ]

    function getKbToggleLabel(val) {
        for (let i = 0; i < root.kbToggleModelArr.length; i++) {
            if (root.kbToggleModelArr[i].val === val) return root.kbToggleModelArr[i].label;
        }
        return "Alt + Shift";
    }

    function saveAppSettings() {
        let config = {
            "uiScale": root.setUiScale,
            "openGuideAtStartup": root.setOpenGuideAtStartup,
            "topbarHelpIcon": root.setTopbarHelpIcon,
            "wallpaperDir": root.setWallpaperDir,
            "language": root.setLanguage,
            "kbOptions": root.setKbOptions,
            "workspaceCount": root.setWorkspaceCount
        };
        let jsonString = JSON.stringify(config, null, 2);
        
        let cmd = "mkdir -p ~/.config/hypr/ && echo '" + jsonString + "' > ~/.config/hypr/settings.json && notify-send 'Quickshell' 'Settings Applied Successfully!'";
                  
        Quickshell.execDetached(["bash", "-c", cmd]);
        
        if (root.setWorkspaceCount !== root.initialWorkspaceCount) {
        Quickshell.execDetached(["qs", "-p", Quickshell.env("HOME") + "/.config/hypr/scripts/quickshell/TopBar.qml", "ipc", "call", "topbar", "queueReload"]);

            root.initialWorkspaceCount = root.setWorkspaceCount; 
        }
    }
    
    Process {
        id: hyprLangReader
        command: ["bash", "-c", "grep -m1 '^ *kb_layout *=' ~/.config/hypr/hyprland.conf | cut -d'=' -f2 | tr -d ' '"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                let out = this.text ? this.text.trim() : "";
                if (out.length > 0 && root.setLanguage === "") {
                    root.setLanguage = out;
                }
            }
        }
    }

    Process {
        id: settingsReader
        command: ["bash", "-c", "cat ~/.config/hypr/settings.json 2>/dev/null || echo '{}'"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    if (this.text && this.text.trim().length > 0 && this.text.trim() !== "{}") {
                        let parsed = JSON.parse(this.text);
                        if (parsed.uiScale !== undefined) root.setUiScale = parsed.uiScale;
                        if (parsed.openGuideAtStartup !== undefined) root.setOpenGuideAtStartup = parsed.openGuideAtStartup;
                        if (parsed.topbarHelpIcon !== undefined) root.setTopbarHelpIcon = parsed.topbarHelpIcon;
                        if (parsed.wallpaperDir !== undefined) root.setWallpaperDir = parsed.wallpaperDir;
                        if (parsed.language !== undefined && parsed.language !== "") root.setLanguage = parsed.language;
                        if (parsed.kbOptions !== undefined) root.setKbOptions = parsed.kbOptions;
                        if (parsed.workspaceCount !== undefined) {
                            root.setWorkspaceCount = parsed.workspaceCount;
                            root.initialWorkspaceCount = parsed.workspaceCount; 
                        }
                    } else {
                        root.saveAppSettings();
                    }
                } catch (e) {
                    console.log("Error parsing global settings:", e);
                }
            }
        }
    }
    
    ListModel {
        id: langModel
        ListElement { code: "us"; name: "English (US)" }
        ListElement { code: "gb"; name: "English (UK)" }
        ListElement { code: "au"; name: "English (Australia)" }
        ListElement { code: "ca"; name: "English/French (Canada)" }
        ListElement { code: "ie"; name: "English (Ireland)" }
        ListElement { code: "nz"; name: "English (New Zealand)" }
        ListElement { code: "za"; name: "English (South Africa)" }
        ListElement { code: "fr"; name: "French" }
        ListElement { code: "de"; name: "German" }
        ListElement { code: "es"; name: "Spanish" }
        ListElement { code: "pt"; name: "Portuguese" }
        ListElement { code: "it"; name: "Italian" }
        ListElement { code: "se"; name: "Swedish" }
        ListElement { code: "no"; name: "Norwegian" }
        ListElement { code: "dk"; name: "Danish" }
        ListElement { code: "fi"; name: "Finnish" }
        ListElement { code: "pl"; name: "Polish" }
        ListElement { code: "ru"; name: "Russian" }
        ListElement { code: "ua"; name: "Ukrainian" }
        ListElement { code: "cn"; name: "Chinese" }
        ListElement { code: "jp"; name: "Japanese" }
        ListElement { code: "kr"; name: "Korean" }
    }

    ListModel { id: pathSuggestModel }
    ListModel { id: langSearchModel }

    function updateLangSearch(query) {
        langSearchModel.clear();
        let q = query.trim().toLowerCase();
        for (let i = 0; i < langModel.count; i++) {
            let item = langModel.get(i);
            if (q === "" || item.code.toLowerCase().includes(q) || item.name.toLowerCase().includes(q)) {
                langSearchModel.append({ code: item.code, name: item.name });
            }
        }
        if (typeof langListView !== "undefined") {
            langListView.currentIndex = 0; // Automatically highlight first match
        }
    }

    Process {
        id: pathSuggestProc
        property string query: ""
        command: ["bash", "-c", "eval ls -dp " + query + "* 2>/dev/null | grep '/$' | head -n 5 || true"]
        stdout: StdioCollector {
            onStreamFinished: {
                pathSuggestModel.clear();
                if (this.text) {
                    let lines = this.text.trim().split('\n');
                    for (let i = 0; i < lines.length; i++) {
                        let line = lines[i];
                        if (line.length > 0) {
                            if (line.endsWith('/')) {
                                line = line.slice(0, -1);
                            }
                            pathSuggestModel.append({ path: line });
                        }
                    }
                }
                if (typeof wpSuggestListView !== "undefined") {
                    wpSuggestListView.currentIndex = 0; // Automatically highlight first match
                }
            }
        }
    }

    // -------------------------------------------------------------------------
    // ANIMATIONS
    // -------------------------------------------------------------------------
    property real introContent: 0.0

    Component.onCompleted: { 
        startupSequence.start(); 
    }

    SequentialAnimation {
        id: startupSequence
        PauseAnimation { duration: 50 }
        NumberAnimation { 
            target: root
            property: "introContent"
            from: 0.0
            to: 1.0
            duration: 600
            easing.type: Easing.OutQuart
        } 
    }

    SequentialAnimation {
        id: closeSequence
        NumberAnimation { 
            target: root
            property: "introContent"
            to: 0.0
            duration: 200
            easing.type: Easing.InQuart
        }
        ScriptAction { 
            script: {
                if (root.requiresReload) {
                    let script = Quickshell.env("HOME") + "/.config/hypr/scripts/qs_manager.sh close; " +
                                 "while [ -n \"$(cat /tmp/qs_current_widget 2>/dev/null)\" ]; do sleep 0.1; done; " +
                                 "sleep 0.2; " + 
                                 "qs -p ~/.config/hypr/scripts/quickshell/TopBar.qml ipc call topbar forceReload";
                    Quickshell.execDetached(["bash", "-c", script]);
                } else {
                    Quickshell.execDetached(["bash", Quickshell.env("HOME") + "/.config/hypr/scripts/qs_manager.sh", "close"]);
                }
            } 
        }
    }

    // -------------------------------------------------------------------------
    // SIDEBAR BACKGROUND
    // -------------------------------------------------------------------------
    Rectangle {
        id: sidebarPanel
        anchors.fill: parent
        color: Qt.rgba(root.base.r, root.base.g, root.base.b, 0.95)
        radius: root.s(16)
        border.width: 1
        border.color: Qt.rgba(root.surface0.r, root.surface0.g, root.surface0.b, 0.8)
        clip: true

        // --- Straighten Left Corners ---
        Rectangle {
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: root.s(16)
            color: sidebarPanel.color

            Rectangle { anchors.top: parent.top; width: parent.width; height: 1; color: sidebarPanel.border.color }
            Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: sidebarPanel.border.color }
            Rectangle { anchors.left: parent.left; width: 1; height: parent.height; color: sidebarPanel.border.color }
        }

        // -------------------------------------------------------------------------
        // FLICKABLE CONTENT AREA
        // -------------------------------------------------------------------------
        Item {
            anchors.fill: parent
            opacity: introContent
            scale: 0.96 + (0.04 * introContent)
            
            // Using transform Translate so the anchors.fill doesn't ignore the y offset
            transform: Translate { y: root.s(40) * (1.0 - introContent) }

            Flickable {
                anchors.fill: parent
                contentWidth: width
                contentHeight: settingsMainCol.implicitHeight + root.s(100)
                boundsBehavior: Flickable.StopAtBounds
                clip: true

                ColumnLayout {
                    id: settingsMainCol
                    width: parent.width - root.s(48)
                    x: root.s(24)
                    y: root.s(24)
                    spacing: root.s(16) // Optimal vertical gap between outer boxes

                    // --- HEADER ---
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.bottomMargin: root.s(8)
                        Text { 
                            text: "Settings"
                            font.family: "Inter"
                            font.weight: Font.Black
                            font.pixelSize: root.s(26)
                            color: root.text
                            Layout.alignment: Qt.AlignVCenter 
                        }
                    }

                    // --- SETTINGS LIST ---
                    
                    // Box 1: Startup & Icons
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: col1.implicitHeight + root.s(40)
                        radius: root.s(16) 
                        color: Qt.alpha(root.surface0, 0.5)
                        border.color: root.surface1
                        border.width: 1
                        
                        ColumnLayout {
                            id: col1
                            anchors.top: parent.top
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.margins: root.s(20) // Restored comfortable inner padding
                            spacing: root.s(20)
                            
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: root.s(16)
                                Item {
                                    Layout.preferredWidth: root.s(24)
                                    Layout.alignment: Qt.AlignTop
                                    Layout.topMargin: root.s(2)
                                    Text { anchors.top: parent.top; anchors.horizontalCenter: parent.horizontalCenter; text: ""; font.family: "Iosevka Nerd Font"; font.pixelSize: root.s(20); color: root.peach }
                                }
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    Layout.alignment: Qt.AlignTop
                                    spacing: root.s(4)
                                    RowLayout {
                                        Layout.fillWidth: true
                                        Text { text: "Guide on startup"; font.family: "Inter"; font.weight: Font.Bold; font.pixelSize: root.s(15); color: root.text; Layout.fillWidth: true }
                                        Rectangle {
                                            Layout.alignment: Qt.AlignTop | Qt.AlignRight
                                            Layout.preferredWidth: root.s(40)
                                            Layout.preferredHeight: root.s(24)
                                            radius: root.s(12)
                                            scale: toggle1Ma.containsMouse ? 1.05 : 1.0
                                            Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutBack } }
                                            
                                            gradient: Gradient {
                                                GradientStop { position: 0.0; color: root.setOpenGuideAtStartup ? Qt.lighter(root.peach, 1.1) : root.surface2 }
                                                GradientStop { position: 1.0; color: root.setOpenGuideAtStartup ? root.peach : root.surface1 }
                                            }

                                            Rectangle {
                                                width: root.s(18); height: root.s(18); radius: root.s(9); color: root.base
                                                y: root.s(3); x: root.setOpenGuideAtStartup ? root.s(19) : root.s(3)
                                                Behavior on x { NumberAnimation { duration: 250; easing.type: Easing.OutBack } }
                                            }
                                            MouseArea { id: toggle1Ma; anchors.fill: parent; hoverEnabled: true; onClicked: root.setOpenGuideAtStartup = !root.setOpenGuideAtStartup; cursorShape: Qt.PointingHandCursor }
                                        }
                                    }
                                    Text { text: "Launch on login"; font.family: "Inter"; font.pixelSize: root.s(12); color: Qt.alpha(root.subtext0, 0.7); Layout.fillWidth: true }
                                }
                            }
                            
                            Rectangle { Layout.fillWidth: true; height: 1; color: Qt.alpha(root.surface1, 0.5) }

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: root.s(16)
                                Item {
                                    Layout.preferredWidth: root.s(24)
                                    Layout.alignment: Qt.AlignTop
                                    Layout.topMargin: root.s(2)
                                    Text { anchors.top: parent.top; anchors.horizontalCenter: parent.horizontalCenter; text: "󰋖"; font.family: "Iosevka Nerd Font"; font.pixelSize: root.s(20); color: root.blue }
                                }
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    Layout.alignment: Qt.AlignTop
                                    spacing: root.s(4)
                                    RowLayout {
                                        Layout.fillWidth: true
                                        Text { text: "Help icon"; font.family: "Inter"; font.weight: Font.Bold; font.pixelSize: root.s(15); color: root.text; Layout.fillWidth: true }
                                        Rectangle {
                                            Layout.alignment: Qt.AlignTop | Qt.AlignRight
                                            Layout.preferredWidth: root.s(40)
                                            Layout.preferredHeight: root.s(24)
                                            radius: root.s(12)
                                            scale: toggle2Ma.containsMouse ? 1.05 : 1.0
                                            Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutBack } }

                                            gradient: Gradient {
                                                GradientStop { position: 0.0; color: root.setTopbarHelpIcon ? Qt.lighter(root.blue, 1.2) : root.surface2 }
                                                GradientStop { position: 1.0; color: root.setTopbarHelpIcon ? root.blue : root.surface1 }
                                            }

                                            Rectangle {
                                                width: root.s(18); height: root.s(18); radius: root.s(9); color: root.base
                                                y: root.s(3); x: root.setTopbarHelpIcon ? root.s(19) : root.s(3)
                                                Behavior on x { NumberAnimation { duration: 250; easing.type: Easing.OutBack } }
                                            }
                                            MouseArea { id: toggle2Ma; anchors.fill: parent; hoverEnabled: true; onClicked: root.setTopbarHelpIcon = !root.setTopbarHelpIcon; cursorShape: Qt.PointingHandCursor }
                                        }
                                    }
                                    Text { text: "Show button in topbar"; font.family: "Inter"; font.pixelSize: root.s(12); color: Qt.alpha(root.subtext0, 0.7); Layout.fillWidth: true }
                                }
                            }
                        }
                    }

                    // Box 2: UI Scale
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: col2.implicitHeight + root.s(40)
                        radius: root.s(16)
                        color: Qt.alpha(root.surface0, 0.5)
                        border.color: root.surface1
                        border.width: 1
                        
                        ColumnLayout {
                            id: col2
                            anchors.top: parent.top
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.margins: root.s(20)
                            
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: root.s(16)
                                Item {
                                    Layout.preferredWidth: root.s(24)
                                    Layout.alignment: Qt.AlignVCenter
                                    Text { anchors.centerIn: parent; text: "󰁦"; font.family: "Iosevka Nerd Font"; font.pixelSize: root.s(20); color: root.sapphire }
                                }
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    Layout.alignment: Qt.AlignVCenter
                                    spacing: root.s(4)
                                    Text { text: "UI Scale"; font.family: "Inter"; font.weight: Font.Bold; font.pixelSize: root.s(15); color: root.text; Layout.fillWidth: true }
                                    Text { text: "Base size scalar"; font.family: "Inter"; font.pixelSize: root.s(12); color: Qt.alpha(root.subtext0, 0.7); Layout.fillWidth: true }
                                }
                                RowLayout {
                                    Layout.alignment: Qt.AlignVCenter | Qt.AlignRight
                                    spacing: root.s(12)
                                    Rectangle {
                                        width: root.s(30); height: root.s(30); radius: root.s(8)
                                        color: sMinusMa.pressed ? Qt.alpha(root.sapphire, 0.4) : (sMinusMa.containsMouse ? root.surface2 : root.surface1)
                                        scale: sMinusMa.pressed ? 0.90 : (sMinusMa.containsMouse ? 1.08 : 1.0)
                                        Behavior on scale { NumberAnimation { duration: 250; easing.type: Easing.OutQuart } }
                                        Behavior on color { ColorAnimation { duration: 250; easing.type: Easing.OutQuart } }
                                        Text { anchors.centerIn: parent; text: "-"; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: root.s(16); color: sMinusMa.pressed ? root.sapphire : root.text }
                                        MouseArea { id: sMinusMa; anchors.fill: parent; hoverEnabled: true; onClicked: root.setUiScale = Math.max(0.5, (root.setUiScale - 0.1).toFixed(1)) }
                                    }
                                    Text { 
                                        text: root.setUiScale.toFixed(1) + "x"
                                        font.family: "JetBrains Mono"
                                        font.weight: Font.Black
                                        font.pixelSize: root.s(14)
                                        color: root.sapphire
                                        Layout.minimumWidth: root.s(40)
                                        horizontalAlignment: Text.AlignHCenter 
                                    }
                                    Rectangle {
                                        width: root.s(30); height: root.s(30); radius: root.s(8)
                                        color: sPlusMa.pressed ? Qt.alpha(root.sapphire, 0.4) : (sPlusMa.containsMouse ? root.surface2 : root.surface1)
                                        scale: sPlusMa.pressed ? 0.90 : (sPlusMa.containsMouse ? 1.08 : 1.0)
                                        Behavior on scale { NumberAnimation { duration: 250; easing.type: Easing.OutQuart } }
                                        Behavior on color { ColorAnimation { duration: 250; easing.type: Easing.OutQuart } }
                                        Text { anchors.centerIn: parent; text: "+"; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: root.s(16); color: sPlusMa.pressed ? root.sapphire : root.text }
                                        MouseArea { id: sPlusMa; anchors.fill: parent; hoverEnabled: true; onClicked: root.setUiScale = Math.min(2.0, (root.setUiScale + 0.1).toFixed(1)) }
                                    }
                                }
                            }
                        }
                    }

                    // Box 3: Keyboard Language & Switcher
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: col3.implicitHeight + root.s(40)
                        radius: root.s(16)
                        color: Qt.alpha(root.surface0, 0.5)
                        border.color: root.surface1
                        border.width: 1
                        
                        ColumnLayout {
                            id: col3
                            anchors.top: parent.top
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.margins: root.s(20)
                            spacing: root.s(20)
                            
                            // Part 1: Language
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: root.s(16)
                                Item {
                                    Layout.preferredWidth: root.s(24)
                                    Layout.alignment: Qt.AlignTop
                                    Layout.topMargin: root.s(2)
                                    Text { anchors.top: parent.top; anchors.horizontalCenter: parent.horizontalCenter; text: "󰌌"; font.family: "Iosevka Nerd Font"; font.pixelSize: root.s(20); color: root.green }
                                }
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    Layout.alignment: Qt.AlignTop
                                    spacing: root.s(4)
                                    Text { text: "Keyboard layouts"; font.family: "Inter"; font.weight: Font.Bold; font.pixelSize: root.s(15); color: root.text; Layout.fillWidth: true }
                                    Text { text: "Matches hyprland.conf. Click ✖ to remove."; font.family: "Inter"; font.pixelSize: root.s(12); color: Qt.alpha(root.subtext0, 0.7); Layout.fillWidth: true }
                                    
                                    Flow {
                                        Layout.fillWidth: true
                                        spacing: root.s(8)
                                        Layout.topMargin: root.s(10)
                                        Repeater {
                                            model: root.setLanguage ? root.setLanguage.split(",").filter(x => x.trim() !== "") : []
                                            Rectangle {
                                                width: langChipLayout.implicitWidth + root.s(24)
                                                height: root.s(28)
                                                radius: root.s(14)
                                                color: root.surface1
                                                border.color: chipMa.containsMouse ? root.red : "transparent"
                                                border.width: chipMa.containsMouse ? 1 : 0
                                                scale: chipMa.containsMouse ? 1.05 : 1.0

                                                Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutBack } }
                                                Behavior on border.color { ColorAnimation { duration: 150 } }

                                                RowLayout {
                                                    id: langChipLayout
                                                    anchors.centerIn: parent
                                                    spacing: root.s(8)
                                                    Text { 
                                                        text: modelData
                                                        font.family: "JetBrains Mono"
                                                        font.weight: Font.Bold
                                                        font.pixelSize: root.s(12)
                                                        color: chipMa.containsMouse ? root.red : root.text 
                                                        Behavior on color { ColorAnimation { duration: 150 } }
                                                    }
                                                    Text { 
                                                        text: "✖"
                                                        font.family: "JetBrains Mono"
                                                        font.pixelSize: root.s(13)
                                                        color: chipMa.containsMouse ? root.red : root.subtext0
                                                        Behavior on color { ColorAnimation { duration: 150 } } 
                                                    }
                                                }
                                                MouseArea {
                                                    id: chipMa
                                                    anchors.fill: parent
                                                    hoverEnabled: true
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: {
                                                        let arr = root.setLanguage.split(",").filter(x => x.trim() !== "");
                                                        arr.splice(index, 1);
                                                        root.setLanguage = arr.join(",");
                                                    }
                                                }
                                            }
                                        }
                                    }

                                    // Search Bar Input
                                    Rectangle {
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: root.s(36)
                                        Layout.topMargin: root.s(10)
                                        radius: root.s(8)
                                        color: root.surface0
                                        border.color: langInput.activeFocus ? root.green : root.surface2
                                        border.width: 1
                                        Behavior on border.color { ColorAnimation { duration: 200 } }

                                        TextInput {
                                            id: langInput
                                            anchors.fill: parent
                                            anchors.margins: root.s(10)
                                            verticalAlignment: TextInput.AlignVCenter
                                            font.family: "JetBrains Mono"
                                            font.pixelSize: root.s(12)
                                            color: root.text
                                            clip: true
                                            selectByMouse: true
                                            
                                            // Intercept Keyboard Navigation & Submission
                                            Keys.onPressed: (event) => {
                                                if (event.key === Qt.Key_Tab || event.key === Qt.Key_Down) {
                                                    if (langSearchModel.count > 0) {
                                                        langListView.incrementCurrentIndex();
                                                        event.accepted = true;
                                                    }
                                                } else if (event.key === Qt.Key_Backtab || event.key === Qt.Key_Up) {
                                                    if (langSearchModel.count > 0) {
                                                        langListView.decrementCurrentIndex();
                                                        event.accepted = true;
                                                    }
                                                }
                                            }

                                            Keys.onReturnPressed: (event) => langInputAccept(event)
                                            Keys.onEnterPressed: (event) => langInputAccept(event)

                                            function langInputAccept(event) {
                                                if (langSearchModel.count > 0 && langListView.currentIndex >= 0) {
                                                    let item = langSearchModel.get(langListView.currentIndex);
                                                    let arr = root.setLanguage ? root.setLanguage.split(",").filter(x => x.trim() !== "") : [];
                                                    if (!arr.includes(item.code)) {
                                                        arr.push(item.code);
                                                        root.setLanguage = arr.join(",");
                                                    }
                                                }
                                                text = "";
                                                focus = false;
                                                event.accepted = true;
                                            }

                                            onActiveFocusChanged: {
                                                if (activeFocus) {
                                                    root.updateLangSearch(text);
                                                }
                                            }
                                            onTextChanged: { root.updateLangSearch(text); }
                                            
                                            Text { text: "Search to add..."; color: Qt.alpha(root.subtext0, 0.7); visible: !parent.text && !parent.activeFocus; font: parent.font; anchors.verticalCenter: parent.verticalCenter }
                                        }
                                    }

                                    // Expanding List Container
                                    Rectangle {
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: langInput.activeFocus && langSearchModel.count > 0 ? Math.min(root.s(160), langSearchModel.count * root.s(32)) : 0
                                        radius: root.s(8) 
                                        color: root.surface0
                                        border.width: 0
                                        clip: true
                                        
                                        Behavior on Layout.preferredHeight { NumberAnimation { duration: 250; easing.type: Easing.OutExpo } }
                                        
                                        ListView {
                                            id: langListView
                                            anchors.fill: parent
                                            model: langSearchModel
                                            interactive: true
                                            opacity: parent.Layout.preferredHeight > root.s(10) ? 1.0 : 0.0
                                            Behavior on opacity { NumberAnimation { duration: 200 } }

                                            ScrollBar.vertical: ScrollBar { active: true; policy: ScrollBar.AsNeeded }
                                            delegate: Rectangle {
                                                width: parent.width
                                                height: root.s(32)
                                                // Highlight currentIndex properly
                                                color: sMa.containsMouse ? root.surface2 : (ListView.isCurrentItem ? root.surface1 : "transparent")
                                                RowLayout {
                                                    anchors.fill: parent
                                                    anchors.leftMargin: root.s(12)
                                                    anchors.rightMargin: root.s(12)
                                                    spacing: root.s(10)
                                                    Text { text: model.code; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: root.s(12); color: root.text }
                                                    Text { text: model.name; font.family: "Inter"; font.pixelSize: root.s(12); color: Qt.alpha(root.subtext0, 0.7); elide: Text.ElideRight; Layout.fillWidth: true }
                                                }
                                                MouseArea {
                                                    id: sMa
                                                    anchors.fill: parent
                                                    hoverEnabled: true
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: {
                                                        let arr = root.setLanguage ? root.setLanguage.split(",").filter(x => x.trim() !== "") : [];
                                                        if (!arr.includes(model.code)) {
                                                            arr.push(model.code);
                                                            root.setLanguage = arr.join(",");
                                                        }
                                                        langInput.text = "";
                                                        langInput.focus = false;
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                            
                            Rectangle { Layout.fillWidth: true; height: 1; color: Qt.alpha(root.surface1, 0.5) }

                            // Part 2: Layout Switcher
                            RowLayout {
                                id: layoutSwitcherBox
                                Layout.fillWidth: true
                                spacing: root.s(16)

                                Item {
                                    Layout.preferredWidth: root.s(24)
                                    Layout.alignment: Qt.AlignTop
                                    Layout.topMargin: root.s(2)
                                    Text { anchors.top: parent.top; anchors.horizontalCenter: parent.horizontalCenter; text: "󰯍"; font.family: "Iosevka Nerd Font"; font.pixelSize: root.s(20); color: Qt.alpha(root.green, 0.7) }
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    Layout.alignment: Qt.AlignTop
                                    spacing: root.s(4)
                                    Text { text: "Layout shortcut"; font.family: "Inter"; font.weight: Font.Bold; font.pixelSize: root.s(15); color: root.text; Layout.fillWidth: true }
                                    Text { text: "Toggle combination"; font.family: "Inter"; font.pixelSize: root.s(12); color: Qt.alpha(root.subtext0, 0.7); Layout.fillWidth: true }

                                    // Switcher Selection Header
                                    Rectangle {
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: root.s(36)
                                        Layout.topMargin: root.s(10)
                                        radius: root.s(8)
                                        color: root.surface0
                                        border.color: root.isLayoutDropdownOpen ? root.green : root.surface2
                                        border.width: 1
                                        Behavior on border.color { ColorAnimation { duration: 200 } }

                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.margins: root.s(10)
                                            Text { 
                                                text: root.getKbToggleLabel(root.setKbOptions)
                                                font.family: "JetBrains Mono"
                                                font.pixelSize: root.s(12)
                                                color: root.text
                                                Layout.fillWidth: true 
                                            }
                                            Text { 
                                                text: root.isLayoutDropdownOpen ? "▴" : "▾"
                                                font.pixelSize: root.s(14)
                                                color: root.subtext0 
                                            }
                                        }
                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                root.isLayoutDropdownOpen = !root.isLayoutDropdownOpen;
                                                if (root.isLayoutDropdownOpen) {
                                                    let idx = root.kbToggleModelArr.findIndex(x => x.val === root.setKbOptions);
                                                    layoutListView.currentIndex = Math.max(0, idx);
                                                }
                                                root.forceActiveFocus(); // Grab focus to let root manage Tab/Enter events
                                            }
                                        }
                                    }

                                    // Expanding Switcher Dropdown
                                    Rectangle {
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: root.isLayoutDropdownOpen ? root.kbToggleModelArr.length * root.s(32) : 0
                                        radius: root.s(8)
                                        color: root.surface0
                                        border.width: 0
                                        clip: true

                                        Behavior on Layout.preferredHeight { NumberAnimation { duration: 250; easing.type: Easing.OutExpo } }
                                        
                                        ListView {
                                            id: layoutListView
                                            anchors.fill: parent
                                            model: root.kbToggleModelArr
                                            interactive: false
                                            opacity: parent.Layout.preferredHeight > root.s(10) ? 1.0 : 0.0
                                            Behavior on opacity { NumberAnimation { duration: 200 } }

                                            delegate: Rectangle {
                                                width: parent.width
                                                height: root.s(32)
                                                // Highlight index using keyboard
                                                color: toggleMa.containsMouse ? root.surface2 : (ListView.isCurrentItem ? root.surface1 : "transparent")
                                                RowLayout {
                                                    anchors.fill: parent
                                                    anchors.leftMargin: root.s(12)
                                                    anchors.rightMargin: root.s(12)
                                                    Text { 
                                                        text: modelData.label
                                                        font.family: "JetBrains Mono"
                                                        font.pixelSize: root.s(12)
                                                        color: root.setKbOptions === modelData.val ? root.green : root.text
                                                        Layout.fillWidth: true 
                                                    }
                                                }
                                                MouseArea {
                                                    id: toggleMa
                                                    anchors.fill: parent
                                                    hoverEnabled: true
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: {
                                                        root.setKbOptions = modelData.val;
                                                        root.isLayoutDropdownOpen = false;
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }                       
                        }
                    }

                    // Box 4: Wallpaper Directory
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: col4.implicitHeight + root.s(40)
                        radius: root.s(16)
                        color: Qt.alpha(root.surface0, 0.5)
                        border.color: root.surface1
                        border.width: 1
                        
                        ColumnLayout {
                            id: col4
                            anchors.top: parent.top
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.margins: root.s(20)
                            
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: root.s(16)
                                Item {
                                    Layout.preferredWidth: root.s(24)
                                    Layout.alignment: Qt.AlignTop
                                    Layout.topMargin: root.s(2)
                                    Text { anchors.top: parent.top; anchors.horizontalCenter: parent.horizontalCenter; text: ""; font.family: "Iosevka Nerd Font"; font.pixelSize: root.s(20); color: root.mauve }
                                }
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    Layout.alignment: Qt.AlignTop
                                    spacing: root.s(4)
                                    Text { text: "Wallpaper directory"; font.family: "Inter"; font.weight: Font.Bold; font.pixelSize: root.s(15); color: root.text; Layout.fillWidth: true }
                                    Text { text: "Absolute source path"; font.family: "Inter"; font.pixelSize: root.s(12); color: Qt.alpha(root.subtext0, 0.7); Layout.fillWidth: true }
                                    
                                    // Text Input
                                    Rectangle {
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: root.s(36)
                                        Layout.topMargin: root.s(10)
                                        radius: root.s(8)
                                        color: root.surface0
                                        border.color: wpDirInput.activeFocus ? root.mauve : root.surface2
                                        border.width: 1
                                        Behavior on border.color { ColorAnimation { duration: 200 } }

                                        TextInput {
                                            id: wpDirInput
                                            anchors.fill: parent
                                            anchors.margins: root.s(10)
                                            verticalAlignment: TextInput.AlignVCenter
                                            text: root.setWallpaperDir
                                            font.family: "JetBrains Mono"
                                            font.pixelSize: root.s(12)
                                            color: root.text
                                            clip: true
                                            selectByMouse: true

                                            // Intercept Keys for dropdown
                                            Keys.onPressed: (event) => {
                                                if (event.key === Qt.Key_Tab || event.key === Qt.Key_Down) {
                                                    if (pathSuggestModel.count > 0) {
                                                        wpSuggestListView.incrementCurrentIndex();
                                                        event.accepted = true;
                                                    }
                                                } else if (event.key === Qt.Key_Backtab || event.key === Qt.Key_Up) {
                                                    if (pathSuggestModel.count > 0) {
                                                        wpSuggestListView.decrementCurrentIndex();
                                                        event.accepted = true;
                                                    }
                                                }
                                            }

                                            Keys.onReturnPressed: (event) => wpDirInputAccept(event)
                                            Keys.onEnterPressed: (event) => wpDirInputAccept(event)

                                            function wpDirInputAccept(event) {
                                                if (pathSuggestModel.count > 0 && wpSuggestListView.currentIndex >= 0) {
                                                    let item = pathSuggestModel.get(wpSuggestListView.currentIndex);
                                                    if (item) {
                                                        text = item.path;
                                                        root.setWallpaperDir = text;
                                                    }
                                                }
                                                pathSuggestModel.clear();
                                                focus = false;
                                                event.accepted = true;
                                            }

                                            onActiveFocusChanged: {
                                                if (activeFocus) {
                                                    pathSuggestProc.query = text; 
                                                    pathSuggestProc.running = false; 
                                                    pathSuggestProc.running = true; 
                                                }
                                            }
                                            onTextChanged: { 
                                                root.setWallpaperDir = text; 
                                                if (activeFocus) { 
                                                    pathSuggestProc.query = text; 
                                                    pathSuggestProc.running = false; 
                                                    pathSuggestProc.running = true; 
                                                } 
                                            }
                                        }
                                    }

                                    // Expanding Suggestions List
                                    Rectangle {
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: wpDirInput.activeFocus && pathSuggestModel.count > 0 ? pathSuggestModel.count * root.s(30) : 0
                                        radius: root.s(8)
                                        color: root.surface0
                                        border.width: 0
                                        clip: true

                                        Behavior on Layout.preferredHeight { NumberAnimation { duration: 250; easing.type: Easing.OutExpo } }
                                        
                                        ListView {
                                            id: wpSuggestListView
                                            anchors.fill: parent
                                            model: pathSuggestModel
                                            interactive: false
                                            opacity: parent.Layout.preferredHeight > root.s(10) ? 1.0 : 0.0
                                            Behavior on opacity { NumberAnimation { duration: 200 } }

                                            delegate: Rectangle {
                                                width: parent.width
                                                height: root.s(30)
                                                // Highlight index visuals
                                                color: suggestMa.containsMouse ? root.surface2 : (ListView.isCurrentItem ? root.surface1 : "transparent")
                                                Text { 
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    x: root.s(12)
                                                    text: model.path
                                                    font.family: "JetBrains Mono"
                                                    font.pixelSize: root.s(11)
                                                    color: root.text
                                                    elide: Text.ElideMiddle
                                                    width: parent.width - root.s(24) 
                                                }
                                                MouseArea {
                                                    id: suggestMa
                                                    anchors.fill: parent
                                                    hoverEnabled: true
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: { 
                                                        wpDirInput.text = model.path; 
                                                        pathSuggestModel.clear(); 
                                                        wpDirInput.focus = false; 
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Box 5: Workspace Count
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: col5.implicitHeight + root.s(40)
                        radius: root.s(16)
                        color: Qt.alpha(root.surface0, 0.5)
                        border.color: root.surface1
                        border.width: 1
                        
                        ColumnLayout {
                            id: col5
                            anchors.top: parent.top
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.margins: root.s(20)
                            
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: root.s(16)
                                Item {
                                    Layout.preferredWidth: root.s(24)
                                    Layout.alignment: Qt.AlignVCenter
                                    Text { anchors.centerIn: parent; text: "󰽿"; font.family: "Iosevka Nerd Font"; font.pixelSize: root.s(20); color: root.yellow }
                                }
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    Layout.alignment: Qt.AlignVCenter
                                    spacing: root.s(4)
                                    Text { text: "Workspaces"; font.family: "Inter"; font.weight: Font.Bold; font.pixelSize: root.s(15); color: root.text; Layout.fillWidth: true }
                                    Text { text: "Static count in topbar"; font.family: "Inter"; font.pixelSize: root.s(12); color: Qt.alpha(root.subtext0, 0.7); Layout.fillWidth: true }
                                }
                                RowLayout {
                                    Layout.alignment: Qt.AlignVCenter | Qt.AlignRight
                                    spacing: root.s(12)
                                    Rectangle {
                                        width: root.s(30); height: root.s(30); radius: root.s(8)
                                        color: wsMinusMa.pressed ? Qt.alpha(root.yellow, 0.4) : (wsMinusMa.containsMouse ? root.surface2 : root.surface1)
                                        scale: wsMinusMa.pressed ? 0.90 : (wsMinusMa.containsMouse ? 1.08 : 1.0)
                                        Behavior on scale { NumberAnimation { duration: 250; easing.type: Easing.OutQuart } }
                                        Behavior on color { ColorAnimation { duration: 250; easing.type: Easing.OutQuart } }
                                        Text { anchors.centerIn: parent; text: "-"; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: root.s(16); color: wsMinusMa.pressed ? root.yellow : root.text }
                                        MouseArea { id: wsMinusMa; anchors.fill: parent; hoverEnabled: true; onClicked: root.setWorkspaceCount = Math.max(2, root.setWorkspaceCount - 1) }
                                    }
                                    Text { 
                                        text: root.setWorkspaceCount.toString()
                                        font.family: "JetBrains Mono"
                                        font.weight: Font.Black
                                        font.pixelSize: root.s(14)
                                        color: root.yellow
                                        Layout.minimumWidth: root.s(40)
                                        horizontalAlignment: Text.AlignHCenter 
                                    }
                                    Rectangle {
                                        width: root.s(30); height: root.s(30); radius: root.s(8)
                                        color: wsPlusMa.pressed ? Qt.alpha(root.yellow, 0.4) : (wsPlusMa.containsMouse ? root.surface2 : root.surface1)
                                        scale: wsPlusMa.pressed ? 0.90 : (wsPlusMa.containsMouse ? 1.08 : 1.0)
                                        Behavior on scale { NumberAnimation { duration: 250; easing.type: Easing.OutQuart } }
                                        Behavior on color { ColorAnimation { duration: 250; easing.type: Easing.OutQuart } }
                                        Text { anchors.centerIn: parent; text: "+"; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: root.s(16); color: wsPlusMa.pressed ? root.yellow : root.text }
                                        MouseArea { id: wsPlusMa; anchors.fill: parent; hoverEnabled: true; onClicked: root.setWorkspaceCount = Math.min(10, root.setWorkspaceCount + 1) }
                                    }
                                }
                            }
                        }
                    }

                }
            }
            
            Rectangle {
                id: floatingSaveBtn
                width: saveRow.implicitWidth + root.s(40)
                height: root.s(40)
                anchors.bottom: parent.bottom
                anchors.right: parent.right
                anchors.margins: root.s(24)
                radius: height / 2 // Retain as pure pill shape
                
                // Subtle border that disappears on hover so the gradient pops cleanly
                border.color: mainSaveMa.containsMouse ? "transparent" : Qt.alpha(root.mauve, 0.5)
                border.width: 1
                
                // Matching the premium tactile push-in animation from the +/- buttons
                scale: mainSaveMa.pressed ? 0.95 : (mainSaveMa.containsMouse ? 1.05 : 1.0)
                Behavior on scale { NumberAnimation { duration: 250; easing.type: Easing.OutQuart } }

                // Clean, monochromatic brightness shift (no muddy color clashing)
                gradient: Gradient {
                    GradientStop { 
                        position: 0.0; 
                        color: mainSaveMa.pressed ? root.mauve : (mainSaveMa.containsMouse ? Qt.lighter(root.mauve, 1.3) : root.surface0) 
                    }
                    GradientStop { 
                        position: 1.0; 
                        color: mainSaveMa.pressed ? Qt.darker(root.mauve, 1.2) : (mainSaveMa.containsMouse ? root.mauve : root.surface0) 
                    }
                }

                RowLayout {
                    id: saveRow
                    anchors.centerIn: parent
                    spacing: root.s(8)
                    
                    Text {
                        text: "󰆓"
                        font.family: "Iosevka Nerd Font"
                        font.pixelSize: root.s(18)
                        color: mainSaveMa.containsMouse ? root.base : root.mauve
                        Behavior on color { ColorAnimation { duration: 150 } }
                    }
                    Text {
                        text: "Apply"
                        font.family: "Inter"
                        font.weight: Font.Bold
                        font.pixelSize: root.s(14)
                        color: mainSaveMa.containsMouse ? root.base : root.text
                        Behavior on color { ColorAnimation { duration: 150 } }
                    }
                }
                
                MouseArea { 
                    id: mainSaveMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.saveAppSettings() 
                }
            }        }
    }
}
