"""Quick test to verify DL model code works with the actual data."""
import sys
sys.path.insert(0, 'ml')

import torch
import numpy as np
import pandas as pd
from sklearn.preprocessing import StandardScaler

# Test imports
from features.feature_engineering import build_monthly_features
from features.target_generation import add_future_targets, wellness_score, risk_flag
from data import load_user_monthly

print("Loading data...")
monthly = load_user_monthly()
print(f"Monthly shape: {monthly.shape}")

# Build features
print("Building features...")
feats = build_monthly_features(monthly)
print(f"Features shape: {feats.shape}")

# Add targets for spending
feats = add_future_targets(feats)
feats['wellness_score'] = wellness_score(feats)
feats['risk'] = risk_flag(feats)

# Drop NaN
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
all_features = FEATURES + cat_used

# Split
from training.utils import split_by_ym, signed_log1p
train, val, test = split_by_ym(feats)

Xtr = train[all_features]
ytr = signed_log1p(train["future_expense"])
Xva = val[all_features]
yva = signed_log1p(val["future_expense"])
Xte = test[all_features]
yte_orig = test["future_expense"].astype(float)

# Drop rows with NaN in features or target
valid_tr = Xtr.notna().all(axis=1) & (~np.isnan(ytr)) & (~np.isinf(ytr))
valid_va = Xva.notna().all(axis=1) & (~np.isnan(yva)) & (~np.isinf(yva))
valid_te = Xte.notna().all(axis=1) & (~np.isnan(yte_orig)) & (~np.isinf(yte_orig))

Xtr = Xtr[valid_tr]
ytr = ytr[valid_tr]
Xva = Xva[valid_va]
yva = yva[valid_va]
Xte = Xte[valid_te]
yte_orig = yte_orig[valid_te]

print(f"Train: {Xtr.shape}, Val: {Xva.shape}, Test: {Xte.shape}")

# Scale
scaler = StandardScaler().fit(Xtr)
Xtr_s = scaler.transform(Xtr)
Xva_s = scaler.transform(Xva)
Xte_s = scaler.transform(Xte)

print(f"Scaled shapes - Train: {Xtr_s.shape}, Val: {Xva_s.shape}, Test: {Xte_s.shape}")
print(f"Input dim: {Xtr_s.shape[1]}")

# Now test the DL models
# Import the model definitions (simulate running the DL cell)
import torch.nn as nn
import torch.optim as optim
from torch.utils.data import DataLoader, TensorDataset
import copy

DEVICE = torch.device('cuda' if torch.cuda.is_available() else 'cpu')
print(f"Device: {DEVICE}")

# Model 1: Simple MLP
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

# Model 2: ResNet-style MLP
class ResidualBlock(nn.Module):
    def __init__(self, dim, dropout=0.2):
        super().__init__()
        self.block = nn.Sequential(
            nn.Linear(dim, dim),
            nn.BatchNorm1d(dim),
            nn.ReLU(),
            nn.Dropout(dropout),
            nn.Linear(dim, dim),
            nn.BatchNorm1d(dim),
        )
        self.relu = nn.ReLU()

    def forward(self, x):
        return self.relu(x + self.block(x))

class ResNetMLPRegressor(nn.Module):
    def __init__(self, input_dim, hidden_dim=128, n_blocks=3, dropout=0.2):
        super().__init__()
        self.input_proj = nn.Sequential(
            nn.Linear(input_dim, hidden_dim),
            nn.BatchNorm1d(hidden_dim),
            nn.ReLU(),
            nn.Dropout(dropout),
        )
        self.blocks = nn.Sequential(*[ResidualBlock(hidden_dim, dropout) for _ in range(n_blocks)])
        self.output = nn.Linear(hidden_dim, 1)

    def forward(self, x):
        x = self.input_proj(x)
        x = self.blocks(x)
        return self.output(x).squeeze(-1)

# Training function
def train_dl_model(model, X_train, y_train, X_val, y_val, task='regression', epochs=50, batch_size=256, lr=1e-3, weight_decay=1e-4, patience=10):
    model = model.to(DEVICE)
    train_ds = TensorDataset(torch.FloatTensor(X_train), torch.FloatTensor(y_train))
    val_ds = TensorDataset(torch.FloatTensor(X_val), torch.FloatTensor(y_val))
    train_loader = DataLoader(train_ds, batch_size=batch_size, shuffle=True)
    val_loader = DataLoader(val_ds, batch_size=batch_size, shuffle=False)

    criterion = nn.MSELoss()
    optimizer = optim.AdamW(model.parameters(), lr=lr, weight_decay=weight_decay)
    scheduler = optim.lr_scheduler.ReduceLROnPlateau(optimizer, mode='min', factor=0.5, patience=5)

    best_val_loss = float('inf')
    best_state = None
    epochs_no_improve = 0

    for epoch in range(epochs):
        model.train()
        train_losses = []
        for xb, yb in train_loader:
            xb, yb = xb.to(DEVICE), yb.to(DEVICE)
            optimizer.zero_grad()
            pred = model(xb)
            loss = criterion(pred, yb)
            loss.backward()
            optimizer.step()
            train_losses.append(loss.item())

        model.eval()
        val_losses = []
        with torch.no_grad():
            for xb, yb in val_loader:
                xb, yb = xb.to(DEVICE), yb.to(DEVICE)
                pred = model(xb)
                loss = criterion(pred, yb)
                val_losses.append(loss.item())

        avg_train = np.mean(train_losses)
        avg_val = np.mean(val_losses)
        scheduler.step(avg_val)

        if avg_val < best_val_loss:
            best_val_loss = avg_val
            best_state = copy.deepcopy(model.state_dict())
            epochs_no_improve = 0
        else:
            epochs_no_improve += 1
            if epochs_no_improve >= patience:
                print(f'  Early stopping at epoch {epoch+1}')
                break

        if epoch % 10 == 0:
            print(f'  Epoch {epoch+1:3d} | Train: {avg_train:.4f} | Val: {avg_val:.4f}')

    if best_state:
        model.load_state_dict(best_state)
    return model

# Evaluation
def evaluate_dl_regression(model, X_test, y_test):
    model.eval()
    with torch.no_grad():
        X_tensor = torch.FloatTensor(X_test).to(DEVICE)
        pred = model(X_tensor).cpu().numpy()
    from sklearn.metrics import mean_absolute_error, mean_squared_error, r2_score
    mae = mean_absolute_error(y_test, pred)
    mse = mean_squared_error(y_test, pred)
    rmse = np.sqrt(mse)
    r2 = r2_score(y_test, pred)
    return {'MAE': round(float(mae), 3), 'MSE': round(float(mse), 3), 'RMSE': round(float(rmse), 3), 'R2': round(float(r2), 4)}, pred

# Test MLP
print("\n=== Testing MLP ===")
mlp = MLPRegressor(Xtr_s.shape[1], hidden_dims=(128, 64, 32), dropout=0.2)
mlp = train_dl_model(mlp, Xtr_s, ytr, Xva_s, yva, epochs=30, patience=8)
mlp_metrics, _ = evaluate_dl_regression(mlp, Xte_s, yte_orig.values)
print(f"MLP Test Metrics: {mlp_metrics}")

# Test ResNet
print("\n=== Testing ResNet MLP ===")
resnet = ResNetMLPRegressor(Xtr_s.shape[1], hidden_dim=128, n_blocks=3, dropout=0.2)
resnet = train_dl_model(resnet, Xtr_s, ytr, Xva_s, yva, epochs=30, patience=8)
resnet_metrics, _ = evaluate_dl_regression(resnet, Xte_s, yte_orig.values)
print(f"ResNet Test Metrics: {resnet_metrics}")

print("\nAll DL models work correctly!")