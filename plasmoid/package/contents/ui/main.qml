/*
 * VRGB - Plasma 6 applet for ASUS Vivobook HID LampArray keyboards.
 *
 * State lives in ~/.config/vrgb/config.json, which the applet reads directly.
 * Colour writes always go through the `vrgb` CLI so the config file has a
 * single owner and the applet never touches hidraw itself.
 *
 * Brightness is deliberately NOT vrgb's own intensity channel. The keyboard
 * has two controls that multiply together: the asus::kbd_backlight level the
 * Fn keys and Plasma drive, and vrgb's LampArray intensity. Driving the latter
 * left the widget out of step with the Fn keys, so the slider here controls
 * the Plasma backlight and vrgb's intensity stays pinned wide open.
 *
 * SPDX-License-Identifier: MIT
 */

import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.plasma5support as P5Support
import org.kde.plasma.private.brightnesscontrolplugin
import org.kde.kirigami as Kirigami

PlasmoidItem {
    id: root

    // Resolved at startup; install.sh puts vrgb in /usr/local/bin, which is not
    // always on plasmashell's PATH.
    property string vrgbBin: "vrgb"
    property color currentColor: "#00aa55"
    property string errorText: ""
    // Suppresses hardware writes while the UI is being seeded from config.json.
    property bool loading: true

    // Brightness comes from Plasma so the Fn keys and the widget stay in step.
    readonly property int backlight: kbdBacklight.brightness
    readonly property int backlightMax: Math.max(1, kbdBacklight.brightnessMax)
    readonly property real litFraction: backlight / backlightMax

    readonly property var presets: [
        "#ff0000", "#ff7f00", "#ffd400", "#7fff00", "#00ff5e", "#00e5ff",
        "#0080ff", "#2b3cff", "#8b00ff", "#ff00c8", "#ff4d6d", "#ffffff"
    ]

    readonly property string hexColor: {
        function ch(v) {
            return Math.round(Math.max(0, Math.min(1, v)) * 255).toString(16).padStart(2, "0");
        }
        return ch(currentColor.r) + ch(currentColor.g) + ch(currentColor.b);
    }

    // The colour as it should actually appear on the keys.
    readonly property color litColor: Qt.rgba(currentColor.r * litFraction,
                                              currentColor.g * litFraction,
                                              currentColor.b * litFraction, 1)

    readonly property string resolveCmd: "command -v vrgb 2>/dev/null || echo /usr/local/bin/vrgb"
    readonly property string readCfgCmd: "cat \"$HOME/.config/vrgb/config.json\" 2>/dev/null"

    Plasmoid.icon: "input-keyboard"
    toolTipMainText: i18n("Keyboard Lighting")
    toolTipSubText: loading ? i18n("Reading configuration…")
                            : i18n("#%1 at %2%", hexColor.toUpperCase(),
                                   Math.round(litFraction * 100))

    preferredRepresentation: compactRepresentation

    function applyNow() {
        if (loading) {
            return;
        }
        applyTimer.stop();
        // hexColor is generated locally, so the command line is safe to build
        // by concatenation. The trailing 100 pins vrgb's intensity wide open --
        // the Plasma backlight level is this applet's brightness control.
        executable.run(vrgbBin + " set " + hexColor + " 100");
    }

    function scheduleApply() {
        if (!loading) {
            applyTimer.restart();
        }
    }

    function loadConfig(text) {
        var cfg = null;
        if (text.length > 0) {
            try {
                cfg = JSON.parse(text);
            } catch (e) {
                cfg = null;
            }
        }
        var percent = 100;
        if (cfg) {
            if (typeof cfg.color === "string" && /^[0-9a-fA-F]{6}$/.test(cfg.color)) {
                currentColor = "#" + cfg.color;
            }
            var p = parseInt(cfg.percent, 10);
            if (!isNaN(p)) {
                percent = p;
            }
        }
        loading = false;

        // Normalise once if the CLI (or an older build of this applet) left
        // vrgb's intensity somewhere other than wide open -- otherwise the
        // backlight slider could never reach full brightness.
        if (percent !== 100) {
            applyNow();
        }
    }

    function handleResult(source, code, out, err) {
        if (source === resolveCmd) {
            if (out.length > 0) {
                vrgbBin = out.split("\n")[0];
            }
            executable.run(readCfgCmd);
        } else if (source === readCfgCmd) {
            loadConfig(out);
        } else {
            errorText = (code === 0) ? ""
                                     : (err.length > 0 ? err : i18n("vrgb exited with code %1", code));
        }
    }

    Timer {
        id: applyTimer
        // vrgb returns in ~25 ms; 60 ms keeps a drag smooth without queueing up
        // one process per mouse move.
        interval: 60
        onTriggered: root.applyNow()
    }

    KeyboardBrightnessControl {
        id: kbdBacklight
        // The popup shows the level itself; a second OSD on every drag step
        // would just be noise.
        isSilent: true
    }

    P5Support.DataSource {
        id: executable

        engine: "executable"
        connectedSources: []

        onNewData: (source, data) => {
            var code = data["exit code"];
            var out = (data["stdout"] || "").trim();
            var err = (data["stderr"] || "").trim();
            disconnectSource(source);
            root.handleResult(source, code, out, err);
        }

        function run(cmd) {
            // The engine keys sources by command string, so re-running an
            // identical command needs an explicit disconnect first.
            if (connectedSources.indexOf(cmd) !== -1) {
                disconnectSource(cmd);
            }
            connectSource(cmd);
        }
    }

    Component.onCompleted: executable.run(resolveCmd)

    compactRepresentation: MouseArea {
        onClicked: root.expanded = !root.expanded

        Kirigami.Icon {
            anchors.centerIn: parent
            width: Math.min(parent.width, parent.height)
            height: width
            // The symbolic variant keeps its key detail when masked; plain
            // input-keyboard flattens to a solid block.
            source: "input-keyboard-symbolic"
            isMask: true
            color: root.backlight > 0 ? root.currentColor : Kirigami.Theme.disabledTextColor
        }
    }

    fullRepresentation: Item {
        Layout.minimumWidth: Kirigami.Units.gridUnit * 15
        Layout.minimumHeight: Kirigami.Units.gridUnit * 21
        Layout.preferredWidth: Kirigami.Units.gridUnit * 17
        Layout.preferredHeight: Kirigami.Units.gridUnit * 23

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Kirigami.Units.largeSpacing
            spacing: Kirigami.Units.smallSpacing

            RowLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.largeSpacing

                Rectangle {
                    Layout.preferredWidth: Kirigami.Units.gridUnit * 2.5
                    Layout.preferredHeight: Kirigami.Units.gridUnit * 2.5
                    radius: 4
                    color: root.litColor
                    border.width: 1
                    border.color: Qt.rgba(0, 0, 0, 0.3)
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0

                    Kirigami.Heading {
                        Layout.fillWidth: true
                        level: 4
                        elide: Text.ElideRight
                        text: i18n("Keyboard Lighting")
                    }

                    PlasmaComponents.Label {
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        font.family: "monospace"
                        opacity: 0.75
                        text: "#" + root.hexColor.toUpperCase()
                    }
                }
            }

            Kirigami.Separator {
                Layout.fillWidth: true
                Layout.topMargin: Kirigami.Units.smallSpacing
                Layout.bottomMargin: Kirigami.Units.smallSpacing
            }

            GridLayout {
                Layout.fillWidth: true
                columns: 6
                columnSpacing: Kirigami.Units.smallSpacing
                rowSpacing: Kirigami.Units.smallSpacing

                Repeater {
                    model: root.presets

                    delegate: Rectangle {
                        required property string modelData

                        Layout.fillWidth: true
                        Layout.preferredHeight: Kirigami.Units.gridUnit * 1.3
                        radius: 3
                        color: modelData
                        border.width: 1
                        border.color: Qt.rgba(0, 0, 0, 0.3)

                        MouseArea {
                            anchors.fill: parent
                            onClicked: {
                                root.currentColor = parent.modelData;
                                picker.setColor(root.currentColor);
                                root.applyNow();
                            }
                        }
                    }
                }
            }

            ColorPicker {
                id: picker

                Layout.fillWidth: true
                Layout.topMargin: Kirigami.Units.smallSpacing

                Component.onCompleted: setColor(root.currentColor)

                onPicked: c => {
                    root.currentColor = c;
                    root.scheduleApply();
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: Kirigami.Units.smallSpacing

                PlasmaComponents.Label {
                    text: i18n("Brightness")
                }

                Item {
                    Layout.fillWidth: true
                }

                PlasmaComponents.Label {
                    opacity: 0.75
                    text: root.backlight + " / " + root.backlightMax
                }
            }

            PlasmaComponents.Slider {
                id: backlightSlider

                Layout.fillWidth: true
                enabled: kbdBacklight.isBrightnessAvailable
                from: 0
                to: root.backlightMax
                stepSize: 1
                snapMode: PlasmaComponents.Slider.SnapAlways

                // Straight to Plasma: this is a D-Bus property rather than a
                // subprocess, so it needs no throttling.
                onMoved: kbdBacklight.brightness = Math.round(value)
            }

            // Follows Plasma -- Fn keys, the brightness applet, anything else --
            // whenever the user is not dragging. Depending on backlightMax as
            // well as backlight matters: PowerDevil publishes the maximum after
            // the current value on startup, and without that dependency the
            // slider can stay clamped against a stale range.
            Binding {
                target: backlightSlider
                property: "value"
                value: Math.min(root.backlight, root.backlightMax)
                when: !backlightSlider.pressed
                restoreMode: Binding.RestoreNone
            }

            Kirigami.InlineMessage {
                Layout.fillWidth: true
                type: Kirigami.MessageType.Error
                text: root.errorText
                visible: root.errorText.length > 0
            }

            Item {
                Layout.fillHeight: true
            }
        }

        // Keep the popup in sync when config.json loads after the popup was built.
        Connections {
            target: root

            function onCurrentColorChanged() {
                picker.setColor(root.currentColor);
            }
        }
    }
}
