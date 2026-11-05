pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls.Basic as Basic
import "components"

Rectangle {
    id: root

    property var dataSource: null
    property int dataRevision: 0
    property string selectedFacility: "All Facilities"
    property string selectedMetric: "kW"
    property string selectedWindow: "1h"
    property string selectedFromDate: Qt.formatDate(new Date(), "dd/MM/yyyy")
    property string selectedToDate: Qt.formatDate(new Date(), "dd/MM/yyyy")
    property string selectedStartTime: "00:00"
    property string selectedEndTime: "23:59"
    property string chartMode: "Line"
    property bool autoRefresh: true
    property real zoomLevel: 1.0
    property string statusMessage: ""
    property var frozenSnapshot: ({})
    property real boardScale: Math.min(width / board.width, height / board.height)

    readonly property color bgColor: "#031624"
    readonly property color panelColor: "#071c2b"
    readonly property color panelHeaderColor: "#092235"
    readonly property color cardColor: "#082034"
    readonly property color lineColor: "#16415f"
    readonly property color textColor: "#eef6ff"
    readonly property color mutedTextColor: "#9db2c5"
    readonly property color blueColor: "#128cff"
    readonly property color cyanColor: "#20c7d7"
    readonly property color greenColor: "#3bd15b"
    readonly property color yellowColor: "#ffc323"
    readonly property color orangeColor: "#f59e0b"
    readonly property color redColor: "#ff4038"
    readonly property color violetColor: "#8b5cf6"

    color: bgColor
    radius: 8
    border.color: "#12324b"
    border.width: 1
    clip: true

    ListModel {
        id: feederModel
    }

    function numberValue(value, fallbackValue) {
        var n = Number(value);
        return isNaN(n) ? fallbackValue : n;
    }

    function clamp(value, minValue, maxValue) {
        return Math.max(minValue, Math.min(maxValue, value));
    }

    function fmt(value, digits) {
        return numberValue(value, 0).toFixed(digits);
    }

    function comma(value, digits) {
        var text = fmt(value, digits);
        var parts = text.split(".");
        var sign = "";
        if (parts[0].charAt(0) === "-") {
            sign = "-";
            parts[0] = parts[0].substring(1);
        }
        var out = "";
        while (parts[0].length > 3) {
            out = "," + parts[0].slice(-3) + out;
            parts[0] = parts[0].slice(0, -3);
        }
        out = sign + parts[0] + out;
        return parts.length > 1 ? out + "." + parts[1] : out;
    }

    function isDash(value) {
        return value === null || value === undefined;
    }

    function fmtOrDash(value, digits) {
        return isDash(value) ? "--" : fmt(value, digits);
    }

    function commaOrDash(value, digits) {
        return isDash(value) ? "--" : comma(value, digits);
    }

    function requestSnapshot() {
        if (dataSource && dataSource.powerMonitoringSnapshot)
            return dataSource.powerMonitoringSnapshot(selectedFacility, "ALL", selectedWindow, zoomLevel, selectedFromDate, selectedToDate, selectedStartTime, selectedEndTime);
        return {
            powerHistory: [],
            summary: {},
            kpis: [],
            trendRows: [],
            feederRows: [],
            phaseVoltageRows: [],
            phaseCurrentRows: [],
            harmonicRows: [],
            qualityRows: []
        };
    }

    function computeSnapshot() {
        dataRevision;
        if (!autoRefresh && frozenSnapshot && frozenSnapshot.kpis)
            return frozenSnapshot;
        return requestSnapshot();
    }

    property var currentSnapshot: computeSnapshot()
    onCurrentSnapshotChanged: root.syncFeederModel(root.feederRows())

    function snapshot() {
        return currentSnapshot;
    }

    function syncFeederModel(newRows) {
        // Xoá row không còn tồn tại trong dữ liệu mới (thiết bị bị lọc/mất khỏi topology)
        for (var i = feederModel.count - 1; i >= 0; i--) {
            var sid = feederModel.get(i).sourceId;
            var stillExists = false;
            for (var n = 0; n < newRows.length; n++) {
                if (newRows[n].sourceId === sid) { stillExists = true; break; }
            }
            if (!stillExists)
                feederModel.remove(i);
        }

        for (var j = 0; j < newRows.length; j++) {
            var row = newRows[j];
            var idx = -1;
            for (var k = 0; k < feederModel.count; k++) {
                if (feederModel.get(k).sourceId === row.sourceId) { idx = k; break; }
            }
            if (idx === -1) {
                feederModel.insert(j, { sourceId: row.sourceId, rowData: row });
            } else {
                feederModel.set(idx, { sourceId: row.sourceId, rowData: row });
                if (idx !== j)
                    feederModel.move(idx, j, 1);
            }
        }
    }

    function powerHistory() {
        return snapshot().powerHistory || [];
    }

    function latestPoint() {
        var rows = powerHistory();
        if (rows.length > 0)
            return rows[rows.length - 1];
        return {};
    }

    function feederRows() {
        return snapshot().feederRows || [];
    }

    function currentSummary() {
        return snapshot().summary || {};
    }

    function kpiCards() {
        return snapshot().kpis || [];
    }

    function metricUnit() {
        if (selectedMetric === "kW")
            return "kW";
        if (selectedMetric === "kvar")
            return "kvar";
        if (selectedMetric === "kVA")
            return "kVA";
        return "PF";
    }

    function trendRows() {
        return snapshot().trendRows || [];
    }

    function trendNote() {
        return snapshot().trendNote || "";
    }

    function phaseVoltageRows() {
        return snapshot().phaseVoltageRows || [];
    }

    function phaseCurrentRows() {
        return snapshot().phaseCurrentRows || [];
    }

    function avgValue(rows) {
        var sum = 0;
        for (var i = 0; i < rows.length; i++)
            sum += rows[i].value;
        return sum / Math.max(1, rows.length);
    }

    function minValue(rows) {
        var minV = rows.length > 0 ? rows[0].value : 0;
        for (var i = 1; i < rows.length; i++)
            minV = Math.min(minV, rows[i].value);
        return minV;
    }

    function maxValue(rows) {
        var maxV = rows.length > 0 ? rows[0].value : 0;
        for (var i = 1; i < rows.length; i++)
            maxV = Math.max(maxV, rows[i].value);
        return maxV;
    }

    function unbalancePct(rows) {
        var avg = Math.max(0.001, avgValue(rows));
        var spread = maxValue(rows) - minValue(rows);
        return spread / avg * 100;
    }

    function harmonicRows() {
        return snapshot().harmonicRows || [];
    }

    function qualityRows() {
        return snapshot().qualityRows || [];
    }

    function deviceOptions() {
        dataRevision;
        if (dataSource && dataSource.deviceOptions)
            return dataSource.deviceOptions();
        return ["All Facilities"];
    }

    function gridOptions() {
        dataRevision;
        var grids = (dataSource && dataSource.availableGrids) ? dataSource.availableGrids : [];
        var names = [];
        for (var i = 0; i < grids.length; i++)
            names.push(grids[i].name || ("Grid " + grids[i].id));
        return names.length > 0 ? names : ["Main Grid"];
    }

    function selectedGridLabel() {
        dataRevision;
        return (dataSource && dataSource.selectedGridName) ? dataSource.selectedGridName : "Main Grid";
    }

    function selectGridByName(name) {
        var grids = (dataSource && dataSource.availableGrids) ? dataSource.availableGrids : [];
        for (var i = 0; i < grids.length; i++) {
            if ((grids[i].name || "") === name) {
                dataSource.setSelectedGrid(Number(grids[i].id || 0));
                return;
            }
        }
    }

    // The four trend lines are always drawn together; the metric tab only chooses
    // which of them the left (Y) axis is scaled to.
    function selectMetric(metric) {
        selectedMetric = metric;
        showStatus("Y axis: " + metricUnit());
    }

    function metricColor(metric) {
        if (metric === "kvar") return greenColor;
        if (metric === "kVA") return violetColor;
        if (metric === "PF") return orangeColor;
        return blueColor;
    }

    function selectWindow(value) {
        selectedWindow = value;
        showStatus("Time window: " + value);
    }

    function selectedTimeRange() {
        return selectedStartTime + " - " + selectedEndTime;
    }

    function selectedDateRange() {
        return selectedFromDate === selectedToDate ? selectedFromDate : selectedFromDate + " - " + selectedToDate;
    }

    function setDateTimeRange(fromDateValue, toDateValue, startValue, endValue) {
        selectedFromDate = fromDateValue;
        selectedToDate = toDateValue;
        selectedStartTime = startValue;
        selectedEndTime = endValue;
        bumpDataRevision();
        showStatus("Time range: " + selectedDateRange() + " " + selectedTimeRange());
    }

    function refreshNow() {
        frozenSnapshot = requestSnapshot();
        bumpDataRevision();
        showStatus("Power monitoring refreshed: " + Qt.formatTime(new Date(), "HH:mm:ss"));
    }

    function setAutoRefresh(enabled) {
        autoRefresh = enabled;
        if (!enabled)
            frozenSnapshot = requestSnapshot();
        else
            frozenSnapshot = ({});
        bumpDataRevision();
        showStatus(enabled ? "Auto refresh enabled" : "Auto refresh paused");
    }

    function zoomIn() {
        zoomLevel = Math.min(3.0, zoomLevel * 1.25);
        bumpDataRevision();
        showStatus("Zoom: " + fmt(zoomLevel, 2) + "x");
    }

    function zoomOut() {
        zoomLevel = Math.max(0.75, zoomLevel / 1.25);
        bumpDataRevision();
        showStatus("Zoom: " + fmt(zoomLevel, 2) + "x");
    }

    function toggleChartMode() {
        chartMode = chartMode === "Line" ? "Area" : "Line";
        bumpDataRevision();
        showStatus("Chart mode: " + chartMode);
    }

    function showStatus(message) {
        statusMessage = message;
        statusTimer.restart();
    }

    function bumpDataRevision() {
        var saveY = feederListView.contentY;
        dataRevision++;
        Qt.callLater(function() {
            var maxY = Math.max(0, feederListView.contentHeight - feederListView.height);
            feederListView.contentY = Math.min(saveY, maxY);
        });
    }

    function scheduleRefresh() {
        if (!refreshCoalesceTimer.running)
            refreshCoalesceTimer.start();
    }

    Timer {
        id: refreshCoalesceTimer
        interval: 700
        repeat: false
        onTriggered: root.bumpDataRevision();
    }

    Connections {
        target: root.dataSource
        ignoreUnknownSignals: true
        function onDataChanged() {
            if (root.autoRefresh)
                root.scheduleRefresh();
        }
    }

    Timer {
        id: statusTimer
        interval: 2600
        repeat: false
        onTriggered: root.statusMessage = ""
    }

    Repeater {
        model: 44
        Rectangle {
            required property int index
            x: index * 42
            width: 1
            height: parent.height
            color: "#0d2a40"
            opacity: 0.38
        }
    }

    Repeater {
        model: 34
        Rectangle {
            required property int index
            y: index * 36
            width: parent.width
            height: 1
            color: "#0d2a40"
            opacity: 0.24
        }
    }

    Item {
        id: board
        width: 1780
        height: 1120
        anchors.centerIn: parent
        scale: root.boardScale

        FilterCombo {
            x: 0
            y: 0
            width: 190
            height: 40
            z: 20
            value: root.selectedGridLabel()
            options: root.gridOptions()
            onSelected: function(value) {
                root.selectGridByName(value);
                root.bumpDataRevision();
                root.showStatus("Main Grid: " + value);
            }
        }

        Row {
            x: 716
            y: 0
            height: 40
            spacing: 14
            z: 20

            FilterCombo {
                width: 162
                value: root.selectedFacility
                options: root.deviceOptions()
                onSelected: function(value) {
                    root.selectedFacility = value;
                    root.bumpDataRevision();
                    root.showStatus("Facility: " + value);
                }
            }
            DateTimeRangePicker {
                width: 608
                fromDate: root.selectedFromDate
                toDate: root.selectedToDate
                startTime: root.selectedStartTime
                endTime: root.selectedEndTime
                textColor: root.textColor
                mutedTextColor: root.mutedTextColor
                accentColor: root.blueColor
                fieldColor: "#071827"
                hoverColor: "#0a2438"
                borderColor: "#173852"
                onRangeEdited: function(fromDateValue, toDateValue, startValue, endValue) {
                    root.setDateTimeRange(fromDateValue, toDateValue, startValue, endValue);
                }
            }
            IconButton {
                width: 40
                iconText: "R"
                tooltip: "Refresh"
                onClicked: root.refreshNow()
            }
            Text {
                height: 36
                text: "Auto Refresh"
                color: root.textColor
                font.pixelSize: 13
                font.bold: true
                verticalAlignment: Text.AlignVCenter
            }
            ToggleSwitch {
                checked: root.autoRefresh
                onToggled: function(value) { root.setAutoRefresh(value); }
            }
        }

        Rectangle {
            x: 1220
            y: 44
            width: 520
            height: 26
            radius: 5
            visible: root.statusMessage.length > 0
            color: "#08243a"
            border.color: root.blueColor
            border.width: 1
            z: 30
            Text {
                anchors.fill: parent
                anchors.leftMargin: 12
                anchors.rightMargin: 12
                text: root.statusMessage
                color: "#ccecff"
                font.pixelSize: 12
                font.bold: true
                verticalAlignment: Text.AlignVCenter
                elide: Text.ElideRight
            }
        }

        Row {
            id: kpiRow
            x: 0
            y: 52
            spacing: 10

            Repeater {
                model: 6
                KpiCard {
                    id: kpiDelegate
                    required property int index
                    readonly property var cardData: root.kpiCards()[kpiDelegate.index] || ({})
                    width: 288
                    height: 156
                    title: cardData.title || ""
                    value: cardData.value || ""
                    unitText: cardData.unit || ""
                    iconText: cardData.icon || ""
                    accent: cardData.accent || root.blueColor
                    delta: cardData.delta
                    metric: cardData.metric || "active"
                    points: cardData.spark || []
                }
            }
        }

        PanelCard {
            x: 0
            y: 228
            width: 880
            height: 408
            title: "POWER TREND"

            Row {
                x: 18
                y: 54
                height: 30
                spacing: 6
                MetricTab { label: "kW"; selected: root.selectedMetric === "kW"; onClicked: root.selectMetric("kW") }
                MetricTab { label: "kvar"; selected: root.selectedMetric === "kvar"; onClicked: root.selectMetric("kvar") }
                MetricTab { label: "kVA"; selected: root.selectedMetric === "kVA"; onClicked: root.selectMetric("kVA") }
                MetricTab { label: "PF"; selected: root.selectedMetric === "PF"; onClicked: root.selectMetric("PF") }
            }

            Row {
                x: parent.width - 326
                y: 54
                height: 30
                spacing: 5
                TimeTab { label: "15m"; selected: root.selectedWindow === "15m"; onClicked: root.selectWindow("15m") }
                TimeTab { label: "1h"; selected: root.selectedWindow === "1h"; onClicked: root.selectWindow("1h") }
                TimeTab { label: "1D"; selected: root.selectedWindow === "1D"; onClicked: root.selectWindow("1D") }
                TimeTab { label: "1W"; selected: root.selectedWindow === "1W"; onClicked: root.selectWindow("1W") }
                TimeTab { label: "1M"; selected: root.selectedWindow === "1M"; onClicked: root.selectWindow("1M") }
                IconButton { width: 28; height: 28; iconText: "+"; tooltip: "Zoom in"; onClicked: root.zoomIn() }
                IconButton { width: 28; height: 28; iconText: "-"; tooltip: "Zoom out"; onClicked: root.zoomOut() }
                IconButton { width: 28; height: 28; iconText: "..."; tooltip: "Chart mode"; onClicked: root.toggleChartMode() }
            }

            TrendChart {
                x: 24
                y: 104
                width: parent.width - 48
                height: 238
                rows: root.trendRows()
                metric: root.selectedMetric
                unitText: root.metricUnit()
                mode: root.chartMode
                visible: root.trendRows().length > 0
            }

            Text {
                x: 24
                y: 104
                width: parent.width - 48
                height: 238
                visible: root.trendRows().length === 0
                text: root.trendNote() || "No historical PQM data"
                color: root.mutedTextColor
                font.pixelSize: 13
                font.bold: true
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                wrapMode: Text.WordWrap
            }

            Row {
                x: 70
                y: parent.height - 38
                spacing: 28
                Repeater {
                    model: ["kW", "kvar", "kVA", "PF"]
                    delegate: LegendDot {
                        required property string modelData
                        label: modelData + (modelData === root.selectedMetric ? "  (Y axis)" : "")
                        accent: root.metricColor(modelData)
                        opacity: modelData === root.selectedMetric ? 1.0 : 0.65
                    }
                }
                LegendDot { label: root.selectedWindow + " window"; accent: root.cyanColor }
                LegendDot { label: root.chartMode; accent: root.yellowColor }
            }
        }

        PanelCard {
            x: 892
            y: 228
            width: 408
            height: 408
            title: "PHASE VOLTAGE (V)"

            PhaseBarChart {
                x: 26
                y: 78
                width: parent.width - 52
                height: 218
                rows: root.phaseVoltageRows()
                maxHint: Math.max(400, root.maxValue(root.phaseVoltageRows()) * 1.22)
                decimals: 0
            }

            Row {
                x: 24
                y: parent.height - 72
                spacing: 10
                StatMini { width: 84; label: "Avg Voltage"; value: root.phaseVoltageRows().length === 0 ? "--" : root.fmt(root.avgValue(root.phaseVoltageRows()) / 1000, 2) + " kV" }
                StatMini { width: 84; label: "Max Voltage"; value: root.phaseVoltageRows().length === 0 ? "--" : root.fmt(root.maxValue(root.phaseVoltageRows()) / 1000, 2) + " kV" }
                StatMini { width: 84; label: "Min Voltage"; value: root.phaseVoltageRows().length === 0 ? "--" : root.fmt(root.minValue(root.phaseVoltageRows()) / 1000, 2) + " kV" }
                StatMini { width: 84; label: "Unbalance"; value: root.phaseVoltageRows().length === 0 ? "--" : root.fmt(root.unbalancePct(root.phaseVoltageRows()), 2) + " %" }
            }
        }

        PanelCard {
            x: 1312
            y: 228
            width: 468
            height: 408
            title: "PHASE CURRENT (A)"

            PhaseBarChart {
                x: 26
                y: 78
                width: parent.width - 52
                height: 218
                rows: root.phaseCurrentRows()
                maxHint: Math.max(40, root.maxValue(root.phaseCurrentRows()) * 1.25)
                decimals: 1
            }

            Row {
                x: 24
                y: parent.height - 72
                spacing: 10
                StatMini { width: 96; label: "Avg Current"; value: root.phaseCurrentRows().length === 0 ? "--" : root.fmt(root.avgValue(root.phaseCurrentRows()), 1) + " A" }
                StatMini { width: 96; label: "Max Current"; value: root.phaseCurrentRows().length === 0 ? "--" : root.fmt(root.maxValue(root.phaseCurrentRows()), 1) + " A" }
                StatMini { width: 96; label: "Min Current"; value: root.phaseCurrentRows().length === 0 ? "--" : root.fmt(root.minValue(root.phaseCurrentRows()), 1) + " A" }
                StatMini { width: 96; label: "Unbalance"; value: root.phaseCurrentRows().length === 0 ? "--" : root.fmt(root.unbalancePct(root.phaseCurrentRows()), 1) + " %" }
            }
        }

        PanelCard {
            x: 0
            y: 648
            width: 1130
            height: 410
            title: "PQM DEVICE SUMMARY"

            Row {
                x: 18
                y: 58
                height: 34
                HeaderCell { width: 144; text: "DEVICE" }
                HeaderCell { width: 76; text: "STATUS"; align: Text.AlignHCenter }
                HeaderCell { width: 198; text: "VOLTAGE (V)"; align: Text.AlignHCenter }
                HeaderCell { width: 198; text: "CURRENT (A)"; align: Text.AlignHCenter }
                HeaderCell { width: 112; text: "ACTIVE\n(kW)"; align: Text.AlignRight }
                HeaderCell { width: 112; text: "REACTIVE\n(kvar)"; align: Text.AlignRight }
                HeaderCell { width: 76; text: "PF"; align: Text.AlignRight }
                HeaderCell { width: 104; text: "FREQ\n(Hz)"; align: Text.AlignRight }
                HeaderCell { width: 72; text: "THD-I\n(%)"; align: Text.AlignRight }
            }

            ListView {
                id: feederListView
                x: 18
                y: 94
                width: parent.width - 36
                height: parent.height - 58 - 94 - 8
                clip: true
                spacing: 0
                boundsBehavior: Flickable.StopAtBounds
                model: feederModel
                delegate: FeederRow {
                    id: feederDelegate
                    required property var model
                    required property int index
                    width: feederDelegate.ListView.view.width
                    rowData: feederDelegate.model.rowData
                    rowIndex: feederDelegate.index
                }
                Basic.ScrollIndicator.vertical: Basic.ScrollIndicator {}
            }

            Rectangle {
                x: 18
                y: parent.height - 58
                width: parent.width - 36
                height: 42
                radius: 6
                color: "#08243a"
                border.color: "#0d3d61"
                border.width: 1
                Row {
                    anchors.fill: parent
                    anchors.leftMargin: 8
                    anchors.rightMargin: 8
                    Text { width: 608; height: parent.height; text: "TOTAL"; color: root.blueColor; font.pixelSize: 13; font.bold: true; verticalAlignment: Text.AlignVCenter }
                    Text { width: 112; height: parent.height; text: root.commaOrDash(root.currentSummary().activeKw, 0); color: root.textColor; font.pixelSize: 13; font.bold: true; horizontalAlignment: Text.AlignRight; verticalAlignment: Text.AlignVCenter }
                    Text { width: 112; height: parent.height; text: root.commaOrDash(root.currentSummary().reactiveKvar, 0); color: root.textColor; font.pixelSize: 13; font.bold: true; horizontalAlignment: Text.AlignRight; verticalAlignment: Text.AlignVCenter }
                    Text { width: 76; height: parent.height; text: root.fmtOrDash(root.currentSummary().pf, 2); color: root.textColor; font.pixelSize: 13; font.bold: true; horizontalAlignment: Text.AlignRight; verticalAlignment: Text.AlignVCenter }
                    Text { width: 104; height: parent.height; text: root.fmtOrDash(root.currentSummary().frequency, 2); color: root.textColor; font.pixelSize: 13; font.bold: true; horizontalAlignment: Text.AlignRight; verticalAlignment: Text.AlignVCenter }
                    Text { width: 72; height: parent.height; text: root.fmtOrDash(root.currentSummary().thd, 1); color: root.textColor; font.pixelSize: 13; font.bold: true; horizontalAlignment: Text.AlignRight; verticalAlignment: Text.AlignVCenter }
                }
            }
        }

        PanelCard {
            x: 1142
            y: 648
            width: 638
            height: 248
            title: "HARMONICS (CURRENT THD %)"

            HarmonicsChart {
                x: 24
                y: 62
                width: parent.width - 48
                height: 158
                rows: root.harmonicRows()
            }
        }

        PanelCard {
            x: 1142
            y: 908
            width: 638
            height: 150
            title: "POWER QUALITY"

            Row {
                x: 16
                y: 56
                spacing: 12
                Repeater {
                    model: root.qualityRows()
                    QualityTile {
                        required property var modelData
                        width: 92
                        label: modelData.label
                        value: modelData.value
                        ok: modelData.ok
                    }
                }
            }
        }
    }

    component PanelCard: Rectangle {
        id: panel
        default property alias content: contentLayer.data
        property string title: ""

        radius: 8
        color: root.panelColor
        border.color: "#143a56"
        border.width: 1
        clip: true

        Rectangle {
            x: 1
            y: 1
            width: parent.width - 2
            height: 49
            radius: 7
            color: root.panelHeaderColor
        }
        Rectangle {
            y: 49
            width: parent.width
            height: 1
            color: root.lineColor
        }
        Text {
            x: 16
            y: 15
            width: parent.width - 32
            height: 20
            text: panel.title
            color: root.textColor
            font.pixelSize: 16
            font.bold: true
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
        }
        Item {
            id: contentLayer
            anchors.fill: parent
        }
    }

    component FilterCombo: Item {
        id: filterCombo
        property string value: ""
        property var options: []
        signal selected(string value)

        width: 160
        height: 36
        z: combo.popup.visible ? 80 : 1

        Basic.ComboBox {
            id: combo
            anchors.fill: parent
            model: filterCombo.options
            currentIndex: Math.max(0, filterCombo.options.indexOf(filterCombo.value))
            onActivated: function(index) {
                if (index >= 0 && index < filterCombo.options.length)
                    filterCombo.selected(filterCombo.options[index]);
            }
            contentItem: Text {
                leftPadding: 14
                rightPadding: 32
                text: filterCombo.value || combo.displayText
                color: root.textColor
                font.pixelSize: 13
                font.bold: true
                verticalAlignment: Text.AlignVCenter
                elide: Text.ElideRight
            }
            indicator: AppIcon {
                x: combo.width - width - 10
                y: (combo.height - height) / 2
                width: 16
                height: 16
                name: "chevron-down"
                tint: "white"

                rotation: combo.popup.visible ? 180 : 0
                Behavior on rotation {
                    NumberAnimation { duration: 150 }
                }
            }
            background: Rectangle {
                radius: 6
                color: combo.hovered ? "#0a2438" : "#071827"
                border.color: combo.hovered || combo.activeFocus ? root.blueColor : "#173852"
                border.width: 1
            }
            delegate: Basic.ItemDelegate {
                id: comboDelegate
                required property int index
                required property string modelData
                width: combo.width
                height: 34
                highlighted: combo.highlightedIndex === index
                contentItem: Text {
                    text: comboDelegate.modelData
                    color: comboDelegate.highlighted ? "#031624" : root.textColor
                    font.pixelSize: 12
                    font.bold: true
                    verticalAlignment: Text.AlignVCenter
                    elide: Text.ElideRight
                }
                background: Rectangle {
                    color: comboDelegate.highlighted ? root.blueColor : "#071827"
                }
            }
            popup: Basic.Popup {
                y: combo.height + 4
                width: combo.width
                implicitHeight: contentItem.implicitHeight
                padding: 0
                background: Rectangle {
                    radius: 6
                    color: "#071827"
                    border.color: root.blueColor
                    border.width: 1
                }
                contentItem: ListView {
                    clip: true
                    implicitHeight: Math.min(contentHeight, 220)
                    model: combo.popup.visible ? combo.delegateModel : null
                    currentIndex: combo.highlightedIndex
                }
            }
        }
    }

    component ToolBox: Rectangle {
        id: tool
        property string label: ""
        property string valueText: ""
        signal clicked()

        height: 36
        radius: 6
        color: mouse.containsMouse ? "#0a2438" : "#071827"
        border.color: mouse.containsMouse ? root.blueColor : "#173852"
        border.width: 1

        Text {
            x: 14
            width: parent.width - 54
            height: parent.height
            text: tool.valueText
            color: root.textColor
            font.pixelSize: 13
            font.bold: true
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
        }
        Text {
            x: parent.width - 42
            width: 28
            height: parent.height
            text: "->"
            color: root.mutedTextColor
            font.pixelSize: 14
            font.bold: true
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }
        MouseArea {
            id: mouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: tool.clicked()
        }
    }

    component ToggleSwitch: Rectangle {
        id: toggle
        property bool checked: true
        signal toggled(bool value)

        width: 48
        height: 24
        radius: 12
        color: checked ? root.greenColor : "#d1d5db"
        border.color: checked ? "#34d399" : "#94a3b8"
        border.width: 1

        Rectangle {
            width: 20
            height: 20
            x: toggle.checked ? parent.width - width - 2 : 2
            anchors.verticalCenter: parent.verticalCenter
            radius: 10
            color: toggle.checked ? "#effff5" : "#2f2f2f"
            Behavior on x { NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }
        }
        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: toggle.toggled(!toggle.checked)
        }
    }

    component IconButton: Rectangle {
        id: button
        property string iconText: ""
        property string tooltip: ""
        signal clicked()

        width: 36
        height: 36
        radius: 6
        color: mouse.containsMouse ? "#0a3150" : "#071827"
        border.color: mouse.containsMouse ? root.blueColor : "#173852"
        border.width: 1
        Text {
            anchors.centerIn: parent
            text: button.iconText
            color: root.textColor
            font.pixelSize: button.iconText === "..." ? 12 : 14
            font.bold: true
        }
        MouseArea {
            id: mouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: button.clicked()
        }
    }

    component MetricTab: Rectangle {
        id: tab
        property string label: ""
        property bool selected: false
        signal clicked()

        width: 50
        height: 30
        radius: 5
        color: selected ? "#0d72d9" : mouse.containsMouse ? "#0a2438" : "#071827"
        border.color: selected ? "#1894ff" : mouse.containsMouse ? root.blueColor : "#173852"
        border.width: 1
        Text {
            anchors.centerIn: parent
            text: tab.label
            color: tab.selected ? "#eaf6ff" : root.mutedTextColor
            font.pixelSize: 12
            font.bold: true
        }
        MouseArea {
            id: mouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: tab.clicked()
        }
    }

    component TimeTab: MetricTab {
        width: 36
    }

    component LegendDot: Row {
        id: dot
        property string label: ""
        property color accent: root.blueColor

        height: 16
        spacing: 8
        Rectangle { width: 24; height: 4; radius: 2; color: dot.accent; anchors.verticalCenter: parent.verticalCenter }
        Text { text: dot.label; color: root.mutedTextColor; font.pixelSize: 11; font.bold: true; anchors.verticalCenter: parent.verticalCenter }
    }

    component KpiCard: Rectangle {
        id: card
        property string title: ""
        property string value: ""
        property string unitText: ""
        property string iconText: ""
        property string metric: "active"
        property var delta: null
        property color accent: root.blueColor
        property var points: []

        radius: 8
        color: root.cardColor
        border.color: "#143a56"
        border.width: 1
        clip: true

        Rectangle {
            x: 20
            y: 22
            width: 48
            height: 48
            radius: 24
            color: Qt.rgba(card.accent.r, card.accent.g, card.accent.b, 0.18)
            border.color: card.accent
            border.width: 1
            Text {
                anchors.centerIn: parent
                text: card.iconText
                color: card.accent
                font.pixelSize: card.iconText.length > 2 ? 11 : 20
                font.bold: true
            }
        }

        Text {
            x: 84
            y: 28
            width: parent.width - 102
            text: card.title
            color: root.mutedTextColor
            font.pixelSize: 12
            font.bold: true
            elide: Text.ElideRight
        }

        Row {
            x: 84
            y: 58
            height: 38
            spacing: 8
            Text {
                text: card.value
                color: root.textColor
                font.pixelSize: 27
                font.bold: true
                verticalAlignment: Text.AlignVCenter
            }
            Text {
                text: card.unitText
                color: root.textColor
                font.pixelSize: 13
                font.bold: true
                anchors.verticalCenter: parent.verticalCenter
            }
        }

        Sparkline {
            x: 72
            y: 98
            width: parent.width - 92
            height: 28
            points: card.points
            metric: card.metric
            accent: card.accent
        }

        Text {
            x: 24
            y: parent.height - 30
            width: parent.width - 48
            height: 18
            text: root.isDash(card.delta) ? "-- vs previous" : (card.delta >= 0 ? "+ " : "- ") + (card.metric === "pf" ? root.fmt(Math.abs(card.delta), 2) : root.fmt(Math.abs(card.delta), card.metric === "frequency" ? 2 : 1)) + (card.metric === "frequency" ? " Hz" : card.metric === "pf" ? "" : " ") + " vs previous"
            color: root.isDash(card.delta) ? root.mutedTextColor : (card.delta >= 0 ? root.greenColor : root.redColor)
            font.pixelSize: 12
            font.bold: true
            elide: Text.ElideRight
        }
    }

    component Sparkline: Canvas {
        id: spark
        property var points: []
        property string metric: "active"
        property color accent: root.blueColor

        onPointsChanged: requestPaint()
        onMetricChanged: requestPaint()
        onAccentChanged: requestPaint()

        onPaint: {
            var ctx = getContext("2d");
            ctx.clearRect(0, 0, width, height);
            var rows = spark.points || [];
            if (rows.length < 2)
                return;
            var values = [];
            var start = Math.max(0, rows.length - 28);
            for (var i = start; i < rows.length; i++) {
                values.push(root.numberValue(rows[i], 0));
            }
            var minV = values[0];
            var maxV = values[0];
            for (var j = 1; j < values.length; j++) {
                minV = Math.min(minV, values[j]);
                maxV = Math.max(maxV, values[j]);
            }
            var range = Math.max(0.01, maxV - minV);
            ctx.beginPath();
            for (var k = 0; k < values.length; k++) {
                var x = k / Math.max(1, values.length - 1) * width;
                var y = height - 2 - (values[k] - minV) / range * (height - 5);
                if (k === 0)
                    ctx.moveTo(x, y);
                else
                    ctx.lineTo(x, y);
            }
            ctx.strokeStyle = spark.accent;
            ctx.lineWidth = 2;
            ctx.stroke();
        }
    }

    component TrendChart: Canvas {
        id: chart
        property var rows: []
        property string metric: "kW"        // metric the left (Y) axis is scaled to
        property string unitText: "kW"
        property string mode: "Line"

        readonly property var seriesKeys: ["kW", "kvar", "kVA", "PF"]

        onRowsChanged: requestPaint()
        onMetricChanged: requestPaint()
        onModeChanged: requestPaint()

        function valueAt(row, key) {
            var v = row ? row[key] : null;
            return (typeof v === "number" && isFinite(v)) ? v : null;
        }

        // Scale of ONE series. Every series is normalised to its own range so kW/kvar/kVA/PF
        // can share the plot; the axis labels show the scale of the selected metric only.
        function scaleFor(key) {
            var lo = Infinity, hi = -Infinity;
            for (var i = 0; i < chart.rows.length; i++) {
                var v = valueAt(chart.rows[i], key);
                if (v === null) continue;
                lo = Math.min(lo, v);
                hi = Math.max(hi, v);
            }
            if (!isFinite(lo)) return { min: 0, max: 1 };
            if (key === "PF")
                return { min: Math.min(0.80, lo - 0.02), max: Math.max(1.0, hi + 0.02) };
            if (lo < 0 && hi > 0) {
                var maxAbs = Math.max(Math.abs(lo), Math.abs(hi));
                return { min: -maxAbs, max: maxAbs };
            }
            if (hi <= 0)
                return { min: Math.min(-1, lo), max: 0 };
            return { min: 0, max: Math.max(1, hi) };
        }

        onPaint: {
            var ctx = getContext("2d");
            ctx.clearRect(0, 0, width, height);
            var data = chart.rows || [];
            var left = 54;
            var right = 16;
            var top = 16;
            var bottom = 34;
            var plotW = width - left - right;
            var plotH = height - top - bottom;
            ctx.font = "11px sans-serif";
            ctx.lineWidth = 1;
            ctx.setLineDash([]);

            var scales = {};
            for (var k = 0; k < chart.seriesKeys.length; k++)
                scales[chart.seriesKeys[k]] = chart.scaleFor(chart.seriesKeys[k]);
            var axis = scales[chart.metric] || { min: 0, max: 1 };
            var axisRange = Math.max(0.01, axis.max - axis.min);
            var axisColor = root.metricColor(chart.metric);

            function xAt(index) { return left + index / Math.max(1, data.length - 1) * plotW; }
            function yAt(key, value) {
                var sc = scales[key];
                var r = Math.max(0.01, sc.max - sc.min);
                return top + (sc.max - value) / r * plotH;
            }

            // grid + Y axis of the selected metric
            ctx.strokeStyle = "#143a56";
            for (var gy = 0; gy <= 4; gy++) {
                var y = top + plotH * gy / 4;
                ctx.beginPath();
                ctx.moveTo(left, y);
                ctx.lineTo(width - right, y);
                ctx.stroke();
                var labelValue = axis.max - axisRange * gy / 4;
                ctx.fillStyle = axisColor;
                ctx.textAlign = "right";
                ctx.fillText(chart.metric === "PF" ? root.fmt(labelValue, 2) : root.comma(labelValue, 0), left - 8, y + 4);
            }
            // zero line of the axis metric (only when the scale crosses zero)
            if (axis.min < 0 && axis.max > 0) {
                var zy = top + (axis.max - 0) / axisRange * plotH;
                ctx.strokeStyle = "#35618a";
                ctx.setLineDash([4, 4]);
                ctx.beginPath();
                ctx.moveTo(left, zy);
                ctx.lineTo(width - right, zy);
                ctx.stroke();
                ctx.setLineDash([]);
            }
            if (data.length < 2)
                return;

            // x labels
            ctx.fillStyle = root.mutedTextColor;
            ctx.textAlign = "center";
            var step = Math.max(1, Math.ceil(data.length / 7));
            for (var lx = 0; lx < data.length; lx += step)
                ctx.fillText(data[lx].label, xAt(lx), height - 10);

            // Series: the axis metric is drawn last (on top), thicker and fully opaque.
            var order = [];
            for (var o = 0; o < chart.seriesKeys.length; o++)
                if (chart.seriesKeys[o] !== chart.metric) order.push(chart.seriesKeys[o]);
            order.push(chart.metric);

            ctx.save();
            ctx.beginPath();
            ctx.rect(left, top - 2, plotW, plotH + 4);
            ctx.clip();
            for (var s = 0; s < order.length; s++) {
                var key = order[s];
                var isAxis = key === chart.metric;
                var color = root.metricColor(key);
                ctx.strokeStyle = color;
                ctx.fillStyle = color;
                ctx.globalAlpha = isAxis ? 1.0 : 0.7;
                ctx.lineWidth = isAxis ? 2.6 : 1.7;

                // line, broken where a bucket has no value for this series
                var drawing = false, runLen = 0, lastX = 0, lastY = 0;
                var firstX = 0, startedRun = false;
                ctx.beginPath();
                for (var j = 0; j < data.length; j++) {
                    var v = chart.valueAt(data[j], key);
                    if (v === null) {
                        if (drawing && runLen === 1) ctx.fillRect(lastX - 2, lastY - 2, 4, 4);
                        drawing = false; runLen = 0;
                        continue;
                    }
                    var px = xAt(j), py = yAt(key, v);
                    if (!drawing) { ctx.moveTo(px, py); drawing = true; runLen = 1; }
                    else { ctx.lineTo(px, py); runLen++; }
                    lastX = px; lastY = py;
                }
                if (drawing && runLen === 1) ctx.fillRect(lastX - 2, lastY - 2, 4, 4);
                ctx.stroke();

                // area fill only for the axis metric, so lines never turn into a muddy stack
                if (chart.mode === "Area" && isAxis) {
                    var runStart = -1;
                    for (var a = 0; a <= data.length; a++) {
                        var av = a < data.length ? chart.valueAt(data[a], key) : null;
                        if (av !== null && runStart < 0) runStart = a;
                        if ((av === null || a === data.length) && runStart >= 0) {
                            var runEnd = a - 1;
                            if (runEnd > runStart) {
                                ctx.beginPath();
                                ctx.moveTo(xAt(runStart), yAt(key, chart.valueAt(data[runStart], key)));
                                for (var f = runStart + 1; f <= runEnd; f++)
                                    ctx.lineTo(xAt(f), yAt(key, chart.valueAt(data[f], key)));
                                ctx.lineTo(xAt(runEnd), top + plotH);
                                ctx.lineTo(xAt(runStart), top + plotH);
                                ctx.closePath();
                                ctx.globalAlpha = 0.16;
                                ctx.fill();
                                ctx.globalAlpha = 1.0;
                            }
                            runStart = -1;
                        }
                    }
                }
            }
            ctx.restore();
            ctx.globalAlpha = 1.0;

            ctx.fillStyle = axisColor;
            ctx.textAlign = "left";
            ctx.fillText(chart.unitText, left, 10);
        }
    }

    component PhaseBarChart: Canvas {
        id: chart
        property var rows: []
        property real maxHint: 1
        property int decimals: 0

        onRowsChanged: requestPaint()
        onMaxHintChanged: requestPaint()
        onDecimalsChanged: requestPaint()

        onPaint: {
            var ctx = getContext("2d");
            ctx.clearRect(0, 0, width, height);
            var data = chart.rows || [];
            var left = 52;
            var bottom = 30;
            var top = 10;
            var plotW = width - left - 16;
            var plotH = height - top - bottom;
            var maxV = Math.max(1, chart.maxHint);
            ctx.font = "11px sans-serif";
            ctx.strokeStyle = "#143a56";
            ctx.fillStyle = root.mutedTextColor;
            for (var gy = 0; gy <= 4; gy++) {
                var y = top + plotH * gy / 4;
                ctx.beginPath();
                ctx.moveTo(left, y);
                ctx.lineTo(width - 10, y);
                ctx.stroke();
                ctx.textAlign = "right";
                ctx.fillText(root.comma(maxV * (1 - gy / 4), 0), left - 8, y + 4);
            }
            var gap = plotW / Math.max(1, data.length);
            var barW = Math.min(42, gap * 0.42);
            for (var i = 0; i < data.length; i++) {
                var cx = left + gap * i + gap / 2;
                var h = data[i].value / maxV * plotH;
                ctx.fillStyle = data[i].color;
                ctx.globalAlpha = 0.9;
                ctx.fillRect(cx - barW / 2, top + plotH - h, barW, h);
                ctx.globalAlpha = 1;
                ctx.fillStyle = root.textColor;
                ctx.textAlign = "center";
                ctx.fillText(root.comma(data[i].value, chart.decimals), cx, top + plotH - h - 8);
                ctx.fillStyle = root.mutedTextColor;
                ctx.fillText(data[i].label, cx, height - 8);
            }
        }
    }

    component HarmonicsChart: Canvas {
        id: chart
        property var rows: []

        onRowsChanged: requestPaint()

        onPaint: {
            var ctx = getContext("2d");
            ctx.clearRect(0, 0, width, height);
            var data = chart.rows || [];
            var left = 36;
            var bottom = 30;
            var top = 12;
            var plotW = width - left - 12;
            var plotH = height - top - bottom;
            if (data.length === 0) {
                ctx.fillStyle = root.mutedTextColor;
                ctx.font = "12px sans-serif";
                ctx.textAlign = "center";
                ctx.fillText("No real harmonic data (not reported by PQM meters)", width / 2, height / 2);
                return;
            }
            var maxV = 10;
            for (var i = 0; i < data.length; i++)
                maxV = Math.max(maxV, data[i].l1, data[i].l2, data[i].l3);
            ctx.font = "11px sans-serif";
            ctx.strokeStyle = "#143a56";
            ctx.fillStyle = root.mutedTextColor;
            for (var gy = 0; gy <= 4; gy++) {
                var y = top + plotH * gy / 4;
                ctx.beginPath();
                ctx.moveTo(left, y);
                ctx.lineTo(width - 8, y);
                ctx.stroke();
                ctx.textAlign = "right";
                ctx.fillText(root.fmt(maxV * (1 - gy / 4), 0), left - 8, y + 4);
            }
            var gap = plotW / Math.max(1, data.length);
            var barW = Math.min(8, gap * 0.18);
            for (var j = 0; j < data.length; j++) {
                var cx = left + gap * j + gap / 2;
                var values = [data[j].l1, data[j].l2, data[j].l3];
                var colors = [root.redColor, root.yellowColor, root.blueColor];
                for (var k = 0; k < 3; k++) {
                    var h = values[k] / maxV * plotH;
                    ctx.fillStyle = colors[k];
                    ctx.fillRect(cx - barW * 1.5 + k * barW * 1.2, top + plotH - h, barW, h);
                }
                ctx.fillStyle = root.mutedTextColor;
                ctx.textAlign = "center";
                ctx.fillText(String(data[j].order), cx, height - 10);
            }
            ctx.fillStyle = root.mutedTextColor;
            ctx.textAlign = "left";
            ctx.fillText("%", 0, 12);
            ctx.textAlign = "center";
            ctx.fillText("Harmonic Order", left + plotW / 2, height - 1);
        }
    }

    component HeaderCell: Text {
        property int align: Text.AlignLeft
        height: 34
        color: root.mutedTextColor
        font.pixelSize: 11
        font.bold: true
        horizontalAlignment: align
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
    }

    component FeederRow: Rectangle {
        id: row
        property var rowData: ({})
        property int rowIndex: 0

        height: 32
        color: rowIndex % 2 === 0 ? "#061a2b" : "#051421"
        border.color: "#12324b"
        border.width: 1

        Row {
            anchors.fill: parent
            anchors.leftMargin: 8
            anchors.rightMargin: 8
            Text { width: 136; height: parent.height; text: row.rowData.name || ""; color: root.textColor; font.pixelSize: 12; font.bold: true; verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight }
            Rectangle {
                width: 76
                height: parent.height
                color: "transparent"
                Rectangle {
                    anchors.centerIn: parent
                    width: 46
                    height: 20
                    radius: 5
                    color: row.rowData.status === "ON" ? "#0f6f35" : "#3a4a5c"
                    Text { anchors.centerIn: parent; text: row.rowData.status || "--"; color: "#d9ffe8"; font.pixelSize: 10; font.bold: true }
                }
            }
            Text { width: 66; height: parent.height; text: root.fmtOrDash(row.rowData.l1v, 2); color: root.textColor; font.pixelSize: 12; horizontalAlignment: Text.AlignRight; verticalAlignment: Text.AlignVCenter }
            Text { width: 66; height: parent.height; text: root.fmtOrDash(row.rowData.l2v, 2); color: root.textColor; font.pixelSize: 12; horizontalAlignment: Text.AlignRight; verticalAlignment: Text.AlignVCenter }
            Text { width: 66; height: parent.height; text: root.fmtOrDash(row.rowData.l3v, 2); color: root.textColor; font.pixelSize: 12; horizontalAlignment: Text.AlignRight; verticalAlignment: Text.AlignVCenter }
            Text { width: 66; height: parent.height; text: root.fmtOrDash(row.rowData.l1a, 1); color: root.textColor; font.pixelSize: 12; horizontalAlignment: Text.AlignRight; verticalAlignment: Text.AlignVCenter }
            Text { width: 66; height: parent.height; text: root.fmtOrDash(row.rowData.l2a, 1); color: root.textColor; font.pixelSize: 12; horizontalAlignment: Text.AlignRight; verticalAlignment: Text.AlignVCenter }
            Text { width: 66; height: parent.height; text: root.fmtOrDash(row.rowData.l3a, 1); color: root.textColor; font.pixelSize: 12; horizontalAlignment: Text.AlignRight; verticalAlignment: Text.AlignVCenter }
            Text { width: 112; height: parent.height; text: root.commaOrDash(row.rowData.activeKw, 0); color: row.rowData.activeKw < 0 ? root.greenColor : root.textColor; font.pixelSize: 12; horizontalAlignment: Text.AlignRight; verticalAlignment: Text.AlignVCenter }
            Text { width: 112; height: parent.height; text: root.commaOrDash(row.rowData.reactiveKvar, 0); color: row.rowData.reactiveKvar < 0 ? root.greenColor : root.textColor; font.pixelSize: 12; horizontalAlignment: Text.AlignRight; verticalAlignment: Text.AlignVCenter }
            Text { width: 76; height: parent.height; text: root.fmtOrDash(row.rowData.pf, 2); color: root.textColor; font.pixelSize: 12; horizontalAlignment: Text.AlignRight; verticalAlignment: Text.AlignVCenter }
            Text { width: 104; height: parent.height; text: root.fmtOrDash(row.rowData.frequency, 2); color: root.textColor; font.pixelSize: 12; horizontalAlignment: Text.AlignRight; verticalAlignment: Text.AlignVCenter }
            Text { width: 72; height: parent.height; text: root.fmtOrDash(row.rowData.thd, 1); color: row.rowData.thd > 5 ? root.orangeColor : root.textColor; font.pixelSize: 12; horizontalAlignment: Text.AlignRight; verticalAlignment: Text.AlignVCenter }
        }
    }

    component StatMini: Rectangle {
        id: stat
        property string label: ""
        property string value: ""

        height: 52
        radius: 5
        color: "#071827"
        border.color: "#12324b"
        border.width: 1
        Text {
            x: 8
            y: 8
            width: parent.width - 16
            text: stat.label
            color: root.mutedTextColor
            font.pixelSize: 10
            font.bold: true
            elide: Text.ElideRight
        }
        Text {
            x: 8
            y: 28
            width: parent.width - 16
            text: stat.value
            color: root.textColor
            font.pixelSize: 13
            font.bold: true
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
        }
    }

    component QualityTile: Rectangle {
        id: tile
        property string label: ""
        property string value: ""
        property bool ok: true

        height: 72
        radius: 6
        color: "#071827"
        border.color: "#12324b"
        border.width: 1
        Text {
            x: 10
            y: 8
            width: parent.width - 20
            height: 28
            text: tile.label
            color: root.mutedTextColor
            font.pixelSize: 11
            font.bold: true
            verticalAlignment: Text.AlignVCenter
        }
        Text {
            x: 10
            y: 42
            width: parent.width - 20
            height: 18
            text: tile.value + (tile.ok ? "  OK" : "  WARN")
            color: tile.ok ? root.textColor : root.orangeColor
            font.pixelSize: 12
            font.bold: true
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
        }
    }
}

