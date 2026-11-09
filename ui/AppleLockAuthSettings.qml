import QtQuick
import qs.Common
import qs.Services
import qs.Modules.Plugins

PluginSettings {
    id: root
    pluginId: "appleLockAuth"

    property string instanceId: ""
    property var instanceData: null

    function syncSetting(key, val) {
        SettingsData.setPluginSetting(root.pluginId, key, val);
        const lockInstances = SettingsData.lockScreenWidgetInstances || [];
        for (let i = 0; i < lockInstances.length; i++) {
            if (lockInstances[i].widgetType === root.pluginId) {
                const updates = {};
                updates[key] = val;
                SettingsData.updateDesktopWidgetInstanceConfig(lockInstances[i].id, updates);
            }
        }
        const greeterInstances = SettingsData.greeterWidgetInstances || [];
        for (let i = 0; i < greeterInstances.length; i++) {
            if (greeterInstances[i].widgetType === root.pluginId) {
                const updates = {};
                updates[key] = val;
                SettingsData.updateDesktopWidgetInstanceConfig(greeterInstances[i].id, updates);
            }
        }
    }

    SelectionSetting {
        settingKey: "barStyle"
        label: "Estilo de barra de contraseña"
        description: "Elige entre el estilo cristal de Apple (macOS) o los estilos nativos de Hyprland / DMS"
        options: [
            { label: "Apple (macOS Cristal)", value: "apple" },
            { label: "Expresivo (Nativo DMS)", value: "expressive" },
            { label: "Píldora (Nativo DMS)", value: "pill" },
            { label: "Puntos / Dots (Nativo DMS)", value: "dots" },
            { label: "Minimalista (Nativo DMS)", value: "minimal" },
            { label: "Anillo / Ring (Nativo DMS)", value: "ring" }
        ]
        defaultValue: "apple"
        onValueChanged: root.syncSetting("barStyle", value)
    }

    SliderSetting {
        settingKey: "generalScale"
        label: "Tamaño general (Barra e Icono)"
        description: "Escala proporcionalmente tanto el icono del perfil como la barra de contraseña"
        defaultValue: 115
        minimum: 60
        maximum: 180
        unit: "%"
        onValueChanged: root.syncSetting("generalScale", value)
    }

    SliderSetting {
        settingKey: "avatarSize"
        label: "Tamaño del icono de perfil"
        description: "Tamaño base circular del avatar de usuario"
        defaultValue: 96
        minimum: 44
        maximum: 150
        unit: "px"
        onValueChanged: root.syncSetting("avatarSize", value)
    }

    SliderSetting {
        settingKey: "barWidth"
        label: "Ancho de la barra"
        description: "Longitud horizontal base del campo de contraseña"
        defaultValue: 240
        minimum: 160
        maximum: 440
        unit: "px"
        onValueChanged: root.syncSetting("barWidth", value)
    }

    SliderSetting {
        settingKey: "barHeight"
        label: "Alto de la barra"
        description: "Grosor vertical base del campo de contraseña"
        defaultValue: 44
        minimum: 32
        maximum: 72
        unit: "px"
        onValueChanged: root.syncSetting("barHeight", value)
    }

    ToggleSetting {
        settingKey: "showActionButtons"
        label: "Botones de acción en estilos nativos"
        description: "Muestra los botones de mostrar contraseña y enviar (Enter) en los estilos nativos"
        defaultValue: true
        onValueChanged: root.syncSetting("showActionButtons", value)
    }
}
