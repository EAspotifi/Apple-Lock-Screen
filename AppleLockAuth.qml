pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Shapes
import Quickshell
import qs.Common
import qs.Modules.Plugins
import qs.Services
import qs.DCommon.Widgets
import qs.DCommon.Session

DesktopPluginComponent {
    id: root

    property var lockHost: null
    property bool acceptsKeyboardFocus: true
    property bool resizable: true

    // --- Plugin Settings ------------------------------------------------
    readonly property var globalSettings: SettingsData.pluginSettings?.appleLockAuth ?? ({})
    function settingVal(key, fallback) {
        if (pluginData && pluginData[key] !== undefined)
            return pluginData[key];
        if (globalSettings && globalSettings[key] !== undefined)
            return globalSettings[key];
        return fallback;
    }

    readonly property string barStyle: String(settingVal("barStyle", "apple"))
    readonly property real generalScale: Math.max(0.5, Number(settingVal("generalScale", 115)) / 100)
    readonly property real baseAvatarSize: Number(settingVal("avatarSize", 96))
    readonly property real baseBarWidth: Number(settingVal("barWidth", 240))
    readonly property real baseBarHeight: Number(settingVal("barHeight", 44))
    readonly property bool showActionButtons: settingVal("showActionButtons", true) !== false

    // Style flags
    readonly property bool isApple: barStyle === "apple"
    readonly property bool isExpressive: barStyle === "expressive"
    readonly property bool isPill: barStyle === "pill"
    readonly property bool isDots: barStyle === "dots"
    readonly property bool isMinimal: barStyle === "minimal"
    readonly property bool isRing: barStyle === "ring"
    readonly property bool isNativeContained: isExpressive || isPill

    // Scaled metrics
    readonly property real avatarSize: Math.round(baseAvatarSize * generalScale)
    readonly property real fieldHeight: Math.round(baseBarHeight * generalScale)
    readonly property real targetFieldWidth: Math.round(baseBarWidth * generalScale)
    readonly property real fieldWidth: Math.min(Math.max(140, width - 32), targetFieldWidth)
    readonly property real liftOffset: Math.round((isRing ? 18 : (fieldHeight * 0.85 + 8)))
    readonly property real ringStroke: Math.max(4, Math.round(6 * generalScale))
    readonly property real ringPadding: Math.max(8, Math.round(12 * generalScale))
    readonly property real ringOuterSize: avatarSize + ringPadding * 2 + ringStroke * 2

    property real defaultWidth: Math.max(360, targetFieldWidth + 64)
    property real defaultHeight: Math.max(260, avatarSize + fieldHeight + 130)
    property real bottomOverflow: (feedbackBox.visible ? feedbackBox.height + 8 : 0) + (capsLockRow.opacity > 0 ? capsLockRow.height + 6 : 0)

    minWidth: 220
    minHeight: 200

    implicitWidth: Math.max(fieldWidth + 40, ringOuterSize + 40)
    implicitHeight: avatarSize + fieldHeight + 110

    // --- Auth host -------------------------------------------------------
    readonly property var pam: lockHost?.pam ?? null
    readonly property bool demoMode: lockHost?.demoMode ?? false
    readonly property string pamState: lockHost?.pamState ?? ""
    readonly property bool unlocking: lockHost?.unlocking ?? false
    readonly property bool authenticating: (pam?.authBusy ?? false) && !unlocking
    readonly property bool failed: pamState !== ""

    // --- Local input state ----------------------------------------------
    property string buffer: ""
    property bool userRevealed: false
    readonly property bool revealed: demoMode || userRevealed || authenticating || unlocking || failed || (pam?.u2fPending ?? false)
    property bool pillVisible: demoMode
    property bool showPasswordText: false
    property real shakeOffset: 0
    property int prevLength: 0
    property real keyAngle: 0

    readonly property var morphShapes: ["cookie4", "clover4", "sunny", "cookie9", "softBurst", "pentagon", "oval", "cookie6"]
    readonly property string morphShape: morphShapes[buffer.length % morphShapes.length]

    readonly property color contentColor: Theme.lockScreenContentColor
    readonly property color accentColor: Theme.primary
    readonly property color applePillColor: inputScope.activeFocus ? "#73000000" : "#59000000"
    readonly property color applePillBorder: inputScope.activeFocus ? "#99FFFFFF" : "#40FFFFFF"

    function encodeFileUrl(path) {
        if (!path)
            return "";
        return "file://" + path.split('/').map(s => encodeURIComponent(s)).join('/');
    }

    readonly property string resolvedProfileImage: {
        if (PortalService.profileImageUrl && PortalService.profileImageUrl !== "")
            return PortalService.profileImageUrl;
        if (!PortalService.profileImage || PortalService.profileImage === "")
            return "";
        if (PortalService.profileImage.startsWith("/"))
            return encodeFileUrl(PortalService.profileImage);
        return PortalService.profileImage;
    }

    // --- Behaviour ------------------------------------------------------
    Timer {
        id: pillDelay
        interval: 90
        onTriggered: root.pillVisible = true
    }

    onBufferChanged: {
        const grew = buffer.length > prevLength;
        prevLength = buffer.length;
        if (!grew || demoMode)
            return;
        keyAngle = (buffer.length * 137.5) % 360;
        if (isRing)
            keyPulse.restart();
        if (isExpressive)
            morphPulse.restart();
    }

    function reveal() {
        if (root.userRevealed)
            return;
        root.userRevealed = true;
        pillDelay.restart();
        if (root.lockHost && root.lockHost.setInputRevealed)
            root.lockHost.setInputRevealed(true);
    }

    function collapse() {
        pillDelay.stop();
        root.pillVisible = false;
        root.userRevealed = false;
        root.showPasswordText = false;
        root.buffer = "";
        if (root.lockHost) {
            if (root.lockHost.passwordEdited)
                root.lockHost.passwordEdited("");
            if (root.lockHost.setInputRevealed)
                root.lockHost.setInputRevealed(false);
        }
    }

    function focusPasswordField() {
        if (root.demoMode)
            return;
        inputScope.forceActiveFocus();
    }

    function submit() {
        if (!root.pam || root.authenticating || root.unlocking || root.buffer.length === 0)
            return;
        if (root.pam.retryFprintOnActivity)
            root.pam.retryFprintOnActivity();
        root.pam.submitPassword();
    }

    function typeText(value) {
        if (!value || !value.length || root.authenticating || root.unlocking)
            return;
        root.reveal();
        root.buffer += value;
        if (root.lockHost && root.lockHost.passwordEdited)
            root.lockHost.passwordEdited(root.buffer);
    }

    function backspace() {
        if (root.buffer.length === 0)
            return;
        root.buffer = root.buffer.slice(0, -1);
        if (root.lockHost && root.lockHost.passwordEdited)
            root.lockHost.passwordEdited(root.buffer);
    }

    function clearBuffer() {
        if (root.buffer.length === 0)
            return;
        root.buffer = "";
        if (root.lockHost && root.lockHost.passwordEdited)
            root.lockHost.passwordEdited("");
    }

    function isPrintable(event) {
        if (event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier))
            return false;
        if (event.text.length === 0)
            return false;
        const code = event.text.charCodeAt(0);
        return code >= 0x20 && code !== 0x7f;
    }

    function handleKey(event) {
        if (root.demoMode)
            return;

        if (root.pam && root.pam.retryFprintOnActivity)
            root.pam.retryFprintOnActivity();

        if (root.unlocking) {
            event.accepted = true;
            return;
        }

        if (event.key === Qt.Key_Escape) {
            if (root.buffer.length > 0)
                root.clearBuffer();
            else
                root.collapse();
            event.accepted = true;
            return;
        }

        if (root.authenticating) {
            event.accepted = true;
            return;
        }

        if ((event.modifiers & Qt.ControlModifier) && !(event.modifiers & (Qt.AltModifier | Qt.MetaModifier))) {
            if (event.key === Qt.Key_U || event.key === Qt.Key_Backspace || event.key === Qt.Key_W) {
                root.clearBuffer();
                event.accepted = true;
                return;
            }
        }

        switch (event.key) {
        case Qt.Key_Return:
        case Qt.Key_Enter:
            root.submit();
            event.accepted = true;
            return;
        case Qt.Key_Backspace:
        case Qt.Key_Delete:
            root.backspace();
            event.accepted = true;
            return;
        }

        if (root.isPrintable(event)) {
            root.typeText(event.text);
            event.accepted = true;
            return;
        }

        // Any other interaction wakes the field up with the Apple slide animation.
        root.reveal();
        event.accepted = true;
    }

    function placeholderPrompt() {
        if (root.unlocking)
            return I18n.tr("Unlocking...");
        if (root.authenticating)
            return I18n.tr("Authenticating...");
        if (root.pam?.u2fPending) {
            if (root.pam.u2fState === "insert")
                return I18n.tr("Insert your security key...");
            return I18n.tr("Touch your security key...");
        }
        if (root.pam?.authPromptText && root.pam.authPromptText !== "")
            return root.pam.authPromptText;
        return I18n.tr("Password") + (root.isApple ? "" : "…");
    }

    function feedbackText() {
        if (!root.pam)
            return "";
        if (root.pam.u2fState === "insert")
            return I18n.tr("Insert your security key...");
        if (root.pam.u2fState === "waiting")
            return I18n.tr("Touch your security key...");
        if (root.pam.lockMessage && root.pam.lockMessage.length > 0)
            return root.pam.lockMessage;
        switch (root.pamState) {
        case "error":
            return I18n.tr("Authentication error - try again");
        case "max":
            return I18n.tr("Too many attempts - locked out");
        case "fail":
            return I18n.tr("Incorrect password - try again");
        }
        if (root.pam.fprint && root.pam.fprint.status !== "disabled") {
            if (root.pam.fprintState === "error")
                return I18n.tr("Fingerprint error");
            if (root.pam.fprintState === "max")
                return I18n.tr("Maximum fingerprint attempts reached. Please use password.");
            if (root.pam.fprintState === "fail")
                return I18n.tr("Fingerprint not recognized (%1/%2). Please try again or use password.").arg(root.pam.fprint.tries).arg(SettingsData.maxFprintTries);
        }
        return "";
    }

    // --- Host wiring ----------------------------------------------------
    onLockHostChanged: {
        if (!lockHost)
            return;
        lockHost.authWidget = root;
        Qt.callLater(() => {
            if (!root.demoMode)
                inputScope.forceActiveFocus();
        });
    }

    Component.onCompleted: {
        if (lockHost) {
            lockHost.authWidget = root;
            Qt.callLater(() => {
                if (!root.demoMode)
                    inputScope.forceActiveFocus();
            });
        }
        if (!demoMode)
            focusRetry.start();
    }

    Component.onDestruction: {
        if (lockHost && lockHost.authWidget === root)
            lockHost.authWidget = null;
    }

    onPamStateChanged: {
        if (pamState === "")
            return;
        shake.restart();
        root.showPasswordText = false;
        root.buffer = "";
    }

    onDemoModeChanged: {
        if (demoMode) {
            userRevealed = false;
            pillVisible = true;
        }
    }

    Connections {
        target: root.lockHost
        enabled: root.lockHost !== null

        function onPasswordBufferChanged() {
            if (root.demoMode)
                return;
            const next = root.lockHost.passwordBuffer ?? "";
            if (next !== root.buffer)
                root.buffer = next;
        }

        function onAuthFailed() {
            shake.restart();
            root.showPasswordText = false;
        }
    }

    SequentialAnimation {
        id: shake
        NumberAnimation { target: root; property: "shakeOffset"; to: -8; duration: 45; easing.type: Easing.OutQuad }
        NumberAnimation { target: root; property: "shakeOffset"; to: 8; duration: 55; easing.type: Easing.InOutQuad }
        NumberAnimation { target: root; property: "shakeOffset"; to: -6; duration: 55; easing.type: Easing.InOutQuad }
        NumberAnimation { target: root; property: "shakeOffset"; to: 4; duration: 55; easing.type: Easing.InOutQuad }
        NumberAnimation { target: root; property: "shakeOffset"; to: 0; duration: 70; easing.type: Easing.OutQuad }
    }

    // --- Avatar + Optional Native Ring ----------------------------------
    Item {
        id: avatarWrap

        width: root.isRing ? root.ringOuterSize : root.avatarSize
        height: width
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
        anchors.verticalCenterOffset: root.revealed ? -root.liftOffset : 0
        scale: root.revealed ? 0.92 : 1
        transform: Translate {
            x: root.isRing ? root.shakeOffset : 0
        }

        Behavior on anchors.verticalCenterOffset {
            NumberAnimation {
                duration: 480
                easing.type: Easing.OutCubic
            }
        }

        Behavior on scale {
            NumberAnimation {
                duration: 480
                easing.type: Easing.OutCubic
            }
        }

        // Native Ring style indicator around the avatar when revealed
        Item {
            id: ringLayer
            anchors.fill: parent
            visible: root.isRing
            opacity: root.pillVisible ? 1 : 0
            readonly property real arcRadius: width / 2 - root.ringStroke / 2

            Behavior on opacity {
                NumberAnimation {
                    duration: 300
                    easing.type: Easing.OutCubic
                }
            }

            Shape {
                anchors.fill: parent
                preferredRendererType: Shape.CurveRenderer

                ShapePath {
                    strokeColor: {
                        if (root.failed)
                            return Theme.withAlpha(Theme.error, Theme.pendingOpacity);
                        if (root.authenticating || (root.buffer.length === 0 && !root.demoMode))
                            return Theme.withAlpha(root.contentColor, Theme.stateLayerDrag);
                        return Theme.withAlpha(root.accentColor, Theme.pendingOpacity);
                    }
                    strokeWidth: root.ringStroke
                    fillColor: "transparent"
                    capStyle: ShapePath.RoundCap

                    PathAngleArc {
                        centerX: ringLayer.width / 2
                        centerY: ringLayer.height / 2
                        radiusX: ringLayer.arcRadius
                        radiusY: ringLayer.arcRadius
                        startAngle: 0
                        sweepAngle: 360
                    }

                    Behavior on strokeColor {
                        ColorAnimation { duration: 200 }
                    }
                }
            }

            Shape {
                id: keySegment
                anchors.fill: parent
                preferredRendererType: Shape.CurveRenderer
                opacity: 0

                ShapePath {
                    strokeColor: root.accentColor
                    strokeWidth: root.ringStroke
                    fillColor: "transparent"
                    capStyle: ShapePath.RoundCap

                    PathAngleArc {
                        centerX: ringLayer.width / 2
                        centerY: ringLayer.height / 2
                        radiusX: ringLayer.arcRadius
                        radiusY: ringLayer.arcRadius
                        startAngle: root.keyAngle - 90
                        sweepAngle: 34
                    }
                }

                SequentialAnimation {
                    id: keyPulse
                    PropertyAction { target: keySegment; property: "opacity"; value: 1 }
                    NumberAnimation {
                        target: keySegment
                        property: "opacity"
                        to: 0
                        duration: 420
                        easing.type: Easing.OutCubic
                    }
                }
            }

            Shape {
                id: verifyArc
                anchors.fill: parent
                preferredRendererType: Shape.CurveRenderer
                visible: root.isRing && (root.authenticating || root.unlocking)

                ShapePath {
                    strokeColor: root.accentColor
                    strokeWidth: root.ringStroke
                    fillColor: "transparent"
                    capStyle: ShapePath.RoundCap

                    PathAngleArc {
                        centerX: ringLayer.width / 2
                        centerY: ringLayer.height / 2
                        radiusX: ringLayer.arcRadius
                        radiusY: ringLayer.arcRadius
                        startAngle: -90
                        sweepAngle: 90
                    }
                }

                RotationAnimator on rotation {
                    running: verifyArc.visible
                    loops: Animation.Infinite
                    duration: 900
                    from: 0
                    to: 360
                }
            }
        }

        DCircularImage {
            anchors.centerIn: parent
            width: root.avatarSize
            height: root.avatarSize
            imageSource: root.resolvedProfileImage
            fallbackIcon: "material:person"
            ringWidth: root.isRing ? 0 : Math.max(1, Math.round(1.5 * root.generalScale))
            ringColor: root.isApple ? "#59FFFFFF" : Theme.avatarRingColor
        }
    }

    // --- User Name ------------------------------------------------------
    Text {
        id: nameShadow

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: avatarWrap.bottom
        anchors.topMargin: Math.round(11 * root.generalScale)
        text: nameText.text
        color: "#59000000"
        font.family: Theme.fontFamily
        font.pixelSize: Math.round(15 * root.generalScale)
        font.weight: 600
        visible: nameText.visible
    }

    Text {
        id: nameText

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: avatarWrap.bottom
        anchors.topMargin: Math.round(10 * root.generalScale)
        text: UserInfoService.fullName || UserInfoService.username || ""
        color: root.contentColor
        font.family: Theme.fontFamily
        font.pixelSize: Math.round(15 * root.generalScale)
        font.weight: 600
        font.letterSpacing: 0.2
        visible: text.length > 0
    }

    // --- Idle hint ------------------------------------------------------
    Text {
        id: hintText

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: nameText.bottom
        anchors.topMargin: Math.round(16 * root.generalScale)
        text: "Haz clic o escribe para desbloquear"
        color: Theme.withAlpha(root.contentColor, 0.62)
        font.family: Theme.fontFamily
        font.pixelSize: Math.max(11, Math.round(13 * root.generalScale))
        opacity: root.revealed ? 0 : 1

        Behavior on opacity {
            NumberAnimation {
                duration: 220
                easing.type: Easing.OutCubic
            }
        }
    }

    // --- Password Bar (Apple & Native DMS Styles) -----------------------
    Rectangle {
        id: passwordBar

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: nameText.bottom
        anchors.topMargin: Math.round(13 * root.generalScale)
        width: root.fieldWidth
        height: root.isRing ? 0 : root.fieldHeight
        visible: !root.isRing
        clip: true

        radius: {
            if (root.isApple || root.isPill)
                return height / 2;
            if (root.isExpressive)
                return Math.round(Theme.cornerRadiusXL * root.generalScale);
            return 0;
        }

        color: {
            if (root.isApple)
                return root.applePillColor;
            if (root.isExpressive)
                return Theme.surfaceContainerHigh;
            if (root.isPill)
                return Theme.cardSurface;
            return "transparent";
        }

        border.width: {
            if (root.isApple)
                return 1;
            if (root.isNativeContained)
                return inputScope.activeFocus ? Math.max(Theme.outlineWidth, Theme.focusRingWidth) : Theme.layerOutlineWidth;
            return 0;
        }

        border.color: {
            if (root.failed)
                return root.isApple ? Theme.withAlpha(Theme.error, 0.85) : Theme.error;
            if (root.isApple)
                return root.applePillBorder;
            if (root.isNativeContained)
                return inputScope.activeFocus ? Theme.focusRingColor : Theme.outlineMedium;
            return "transparent";
        }

        opacity: root.pillVisible ? 1 : 0
        scale: root.pillVisible ? 1 : 0.94
        transform: Translate {
            x: root.shakeOffset
        }

        Behavior on opacity {
            NumberAnimation {
                duration: 260
                easing.type: Easing.OutCubic
            }
        }

        Behavior on scale {
            NumberAnimation {
                duration: 380
                easing.type: Easing.OutCubic
            }
        }

        Behavior on color {
            ColorAnimation { duration: 180 }
        }

        Behavior on border.color {
            ColorAnimation { duration: 180 }
        }

        // Minimal style bottom underline
        Rectangle {
            id: minimalUnderline
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            visible: root.isMinimal
            height: inputScope.activeFocus ? Math.max(2, Theme.outlineWidthFocused) : Math.max(1, Theme.dividerWidth)
            color: {
                if (root.failed)
                    return Theme.error;
                return inputScope.activeFocus ? root.accentColor : Theme.withAlpha(root.contentColor, Theme.pendingOpacity);
            }

            Behavior on color {
                ColorAnimation { duration: 180 }
            }
        }

        // Left morph / lock icon for Expressive & Pill native styles
        Item {
            id: nativeLeftIcon
            anchors.left: parent.left
            anchors.leftMargin: root.isExpressive ? Math.round(8 * root.generalScale) : Math.round(14 * root.generalScale)
            anchors.verticalCenter: parent.verticalCenter
            visible: root.isExpressive || root.isPill
            width: !visible ? 0 : (root.isExpressive ? Math.max(24, root.fieldHeight - Math.round(14 * root.generalScale)) : Math.round(Theme.iconSizeSmall * root.generalScale))
            height: width

            DMaterialShape {
                id: morphContainer
                anchors.fill: parent
                visible: root.isExpressive
                shape: root.morphShape
                color: root.failed ? Theme.errorContainer : Theme.primaryContainer

                SequentialAnimation {
                    id: morphPulse
                    NumberAnimation {
                        target: morphContainer
                        property: "scale"
                        to: 1.15
                        duration: 90
                        easing.type: Easing.OutQuad
                    }
                    NumberAnimation {
                        target: morphContainer
                        property: "scale"
                        to: 1.0
                        duration: 160
                        easing.type: Easing.OutCubic
                    }
                }

                Behavior on color {
                    ColorAnimation { duration: 180 }
                }
            }

            DLoadingIndicator {
                anchors.centerIn: parent
                size: parent.width
                contained: true
                visible: root.isExpressive && (root.authenticating || root.unlocking)
                running: visible
            }

            DIcon {
                anchors.centerIn: parent
                visible: !(root.isExpressive && (root.authenticating || root.unlocking))
                name: {
                    if (!root.pam)
                        return "lock";
                    if (root.pam.u2fPending)
                        return "passkey";
                    if (root.pam.fprint) {
                        switch (root.pam.fprint.status) {
                        case "max":
                        case "stopped":
                            return "fingerprint_off";
                        case "active":
                            return "fingerprint";
                        case "retrying":
                            return "hourglass_empty";
                        }
                    }
                    return root.unlocking ? "lock_open" : "lock";
                }
                size: Math.round(Theme.iconSizeSmall * root.generalScale)
                color: {
                    if (root.isExpressive)
                        return root.failed ? Theme.onErrorContainer : Theme.onPrimaryContainer;
                    if (inputScope.activeFocus)
                        return root.accentColor;
                    return Theme.surfaceVariantText;
                }
            }
        }

        // Content area bounds
        readonly property real contentLeftMargin: {
            if (root.isMinimal)
                return 4;
            if (root.isExpressive || root.isPill)
                return nativeLeftIcon.x + nativeLeftIcon.width + Math.round(10 * root.generalScale);
            return Math.round(18 * root.generalScale);
        }

        readonly property real contentRightMargin: {
            let right = Math.round(14 * root.generalScale);
            if (spinner.visible)
                right += spinner.width + 8;
            if (nativeEnterButton.visible)
                right += nativeEnterButton.width + 4;
            if (nativeRevealButton.visible)
                right += nativeRevealButton.width + 4;
            return right;
        }

        // Native "dots" style circles
        Item {
            id: nativeDotsViewport
            anchors.left: parent.left
            anchors.leftMargin: passwordBar.contentLeftMargin
            anchors.right: parent.right
            anchors.rightMargin: passwordBar.contentRightMargin
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            clip: true
            visible: root.isDots && !root.showPasswordText

            Row {
                anchors.verticalCenter: parent.verticalCenter
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: Math.round(8 * root.generalScale)

                Repeater {
                    model: root.demoMode ? 6 : Math.max(1, root.buffer.length)

                    Rectangle {
                        required property int index
                        readonly property bool filled: root.demoMode || index < root.buffer.length
                        readonly property color tone: root.failed ? Theme.error : root.accentColor

                        anchors.verticalCenter: parent.verticalCenter
                        width: Math.max(10, Math.round(14 * root.generalScale))
                        height: width
                        radius: width / 2
                        color: filled ? tone : "transparent"
                        border.width: 2
                        border.color: filled ? tone : Theme.withAlpha(root.contentColor, Theme.pendingOpacity)
                        scale: filled ? 1 : 0.8

                        Behavior on scale {
                            NumberAnimation { duration: 150; easing.type: Easing.OutBack }
                        }
                    }
                }
            }
        }

        // Placeholder text
        Text {
            id: placeholder

            anchors.left: parent.left
            anchors.leftMargin: passwordBar.contentLeftMargin
            anchors.right: parent.right
            anchors.rightMargin: passwordBar.contentRightMargin
            anchors.verticalCenter: parent.verticalCenter
            text: root.placeholderPrompt()
            color: {
                if (root.unlocking || root.authenticating)
                    return root.isApple ? root.contentColor : root.accentColor;
                if (root.isNativeContained)
                    return Theme.outline;
                return Theme.withAlpha(root.contentColor, 0.62);
            }
            font.family: Theme.fontFamily
            font.pixelSize: Math.max(11, Math.round(14 * root.generalScale))
            visible: !root.isDots && ((root.buffer.length === 0 && !root.demoMode) || root.authenticating || root.unlocking)
            elide: Text.ElideRight
        }

        // Password characters / dots text
        Text {
            id: dotsText

            anchors.left: parent.left
            anchors.leftMargin: passwordBar.contentLeftMargin
            anchors.verticalCenter: parent.verticalCenter
            width: Math.max(20, parent.width - passwordBar.contentLeftMargin - passwordBar.contentRightMargin)
            text: {
                const sample = root.demoMode && root.buffer.length === 0 ? "••••••••" : root.buffer;
                if (root.showPasswordText)
                    return sample;
                return (root.isApple ? "\u25CF" : "•").repeat(sample.length);
            }
            color: root.isNativeContained ? Theme.surfaceText : root.contentColor
            font.family: Theme.fontFamily
            font.pixelSize: {
                if (root.showPasswordText)
                    return Math.max(11, Math.round(14 * root.generalScale));
                if (root.isApple)
                    return Math.max(7, Math.round(9 * root.generalScale));
                return Math.max(13, Math.round(18 * root.generalScale));
            }
            font.letterSpacing: root.isApple && !root.showPasswordText ? Math.round(4 * root.generalScale) : 1
            elide: Text.ElideLeft
            visible: (!root.isDots || root.showPasswordText) && (root.buffer.length > 0 || (root.demoMode && !root.isApple)) && !root.authenticating && !root.unlocking
        }

        // Blinking cursor
        Rectangle {
            id: cursor

            x: dotsText.x + (dotsText.visible ? Math.min(dotsText.contentWidth, dotsText.width) + 3 : 0)
            anchors.verticalCenter: parent.verticalCenter
            width: Math.max(1.5, Math.round(1.5 * root.generalScale))
            height: Math.round(19 * root.generalScale)
            radius: width / 2
            color: root.isApple ? root.contentColor : root.accentColor
            visible: !root.isDots && inputScope.activeFocus && !root.authenticating && !root.unlocking && !root.demoMode
            opacity: 1

            Timer {
                interval: 530
                running: cursor.visible
                repeat: true
                onTriggered: cursor.opacity = cursor.opacity > 0 ? 0 : 1
            }
        }

        // Native action button: Reveal password
        LockActionButton {
            id: nativeRevealButton
            anchors.right: nativeEnterButton.visible ? nativeEnterButton.left : (spinner.visible ? spinner.left : parent.right)
            anchors.rightMargin: 2
            anchors.verticalCenter: parent.verticalCenter
            iconName: root.showPasswordText ? "visibility_off" : "visibility"
            buttonSize: Math.max(24, Math.round(Theme.buttonHeightXS * root.generalScale))
            visible: !root.isApple && !root.isMinimal && root.showActionButtons && !root.demoMode && root.buffer.length > 0 && !root.authenticating && !root.unlocking
            enabled: visible
            onClicked: {
                root.showPasswordText = !root.showPasswordText;
                inputScope.forceActiveFocus();
            }
        }

        // Native action button: Submit / Enter
        LockActionButton {
            id: nativeEnterButton
            anchors.right: parent.right
            anchors.rightMargin: Math.round(4 * root.generalScale)
            anchors.verticalCenter: parent.verticalCenter
            iconName: "keyboard_return"
            buttonSize: Math.max(24, Math.round(Theme.buttonHeightXS * root.generalScale))
            visible: !root.isApple && !root.isMinimal && root.showActionButtons && !root.authenticating && !root.unlocking
            enabled: !root.demoMode && root.pillVisible
            onClicked: root.submit()
        }

        // Loading spinner (Apple & non-expressive native styles)
        DLoadingIndicator {
            id: spinner

            anchors.right: nativeEnterButton.visible ? nativeEnterButton.left : parent.right
            anchors.rightMargin: Math.round(14 * root.generalScale)
            anchors.verticalCenter: parent.verticalCenter
            size: Math.round(18 * root.generalScale)
            contained: false
            color: root.isApple ? root.contentColor : root.accentColor
            visible: !root.isExpressive && (root.authenticating || root.unlocking)
            running: visible
        }
    }

    // --- Feedback & Caps Lock -------------------------------------------
    Rectangle {
        id: feedbackBox

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: root.isRing ? nameText.bottom : passwordBar.bottom
        anchors.topMargin: Math.round(9 * root.generalScale)
        width: Math.min(root.width - 24, feedbackLabel.implicitWidth + 24)
        height: Math.round(27 * root.generalScale)
        radius: height / 2
        color: "#66000000"
        border.width: 1
        border.color: "#2EFFFFFF"
        visible: root.pillVisible && feedbackLabel.text.length > 0
        opacity: visible ? 1 : 0
        transform: Translate {
            x: root.shakeOffset
        }

        Behavior on opacity {
            NumberAnimation { duration: 180 }
        }

        Text {
            id: feedbackLabel

            anchors.centerIn: parent
            width: Math.min(implicitWidth, feedbackBox.width - 20)
            text: root.feedbackText()
            color: root.pamState === "fail" || root.pamState === "max" || root.pamState === "error" ? "#FFB4AB" : root.contentColor
            font.family: Theme.fontFamily
            font.pixelSize: Math.max(10, Math.round(12 * root.generalScale))
            elide: Text.ElideRight
            horizontalAlignment: Text.AlignHCenter
        }
    }

    Row {
        id: capsLockRow
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: feedbackBox.visible ? feedbackBox.bottom : (root.isRing ? nameText.bottom : passwordBar.bottom)
        anchors.topMargin: Math.round(6 * root.generalScale)
        spacing: 4
        opacity: DMSService.capsLockState && root.pillVisible ? 1 : 0

        DIcon {
            name: "shift_lock"
            size: Math.round(14 * root.generalScale)
            color: Theme.error
            anchors.verticalCenter: parent.verticalCenter
        }

        Text {
            text: I18n.tr("Caps Lock is on")
            font.family: Theme.fontFamily
            font.pixelSize: Math.max(10, Math.round(12 * root.generalScale))
            color: Theme.error
            anchors.verticalCenter: parent.verticalCenter
        }

        Behavior on opacity {
            NumberAnimation { duration: 180 }
        }
    }

    // --- Interaction ----------------------------------------------------
    HoverHandler {
        enabled: !root.demoMode
        onHoveredChanged: {
            if (hovered)
                root.reveal();
        }
    }

    MouseArea {
        anchors.fill: parent
        z: -1
        enabled: !root.demoMode
        acceptedButtons: Qt.LeftButton
        cursorShape: Qt.PointingHandCursor
        onClicked: {
            root.reveal();
            inputScope.forceActiveFocus();
        }
    }

    FocusScope {
        id: inputScope

        anchors.fill: parent
        focus: !root.demoMode
        enabled: !root.demoMode
        Keys.onPressed: event => root.handleKey(event)
    }

    // Focus can be stolen while the lock surface settles. Reclaim it a few
    // times during the first second so the first keystroke is never lost.
    Timer {
        id: focusRetry

        property int tries: 0

        interval: 120
        repeat: true
        running: false
        onTriggered: {
            if (inputScope.activeFocus || tries >= 12) {
                stop();
                return;
            }
            tries++;
            inputScope.forceActiveFocus();
        }
    }
}
