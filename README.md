The forecasting pipeline predicts monthly material requirements in Purchase Unit and loads the selected official forecasts into `MaterialDW` for downstream DSS processing.

## Project Structure

```text
data/
    forecast_dataset.csv

notebooks/
    G06_Forecasting_Naive_MA.ipynb
    G09_Forecasting_ETS.ipynb
    G10_Forecasting_ARIMA.ipynb
    G11_Forecast_Model_Selection.ipynb

output/
    G06_*.csv
    G09_*.csv
    G10_*.csv
    G11_*.csv

Forecasting Workflow
The notebooks must be executed in this order:
1. G06_Forecasting_Naive_MA.ipynb
   - Data validation
   - Train/Test split
   - Naive
   - Moving Average (MA3, MA6)
   - MAE, RMSE, Bias
2. G09_Forecasting_ETS.ipynb
   - Simple Exponential Smoothing
   - Holt Trend
   - Holt-Winters / ETS Seasonal
   - 6-month test evaluation
3. G10_Forecasting_ARIMA.ipynb
   - Bounded ARIMA order search
   - AIC-based order selection using training data
   - 6-month test evaluation
4. G11_Forecast_Model_Selection.ipynb
   - Merge results from G06, G09 and G10
   - Select best model per material
   - Refit selected models
   - Generate official 6-month forecasts
   - Prepare DW load files
Forecast Window
Historical forecast window:
- 2022-07 to 2025-05
Evaluation design:
- Train: 2022-07 to 2024-11
- Test: 2024-12 to 2025-05
Official forecast horizon:
- 2025-06 to 2025-11
Model Selection
Models evaluated:
- Naive
- MA(3)
- MA(6)
- ETS Level
- ETS Trend
- ETS Seasonal
- ARIMA
Selection uses:
1. MAE as the primary metric
2. RMSE as secondary metric
3. Simpler model for near-ties
4. Bias as a diagnostic metric
Python Setup
Python 3 is required.
1. Clone the repository
git clone https://github.com/phuongtrinh05/Nhom07-BI-DSS.git
cd Nhom07-BI-DSS

2. Create virtual environment
Windows:
py -m venv .venv

3. Activate virtual environment
PowerShell:
.\.venv\Scripts\Activate.ps1

Command Prompt:
.venv\Scripts\activate

4. Install dependencies
python -m pip install --upgrade pip
pip install -r requirements.txt

5. Run Jupyter notebooks
Open the project in VS Code and select the Python interpreter from .venv.

Run notebooks in this order:
G06 → G09 → G10 → G11

Do not run G11 before the output files from G06, G09 and G10 have been generated.
Current Forecast Result
35 materials are in the forecasting scope.
- 34 materials have validated official forecasts.
- 1 material does not have a validated model because a complete 6-month test period is unavailable.
- Official forecast horizon contains 204 material-month forecasts.
Selected model distribution:
- ETS Seasonal: 28 materials
- MA(6): 3 materials
- ARIMA: 2 materials
- MA(3): 1 material
Missing historical months are not automatically treated as zero demand.
Data Warehouse Output
Final forecasting results are loaded into:
- Dim_ForecastRun
- Fact_ForecastEvaluation
- Fact_DemandForecast
The official forecast contains:
34 materials × 6 months = 204 forecast records