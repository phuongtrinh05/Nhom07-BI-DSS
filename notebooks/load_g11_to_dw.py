# Nạp kết quả G11 vào MaterialDW (container sql2025, cổng 1435)
# Chạy: cd notebooks ; python load_g11_to_dw.py
# Chạy lại nhiều lần được: mỗi lần sẽ xóa các run "NHOM07_G11_*" cũ rồi nạp lại.

from datetime import datetime
from pathlib import Path
import pandas as pd
import pyodbc

import os
SA_PASSWORD = os.environ.get("MATERIALDW_SA_PASSWORD")
if not SA_PASSWORD:
    raise SystemExit("Set MATERIALDW_SA_PASSWORD before running, e.g. PowerShell: $env:MATERIALDW_SA_PASSWORD = '<password>'")

CONN_STR = (
    "DRIVER={ODBC Driver 18 for SQL Server};"
    "SERVER=localhost,1435;DATABASE=MaterialDW;"
    f"UID=sa;PWD={SA_PASSWORD};TrustServerCertificate=yes;"
)

PREFIX = "NHOM07_G11"
# Khung thời gian theo README / notebook G11
EVAL_WINDOW = ("2022-07-01", "2024-11-30", "2024-12-01", "2025-05-31")  # train, test
OFFICIAL_WINDOW = ("2022-07-01", "2025-05-31", None, None)               # refit toàn bộ lịch sử

OUTPUT_DIR = Path(__file__).resolve().parent.parent / "output"  # chạy từ thư mục nào cũng được

demand = pd.read_csv(OUTPUT_DIR / "G11_DW_demand_forecast_load.csv")
evals = pd.read_csv(OUTPUT_DIR / "G11_DW_forecast_evaluation_load.csv")
models = sorted(set(demand["SelectedModel"]) | set(evals["SelectedModel"]))

# Naive benchmark (G06): chỉ dùng để so sánh accuracy trên dashboard P2, KHÔNG phải model được chọn.
# Lấy đúng các cặp vật tư-tháng test đã có trong evals để cùng mẫu số với model được chọn.
BENCHMARK_MODEL = "Naive"
naive = pd.read_csv(OUTPUT_DIR / "G06_baseline_predictions.csv")
naive = naive[naive["Model"] == BENCHMARK_MODEL].copy()
naive["TestMonthKey"] = pd.to_datetime(naive["ForecastMonth"]).dt.strftime("%Y%m%d").astype(int)
naive = naive.merge(evals[["MaterialKey", "TestMonthKey", "ActualQty"]],
                    on=["MaterialKey", "TestMonthKey"], suffixes=("", "_sel"))
if len(naive) != len(evals) or (naive["ActualQty"] - naive["ActualQty_sel"]).abs().max() > 1e-6:
    raise SystemExit("Naive benchmark khong khop so dong/ActualQty voi evals - dung lai, chua ghi DW")
run_time = datetime.now().replace(microsecond=0)

conn = pyodbc.connect(CONN_STR, autocommit=False)
cur = conn.cursor()
try:
    # 1. Xóa dữ liệu của lần chạy trước (nếu có)
    old = f"SELECT ForecastRunKey FROM dbo.Dim_ForecastRun WHERE ForecastRunID LIKE '{PREFIX}_%'"
    cur.execute(f"DELETE FROM dbo.Fact_DemandForecast WHERE ForecastRunKey IN ({old})")
    cur.execute(f"DELETE FROM dbo.Fact_ForecastEvaluation WHERE ForecastRunKey IN ({old})")
    cur.execute(f"DELETE FROM dbo.Dim_ForecastRun WHERE ForecastRunID LIKE '{PREFIX}_%'")

    # 2. Tạo dòng Dim_ForecastRun: mỗi model có 1 run EVAL + 1 run OFFICIAL
    is_identity = cur.execute(
        "SELECT COLUMNPROPERTY(OBJECT_ID('dbo.Dim_ForecastRun'),'ForecastRunKey','IsIdentity')"
    ).fetchone()[0] == 1

    run_key = {}  # (kind, model) -> ForecastRunKey
    # (kind, model, window, IsSelected): model được chọn = 1; Naive benchmark = 0
    runs = [("EVAL", m, EVAL_WINDOW, 1) for m in models] \
         + [("OFFICIAL", m, OFFICIAL_WINDOW, 1) for m in models] \
         + [("BENCHMARK", BENCHMARK_MODEL, EVAL_WINDOW, 0)]
    for kind, m, (tr_s, tr_e, te_s, te_e), selected in runs:
        run_id = f"{PREFIX}_{kind}_{m}"
        vals = (run_id, m, run_time, tr_s, tr_e, te_s, te_e, selected)
        if is_identity:
            key = cur.execute(
                "INSERT INTO dbo.Dim_ForecastRun (ForecastRunID, ModelName, RunDate, TrainStart, TrainEnd, "
                "TestStart, TestEnd, IsSelected) OUTPUT INSERTED.ForecastRunKey VALUES (?,?,?,?,?,?,?,?)",
                *vals,
            ).fetchone()[0]
        else:
            key = cur.execute("SELECT ISNULL(MAX(ForecastRunKey),0)+1 FROM dbo.Dim_ForecastRun").fetchone()[0]
            cur.execute(
                "INSERT INTO dbo.Dim_ForecastRun (ForecastRunKey, ForecastRunID, ModelName, RunDate, TrainStart, "
                "TrainEnd, TestStart, TestEnd, IsSelected) VALUES (?,?,?,?,?,?,?,?,?)",
                key, *vals,
            )
        run_key[(kind, m)] = int(key)

    # 3. Fact_DemandForecast (dự báo chính thức 2025-06 -> 2025-11)
    rows = [
        (int(r.MaterialKey), int(r.ForecastMonthKey), run_key[("OFFICIAL", r.SelectedModel)],
         int(r.UoMKey), round(float(r.ForecastQty), 4),
         None if pd.isna(r.ForecastQtyPurchaseUoM) else round(float(r.ForecastQtyPurchaseUoM), 4))
        for r in demand.itertuples(index=False)
    ]
    cur.fast_executemany = True
    cur.executemany(
        "INSERT INTO dbo.Fact_DemandForecast (MaterialKey, ForecastMonthKey, ForecastRunKey, UoMKey, "
        "ForecastQty, ForecastQtyPurchaseUoM) VALUES (?,?,?,?,?,?)", rows)
    print(f"Fact_DemandForecast: {len(rows)} rows")

    # 4. Fact_ForecastEvaluation (kỳ test 2024-12 -> 2025-05)
    rows = [
        (int(r.MaterialKey), int(r.TestMonthKey), run_key[("EVAL", r.SelectedModel)],
         round(float(r.ActualQty), 4), round(float(r.ForecastQty), 4))
        for r in evals.itertuples(index=False)
    ] + [
        (int(r.MaterialKey), int(r.TestMonthKey), run_key[("BENCHMARK", BENCHMARK_MODEL)],
         round(float(r.ActualQty), 4), round(float(r.ForecastQty), 4))
        for r in naive.itertuples(index=False)
    ]
    cur.executemany(
        "INSERT INTO dbo.Fact_ForecastEvaluation (MaterialKey, TestMonthKey, ForecastRunKey, "
        "ActualQty, ForecastQty) VALUES (?,?,?,?,?)", rows)
    print(f"Fact_ForecastEvaluation: {len(rows)} rows")
    print(f"Dim_ForecastRun: {len(run_key)} runs")

    conn.commit()
    print("DONE - da commit vao MaterialDW")
except Exception as e:
    conn.rollback()
    print("LOI - da rollback, DW khong thay doi:\n", e)
finally:
    conn.close()
