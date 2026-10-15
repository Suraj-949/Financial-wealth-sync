"""
Train all 4 tasks with DL models and generate final 5-model comparison tables.
"""
import sys
sys.path.insert(0, 'ml')

import torch
import torch.nn as nn
import torch.optim as optim
from torch.utils.data import DataLoader, TensorDataset
import numpy as np
import pandas as pd
import json
from pathlib import Path
from sklearn.preprocessing import StandardScaler
from sklearn.metrics import (mean_absolute_error, mean_squared_error, r2_score,
                             accuracy_score, precision_score, recall_score, f1_score, roc_auc_score)
import copy

# ML imports
from features.feature_engineering import build_monthly_features
from features.target_generation import add_future_targets, wellness_score, risk_flag
from data import load_user_monthly
from training.utils import split_by_ym, signed_log1p, signed_expm1
from sklearn.ensemble import RandomForestRegressor, GradientBoostingRegressor, RandomForestClassifier
from sklearn.linear_model import LogisticRegression
from xgboost import XGBRegressor, XGBClassifier

torch.manual_seed(42)
np.random.seed(42)
DEVICE = torch.device('cuda' if torch.cuda.is_available() else 'cpu')
print(f"Device: {DEVICE}")

# ============================================================
# DL Model Definitions
# ============================================================
class MLPRegressor(nn.Module):
    def __init__(self, input_dim, hidden_dims=(128, 64, 32), dropout=0.2):
        super().__init__()
        layers = []
        prev = input_dim
        for h in hidden_dims:
            layers.append(nn.Linear(prev, h))
            layers.append(nn.BatchNorm1d(h))
            layers.append(nn.ReLU())
            layers.append(nn.Dropout(dropout))
            prev = h
        layers.append(nn.Linear(prev, 1))
        self.net = nn.Sequential(*layers)
    def forward(self, x):
        return self.net(x).squeeze(-1)

class MLPClassifier(nn.Module):
    def __init__(self, input_dim, hidden_dims=(128, 64, 32), dropout=0.2):
        super().__init__()
        layers = []
        prev = input_dim
        for h in hidden_dims:
            layers.append(nn.Linear(prev, h))
            layers.append(nn.BatchNorm1d(h))
            layers.append(nn.ReLU())
            layers.append(nn.Dropout(dropout))
            prev = h
        layers.append(nn.Linear(prev, 1))
        self.net = nn.Sequential(*layers)
    def forward(self, x):
        return self.net(x).squeeze(-1)

class ResidualBlock(nn.Module):
    def __init__(self, dim, dropout=0.2):
        super().__init__()
        self.block = nn.Sequential(
            nn.Linear(dim, dim), nn.BatchNorm1d(dim), nn.ReLU(), nn.Dropout(dropout),
            nn.Linear(dim, dim), nn.BatchNorm1d(dim),
        )
        self.relu = nn.ReLU()
    def forward(self, x):
        return self.relu(x + self.block(x))

class ResNetMLPRegressor(nn.Module):
    def __init__(self, input_dim, hidden_dim=128, n_blocks=3, dropout=0.2):
        super().__init__()
        self.input_proj = nn.Sequential(
            nn.Linear(input_dim, hidden_dim), nn.BatchNorm1d(hidden_dim), nn.ReLU(), nn.Dropout(dropout))
        self.blocks = nn.Sequential(*[ResidualBlock(hidden_dim, dropout) for _ in range(n_blocks)])
        self.output = nn.Linear(hidden_dim, 1)
    def forward(self, x):
        x = self.input_proj(x)
        x = self.blocks(x)
        return self.output(x).squeeze(-1)

class ResNetMLPClassifier(nn.Module):
    def __init__(self, input_dim, hidden_dim=128, n_blocks=3, dropout=0.2):
        super().__init__()
        self.input_proj = nn.Sequential(
            nn.Linear(input_dim, hidden_dim), nn.BatchNorm1d(hidden_dim), nn.ReLU(), nn.Dropout(dropout))
        self.blocks = nn.Sequential(*[ResidualBlock(hidden_dim, dropout) for _ in range(n_blocks)])
        self.output = nn.Linear(hidden_dim, 1)
    def forward(self, x):
        x = self.input_proj(x)
        x = self.blocks(x)
        return self.output(x).squeeze(-1)

def train_dl_regression(model, X_train, y_train, X_val, y_val, epochs=80, batch_size=256, lr=1e-3, patience=12):
    model = model.to(DEVICE)
    train_ds = TensorDataset(torch.FloatTensor(X_train), torch.FloatTensor(y_train))
    val_ds = TensorDataset(torch.FloatTensor(X_val), torch.FloatTensor(y_val))
    train_loader = DataLoader(train_ds, batch_size=batch_size, shuffle=True)
    val_loader = DataLoader(val_ds, batch_size=batch_size, shuffle=False)
    criterion = nn.MSELoss()
    optimizer = optim.AdamW(model.parameters(), lr=lr, weight_decay=1e-4)
    scheduler = optim.lr_scheduler.ReduceLROnPlateau(optimizer, mode='min', factor=0.5, patience=6)
    best_val = float('inf')
    best_state = None
    no_improve = 0
    for epoch in range(epochs):
        model.train()
        tl = []
        for xb, yb in train_loader:
            xb, yb = xb.to(DEVICE), yb.to(DEVICE)
            optimizer.zero_grad()
            loss = criterion(model(xb), yb)
            loss.backward()
            optimizer.step()
            tl.append(loss.item())
        model.eval()
        vl = []
        with torch.no_grad():
            for xb, yb in val_loader:
                xb, yb = xb.to(DEVICE), yb.to(DEVICE)
                vl.append(criterion(model(xb), yb).item())
        avg_v = np.mean(vl)
        scheduler.step(avg_v)
        if avg_v < best_val:
            best_val = avg_v
            best_state = copy.deepcopy(model.state_dict())
            no_improve = 0
        else:
            no_improve += 1
            if no_improve >= patience:
                break
    if best_state:
        model.load_state_dict(best_state)
    return model

def train_dl_classification(model, X_train, y_train, X_val, y_val, epochs=80, batch_size=256, lr=1e-3, patience=12):
    model = model.to(DEVICE)
    train_ds = TensorDataset(torch.FloatTensor(X_train), torch.FloatTensor(y_train))
    val_ds = TensorDataset(torch.FloatTensor(X_val), torch.FloatTensor(y_val))
    train_loader = DataLoader(train_ds, batch_size=batch_size, shuffle=True)
    val_loader = DataLoader(val_ds, batch_size=batch_size, shuffle=False)
    criterion = nn.BCEWithLogitsLoss()
    optimizer = optim.AdamW(model.parameters(), lr=lr, weight_decay=1e-4)
    scheduler = optim.lr_scheduler.ReduceLROnPlateau(optimizer, mode='min', factor=0.5, patience=6)
    best_val = float('inf')
    best_state = None
    no_improve = 0
    for epoch in range(epochs):
        model.train()
        for xb, yb in train_loader:
            xb, yb = xb.to(DEVICE), yb.to(DEVICE)
            optimizer.zero_grad()
            loss = criterion(model(xb), yb)
            loss.backward()
            optimizer.step()
        model.eval()
        vl = []
        with torch.no_grad():
            for xb, yb in val_loader:
                xb, yb = xb.to(DEVICE), yb.to(DEVICE)
                vl.append(criterion(model(xb), yb).item())
        avg_v = np.mean(vl)
        scheduler.step(avg_v)
        if avg_v < best_val:
            best_val = avg_v
            best_state = copy.deepcopy(model.state_dict())
            no_improve = 0
        else:
            no_improve += 1
            if no_improve >= patience:
                break
    if best_state:
        model.load_state_dict(best_state)
    return model

def eval_dl_reg(model, X_test, y_test):
    model.eval()
    with torch.no_grad():
        pred = model(torch.FloatTensor(X_test).to(DEVICE)).cpu().numpy()
    return {'MAE': round(float(mean_absolute_error(y_test, pred)), 3),
            'RMSE': round(float(np.sqrt(mean_squared_error(y_test, pred))), 3),
            'R2': round(float(r2_score(y_test, pred)), 4)}, pred

def eval_dl_clf(model, X_test, y_test):
    model.eval()
    with torch.no_grad():
        logits = model(torch.FloatTensor(X_test).to(DEVICE)).cpu().numpy()
        probs = 1 / (1 + np.exp(-logits))
        preds = (probs >= 0.5).astype(int)
    try:
        auc = roc_auc_score(y_test, probs)
    except:
        auc = None
    return {'Accuracy': round(float(accuracy_score(y_test, preds)), 4),
            'Precision': round(float(precision_score(y_test, preds, average='weighted', zero_division=0)), 4),
            'Recall': round(float(recall_score(y_test, preds, average='weighted', zero_division=0)), 4),
            'F1': round(float(f1_score(y_test, preds, average='weighted', zero_division=0)), 4),
            'ROC_AUC': round(float(auc), 4) if auc else None}, preds, probs

# ============================================================
# Load and prepare data
# ============================================================
print("Loading data...")
monthly = load_user_monthly()
feats = build_monthly_features(monthly)
feats = add_future_targets(feats)
feats['wellness_score'] = wellness_score(feats)
feats['risk'] = risk_flag(feats)

FEATURES = [
    "income", "expense", "cash_flow", "expense_ratio",
    "expense_1m", "expense_2m", "expense_3m_mean",
    "income_1m", "income_2m", "income_3m_mean",
    "cash_flow_1m", "cash_flow_3m_mean",
    "expense_trend", "income_trend",
    "spending_stability", "income_stability",
    "txn_count", "avg_txn_amount", "month", "year",
]
cat_cols = [c for c in feats.columns if c.startswith("cat_")]
cat_used = [c for c in cat_cols if feats[c].sum() > 0]
ALL_FEATURES = FEATURES + cat_used

train, val, test = split_by_ym(feats)

# ----- Helper to clean & scale -----
def prep_regression(train_df, val_df, test_df, features, target_col, log_transform=True):
    Xtr = train_df[features]
    ytr_raw = train_df[target_col]
    Xva = val_df[features]
    yva_raw = val_df[target_col]
    Xte = test_df[features]
    yte = test_df[target_col].astype(float)
    if log_transform:
        ytr = signed_log1p(ytr_raw)
        yva = signed_log1p(yva_raw)
    else:
        ytr = ytr_raw.astype(float)
        yva = yva_raw.astype(float)
    # Drop NaN
    mtr = Xtr.notna().all(axis=1) & (~np.isnan(ytr)) & (~np.isinf(ytr))
    mva = Xva.notna().all(axis=1) & (~np.isnan(yva)) & (~np.isinf(yva))
    mte = Xte.notna().all(axis=1) & (~np.isnan(yte)) & (~np.isinf(yte))
    Xtr, ytr = Xtr[mtr], ytr[mtr]
    Xva, yva = Xva[mva], yva[mva]
    Xte, yte = Xte[mte], yte[mte]
    scaler = StandardScaler().fit(Xtr)
    return (scaler.transform(Xtr), ytr.values, scaler.transform(Xva), yva.values,
            scaler.transform(Xte), yte.values, scaler)

def prep_classification(train_df, val_df, test_df, features, target_col):
    Xtr = train_df[features]
    ytr = train_df[target_col].astype(int).values
    Xva = val_df[features]
    yva = val_df[target_col].astype(int).values
    Xte = test_df[features]
    yte = test_df[target_col].astype(int).values
    mtr = Xtr.notna().all(axis=1)
    mva = Xva.notna().all(axis=1)
    mte = Xte.notna().all(axis=1)
    Xtr, ytr = Xtr[mtr], ytr[mtr]
    Xva, yva = Xva[mva], yva[mva]
    Xte, yte = Xte[mte], yte[mte]
    scaler = StandardScaler().fit(Xtr)
    return scaler.transform(Xtr), ytr, scaler.transform(Xva), yva, scaler.transform(Xte), yte, scaler

# ============================================================
# Task 1: SPENDING
# ============================================================
print("\n" + "="*60)
print("TASK 1: SPENDING PREDICTION")
print("="*60)

Xtr, ytr, Xva, yva, Xte, yte, scaler = prep_regression(train, val, test, ALL_FEATURES, "future_expense")

# Traditional ML
results_spending = {}
for name, model in [
    ("RandomForestRegressor", RandomForestRegressor(n_estimators=250, max_depth=10, min_samples_leaf=1, random_state=42, n_jobs=-1)),
    ("GradientBoostingRegressor", GradientBoostingRegressor(n_estimators=100, learning_rate=0.05, max_depth=3, random_state=42)),
    ("XGBRegressor", XGBRegressor(n_estimators=100, learning_rate=0.05, max_depth=3, subsample=1.0, random_state=42, n_jobs=-1)),
]:
    model.fit(Xtr, ytr)
    pred = signed_expm1(model.predict(Xte))
    mae = mean_absolute_error(yte, pred)
    rmse = np.sqrt(mean_squared_error(yte, pred))
    r2 = r2_score(yte, pred)
    results_spending[name] = {'MAE': round(mae, 2), 'RMSE': round(rmse, 2), 'R2': round(r2, 4)}
    print(f"  {name}: MAE={mae:.1f}, RMSE={rmse:.1f}, R2={r2:.4f}")

# DL Models
input_dim = Xtr.shape[1]
print("  Training MLP...")
mlp = train_dl_regression(MLPRegressor(input_dim), Xtr, ytr, Xva, yva)
m, _ = eval_dl_reg(mlp, Xte, yte)
results_spending["MLP"] = m
print(f"  MLP: MAE={m['MAE']}, RMSE={m['RMSE']}, R2={m['R2']}")

print("  Training ResNet MLP...")
resnet = train_dl_regression(ResNetMLPRegressor(input_dim), Xtr, ytr, Xva, yva)
r, _ = eval_dl_reg(resnet, Xte, yte)
results_spending["ResNet_MLP"] = r
print(f"  ResNet_MLP: MAE={r['MAE']}, RMSE={r['RMSE']}, R2={r['R2']}")

# ============================================================
# Task 2: SAVINGS
# ============================================================
print("\n" + "="*60)
print("TASK 2: SAVINGS PREDICTION")
print("="*60)

SAVINGS_FEATURES = [
    "income", "expense", "cash_flow", "expense_ratio", "savings_ratio",
    "savings_1m", "savings_3m_mean",
    "income_1m", "income_2m", "income_3m_mean",
    "expense_1m", "expense_2m", "expense_3m_mean",
    "cash_flow_1m", "cash_flow_3m_mean",
    "income_trend", "expense_trend",
    "spending_stability", "income_stability",
    "txn_count", "avg_txn_amount", "month", "year",
]
Xtr, ytr, Xva, yva, Xte, yte, scaler = prep_regression(train, val, test, SAVINGS_FEATURES, "future_savings")

results_savings = {}
for name, model in [
    ("GradientBoostingRegressor", GradientBoostingRegressor(n_estimators=200, learning_rate=0.1, max_depth=3, random_state=42)),
    ("RandomForestRegressor", RandomForestRegressor(n_estimators=250, max_depth=10, min_samples_leaf=1, random_state=42, n_jobs=-1)),
    ("XGBRegressor", XGBRegressor(n_estimators=200, learning_rate=0.1, max_depth=3, subsample=1.0, random_state=42, n_jobs=-1)),
]:
    model.fit(Xtr, ytr)
    pred = signed_expm1(model.predict(Xte))
    mae = mean_absolute_error(yte, pred)
    rmse = np.sqrt(mean_squared_error(yte, pred))
    r2 = r2_score(yte, pred)
    results_savings[name] = {'MAE': round(mae, 2), 'RMSE': round(rmse, 2), 'R2': round(r2, 4)}
    print(f"  {name}: MAE={mae:.1f}, RMSE={rmse:.1f}, R2={r2:.4f}")

input_dim = Xtr.shape[1]
print("  Training MLP...")
mlp = train_dl_regression(MLPRegressor(input_dim), Xtr, ytr, Xva, yva)
m, _ = eval_dl_reg(mlp, Xte, yte)
results_savings["MLP"] = m
print(f"  MLP: MAE={m['MAE']}, RMSE={m['RMSE']}, R2={m['R2']}")

print("  Training ResNet MLP...")
resnet = train_dl_regression(ResNetMLPRegressor(input_dim), Xtr, ytr, Xva, yva)
r, _ = eval_dl_reg(resnet, Xte, yte)
results_savings["ResNet_MLP"] = r
print(f"  ResNet_MLP: MAE={r['MAE']}, RMSE={r['RMSE']}, R2={r['R2']}")

# ============================================================
# Task 3: WELLNESS
# ============================================================
print("\n" + "="*60)
print("TASK 3: WELLNESS PREDICTION")
print("="*60)

WELLNESS_FEATURES = [
    "income", "expense", "cash_flow", "expense_ratio", "savings_ratio", "rent_burden",
    "spending_stability", "income_stability",
    "savings_3m_mean", "cash_flow_3m_mean", "income_3m_mean", "expense_3m_mean",
    "income_trend", "expense_trend",
    "txn_count", "avg_txn_amount", "month", "year",
]
Xtr, ytr, Xva, yva, Xte, yte, scaler = prep_regression(train, val, test, WELLNESS_FEATURES, "wellness_score", log_transform=False)

results_wellness = {}
for name, model in [
    ("XGBRegressor", XGBRegressor(n_estimators=200, learning_rate=0.1, max_depth=4, subsample=1.0, random_state=42, n_jobs=-1)),
    ("RandomForestRegressor", RandomForestRegressor(n_estimators=250, max_depth=None, min_samples_leaf=1, random_state=42, n_jobs=-1)),
    ("GradientBoostingRegressor", GradientBoostingRegressor(n_estimators=200, learning_rate=0.1, max_depth=4, random_state=42)),
]:
    model.fit(Xtr, ytr)
    pred = model.predict(Xte)
    mae = mean_absolute_error(yte, pred)
    rmse = np.sqrt(mean_squared_error(yte, pred))
    r2 = r2_score(yte, pred)
    results_wellness[name] = {'MAE': round(mae, 3), 'RMSE': round(rmse, 3), 'R2': round(r2, 4)}
    print(f"  {name}: MAE={mae:.3f}, RMSE={rmse:.3f}, R2={r2:.4f}")

input_dim = Xtr.shape[1]
print("  Training MLP...")
mlp = train_dl_regression(MLPRegressor(input_dim), Xtr, ytr, Xva, yva)
m, _ = eval_dl_reg(mlp, Xte, yte)
results_wellness["MLP"] = m
print(f"  MLP: MAE={m['MAE']}, RMSE={m['RMSE']}, R2={m['R2']}")

print("  Training ResNet MLP...")
resnet = train_dl_regression(ResNetMLPRegressor(input_dim), Xtr, ytr, Xva, yva)
r, _ = eval_dl_reg(resnet, Xte, yte)
results_wellness["ResNet_MLP"] = r
print(f"  ResNet_MLP: MAE={r['MAE']}, RMSE={r['RMSE']}, R2={r['R2']}")

# ============================================================
# Task 4: RISK
# ============================================================
print("\n" + "="*60)
print("TASK 4: RISK PREDICTION")
print("="*60)

RISK_FEATURES = [
    "income", "expense", "cash_flow", "expense_ratio",
    "savings", "savings_ratio",
    "cash_flow_1m", "cash_flow_3m_mean",
    "income_1m", "income_2m", "income_3m_mean",
    "expense_1m", "expense_2m", "expense_3m_mean",
    "expense_trend", "income_trend",
    "spending_stability", "income_stability",
    "txn_count", "avg_txn_amount", "month", "year",
]
Xtr, ytr, Xva, yva, Xte, yte, scaler = prep_classification(train, val, test, RISK_FEATURES, "risk")

results_risk = {}
for name, model in [
    ("LogisticRegression", LogisticRegression(C=10.0, class_weight='balanced', max_iter=5000, random_state=42)),
    ("RandomForestClassifier", RandomForestClassifier(n_estimators=250, max_depth=None, min_samples_leaf=4, random_state=42, n_jobs=-1)),
    ("XGBClassifier", XGBClassifier(n_estimators=200, learning_rate=0.05, max_depth=3, subsample=1.0, random_state=42, n_jobs=-1, eval_metric='logloss')),
]:
    model.fit(Xtr, ytr)
    pred = model.predict(Xte)
    proba = model.predict_proba(Xte)[:, 1] if hasattr(model, 'predict_proba') else None
    acc = accuracy_score(yte, pred)
    prec = precision_score(yte, pred, average='weighted', zero_division=0)
    rec = recall_score(yte, pred, average='weighted', zero_division=0)
    f1 = f1_score(yte, pred, average='weighted', zero_division=0)
    auc = roc_auc_score(yte, proba) if proba is not None else None
    results_risk[name] = {'Accuracy': round(acc, 4), 'Precision': round(prec, 4), 'Recall': round(rec, 4), 'F1': round(f1, 4), 'ROC_AUC': round(auc, 4) if auc else None}
    print(f"  {name}: Acc={acc:.4f}, F1={f1:.4f}, ROC-AUC={auc:.4f}")

input_dim = Xtr.shape[1]
print("  Training MLP...")
mlp = train_dl_classification(MLPClassifier(input_dim), Xtr, ytr, Xva, yva)
m, _, _ = eval_dl_clf(mlp, Xte, yte)
results_risk["MLP"] = m
print(f"  MLP: Acc={m['Accuracy']:.4f}, F1={m['F1']:.4f}, ROC-AUC={m['ROC_AUC']}")

print("  Training ResNet MLP...")
resnet = train_dl_classification(ResNetMLPClassifier(input_dim), Xtr, ytr, Xva, yva)
r, _, _ = eval_dl_clf(resnet, Xte, yte)
results_risk["ResNet_MLP"] = r
print(f"  ResNet_MLP: Acc={r['Accuracy']:.4f}, F1={r['F1']:.4f}, ROC-AUC={r['ROC_AUC']}")

# ============================================================
# FINAL COMPARISON TABLES
# ============================================================
print("\n" + "="*80)
print("FINAL 5-MODEL COMPARISON TABLES")
print("="*80)

# Spending
print("\n### SPENDING PREDICTION (5 Models)")
df = pd.DataFrame([
    {"Algorithm": k, "MAE": v['MAE'], "RMSE": v['RMSE'], "R2": v['R2']}
    for k, v in results_spending.items()
])
print(df.to_string(index=False))

# Savings
print("\n### SAVINGS PREDICTION (5 Models)")
df = pd.DataFrame([
    {"Algorithm": k, "MAE": v['MAE'], "RMSE": v['RMSE'], "R2": v['R2']}
    for k, v in results_savings.items()
])
print(df.to_string(index=False))

# Wellness
print("\n### WELLNESS PREDICTION (5 Models)")
df = pd.DataFrame([
    {"Algorithm": k, "MAE": v['MAE'], "RMSE": v['RMSE'], "R2": v['R2']}
    for k, v in results_wellness.items()
])
print(df.to_string(index=False))

# Risk
print("\n### RISK PREDICTION (5 Models)")
df = pd.DataFrame([
    {"Algorithm": k, "Accuracy": v['Accuracy'], "Precision": v['Precision'], 
     "Recall": v['Recall'], "F1": v['F1'], "ROC_AUC": v['ROC_AUC']}
    for k, v in results_risk.items()
])
print(df.to_string(index=False))

# Best model per task
print("\n" + "="*80)
print("BEST MODEL PER TASK (by primary metric)")
print("="*80)
best_spending = min(results_spending, key=lambda k: results_spending[k]['MAE'])
best_savings = min(results_savings, key=lambda k: results_savings[k]['MAE'])
best_wellness = min(results_wellness, key=lambda k: results_wellness[k]['MAE'])
best_risk = max(results_risk, key=lambda k: results_risk[k]['ROC_AUC'] if results_risk[k]['ROC_AUC'] else -1)
print(f"Spending:   {best_spending} (MAE={results_spending[best_spending]['MAE']})")
print(f"Savings:    {best_savings} (MAE={results_savings[best_savings]['MAE']})")
print(f"Wellness:   {best_wellness} (MAE={results_wellness[best_wellness]['MAE']})")
print(f"Risk:       {best_risk} (ROC-AUC={results_risk[best_risk]['ROC_AUC']})")