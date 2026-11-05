# This Python file uses the following encoding: utf-8
from __future__ import annotations

import math
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timedelta
from typing import Any

from PySide6.QtCore import Property, QObject, Signal, Slot

from backend.models.pqm_data import PqmData, PqmDataStore, pqm_display_metrics
from backend.models.topology import Device
from backend.services.historian.historian_service import (
    PLANT_LOCAL_TZ,
    SNAPSHOT_KW_DIVISOR,
    SYSTEM_SNAPSHOT_MEASUREMENT,
    local_today_iso,
    to_query_iso,
)
from backend.services.influx.influx_client import InfluxClient
from backend.services.influx.query_cache import BackgroundQueryCache
from backend.services.rollup.rollup_store import InfluxRollupStore
from backend.viewmodels.pms_topology_viewmodel import PmsTopologyViewModel

_GROUP_ACCENT = {
    "_CFG_PWRSRCTYPE_GRID": "#128cff",
    "_CFG_PWRSRCTYPE_SOLAR": "#ffc323",
    "_CFG_PWRSRCTYPE_BESS": "#3bd15b",
    "_CFG_PWRSRCTYPE_LOAD": "#20c7d7",
}
_DEFAULT_ACCENT = "#8b5cf6"

_KPI_SPECS = [
    ("TOTAL ACTIVE POWER", "activeKw", "kW", "active", "#128cff", "P", 0),
    ("TOTAL REACTIVE POWER", "reactiveKvar", "kvar", "reactive", "#3bd15b", "Q", 0),
    ("APPARENT POWER", "apparentKva", "kVA", "apparent", "#8b5cf6", "S", 0),
    ("POWER FACTOR", "pf", "", "pf", "#f59e0b", "PF", 2),
    ("FREQUENCY", "frequency", "Hz", "frequency", "#20c7d7", "Hz", 2),
    ("TDD (THD CURRENT)", "thd", "%", "thd", "#ffc323", "THD", 1),
]

_WINDOW_SPECS: dict[str, tuple[timedelta, int]] = {
    "15m": (timedelta(minutes=15), 15),
    "1h": (timedelta(hours=1), 20),
    "1D": (timedelta(days=1), 48),
    "1W": (timedelta(days=7), 56),
    "1M": (timedelta(days=30), 30),
}
_RAW_SPAN_LIMIT = timedelta(hours=2)
_RAW_SPAN_LIMIT_SINGLE_DEVICE = timedelta(days=7)
_HOURLY_ROLLUP_SPAN_LIMIT = timedelta(days=3)
_KPI_DELTA_LOOKBACK = timedelta(minutes=5)
_HISTORY_RETENTION = timedelta(minutes=20)

class PowerMonitoringViewModel(QObject):
    dataChanged = Signal()
    selectedGridChanged = Signal()

    def __init__(
        self,
        topology_vm: PmsTopologyViewModel,
        pqm_store: PqmDataStore,
        influx_client: InfluxClient | None = None,
        rollup_hourly: InfluxRollupStore | None = None,
        rollup_daily: InfluxRollupStore | None = None,
    ):
        super().__init__()
        self._topology_vm = topology_vm
        self._pqm_store = pqm_store
        self._influx_client = influx_client
        self._rollup_hourly = rollup_hourly
        self._rollup_daily = rollup_daily
        self._query_cache = BackgroundQueryCache(max_entries=128, name="power_monitoring")
        self._history: list[tuple[datetime, list[dict[str, Any]]]] = []
        self._topology_vm.configChanged.connect(self.notify_data_changed)
        self._topology_vm.selectedGridChanged.connect(self.selectedGridChanged)
        self._topology_vm.selectedGridChanged.connect(self.notify_data_changed)

    def notify_data_changed(self) -> None:
        self._record_history()
        self.dataChanged.emit()

    @Property("QVariant", notify=dataChanged)
    def availableGrids(self):
        return [item.to_dict() for item in self._topology_vm.topology_model.main_grids]

    @Property(int, notify=selectedGridChanged)
    def selectedGridId(self):
        return self._topology_vm.selectedGridId

    @Property(str, notify=selectedGridChanged)
    def selectedGridName(self):
        grid = self._topology_vm.topology_model.grid_by_id(self._topology_vm.selectedGridId)
        return grid.name if grid else ""

    @Slot(int)
    def setSelectedGrid(self, grid_id: int) -> None:
        self._topology_vm.setSelectedGrid(grid_id)

    # ------------------------------------------------------------------ topology / device rows

    def _pqm_devices(self, grid_id: int) -> list[Device]:
        topology = self._topology_vm.topology_model
        group_ids = {group.id for group in topology.groups_by_grid(grid_id)}
        source_ids = {source.id for source in topology.power_sources if source.group_id in group_ids}
        return [
            item for item in topology.devices
            if item.enabled and item.type.startswith("_DEVCFG_DEVTYPE_PQM") and item.source_id in source_ids
        ]

    def _pqm_row(self, device: Device) -> dict[str, Any]:
        topology = self._topology_vm.topology_model
        source = next((item for item in topology.power_sources if item.id == device.source_id), None)
        group = next((item for item in topology.power_source_groups if source and item.id == source.group_id), None)
        stored = self._pqm_store.source(device.source_id) or self._pqm_store.device(device.id)
        data = stored.data if stored else PqmData()
        metrics = pqm_display_metrics(data)
        is_schneider = device.type_label.startswith("PQM_SCHNEIDER")
        has_data = bool(
            data.p_tot or data.grid_kw or data.q_tot or data.grid_kvar
            or data.volt_ab or data.hz or data.cur_a
        )
        group_type = group.type if group else ""
        return {
            "name": device.name or (source.name if source else ""),
            "sourceId": device.source_id,
            "deviceId": device.id,
            "groupName": group.name if group else "",
            "groupType": group_type,
            "vendor": "Schneider" if is_schneider else "VinFast",
            "status": "ON" if has_data else "--",
            "l1v": metrics["voltAB"],
            "l2v": metrics["voltBC"],
            "l3v": metrics["voltCA"],
            "l1a": metrics["curA"],
            "l2a": metrics["curB"],
            "l3a": metrics["curC"],
            "activeKw": metrics["activeKw"],
            "reactiveKvar": metrics["reactiveKvar"],
            "pf": metrics["powerFactor"],
            "frequency": metrics["frequencyHz"],
            "thd": None,
            "color": _GROUP_ACCENT.get(group_type, _DEFAULT_ACCENT),
        }

    @staticmethod
    def _dedupe_by_source(rows: list[dict[str, Any]]) -> list[dict[str, Any]]:
        best: dict[int, dict[str, Any]] = {}
        for row in rows:
            source_id = row["sourceId"]
            current = best.get(source_id)
            rank = (row["status"] == "ON", row["vendor"] == "Schneider", -row["deviceId"])
            if current is None:
                best[source_id] = row
                continue
            current_rank = (current["status"] == "ON", current["vendor"] == "Schneider", -current["deviceId"])
            if rank > current_rank:
                best[source_id] = row
        return list(best.values())

    def _device_rows(self, grid_id: int) -> list[dict[str, Any]]:
        rows = self._dedupe_by_source([self._pqm_row(device) for device in self._pqm_devices(grid_id)])
        rows.sort(key=lambda row: (row["groupType"], row["name"]))
        return rows

    @Slot(result="QVariant")
    def deviceOptions(self) -> list[str]:
        rows = self._device_rows(self._topology_vm.selectedGridId)
        return ["All Facilities"] + [row["name"] for row in rows]

    # ------------------------------------------------------------------------------- aggregation

    @staticmethod
    def _supply_side_rows(rows: list[dict[str, Any]]) -> list[dict[str, Any]]:
        return [
            row for row in rows
            if row["groupType"] in ("_CFG_PWRSRCTYPE_GRID", "_CFG_PWRSRCTYPE_SOLAR")
            or (row["groupType"] == "_CFG_PWRSRCTYPE_BESS" and (row["activeKw"] or 0.0) > 0)
        ]

    def _summary(self, rows: list[dict[str, Any]]) -> dict[str, float | None]:
        active_vals = [row["activeKw"] for row in rows if row["activeKw"] is not None]
        reactive_vals = [row["reactiveKvar"] for row in rows if row["reactiveKvar"] is not None]
        active_kw = sum(active_vals) if active_vals else None
        reactive_kvar = sum(reactive_vals) if reactive_vals else None
        if active_kw is not None or reactive_kvar is not None:
            apparent_kva: float | None = math.hypot(active_kw or 0.0, reactive_kvar or 0.0)
        else:
            apparent_kva = None
        if active_kw is not None and apparent_kva:
            pf: float | None = abs(active_kw) / max(1e-6, apparent_kva)
        else:
            pf_vals = [row["pf"] for row in rows if row["pf"] is not None]
            pf = sum(pf_vals) / len(pf_vals) if pf_vals else None
        freq_vals = [row["frequency"] for row in rows if row["frequency"] is not None]
        frequency = sum(freq_vals) / len(freq_vals) if freq_vals else None
        return {
            "activeKw": active_kw,
            "reactiveKvar": reactive_kvar,
            "apparentKva": apparent_kva,
            "pf": pf,
            "frequency": frequency,
            "thd": None,
            "currentA": None,
        }

    def _record_history(self) -> None:
        now = datetime.now(PLANT_LOCAL_TZ)
        self._history.append((now, self._device_rows(self._topology_vm.selectedGridId)))
        cutoff = now - _HISTORY_RETENTION
        self._history = [entry for entry in self._history if entry[0] >= cutoff]

    @staticmethod
    def _filter_rows(rows: list[dict[str, Any]], device_key: str) -> list[dict[str, Any]]:
        if not device_key or device_key == "All Facilities":
            return rows
        return [row for row in rows if row["name"] == device_key]

    def _history_summaries(self, device_key: str) -> list[tuple[datetime, dict[str, float | None]]]:
        is_aggregate = not device_key or device_key == "All Facilities"
        summaries = []
        for timestamp, snapshot in self._history:
            rows = self._filter_rows(snapshot, device_key)
            if is_aggregate:
                rows = self._supply_side_rows(rows)
            summaries.append((timestamp, self._summary(rows)))
        return summaries

    @staticmethod
    def _kpi_delta(history_summaries: list[tuple[datetime, dict[str, float | None]]], field: str) -> float | None:
        if len(history_summaries) < 2:
            return None
        now_ts, now_summary = history_summaries[-1]
        now_value = now_summary.get(field)
        if now_value is None:
            return None
        target_ts = now_ts - _KPI_DELTA_LOOKBACK
        before_value = None
        for timestamp, summary in reversed(history_summaries[:-1]):
            if timestamp <= target_ts:
                before_value = summary.get(field)
                break
        else:
            before_value = history_summaries[0][1].get(field)
        if before_value is None:
            return None
        return now_value - before_value

    @staticmethod
    def _kpi_spark(history_summaries: list[tuple[datetime, dict[str, float | None]]], field: str) -> list[float]:
        return [
            value for value in (entry[1].get(field) for entry in history_summaries[-28:])
            if value is not None
        ]

    @staticmethod
    def _comma_or_dash(value: float | None, digits: int = 0) -> str:
        if value is None:
            return "--"
        return f"{value:,.{digits}f}"

    def _kpi_cards(
        self, summary: dict[str, float | None], history_summaries: list[dict[str, float | None]]
    ) -> list[dict[str, Any]]:
        return [
            {
                "title": title,
                "value": self._comma_or_dash(summary.get(field), digits),
                "unit": unit,
                "metric": metric,
                "delta": self._kpi_delta(history_summaries, field),
                "accent": accent,
                "icon": icon,
                "spark": self._kpi_spark(history_summaries, field),
            }
            for title, field, unit, metric, accent, icon, digits in _KPI_SPECS
        ]

    def _phase_rows(
        self, selected_device: dict[str, Any] | None, rows: list[dict[str, Any]]
    ) -> tuple[list[dict[str, Any]], list[dict[str, Any]]]:
        device = selected_device or next((row for row in rows if row["l1v"] is not None), None)
        if device is None:
            return [], []
        voltage_rows = []
        if device["l1v"] is not None:
            voltage_rows = [
                {"label": "L1", "value": device["l1v"], "color": "#128cff"},
                {"label": "L2", "value": device["l2v"], "color": "#3bd15b"},
                {"label": "L3", "value": device["l3v"], "color": "#ffc323"},
            ]
        current_rows = []
        if device["l1a"] is not None:
            current_rows = [
                {"label": "L1", "value": device["l1a"], "color": "#128cff"},
                {"label": "L2", "value": device["l2a"], "color": "#3bd15b"},
                {"label": "L3", "value": device["l3a"], "color": "#ffc323"},
            ]
        return voltage_rows, current_rows

    @staticmethod
    def _quality_rows() -> list[dict[str, Any]]:
        return [
            {"label": "Voltage THD", "value": "--", "ok": True},
            {"label": "Current THD", "value": "--", "ok": True},
            {"label": "Frequency Deviation", "value": "--", "ok": True},
            {"label": "Voltage Unbalance", "value": "--", "ok": True},
        ]

    # ---------------------------------------------------------------------------------- snapshot

    @staticmethod
    def _clamp(value: float, lo: float, hi: float) -> float:
        return max(lo, min(hi, value))

    @Slot(str, str, str, float, str, str, str, str, result="QVariant")
    def powerMonitoringSnapshot(
        self, device_key, metric, window, zoom, from_date, to_date, start_time, end_time
    ) -> dict[str, Any]:
        device_key = str(device_key or "All Facilities")
        metric = str(metric or "kW")
        window = str(window or "1h")
        zoom = self._clamp(float(zoom or 1.0), 0.75, 3.0)
        from_date = str(from_date or "")
        to_date = str(to_date or from_date)
        start_time = str(start_time or "00:00")
        end_time = str(end_time or "23:59")

        rows = self._device_rows(self._topology_vm.selectedGridId)
        selected_device = None
        if device_key not in ("", "All Facilities"):
            selected_device = next((row for row in rows if row["name"] == device_key), None)
        filtered_rows = [selected_device] if selected_device else rows
        summary_rows = filtered_rows if selected_device else self._supply_side_rows(rows)
        summary = self._summary(summary_rows)
        history_summaries = self._history_summaries(device_key)

        phase_voltage_rows, phase_current_rows = self._phase_rows(selected_device, rows)
        # All four series (kW / kvar / kVA / PF) are returned together; `metric` only chooses
        # which one the UI uses for the Y axis, so it no longer affects the query.
        trend_rows, trend_note = self._trend_rows(
            rows, selected_device, window, zoom, from_date, to_date, start_time, end_time
        )

        return {
            "timestamp": datetime.now(PLANT_LOCAL_TZ).isoformat(timespec="seconds"),
            "selectedDate": from_date if from_date == to_date else f"{from_date} - {to_date}",
            "selectedFromDate": from_date,
            "selectedToDate": to_date,
            "selectedTimeRange": f"{start_time} - {end_time}",
            "powerHistory": [],
            "summary": summary,
            "kpis": self._kpi_cards(summary, history_summaries),
            "trendRows": trend_rows,
            "trendNote": trend_note,
            "feederRows": filtered_rows,
            "phaseVoltageRows": phase_voltage_rows,
            "phaseCurrentRows": phase_current_rows,
            "harmonicRows": [],
            "qualityRows": self._quality_rows(),
        }

    # -------------------------------------------------------------------------- Influx trend query

    def _resolve_range(
        self, now: datetime, duration: timedelta, from_date: str, to_date: str, start_time: str, end_time: str
    ) -> tuple[datetime, datetime]:
        today_iso = local_today_iso(now)
        if from_date and to_date and not (from_date == today_iso and to_date == today_iso):
            try:
                start_dt = self._combine(from_date, start_time)
                stop_dt = self._combine(to_date, end_time)
                if stop_dt > start_dt:
                    return start_dt, stop_dt
            except ValueError:
                pass
        return now - duration, now

    @staticmethod
    def _combine(date_iso: str, time_hhmm: str) -> datetime:
        year, month, day = (int(part) for part in date_iso.split("-"))
        hour, minute = (int(part) for part in time_hhmm.split(":"))
        return datetime(year, month, day, hour, minute, tzinfo=PLANT_LOCAL_TZ)

    def _query_source_field_buckets(
        self, source_id: int, field: str, start_dt: datetime, stop_dt: datetime, bucket_count: int
    ) -> dict[int, float]:
        if not self._influx_client or not source_id:
            return {}
        key = ("pqm_trend", source_id, field, to_query_iso(start_dt), to_query_iso(stop_dt), bucket_count)
        return self._query_cache.get(
            key,
            lambda: self._bucketize(
                self._query_source_field_now(source_id, field, start_dt, stop_dt, bucket_count),
                field, start_dt, stop_dt, bucket_count,
            ),
            {},
        )

    def _query_source_field_now(
        self, source_id: int, field: str, start_dt: datetime, stop_dt: datetime, bucket_count: int
    ) -> list[dict[str, Any]]:
        span = (stop_dt - start_dt).total_seconds()
        interval = span / bucket_count if bucket_count else span
        return self._influx_client.query_range_grouped_by_time(
            SYSTEM_SNAPSHOT_MEASUREMENT, to_query_iso(start_dt), to_query_iso(stop_dt),
            {"Tsrc_id": source_id}, fields=[field], interval_seconds=interval,
        )

    @staticmethod
    def _bucketize(
        rows: list[dict[str, Any]], field: str, start_dt: datetime, stop_dt: datetime, bucket_count: int
    ) -> dict[int, float]:
        span = (stop_dt - start_dt).total_seconds()
        if span <= 0:
            return {}
        buckets: dict[int, list[float]] = {}
        for row in rows:
            value = row.get(field)
            if value is None:
                continue
            try:
                ts = datetime.fromisoformat(str(row.get("time", "")).replace("Z", "+00:00"))
            except ValueError:
                continue
            elapsed = (ts - start_dt).total_seconds()
            index = min(bucket_count - 1, max(0, int(elapsed / span * bucket_count)))
            buckets.setdefault(index, []).append(float(value))
        return {index: sum(values) / len(values) for index, values in buckets.items()}

    def _source_pq_buckets(
        self, source_id: int, start_dt: datetime, stop_dt: datetime, bucket_count: int
    ) -> tuple[dict[int, float], dict[int, float]]:
        with ThreadPoolExecutor(max_workers=2) as pool:
            p_future = pool.submit(self._query_source_field_buckets, source_id, "src_actual_P", start_dt, stop_dt, bucket_count)
            q_future = pool.submit(self._query_source_field_buckets, source_id, "src_actual_Q", start_dt, stop_dt, bucket_count)
            p_buckets = p_future.result()
            q_buckets = q_future.result()
        return (
            {index: value / SNAPSHOT_KW_DIVISOR for index, value in p_buckets.items()},
            {index: value / SNAPSHOT_KW_DIVISOR for index, value in q_buckets.items()},
        )

    @staticmethod
    def _series_from_pq(
        p_buckets: dict[int, float], q_buckets: dict[int, float]
    ) -> dict[int, dict[str, float | None]]:
        """Per bucket: kW, kvar, kVA and PF derived from the same P/Q pair (None = no sample)."""
        result: dict[int, dict[str, float | None]] = {}
        for index in set(p_buckets) | set(q_buckets):
            p_value = p_buckets.get(index)
            q_value = q_buckets.get(index)
            apparent = math.hypot(p_value or 0.0, q_value or 0.0)
            pf: float | None = None
            if p_value is not None and q_value is not None and apparent > 1e-9:
                pf = min(1.0, abs(p_value) / apparent)
            result[index] = {"kW": p_value, "kvar": q_value, "kVA": apparent, "PF": pf}
        return result

    def _aggregate_pq_buckets(
        self, rows: list[dict[str, Any]], start_dt: datetime, stop_dt: datetime, bucket_count: int
    ) -> tuple[dict[int, float], dict[int, float], str]:
        p_totals: dict[int, float] = {}
        q_totals: dict[int, float] = {}
        any_device = False
        for row in rows:
            if not row.get("sourceId"):
                continue
            if row["groupType"] not in ("_CFG_PWRSRCTYPE_GRID", "_CFG_PWRSRCTYPE_SOLAR", "_CFG_PWRSRCTYPE_BESS"):
                continue
            is_bess = row["groupType"] == "_CFG_PWRSRCTYPE_BESS"
            p_buckets, q_buckets = self._source_pq_buckets(row["sourceId"], start_dt, stop_dt, bucket_count)
            for index in set(p_buckets) | set(q_buckets):
                p_value = p_buckets.get(index, 0.0)
                if is_bess and p_value <= 0:
                    continue
                p_totals[index] = p_totals.get(index, 0.0) + p_value
                q_totals[index] = q_totals.get(index, 0.0) + q_buckets.get(index, 0.0)
                any_device = True
        if not any_device:
            return {}, {}, "No historical PQM data"
        return p_totals, q_totals, ""

    def _trend_label_format(self, duration: timedelta) -> str:
        if duration <= timedelta(days=1):
            return "%H:%M"
        return "%d/%m"

    def _query_rollup(
        self, store: InfluxRollupStore, grid_id: int, group_type: str, start_dt: datetime, stop_dt: datetime
    ) -> list[dict[str, Any]]:
        key = ("pqm_rollup", id(store), grid_id, group_type, to_query_iso(start_dt), to_query_iso(stop_dt))
        return self._query_cache.get(
            key,
            lambda: store.query_range(grid_id, group_type, to_query_iso(start_dt), to_query_iso(stop_dt)),
            [],
        )

    def _rollup_pq_buckets(
        self, store: InfluxRollupStore, grid_id: int, start_dt: datetime, stop_dt: datetime, bucket_count: int
    ) -> tuple[dict[int, float], dict[int, float]]:
        per_period_kw: dict[str, float] = {}
        per_period_kvar: dict[str, float] = {}
        for group_type in ("_CFG_PWRSRCTYPE_GRID", "_CFG_PWRSRCTYPE_SOLAR", "_CFG_PWRSRCTYPE_BESS"):
            for row in self._query_rollup(store, grid_id, group_type, start_dt, stop_dt):
                kw = row["avg_kw"]
                if group_type == "_CFG_PWRSRCTYPE_BESS" and kw <= 0:
                    continue
                period = row["period_start_utc"]
                per_period_kw[period] = per_period_kw.get(period, 0.0) + kw
                per_period_kvar[period] = per_period_kvar.get(period, 0.0) + row["avg_kvar"]
        kw_rows = [{"time": period, "avg_kw": value} for period, value in per_period_kw.items()]
        kvar_rows = [{"time": period, "avg_kvar": value} for period, value in per_period_kvar.items()]
        return (
            self._bucketize(kw_rows, "avg_kw", start_dt, stop_dt, bucket_count),
            self._bucketize(kvar_rows, "avg_kvar", start_dt, stop_dt, bucket_count),
        )

    def _trend_rows(
        self,
        rows: list[dict[str, Any]],
        selected_device: dict[str, Any] | None,
        window: str,
        zoom: float,
        from_date: str,
        to_date: str,
        start_time: str,
        end_time: str,
    ) -> tuple[list[dict[str, Any]], str]:
        if not self._influx_client:
            return [], "No historical PQM data (Influx not connected)"
        duration, base_buckets = _WINDOW_SPECS.get(window, _WINDOW_SPECS["1h"])
        bucket_count = max(8, round(base_buckets / max(0.75, zoom)))
        now = datetime.now(PLANT_LOCAL_TZ).replace(second=0, microsecond=0)
        now -= timedelta(minutes=now.minute % 5)
        start_dt, stop_dt = self._resolve_range(now, duration, from_date, to_date, start_time, end_time)
        span = stop_dt - start_dt

        p_buckets: dict[int, float] = {}
        q_buckets: dict[int, float] = {}
        if selected_device is not None:
            if span <= _RAW_SPAN_LIMIT_SINGLE_DEVICE:
                p_buckets, q_buckets = self._source_pq_buckets(selected_device["sourceId"], start_dt, stop_dt, bucket_count)
                note = ""
            else:
                note = "Not enough data: single-device trend only covers up to 1 week (select 15m/1h/1D/1W, or All Facilities for 1M)"
        elif span <= _RAW_SPAN_LIMIT:
            # Raw path: P and Q are summed over the supply-side devices, PF is derived from the
            # SUMMED P/Q (previously PF was simply not computed here -> empty 15m/1h PF trend).
            p_buckets, q_buckets, note = self._aggregate_pq_buckets(rows, start_dt, stop_dt, bucket_count)
        else:
            store = self._rollup_hourly if span <= _HOURLY_ROLLUP_SPAN_LIMIT else self._rollup_daily
            if store is None:
                note = "Rollup data not available for this window"
            else:
                grid_id = self._topology_vm.selectedGridId
                p_buckets, q_buckets = self._rollup_pq_buckets(store, grid_id, start_dt, stop_dt, bucket_count)
                note = ""
        series = self._series_from_pq(p_buckets, q_buckets)
        if not series:
            return [], note or "No historical PQM data for this selection"

        label_fmt = self._trend_label_format(duration)
        trend_rows = []
        for index in range(bucket_count):
            if index not in series:
                continue
            bucket_dt = start_dt + span * index / max(1, bucket_count - 1)
            trend_rows.append({"label": bucket_dt.strftime(label_fmt), **series[index]})
        if len(trend_rows) < 2:
            return [], "Not enough historical PQM data for this selection"
        return trend_rows, ""
