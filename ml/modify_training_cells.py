import json

with open('Feature_Engineering_and_label_generation.ipynb', 'r') as f:
    nb = json.load(f)

# ============================================================
# HELPER: Create DL training code for regression tasks
# ============================================================
def make_dl_regression_code(task_name, target_col, run_name, ylog_transform=True):
    if ylog_transform:
        ytr_line = 'ytr = signed_log1p(train["' + target_col + '"])'
        yva_line = 'yva = signed_log1p(val["' + target_col + '"])'
        yte_orig = 'yte_orig = test["' + target_col + '"].astype(float)'
    else:
        ytr_line = 'ytr = train["' + target_col + '"].astype(float)'
        yva_line = 'yva = val["' + target_col + '"].astype(float)'
        yte_orig = 'yte_orig = test["' + target_col + '"].astype(float)'
    
    return f'''

# ---------------------------------------------------------
# Deep Learning Models (Regression)
# ---------------------------------------------------------

# Scale features for DL (StandardScaler fitted on TRAIN only)
scaler_dl = StandardScaler().fit(Xtr)
Xtr_dl = scaler_dl.transform(Xtr)
Xva_dl = scaler_dl.transform(Xva)
Xte_dl = scaler_dl.transform(Xte)

# Prepare y arrays for DL
{ytr_line}
{yva_line}
{yte_orig}

# Convert to numpy
ytr_np = ytr.values if hasattr(ytr, 'values') else np.array(ytr)
yva_np = yva.values if hasattr(yva, 'values') else np.array(yva)

input_dim = Xtr_dl.shape[1]

print(f"\\n=== Training Deep Learning Models for {task_name} ===")
print(f"Input dim: {{input_dim}} | Train: {{len(Xtr_dl)}} | Val: {{len(Xva_dl)}} | Test: {{len(Xte_dl)}}")

# ---- MLP ----
print("\\n--- MLP ---")
mlp_reg = MLPRegressor(input_dim, hidden_dims=(128, 64, 32), dropout=0.2)
mlp_reg, mlp_history = train_dl_model(
    mlp_reg, Xtr_dl, ytr_np, Xva_dl, yva_np,
    task='regression', epochs=100, batch_size=256, lr=1e-3, patience=15
)
mlp_metrics, mlp_preds = evaluate_dl_regression(mlp_reg, Xte_dl, yte_orig)
print(f"MLP Test: MAE={{mlp_metrics['MAE']:.2f}}, RMSE={{mlp_metrics['RMSE']:.2f}}, R2={{mlp_metrics['R2']:.4f}}")

# ---- ResNet-style MLP ----
print("\\n--- ResNet MLP ---")
resnet_reg = ResNetMLPRegressor(input_dim, hidden_dim=128, n_blocks=3, dropout=0.2)
resnet_reg, resnet_history = train_dl_model(
    resnet_reg, Xtr_dl, ytr_np, Xva_dl, yva_np,
    task='regression', epochs=100, batch_size=256, lr=1e-3, patience=15
)
resnet_metrics, resnet_preds = evaluate_dl_regression(resnet_reg, Xte_dl, yte_orig)
print(f"ResNet MLP Test: MAE={{resnet_metrics['MAE']:.2f}}, RMSE={{resnet_metrics['RMSE']:.2f}}, R2={{resnet_metrics['R2']:.4f}}")

# ---------------------------------------------------------
# Combine DL results with traditional ML comparison
# ---------------------------------------------------------

# Add DL models to comparison
comparison["MLP"] = {{"test_MAE": mlp_metrics['MAE'], "test_RMSE": mlp_metrics['RMSE'], "test_R2": mlp_metrics['R2'], "params": "hidden=(128,64,32), dropout=0.2"}}
comparison["ResNet_MLP"] = {{"test_MAE": resnet_metrics['MAE'], "test_RMSE": resnet_metrics['RMSE'], "test_R2": resnet_metrics['R2'], "params": "hidden=128, blocks=3, dropout=0.2"}}

# Save DL model artifacts
import joblib
joblib.dump(mlp_reg.state_dict(), ARTIFACTS_DIR / "{run_name}" / "mlp_state_dict.pt")
joblib.dump(scaler_dl, ARTIFACTS_DIR / "{run_name}" / "scaler_dl.pkl")
joblib.dump(resnet_reg.state_dict(), ARTIFACTS_DIR / "{run_name}" / "resnet_state_dict.pt")

# Update metrics dict for saving
metrics["test_dl"] = {{
    "MLP": mlp_metrics,
    "ResNet_MLP": resnet_metrics
}}
metrics["algorithm_comparison"] = comparison
'''

# ============================================================
# HELPER: Create DL training code for classification (Risk)
# ============================================================
def make_dl_classification_code(task_name, target_col, run_name):
    return f'''

# ---------------------------------------------------------
# Deep Learning Models (Classification)
# ---------------------------------------------------------

# Scale features for DL (StandardScaler fitted on TRAIN only)
scaler_dl = StandardScaler().fit(Xtr)
Xtr_dl = scaler_dl.transform(Xtr)
Xva_dl = scaler_dl.transform(Xva)
Xte_dl = scaler_dl.transform(Xte)

# Prepare y arrays for DL
ytr = train["{target_col}"].astype(int)
yva = val["{target_col}"].astype(int)
yte = test["{target_col}"].astype(int)

ytr_np = ytr.values
yva_np = yva.values
yte_np = yte.values

input_dim = Xtr_dl.shape[1]

print(f"\\n=== Training Deep Learning Models for {task_name} ===")
print(f"Input dim: {{input_dim}} | Train: {{len(Xtr_dl)}} | Val: {{len(Xva_dl)}} | Test: {{len(Xte_dl)}}")

# ---- MLP Classifier ----
print("\\n--- MLP Classifier ---")
mlp_clf = MLPClassifier(input_dim, hidden_dims=(128, 64, 32), dropout=0.2)
mlp_clf, mlp_history = train_dl_model(
    mlp_clf, Xtr_dl, ytr_np, Xva_dl, yva_np,
    task='classification', epochs=100, batch_size=256, lr=1e-3, patience=15
)
mlp_metrics, mlp_preds, mlp_probs = evaluate_dl_classification(mlp_clf, Xte_dl, yte_np)
print(f"MLP Test: Acc={{mlp_metrics['Accuracy']:.4f}}, F1={{mlp_metrics['F1_weighted']:.4f}}, ROC-AUC={{mlp_metrics['ROC_AUC']}}")

# ---- ResNet-style MLP Classifier ----
print("\\n--- ResNet MLP Classifier ---")
resnet_clf = ResNetMLPClassifier(input_dim, hidden_dim=128, n_blocks=3, dropout=0.2)
resnet_clf, resnet_history = train_dl_model(
    resnet_clf, Xtr_dl, ytr_np, Xva_dl, yva_np,
    task='classification', epochs=100, batch_size=256, lr=1e-3, patience=15
)
resnet_metrics, resnet_preds, resnet_probs = evaluate_dl_classification(resnet_clf, Xte_dl, yte_np)
print(f"ResNet MLP Test: Acc={{resnet_metrics['Accuracy']:.4f}}, F1={{resnet_metrics['F1_weighted']:.4f}}, ROC-AUC={{resnet_metrics['ROC_AUC']}}")

# ---------------------------------------------------------
# Combine DL results with traditional ML comparison
# ---------------------------------------------------------

comparison["MLP"] = {{"test_Accuracy": mlp_metrics['Accuracy'], "test_F1": mlp_metrics['F1_weighted'], "test_ROC_AUC": mlp_metrics['ROC_AUC'], "params": "hidden=(128,64,32), dropout=0.2"}}
comparison["ResNet_MLP"] = {{"test_Accuracy": resnet_metrics['Accuracy'], "test_F1": resnet_metrics['F1_weighted'], "test_ROC_AUC": resnet_metrics['ROC_AUC'], "params": "hidden=128, blocks=3, dropout=0.2"}}

# Save DL model artifacts
import joblib
joblib.dump(mlp_clf.state_dict(), ARTIFACTS_DIR / "{run_name}" / "mlp_state_dict.pt")
joblib.dump(scaler_dl, ARTIFACTS_DIR / "{run_name}" / "scaler_dl.pkl")
joblib.dump(resnet_clf.state_dict(), ARTIFACTS_DIR / "{run_name}" / "resnet_state_dict.pt")

# Update metrics dict for saving
metrics["test_dl"] = {{
    "MLP": mlp_metrics,
    "ResNet_MLP": resnet_metrics
}}
metrics["algorithm_comparison"] = comparison
'''

# ============================================================
# Now modify each training cell
# ============================================================

# Cell 25: Spending training code
spending_dl = make_dl_regression_code("Spending Prediction", "future_expense", "spending", ylog_transform=True)

spending_cell = nb['cells'][25]
spending_source = spending_cell['source']

# Find the line with "save_predict_api_meta(" that's not inside a function
insert_idx = -1
for i, line in enumerate(spending_source):
    if 'save_predict_api_meta(' in line:
        # Check it's not inside a function def
        context = ''.join(spending_source[max(0,i-10):i])
        if 'def ' not in context:
            insert_idx = i
            break

if insert_idx > 0:
    new_source = spending_source[:insert_idx] + [spending_dl + '\n\n'] + spending_source[insert_idx:]
    spending_cell['source'] = new_source
    print(f"Modified spending cell: inserted at line {insert_idx}")
else:
    print("Could not find insertion point for spending")

# Cell 27: Savings training code
savings_dl = make_dl_regression_code("Savings Prediction", "future_savings", "savings", ylog_transform=True)

savings_cell = nb['cells'][27]
savings_source = savings_cell['source']
insert_idx = -1
for i, line in enumerate(savings_source):
    if 'save_predict_api_meta(' in line:
        context = ''.join(savings_source[max(0,i-10):i])
        if 'def ' not in context:
            insert_idx = i
            break

if insert_idx > 0:
    new_source = savings_source[:insert_idx] + [savings_dl + '\n\n'] + savings_source[insert_idx:]
    savings_cell['source'] = new_source
    print(f"Modified savings cell: inserted at line {insert_idx}")
else:
    print("Could not find insertion point for savings")

# Cell 29: Wellness training code
wellness_dl = make_dl_regression_code("Wellness Prediction", "wellness_score", "wellness", ylog_transform=False)

wellness_cell = nb['cells'][29]
wellness_source = wellness_cell['source']
insert_idx = -1
for i, line in enumerate(wellness_source):
    if 'save_predict_api_meta(' in line:
        context = ''.join(wellness_source[max(0,i-10):i])
        if 'def ' not in context:
            insert_idx = i
            break

if insert_idx > 0:
    new_source = wellness_source[:insert_idx] + [wellness_dl + '\n\n'] + wellness_source[insert_idx:]
    wellness_cell['source'] = new_source
    print(f"Modified wellness cell: inserted at line {insert_idx}")
else:
    print("Could not find insertion point for wellness")

# Cell 31: Risk training code
risk_dl = make_dl_classification_code("Risk Prediction", "risk", "risk")

risk_cell = nb['cells'][31]
risk_source = risk_cell['source']
insert_idx = -1
for i, line in enumerate(risk_source):
    if 'save_predict_api_meta(' in line:
        context = ''.join(risk_source[max(0,i-10):i])
        if 'def ' not in context:
            insert_idx = i
            break

if insert_idx > 0:
    new_source = risk_source[:insert_idx] + [risk_dl + '\n\n'] + risk_source[insert_idx:]
    risk_cell['source'] = new_source
    print(f"Modified risk cell: inserted at line {insert_idx}")
else:
    print("Could not find insertion point for risk")

# ============================================================
# Update Dashboard cell (index 34)
# ============================================================
dashboard_cell = nb['cells'][34]

new_dashboard_code = '''from __future__ import annotations

import json
from pathlib import Path
import pandas as pd

ARTIFACTS_DIR = Path("/content/artifacts")

def load_metrics(model_name):
    path = ARTIFACTS_DIR / model_name / "training_metrics.json"
    if path.exists():
        with open(path) as f:
            return json.load(f)
    return None

def load_comparison(model_name):
    metrics = load_metrics(model_name)
    if metrics and "algorithm_comparison" in metrics:
        return metrics["algorithm_comparison"]
    return None

# ---------------------------------------------------------
# Print Comparison Tables for All 4 Tasks (5 Models Each)
# ---------------------------------------------------------

tasks = {
    "spending": ("Spending Prediction", ["MAE", "RMSE", "R2"]),
    "savings": ("Savings Prediction", ["MAE", "RMSE", "R2"]),
    "wellness": ("Wellness Prediction", ["MAE", "RMSE", "R2"]),
    "risk": ("Risk Prediction", ["Accuracy", "Precision_weighted", "Recall_weighted", "F1_weighted", "ROC_AUC"]),
}

for model_key, (title, metrics_names) in tasks.items():
    comp = load_comparison(model_key)
    if not comp:
        continue
    print(f"\\n{'='*80}")
    print(f"Model: {title.upper()} (5 Models)")
    print(f"{'='*80}")
    
    rows = []
    for algo, vals in comp.items():
        row = {"Algorithm": algo}
        for m in metrics_names:
            key = f"test_{m}" if f"test_{m}" in vals else f"val_{m}" if f"val_{m}" in vals else m
            row[m] = vals.get(key, vals.get(m, "N/A"))
        rows.append(row)
    
    df = pd.DataFrame(rows)
    print(df.to_string(index=False))

# Also print the detailed metrics for each model
print("\\n\\n" + "="*80)
print("DETAILED TEST METRICS PER MODEL")
print("="*80)

for model_key in ["spending", "savings", "wellness", "risk"]:
    metrics = load_metrics(model_key)
    if not metrics:
        continue
    print(f"\\n--- {model_key.upper()} ---")
    if "test" in metrics:
        test_m = metrics["test"]
        if isinstance(test_m, dict):
            for k, v in test_m.items():
                if k != "Confusion_Matrix":
                    print(f"  {k}: {v}")
    if "test_dl" in metrics:
        print("  Deep Learning:")
        for dl_name, dl_m in metrics["test_dl"].items():
            for k, v in dl_m.items():
                print(f"    {dl_name} {k}: {v}")'''

dashboard_cell['source'] = [new_dashboard_code + '\n']

# Save
with open('Feature_Engineering_and_label_generation.ipynb', 'w') as f:
    json.dump(nb, f, indent=2)

print("\nAll modifications complete!")