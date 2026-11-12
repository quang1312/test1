pragma ComponentBehavior: Bound

import QtQuick
import "components"

Rectangle {
    id: sldPanel
    implicitWidth: 1760
    implicitHeight: 960
    color: "#04111f"
    radius: 10
    border.color: "#1e3a5f"
    border.width: 1
    clip: true

    property var dataSource: null
    property var sldSource: null
    property var siteFactsSource: null
    property string factGridVoltageKv: "22kV"
    property string factPvTransformerRatio: "0.69/22kV"
    property string factBessTransformerRatio: "0.69/22kV"
    property string factLoadTransformerRatio: "22/0.4kV"

    property var devices: sldSource && sldSource.devices ? sldSource.devices : dataSource && dataSource.devices ? dataSource.devices : ({})
    property int dataTick: 0
    property string selectedKey: "bus"
    property bool detailOpen: false
    property string selectedTitle: "22kV Bus"
    property string selectedType: "Busbar"
    property bool tooltipVisible: false
    property string tooltipText: ""
    property real tooltipX: 0
    property real tooltipY: 0

    signal navigateToTab(string tabName)

    readonly property color bg: "#04111f"
    readonly property color panel: "#071827"
    readonly property color panel2: "#0b2237"
    readonly property color lineBase: "#d8e7f5"
    readonly property color textMain: "#eaf4ff"
    readonly property color textMuted: "#94a9c2"
    readonly property color cyan: "#38bdf8"
    readonly property color green: "#22c55e"
    readonly property color blue: "#3b82f6"
    readonly property color yellow: "#facc15"
    readonly property color red: "#ef4444"
    readonly property color gray: "#64748b"
    readonly property real designWidth: 1380
    readonly property real designHeight: 960
    readonly property real fitScale: Math.min(width / designWidth, height / designHeight)

    function device(key) {
        dataTick;
        var map = devices || {};
        return map && map[key] ? map[key] : {};
    }

    function availableGrids() {
        dataTick;
        return sldSource && sldSource.availableGrids ? sldSource.availableGrids : [];
    }

    function selectedGridIndex() {
        var grids = availableGrids();
        var selectedId = sldSource ? Number(sldSource.selectedGridId || 0) : 0;
        for (var i = 0; i < grids.length; i++) {
            if (Number(grids[i].id || 0) === selectedId)
                return i;
        }
        return grids.length > 0 ? 0 : -1;
    }

    function selectedGridTitle() {
        return sldSource && sldSource.selectedGridName ? sldSource.selectedGridName : "Main Grid";
    }

    function setSelectedGridByIndex(index) {
        var grids = availableGrids();
        if (!sldSource || index < 0 || index >= grids.length)
            return;
        sldSource.setSelectedGrid(Number(grids[index].id || 0));
    }

    function exists(value) {
        return value !== undefined && value !== null;
    }

    function numberText(value, digits) {
        if (!exists(value) || value === "")
            return "--";
        if (typeof value === "number")
            return value.toFixed(digits === undefined ? 2 : digits);
        return String(value);
    }

    function field(key, name, unit, digits) {
        var value = device(key)[name];
        var text = numberText(value, digits);
        return unit && text !== "--" ? text + " " + unit : text;
    }

    function powerField(key, name, bigUnit, absolute) {
        var raw = device(key)[name];
        if (!exists(raw) || raw === "")
            return "--";
        var mw = Number(raw);
        if (absolute)
            mw = Math.abs(mw);
        if (Math.abs(mw) < 10.0)
            return (mw * 1000).toFixed(0) + " k" + bigUnit.slice(1);
        return mw.toFixed(2) + " " + bigUnit;
    }

    function statusColor(status) {
        if (status === "Normal" || status === "Running" || status === "Closed" || status === "Healthy")
            return green;
        if (status === "Warning")
            return yellow;
        if (status === "Fault" || status === "Trip" || status === "Critical")
            return red;
        if (status === "Standby")
            return blue;
        return gray;
    }

    function isClosed(status) {
        return status === "Closed";
    }

    function branchClosed(key) {
        return isClosed(device(key).breakerStatus);
    }

    function branchPower(key) {
        var d = device(key);
        if (exists(d.flowMw))
            return Math.abs(Number(d.flowMw));
        if (key === "grid")
            return Math.abs(Number(d.pMw || 0));
        if (key === "bess")
            return Math.abs(Number(d.pcsPmw || 0));
        return Math.abs(Number(d.pMw || d.inverterAcMw || 0));
    }

    function flowActive(key) {
        return branchClosed(key) && branchPower(key) > 0.001 && device(key).status !== "Offline";
    }

    function flowColor(key) {
        var d = device(key);
        if (!branchClosed(key) || d.status === "Offline")
            return gray;
        if (d.status === "Fault" || d.breakerStatus === "Trip")
            return red;
        if (d.status === "Warning")
            return yellow;
        if (key === "bess" && Number(d.pcsPmw || 0) < -0.001)
            return blue;
        if (d.status === "Standby")
            return blue;
        return green;
    }

    function flowReverse(key) {
        if (key === "grid")
            return Number(device("grid").pMw || 0) < 0;
        if (key === "bess")
            return Number(device("bess").pcsPmw || 0) < -0.001;
        return false;
    }

    function flowDuration(key) {
        return Math.max(1800, Math.min(4600, 5200 / Math.max(0.24, branchPower(key))));
    }

    function breakerTip(key) {
        var d = device(key);
        return d.title + "\nStatus: " + (d.breakerStatus || d.status || "--") + "\nInterlock: " + (d.interlock || "--");
    }

    function openDetail(key, title, type) {
        selectedKey = key;
        selectedTitle = title || device(key).title || key;
        selectedType = type || "Device";
        tooltipVisible = false;
        detailOpen = true;
    }

    function showTooltip(text, xPos, yPos) {
        var nextX = xPos + 18;
        var nextY = yPos + 18;

        if (nextY < 168)
            nextY = 168;
        if (nextX < 300 && nextY < 360)
            nextX = 318;
        if (nextX + 286 > 1346)
            nextX = xPos - 304;
        if (nextY + 120 > 900)
            nextY = yPos - 132;

        tooltipText = text;
        tooltipX = Math.min(1050, Math.max(16, nextX));
        tooltipY = Math.min(880, Math.max(168, nextY));
        tooltipVisible = true;
    }

    function hideTooltip() {
        tooltipVisible = false;
    }

    function row(label, value) {
        return {"label": label, "value": value};
    }

    function detailRows(key) {
        dataTick;
        var d = device(key);
        if (key === "grid") {
            return [
                row("Grid status", d.status || "--"),
                row("Voltage", field(key, "voltageKv", "kV", 2)),
                row("Frequency", field(key, "frequencyHz", "Hz", 2)),
                row("Active power P", powerField(key, "pMw", "MW")),
                row("Reactive power Q", powerField(key, "qMvar", "MVar")),
                row("Power factor", field(key, "pf", "", 2)),
                row("Import today", field(key, "energyImportTodayMwh", "MWh", 2)),
                row("Export today", field(key, "energyExportTodayMwh", "MWh", 2)),
                row("Breaker", d.breakerStatus || "--"),
                row("Protection relay", d.relayStatus || "--"),
                row("Power flow", d.flowDirection || "--")
            ];
        }
        if (key === "bus") {
            return [
                row("Bus status", d.status || "--"),
                row("Bus voltage", field(key, "voltageKv", "kV", 2)),
                row("Bus frequency", field(key, "frequencyHz", "Hz", 2)),
                row("Total generation", powerField(key, "totalGenerationMw", "MW")),
                row("Total load", powerField(key, "totalLoadMw", "MW")),
                row("Net balance", powerField(key, "netPowerMw", "MW")),
                row("Synchronization", d.syncStatus || "--"),
                row("Power quality", d.powerQualityStatus || "--"),
                row("Alarm count", numberText(d.alarmCount, 0))
            ];
        }
        if (key === "pv") {
            return [
                row("PV DC power", powerField(key, "pvDcMw", "MW")),
                row("Irradiance", field(key, "irradiance", "W/m2", 0)),
                row("Inverter AC power", powerField(key, "inverterAcMw", "MW")),
                row("Inverter status", d.inverterStatus || "--"),
                row("DC voltage", field(key, "dcVoltage", "V", 0)),
                row("AC voltage", field(key, "acVoltageKv", "kV", 2)),
                row("Transformer loading", field(key, "transformerLoadingPct", "%", 1)),
                row("Transformer temp.", field(key, "transformerTempC", "degC", 1)),
                row("Breaker", d.breakerStatus || "--"),
                row("Generated today", field(key, "energyTodayMwh", "MWh", 2)),
                row("Alarm count", numberText(d.alarmCount, 0)),
                row("Power flow", d.flowDirection || "--")
            ];
        }
        if (key === "bess") {
            return [
                row("BESS status", d.status || "--"),
                row("SOC", field(key, "soc", "%", 1)),
                row("SOH", field(key, "soh", "%", 1)),
                row("Available energy", field(key, "availableEnergyMwh", "MWh", 2)),
                row("PCS active power", powerField(key, "pcsPmw", "MW", true)),
                row("PCS reactive power", powerField(key, "pcsQmvar", "MVar")),
                row("PCS mode", d.pcsMode || "--"),
                row("DC voltage", field(key, "dcVoltage", "V", 0)),
                row("AC voltage", field(key, "acVoltageKv", "kV", 2)),
                row("Transformer loading", field(key, "transformerLoadingPct", "%", 1)),
                row("Transformer temp.", field(key, "transformerTempC", "degC", 1)),
                row("Breaker", d.breakerStatus || "--"),
                row("Charged today", field(key, "energyChargedTodayMwh", "MWh", 2)),
                row("Discharged today", field(key, "energyDischargedTodayMwh", "MWh", 2)),
                row("Alarm count", numberText(d.alarmCount, 0)),
                row("Power flow", d.flowDirection || "--")
            ];
        }
        if (key === "load") {
            return [
                row("Load status", d.status || "--"),
                row("Active demand", powerField(key, "pMw", "MW")),
                row("Reactive power", powerField(key, "qMvar", "MVar")),
                row("Power factor", field(key, "pf", "", 2)),
                row("LV voltage", field(key, "voltageLvKv", "kV", 2)),
                row("Transformer loading", field(key, "transformerLoadingPct", "%", 1)),
                row("Transformer temp.", field(key, "transformerTempC", "degC", 1)),
                row("Consumed today", field(key, "energyConsumedTodayMwh", "MWh", 2)),
                row("Critical load", powerField(key, "criticalLoadMw", "MW")),
                row("Non-critical load", powerField(key, "nonCriticalLoadMw", "MW")),
                row("Breaker", d.breakerStatus || "--"),
                row("Alarm count", numberText(d.alarmCount, 0)),
                row("Power flow", d.flowDirection || "--")
            ];
        }
        if (key.indexOf("Transformer") >= 0) {
            return [
                row("Transformer status", d.status || "--"),
                row("Primary voltage", d.primaryVoltage || "--"),
                row("Secondary voltage", d.secondaryVoltage || "--"),
                row("Loading", field(key, "loadingPct", "%", 1)),
                row("Winding temp.", field(key, "windingTempC", "degC", 1)),
                row("Oil temperature", field(key, "oilTempC", "degC", 1)),
                row("Alarm status", d.alarmStatus || "--"),
                row("Trip status", d.tripStatus || "--")
            ];
        }
        if (key.indexOf("Breaker") >= 0) {
            return [
                row("Breaker status", d.breakerStatus || d.status || "--"),
                row("Command status", d.commandStatus || "--"),
                row("Interlock", d.interlock || "--"),
                row("Protection relay", d.protectionRelay || "--"),
                row("Trip cause", d.tripCause || "--")
            ];
        }
        return [row("No data", "--")];
    }

    Connections {
        target: sldPanel.dataSource
        function onDataChanged() {
            sldPanel.dataTick += 1;
        }
    }

    Connections {
        target: sldPanel.sldSource
        ignoreUnknownSignals: true
        function onDataChanged() {
            sldPanel.devices = sldPanel.sldSource && sldPanel.sldSource.devices ? sldPanel.sldSource.devices : ({});
            sldPanel.dataTick += 1;
        }

        function onSelectedGridChanged() {
            sldPanel.devices = sldPanel.sldSource && sldPanel.sldSource.devices ? sldPanel.sldSource.devices : ({});
            sldPanel.selectedKey = "bus";
            sldPanel.selectedTitle = sldPanel.factGridVoltageKv + " Bus";
            sldPanel.selectedType = "Busbar";
            sldPanel.dataTick += 1;
        }
    }

    function loadSiteFacts() {
        var facts = (sldPanel.siteFactsSource && sldPanel.siteFactsSource.siteFacts) || {};
        sldPanel.factGridVoltageKv = facts.gridVoltageKv || "22kV";
        sldPanel.factPvTransformerRatio = facts.pvTransformerRatio || "0.69/22kV";
        sldPanel.factBessTransformerRatio = facts.bessTransformerRatio || "0.69/22kV";
        sldPanel.factLoadTransformerRatio = facts.loadTransformerRatio || "22/0.4kV";
        sldPanel.selectedTitle = sldPanel.factGridVoltageKv + " Bus";
    }

    Connections {
        target: sldPanel.siteFactsSource
        ignoreUnknownSignals: true
        function onFactsChanged() {
            sldPanel.loadSiteFacts();
        }
    }

    Component.onCompleted: {
        sldPanel.loadSiteFacts();
    }

    Item {
        id: sheet
        width: sldPanel.designWidth
        height: sldPanel.designHeight
        x: (sldPanel.width - width * sldPanel.fitScale) / 2
        y: (sldPanel.height - height * sldPanel.fitScale) / 2
        scale: sldPanel.fitScale
        transformOrigin: Item.TopLeft

        Rectangle {
            anchors.fill: parent
            color: sldPanel.bg
            radius: 10
        }

        Rectangle {
            x: 18
            y: 12
            width: 1328
            height: 64
            radius: 8
            color: "#071a2c"
            border.color: "#174568"
            border.width: 1

            Text {
                x: 18
                y: 10
                text: "SINGLE LINE DIAGRAM - MICROGRID " + sldPanel.factGridVoltageKv
                color: sldPanel.textMain
                font.pixelSize: 22
                font.bold: true
            }

            Text {
                x: 20
                y: 38
                width: 610
                elide: Text.ElideRight
                text: "IEC-style vector SLD | Realtime source: " + (sldPanel.device("meta").source || "Simulated realtime") + " | Last update: " + (sldPanel.device("meta").timestamp || "--")
                color: sldPanel.textMuted
                font.pixelSize: 13
            }

            Row {
                x: 700
                y: 14
                spacing: 8
                LegendChip { label: "Normal"; chipColor: sldPanel.green }
                LegendChip { label: "Standby"; chipColor: sldPanel.blue }
                LegendChip { label: "Warning"; chipColor: sldPanel.yellow }
                LegendChip { label: "Fault/Trip"; chipColor: sldPanel.red }
            }

            FilterComboBox {
                id: gridSelector
                x: parent.width - width - 14
                y: 3
                width: 210
                height: 58
                visible: sldPanel.availableGrids().length > 0
                highlightOnFocus: false
                restingBorderColor: "#2c6f99"
                label: "Main Grid"
                model: sldPanel.availableGrids()
                textRole: "name"
                fallbackText: sldPanel.selectedGridTitle()
                currentIndex: sldPanel.selectedGridIndex()
                enabled: count > 1
                onActivated: function(index) {
                    sldPanel.setSelectedGridByIndex(index);
                }
            }
        }

        Row {
            id: kpiRow
            x: 24
            y: 86
            width: gridArea.width
            spacing: 10
        
            KpiTile { width: (kpiRow.width - kpiRow.spacing * 4) / 5; label: "GRID"; value: sldPanel.powerField("grid", "pMw", "MW"); note: sldPanel.device("grid").pMw >= 0 ? "Import" : "Export"; accent: sldPanel.flowColor("grid") }
            KpiTile { width: (kpiRow.width - kpiRow.spacing * 4) / 5; label: "PV"; value: sldPanel.powerField("pv", "inverterAcMw", "MW"); note: sldPanel.device("pv").inverterStatus || "--"; accent: sldPanel.flowColor("pv") }
            KpiTile { width: (kpiRow.width - kpiRow.spacing * 4) / 5; label: "BESS"; value: sldPanel.powerField("bess", "pcsPmw", "MW", true); note: sldPanel.device("bess").pcsMode || "--"; accent: sldPanel.flowColor("bess") }
            KpiTile { width: (kpiRow.width - kpiRow.spacing * 4) / 5; label: "LOAD"; value: sldPanel.powerField("load", "pMw", "MW"); note: "Demand"; accent: sldPanel.flowColor("load") }
            KpiTile { width: (kpiRow.width - kpiRow.spacing * 4) / 5; label: "BUS"; value: sldPanel.field("bus", "voltageKv", "kV", 2); note: sldPanel.device("bus").syncStatus || "--"; accent: sldPanel.statusColor(sldPanel.device("bus").status) }
        }

        Rectangle {
            id: gridArea
            x: 24
            y: 168
            width: 1322
            height: 760
            radius: 8
            color: "#03101d"
            border.color: "#123d5b"
            border.width: 1
        }

        Rectangle {
            id: busbar
            x: 304
            y: 324
            width: 1016
            height: 14
            radius: 3
            color: sldPanel.red
            border.color: "#fecaca"
            border.width: 1

            SequentialAnimation on opacity {
                running: sldPanel.device("bus").status === "Warning"
                loops: Animation.Infinite
                NumberAnimation { from: 0.72; to: 1.0; duration: 700 }
                NumberAnimation { from: 1.0; to: 0.72; duration: 700 }
            }
        }

        Hotspot {
            x: busbar.x
            y: busbar.y - 14
            width: busbar.width
            height: 42
            itemKey: "bus"
            title: sldPanel.factGridVoltageKv + " Bus"
            kind: "Busbar"
            tip: sldPanel.factGridVoltageKv + " BUS\nVoltage: " + sldPanel.field("bus", "voltageKv", "kV", 2) + "\nTotal load: " + sldPanel.powerField("bus", "totalLoadMw", "MW")
        }

        BusInfoCard {
            x: 570
            y: 220
            title: sldPanel.factGridVoltageKv + " BUS"
            status: sldPanel.device("bus").status || "--"
            line1: "V " + sldPanel.field("bus", "voltageKv", "kV", 2) + "  |  f " + sldPanel.field("bus", "frequencyHz", "Hz", 2)
            line2: "Gen " + sldPanel.powerField("bus", "totalGenerationMw", "MW") + "  |  Load " + sldPanel.powerField("bus", "totalLoadMw", "MW")
            line3: "Balance " + sldPanel.powerField("bus", "netPowerMw", "MW") + "  |  PQ " + (sldPanel.device("bus").powerQualityStatus || "--")
            accent: sldPanel.statusColor(sldPanel.device("bus").status)
        }

        Wire { x: 276; y: 188; width: 5; height: 66; branchKey: "grid"; lineColor: sldPanel.red }
        Wire { x: 276; y: 302; width: 5; height: 29; branchKey: "grid"; lineColor: sldPanel.red }
        Wire { x: 276; y: 326; width: 40; height: 5; branchKey: "grid"; lineColor: sldPanel.red }
        MeterSymbol { x: 248; y: 166; label: "M" }
        RelaySymbol { x: 316; y: 202; itemKey: "grid"; label: "87/50" }
        BreakerSymbol {
            x: 244
            y: 254
            itemKey: "gridBreaker"
            status: sldPanel.device("grid").breakerStatus || "Open"
            title: "Grid RMU"
        }

        GridSymbol {
            x: 42
            y: 188
            status: sldPanel.device("grid").status || "--"
            activePower: sldPanel.powerField("grid", "pMw", "MW")
            flowText: sldPanel.device("grid").flowDirection || "--"
        }

        Hotspot {
            x: 42
            y: 188
            width: 190
            height: 96
            itemKey: "grid"
            title: "Grid " + sldPanel.factGridVoltageKv
            kind: "Source"
            tip: "Grid " + sldPanel.factGridVoltageKv + "\nP: " + sldPanel.powerField("grid", "pMw", "MW") + "\nQ: " + sldPanel.powerField("grid", "qMvar", "MVar") + "\n" + (sldPanel.device("grid").flowDirection || "--")
        }

        property real pvX: 430
        property real bessX: 820
        property real loadX: 1210

        FeederLabel { x: sheet.pvX - 214; y: 350; title: "PV FEEDER"; subtitle: "" ; accent: sldPanel.flowColor("pv") }
        Wire { x: sheet.pvX - 2; y: 338; width: 5; height: 84; branchKey: "pv" }
        BreakerSymbol { x: sheet.pvX - 36; y: 420; itemKey: "pvBreaker"; status: sldPanel.device("pv").breakerStatus || "Open"; title: "PV RMU" }
        Wire { x: sheet.pvX - 2; y: 468; width: 5; height: 54; branchKey: "pv" }
        TransformerSymbol { x: sheet.pvX - 48; y: 520; itemKey: "pvTransformer"; title: "TX-PV"; ratio: sldPanel.factPvTransformerRatio; branchKey: "pv" }
        Wire { x: sheet.pvX - 2; y: 612; width: 5; height: 38; branchKey: "pv" }
        InverterSymbol { x: sheet.pvX - 74; y: 650; itemKey: "pv"; label: "PV INVERTER"; value: sldPanel.powerField("pv", "inverterAcMw", "MW"); branchKey: "pv" }
        Wire { x: sheet.pvX - 2; y: 714; width: 5; height: 36; branchKey: "pv" }
        PvArraySymbol { x: sheet.pvX - 96; y: 750; itemKey: "pv"; power: sldPanel.powerField("pv", "pvDcMw", "MWdc"); irradiance: sldPanel.field("pv", "irradiance", "W/m2", 0); branchKey: "pv" }

        FeederLabel { x: sheet.bessX - 214; y: 350; title: "BESS FEEDER"; subtitle: "" ; accent: sldPanel.flowColor("bess") }
        Wire { x: sheet.bessX - 2; y: 338; width: 5; height: 84; branchKey: "bess" }
        BreakerSymbol { x: sheet.bessX - 36; y: 420; itemKey: "bessBreaker"; status: sldPanel.device("bess").breakerStatus || "Open"; title: "BESS RMU" }
        Wire { x: sheet.bessX - 2; y: 468; width: 5; height: 54; branchKey: "bess" }
        TransformerSymbol { x: sheet.bessX - 48; y: 520; itemKey: "bessTransformer"; title: "TX-BESS"; ratio: sldPanel.factBessTransformerRatio; branchKey: "bess" }
        Wire { x: sheet.bessX - 2; y: 612; width: 5; height: 38; branchKey: "bess" }
        InverterSymbol { x: sheet.bessX - 74; y: 650; itemKey: "bess"; label: "PCS"; value: sldPanel.powerField("bess", "pcsPmw", "MW", true); branchKey: "bess" }
        Wire { x: sheet.bessX - 2; y: 714; width: 5; height: 36; branchKey: "bess" }
        BatterySymbol { x: sheet.bessX - 96; y: 750; itemKey: "bess"; soc: sldPanel.field("bess", "soc", "%", 1); mode: sldPanel.device("bess").pcsMode || "--"; branchKey: "bess" }

        FeederLabel { x: sheet.loadX - 214; y: 350; title: "LOAD FEEDER"; subtitle: "" ; accent: sldPanel.flowColor("load") }
        Wire { x: sheet.loadX - 2; y: 338; width: 5; height: 84; branchKey: "load" }
        BreakerSymbol { x: sheet.loadX - 36; y: 420; itemKey: "loadBreaker"; status: sldPanel.device("load").breakerStatus || "Open"; title: "LOAD RMU" }
        Wire { x: sheet.loadX - 2; y: 468; width: 5; height: 54; branchKey: "load" }
        TransformerSymbol { x: sheet.loadX - 48; y: 520; itemKey: "loadTransformer"; title: "TX-LOAD"; ratio: sldPanel.factLoadTransformerRatio; branchKey: "load" }
        Wire { x: sheet.loadX - 2; y: 612; width: 5; height: 70; branchKey: "load" }
        LoadSymbol { x: sheet.loadX - 96; y: 682; itemKey: "load"; demand: sldPanel.powerField("load", "pMw", "MW"); critical: sldPanel.powerField("load", "criticalLoadMw", "MW"); branchKey: "load" }

        PowerFlowArrow {
            fromX: 278
            fromY: sldPanel.flowReverse("grid") ? 326 : 188
            toX: 278
            toY: sldPanel.flowReverse("grid") ? 188 : 326
            arrowColor: sldPanel.flowColor("grid")
            active: sldPanel.flowActive("grid")
            duration: sldPanel.flowDuration("grid")
            arrowSize: 25
        }
        PowerFlowArrow {
            fromX: sheet.pvX
            fromY: 746
            toX: sheet.pvX
            toY: 326
            arrowColor: sldPanel.flowColor("pv")
            active: sldPanel.flowActive("pv")
            duration: sldPanel.flowDuration("pv")
            arrowSize: 25
        }
        PowerFlowArrow {
            fromX: sheet.bessX
            fromY: sldPanel.flowReverse("bess") ? 326 : 746
            toX: sheet.bessX
            toY: sldPanel.flowReverse("bess") ? 746 : 326
            arrowColor: sldPanel.flowColor("bess")
            active: sldPanel.flowActive("bess")
            duration: sldPanel.flowDuration("bess")
            arrowSize: 25
        }
        PowerFlowArrow {
            fromX: sheet.loadX
            fromY: 326
            toX: sheet.loadX
            toY: 680
            arrowColor: sldPanel.flowColor("load")
            active: sldPanel.flowActive("load")
            duration: sldPanel.flowDuration("load")
            arrowSize: 25
        }

        Row {
            x: 36
            y: 890
            spacing: 12
            LegendChip { label: "Green: generation / supply"; chipColor: sldPanel.green }
            LegendChip { label: "Blue: BESS charging"; chipColor: sldPanel.blue }
            LegendChip { label: "Yellow: standby / warning"; chipColor: sldPanel.yellow }
            LegendChip { label: "Red: fault / trip"; chipColor: sldPanel.red }
            LegendChip { label: "Gray: open / offline"; chipColor: sldPanel.gray }
        }

        Rectangle {
            id: tooltip
            x: sldPanel.tooltipX
            y: sldPanel.tooltipY
            width: Math.min(310, tooltipTextItem.implicitWidth + 24)
            height: tooltipTextItem.implicitHeight + 18
            radius: 6
            color: "#0b2237"
            border.color: sldPanel.cyan
            border.width: 1
            visible: sldPanel.tooltipVisible
            z: 1000

            Text {
                id: tooltipTextItem
                x: 12
                y: 9
                width: parent.width - 24
                text: sldPanel.tooltipText
                color: sldPanel.textMain
                font.pixelSize: 12
                wrapMode: Text.WordWrap
            }
        }

    }

    Rectangle {
        anchors.fill: parent
        visible: sldPanel.detailOpen
        color: "#000000aa"
        z: 3000
        MouseArea { anchors.fill: parent; onClicked: sldPanel.detailOpen = false }
    }

    Rectangle {
        id: detailPanel
        visible: sldPanel.detailOpen
        z: 3001
        anchors.centerIn: parent
        width: Math.min(760, sldPanel.width - 48)
        height: Math.min(360, sldPanel.height - 48)
        radius: 10
        color: "#071827"
        border.color: "#1f5f85"
        border.width: 1

        MouseArea { anchors.fill: parent }

        // Thanh trên cùng: chứa nút đóng, nằm ngoài khối header
        Item {
            id: detailTopBar
            x: 14
            y: 8
            width: parent.width - 28
            height: 34

            Rectangle {
                width: 30
                height: 30
                radius: 15
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                color: sldCloseMouse.containsMouse ? "#1e293b" : "#0b2237"
                border.color: sldPanel.textMuted
                Text { anchors.centerIn: parent; text: "✕"; color: sldPanel.textMain; font.pixelSize: 14; font.bold: true }
                MouseArea {
                    id: sldCloseMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: sldPanel.detailOpen = false
                }
            }
        }

        Rectangle {
            id: detailHeader
            x: 14
            y: detailTopBar.y + detailTopBar.height + 4
            width: parent.width - 28
            height: 90
            radius: 8
            color: "#0b2237"
            border.color: sldPanel.statusColor(sldPanel.device(sldPanel.selectedKey).status || sldPanel.device(sldPanel.selectedKey).breakerStatus)
            border.width: 1

            Text {
                x: 14
                y: 12
                width: parent.width - 28
                text: sldPanel.selectedTitle
                color: sldPanel.textMain
                font.pixelSize: 20
                font.bold: true
                elide: Text.ElideRight
            }

            Text {
                x: 14
                y: 42
                text: sldPanel.selectedType
                color: sldPanel.textMuted
                font.pixelSize: 13
            }

            StatusBadge {
                x: parent.width - width - 14
                y: 50
                label: sldPanel.device(sldPanel.selectedKey).status || sldPanel.device(sldPanel.selectedKey).breakerStatus || "--"
                badgeColor: sldPanel.statusColor(label)
            }
        }

        Flickable {
            id: detailFlick
            x: 14
            y: detailHeader.y + detailHeader.height + 12
            width: parent.width - 28
            height: parent.height - y - 14
            clip: true
            contentWidth: width
            contentHeight: detailGrid.height
            boundsBehavior: Flickable.StopAtBounds

            Grid {
                id: detailGrid
                width: detailFlick.width
                columns: 2
                columnSpacing: 12
                rowSpacing: 8

                Repeater {
                    model: sldPanel.detailRows(sldPanel.selectedKey)
                    delegate: DetailRow {
                        required property var modelData
                        width: (detailGrid.width - detailGrid.columnSpacing) / 2
                        label: modelData.label
                        value: modelData.value
                    }
                }
            }
        }
    }

    component Wire: Rectangle {
        property string branchKey: ""
        property color lineColor: sldPanel.flowColor(branchKey)
        color: lineColor
        opacity: sldPanel.branchClosed(branchKey) ? 0.96 : 0.28
        radius: Math.min(width, height) / 2
        border.color: "#e2e8f055"
        border.width: sldPanel.branchClosed(branchKey) ? 0 : 1
    }

    component Hotspot: MouseArea {
        property string itemKey: ""
        property string title: ""
        property string kind: "Device"
        property string tip: ""
        property string navigationTarget: ""
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor

        onEntered: {
            var p = mapToItem(sheet, width / 2, height / 2);
            sldPanel.showTooltip(tip, p.x, p.y);
        }
        onPositionChanged: function(mouse) {
            if (containsMouse) {
                var p = mapToItem(sheet, mouse.x, mouse.y);
                sldPanel.showTooltip(tip, p.x, p.y);
            }
        }
        onExited: sldPanel.hideTooltip()
        onClicked: function(mouse) {
            if (navigationTarget.length > 0) {
                sldPanel.hideTooltip();
                sldPanel.navigateToTab(navigationTarget);
            } else {
                sldPanel.openDetail(itemKey, title, kind);
            }
        }
    }

    component KpiTile: Rectangle {
        id: kpiTile
        property string label: ""
        property string value: ""
        property string note: ""
        property color accent: sldPanel.cyan
        width: 210
        height: 58
        radius: 8
        color: "#071827"
        border.color: accent
        border.width: 1

        Rectangle {
            x: 0
            y: 0
            width: 5
            height: parent.height
            radius: 2
            color: accent
        }

        Text {
            x: 14
            y: 8
            text: label
            color: sldPanel.textMuted
            font.pixelSize: 12
            font.bold: true
        }
        Text {
            x: 14
            y: 25
            width: 114
            text: value
            color: sldPanel.textMain
            font.pixelSize: 19
            font.bold: true
            elide: Text.ElideRight
        }
        Text {
            x: 130
            y: 30
            width: kpiTile.width - 140
            text: note
            color: accent
            font.pixelSize: 11
            horizontalAlignment: Text.AlignRight
            elide: Text.ElideRight
        }
    }

    component LegendChip: Row {
        property string label: ""
        property color chipColor: sldPanel.green
        spacing: 6
        height: 24

        Rectangle {
            width: 14
            height: 14
            radius: 3
            color: chipColor
            anchors.verticalCenter: parent.verticalCenter
        }
        Text {
            text: label
            color: sldPanel.textMain
            font.pixelSize: 12
            font.bold: true
            anchors.verticalCenter: parent.verticalCenter
        }
    }

    component StatusBadge: Rectangle {
        property string label: "--"
        property color badgeColor: sldPanel.gray
        width: Math.max(78, labelText.implicitWidth + 24)
        height: 26
        radius: 13
        color: badgeColor
        opacity: 0.94

        Text {
            id: labelText
            anchors.centerIn: parent
            text: label
            color: "#03101d"
            font.pixelSize: 12
            font.bold: true
        }
    }

    component DetailRow: Rectangle {
        property string label: ""
        property string value: ""
        height: Math.max(34, valueText.implicitHeight + 14)
        radius: 6
        color: "#0a1f33"
        border.color: "#173d5c"
        border.width: 1

        Text {
            x: 10
            y: 8
            width: 148
            text: label
            color: sldPanel.textMuted
            font.pixelSize: 12
            elide: Text.ElideRight
        }

        Text {
            id: valueText
            x: 160
            y: 8
            width: parent.width - 170
            text: value
            color: sldPanel.textMain
            font.pixelSize: 13
            font.bold: true
            wrapMode: Text.WordWrap
            horizontalAlignment: Text.AlignRight
        }
    }

    component BusInfoCard: Rectangle {
        id: busInfoCard
        property string title: ""
        property string status: ""
        property string line1: ""
        property string line2: ""
        property string line3: ""
        property color accent: sldPanel.green
        width: 340
        height: 88
        radius: 8
        color: "#071827dd"
        border.color: accent
        border.width: 1

        Text {
            x: 12
            y: 8
            width: parent.width - 120
            text: title
            color: sldPanel.textMain
            font.pixelSize: 16
            font.bold: true
            elide: Text.ElideRight
        }
        StatusBadge {
            x: parent.width - width - 10
            y: 8
            label: status
            badgeColor: accent
        }
        Text { x: 12; y: 34; width: busInfoCard.width - 24; text: line1; color: sldPanel.textMuted; font.pixelSize: 12; elide: Text.ElideRight }
        Text { x: 12; y: 52; width: busInfoCard.width - 24; text: line2; color: sldPanel.textMuted; font.pixelSize: 12; elide: Text.ElideRight }
        Text { x: 12; y: 70; width: busInfoCard.width - 24; text: line3; color: sldPanel.textMuted; font.pixelSize: 12; elide: Text.ElideRight }
    }

    component FeederLabel: Rectangle {
        property string title: ""
        property string subtitle: ""
        property color accent: sldPanel.green
        width: 180
        height: 42
        radius: 7
        color: "#071827"
        border.color: accent
        border.width: 1

        Text {
            x: 10
            y: 5
            text: title
            color: sldPanel.textMain
            font.pixelSize: 13
            font.bold: true
        }
        Text {
            x: 10
            y: 23
            width: parent.width - 20
            text: subtitle
            visible: subtitle.length > 0
            color: sldPanel.textMuted
            font.pixelSize: 10
            elide: Text.ElideRight
        }
    }

    component GridSymbol: Rectangle {
        id: gridSymbol
        property string status: ""
        property string activePower: ""
        property string flowText: ""
        width: 190
        height: 96
        radius: 10
        color: "#071827"
        border.color: sldPanel.statusColor(status)
        border.width: 1

        Text {
            x: 12
            y: 10
            width: 78
            text: "GRID " + sldPanel.factGridVoltageKv
            color: sldPanel.textMain
            font.pixelSize: 14
            font.bold: true
            elide: Text.ElideRight
        }
        StatusBadge {
            x: parent.width - width - 12
            y: 10
            label: status
            badgeColor: sldPanel.statusColor(status)
        }
        Text { x: 12; y: 38; width: 118; text: "P " + activePower; color: sldPanel.textMain; font.pixelSize: 16; font.bold: true; elide: Text.ElideRight }
        Text { x: 12; y: 66; width: 118; text: flowText; color: sldPanel.textMuted; font.pixelSize: 12; elide: Text.ElideRight }
        Canvas {
            x: 140
            y: 58
            width: 36
            height: 26
            opacity: 0.65
            onPaint: {
                var c = getContext("2d");
                c.clearRect(0, 0, width, height);
                c.strokeStyle = sldPanel.cyan;
                c.lineWidth = 2;
                c.beginPath();
                for (var i = 0; i < width; i++) {
                    var yv = height / 2 + Math.sin(i / width * Math.PI * 4) * 9;
                    if (i === 0) c.moveTo(i, yv); else c.lineTo(i, yv);
                }
                c.stroke();
            }
        }
    }

    component BreakerSymbol: Item {
        id: breaker
        property string itemKey: ""
        property string status: "Open"
        property string title: "RMU"
        width: 170
        height: 48

        Rectangle {
            width: 72
            height: 48
            radius: 5
            color: breaker.status === "Trip" ? "#3b0b12" : "#071827"
            border.color: sldPanel.statusColor(breaker.status)
            border.width: 2

            SequentialAnimation on opacity {
                running: breaker.status === "Trip"
                loops: Animation.Infinite
                NumberAnimation { from: 0.45; to: 1.0; duration: 430 }
                NumberAnimation { from: 1.0; to: 0.45; duration: 430 }
            }
        }

        Canvas {
            id: breakerCanvas
            x: 7
            y: 7
            width: 58
            height: 34
            onPaint: {
                var c = getContext("2d");
                c.clearRect(0, 0, width, height);
                c.strokeStyle = sldPanel.statusColor(breaker.status);
                c.lineWidth = 3;
                c.lineCap = "round";
                c.beginPath();
                c.arc(width / 2, 8, 4, 0, Math.PI * 2);
                c.arc(width / 2, height - 8, 4, 0, Math.PI * 2);
                c.stroke();
                c.beginPath();
                if (breaker.status === "Closed") {
                    c.moveTo(width / 2, 12);
                    c.lineTo(width / 2, height - 12);
                } else {
                    c.moveTo(width / 2, 12);
                    c.lineTo(width / 2 + 16, height - 15);
                }
                c.stroke();
                if (breaker.status === "Trip") {
                    c.strokeStyle = sldPanel.red;
                    c.lineWidth = 2.5;
                    c.beginPath();
                    c.moveTo(8, 6);
                    c.lineTo(width - 8, height - 6);
                    c.moveTo(width - 8, 6);
                    c.lineTo(8, height - 6);
                    c.stroke();
                }
            }
        }

        Rectangle {
            x: 78
            y: 14
            width: 82
            height: 20
            radius: 3
            color: "#03101dee"
            border.color: "#123d5b"
            border.width: 1
            z: 3

            Text {
                anchors.centerIn: parent
                width: parent.width - 6
                text: breaker.title
                color: sldPanel.textMuted
                font.pixelSize: 9
                font.bold: true
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
            }
        }

        onStatusChanged: breakerCanvas.requestPaint()

        Hotspot {
            anchors.fill: parent
            itemKey: breaker.itemKey
            title: breaker.title
            kind: "Breaker"
            tip: sldPanel.breakerTip(breaker.itemKey)
        }
    }

    component TransformerSymbol: Item {
        id: tx
        property string itemKey: ""
        property string title: ""
        property string ratio: ""
        property string branchKey: ""
        readonly property color canvasColor: sldPanel.flowColor(branchKey)
        width: 96
        height: 92

        Rectangle {
            anchors.fill: parent
            radius: 8
            color: "#071827"
            border.color: sldPanel.statusColor(sldPanel.device(itemKey).status || "Normal")
            border.width: 1
        }

        onCanvasColorChanged: txCanvas.requestPaint()

        Canvas {
            id: txCanvas
            x: 26
            y: 4
            width: 44
            height: 54
            onPaint: {
                var c = getContext("2d");
                c.clearRect(0, 0, width, height);
                c.strokeStyle = tx.canvasColor;
                c.lineWidth = 2;
                c.beginPath();
                c.arc(22, 20, 17, 0, Math.PI * 2);
                c.stroke();
                c.beginPath();
                c.arc(22, 34, 17, 0, Math.PI * 2);
                c.stroke();
            }
        }

        Text {
            x: 6
            y: 56
            width: parent.width - 12
            text: title
            color: sldPanel.textMain
            font.pixelSize: 11
            font.bold: true
            horizontalAlignment: Text.AlignHCenter
        }
        Text {
            x: 6
            y: 72
            width: parent.width - 12
            text: ratio
            color: sldPanel.textMuted
            font.pixelSize: 10
            horizontalAlignment: Text.AlignHCenter
        }

        Hotspot {
            anchors.fill: parent
            itemKey: tx.itemKey
            title: tx.title
            kind: "Transformer"
            tip: tx.title + "\nLoading: " + sldPanel.field(tx.itemKey, "loadingPct", "%", 1) + "\nWinding: " + sldPanel.field(tx.itemKey, "windingTempC", "degC", 1)
        }
    }

    component MeterSymbol: Item {
        property string label: "M"
        width: 58
        height: 44
        Rectangle {
            anchors.centerIn: parent
            width: 38
            height: 38
            radius: 19
            color: "#071827"
            border.color: sldPanel.cyan
            border.width: 2
        }
        Text {
            anchors.centerIn: parent
            text: label
            color: sldPanel.textMain
            font.pixelSize: 14
            font.bold: true
        }
    }

    component RelaySymbol: Rectangle {
        property string itemKey: ""
        property string label: "Relay"
        width: 74
        height: 38
        radius: 5
        color: "#071827"
        border.color: sldPanel.cyan
        border.width: 1

        Text {
            anchors.centerIn: parent
            text: label
            color: sldPanel.textMain
            font.pixelSize: 12
            font.bold: true
        }

        Hotspot {
            anchors.fill: parent
            itemKey: parent.itemKey
            title: "Protection Relay"
            kind: "Relay"
            tip: "Protection relay\nStatus: " + (sldPanel.device(parent.itemKey).relayStatus || "Healthy")
        }
    }

    component InverterSymbol: Rectangle {
        id: inv
        property string itemKey: ""
        property string label: ""
        property string value: ""
        property string branchKey: ""
        property string navigationTarget: ""
        readonly property color canvasColor: sldPanel.flowColor(branchKey)
        width: 148
        height: 64
        radius: 8
        color: "#071827"
        border.color: sldPanel.flowColor(branchKey)
        border.width: 1

        onCanvasColorChanged: invCanvas.requestPaint()

        Canvas {
            id: invCanvas
            x: 10
            y: 14
            width: 36
            height: 34
            onPaint: {
                var c = getContext("2d");
                c.clearRect(0, 0, width, height);
                c.strokeStyle = inv.canvasColor;
                c.lineWidth = 2;
                c.strokeRect(1, 1, width - 2, height - 2);
                c.beginPath();
                c.moveTo(4, height - 5);
                c.lineTo(width - 5, 5);
                c.stroke();
                c.font = "10px Arial";
                c.fillStyle = sldPanel.textMain;
                c.fillText("DC", 5, 13);
                c.fillText("AC", width - 20, height - 7);
            }
        }
        Text { x: 52; y: 12; width: 86; text: label; color: sldPanel.textMain; font.pixelSize: 12; font.bold: true; elide: Text.ElideRight }
        Text { x: 52; y: 34; width: 86; text: value; color: sldPanel.flowColor(branchKey); font.pixelSize: 13; font.bold: true; elide: Text.ElideRight }

        Hotspot {
            anchors.fill: parent
            itemKey: inv.itemKey
            title: inv.label
            kind: inv.label === "PCS" ? "PCS + BESS" : "PV Inverter"
            tip: inv.label + "\nPower: " + inv.value + "\nStatus: " + (sldPanel.device(inv.itemKey).pcsMode || sldPanel.device(inv.itemKey).inverterStatus || "--")
            navigationTarget: inv.navigationTarget
        }
    }

    component PvArraySymbol: Rectangle {
        id: pv
        property string itemKey: ""
        property string power: ""
        property string irradiance: ""
        property string branchKey: ""
        property string navigationTarget: ""
        readonly property color canvasColor: sldPanel.flowColor(branchKey)
        width: 192
        height: 92
        radius: 8
        color: "#071827"
        border.color: sldPanel.flowColor(branchKey)
        border.width: 1

        onCanvasColorChanged: pvCanvas.requestPaint()

        Canvas {
            id: pvCanvas
            x: 12
            y: 10
            width: 78
            height: 56
            onPaint: {
                var c = getContext("2d");
                c.clearRect(0, 0, width, height);
                c.strokeStyle = pv.canvasColor;
                c.lineWidth = 1.5;
                c.fillStyle = "#0f2d3f";
                c.fillRect(1, 1, width - 2, height - 2);
                c.strokeRect(1, 1, width - 2, height - 2);
                for (var i = 1; i < 4; i++) {
                    c.beginPath();
                    c.moveTo(i * width / 4, 1);
                    c.lineTo(i * width / 4, height - 1);
                    c.stroke();
                }
                for (var j = 1; j < 3; j++) {
                    c.beginPath();
                    c.moveTo(1, j * height / 3);
                    c.lineTo(width - 1, j * height / 3);
                    c.stroke();
                }
            }
        }
        Text { x: 100; y: 12; width: 82; text: "PV ARRAY"; color: sldPanel.textMain; font.pixelSize: 13; font.bold: true }
        Text { x: 100; y: 34; width: 82; text: power; color: sldPanel.flowColor(branchKey); font.pixelSize: 13; font.bold: true }
        Text { x: 100; y: 56; width: 82; text: irradiance; color: sldPanel.textMuted; font.pixelSize: 11; elide: Text.ElideRight }

        Hotspot {
            anchors.fill: parent
            itemKey: pv.itemKey
            title: "PV Feeder"
            kind: "PV"
            tip: "PV Array\nDC: " + pv.power + "\nIrradiance: " + pv.irradiance
            navigationTarget: pv.navigationTarget
        }
    }

    component BatterySymbol: Rectangle {
        id: batt
        property string itemKey: ""
        property string soc: ""
        property string mode: ""
        property string branchKey: ""
        property string navigationTarget: ""
        width: 192
        height: 92
        radius: 8
        color: "#071827"
        border.color: sldPanel.flowColor(branchKey)
        border.width: 1

        Rectangle {
            x: 14
            y: 18
            width: 86
            height: 48
            radius: 5
            color: "#082617"
            border.color: sldPanel.flowColor(batt.branchKey)
            border.width: 2
            Rectangle { x: parent.width; y: 14; width: 7; height: 20; radius: 2; color: parent.border.color }
            Rectangle {
                x: 5
                y: 5
                width: Math.max(3, (parent.width - 10) * Math.max(0, Math.min(100, Number(sldPanel.device("bess").soc || 0))) / 100)
                height: parent.height - 10
                radius: 3
                color: sldPanel.flowColor(batt.branchKey)
                opacity: 0.85
            }
        }
        Text { x: 112; y: 12; width: 70; text: "BESS"; color: sldPanel.textMain; font.pixelSize: 13; font.bold: true }
        Text { x: 112; y: 34; width: 70; text: "SOC " + soc; color: sldPanel.flowColor(branchKey); font.pixelSize: 13; font.bold: true }
        Text { x: 112; y: 56; width: 70; text: mode; color: sldPanel.textMuted; font.pixelSize: 11; elide: Text.ElideRight }

        Hotspot {
            anchors.fill: parent
            itemKey: batt.itemKey
            title: "BESS Feeder"
            kind: "BESS"
            tip: "BESS\nSOC: " + batt.soc + "\nMode: " + batt.mode + "\nPCS P: " + sldPanel.powerField("bess", "pcsPmw", "MW", true)
            navigationTarget: batt.navigationTarget
        }
    }

    component LoadSymbol: Rectangle {
        id: load
        property string itemKey: ""
        property string demand: ""
        property string critical: ""
        property string branchKey: ""
        readonly property color canvasColor: sldPanel.flowColor(branchKey)
        width: 192
        height: 132
        radius: 8
        color: "#071827"
        border.color: sldPanel.flowColor(branchKey)
        border.width: 1

        onCanvasColorChanged: loadCanvas.requestPaint()

        Canvas {
            id: loadCanvas
            x: 16
            y: 18
            width: 72
            height: 82
            onPaint: {
                var c = getContext("2d");
                c.clearRect(0, 0, width, height);
                c.strokeStyle = load.canvasColor;
                c.lineWidth = 2;
                c.strokeRect(12, 2, 48, 70);
                c.beginPath();
                c.moveTo(36, 72);
                c.lineTo(20, 82);
                c.moveTo(36, 72);
                c.lineTo(52, 82);
                c.stroke();
                c.fillStyle = load.canvasColor;
                c.fillRect(24, 18, 24, 8);
                c.fillRect(24, 34, 24, 8);
                c.fillRect(24, 50, 24, 8);
            }
        }
        Text { x: 100; y: 16; width: 82; text: "LOAD"; color: sldPanel.textMain; font.pixelSize: 14; font.bold: true }
        Text { x: 100; y: 40; width: 82; text: demand; color: sldPanel.flowColor(branchKey); font.pixelSize: 14; font.bold: true }
        Text { x: 100; y: 64; width: 82; text: "Critical"; color: sldPanel.textMuted; font.pixelSize: 11 }
        Text { x: 100; y: 82; width: 82; text: critical; color: sldPanel.textMain; font.pixelSize: 12; font.bold: true }

        Hotspot {
            anchors.fill: parent
            itemKey: load.itemKey
            title: "Load Feeder"
            kind: "Load"
            tip: "Load\nDemand: " + load.demand + "\nCritical: " + load.critical
        }
    }
}
