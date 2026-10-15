import json

with open('Model_Training_All_Tasks.ipynb', 'r', encoding='utf-8') as f:
    nb = json.load(f)

util_code = """
# Time windows for the dataset
TRAIN_MONTHS = ("2021-01", "2023-06")
VAL_MONTHS = ("2023-07", "2023-12")
TEST_MONTHS = ("2024-01", "2024-12")

def split_by_ym(df):
    '''Split monthly frames by the SAMPLE month (feature time), time-ordered.'''
    ym = df["ym_dt"].dt.strftime("%Y-%m")
    
    def window(lo: str, hi: str):
        return (ym >= lo) & (ym <= hi)
        
    train = df[window(*TRAIN_MONTHS)]
    val = df[window(*VAL_MONTHS)]
    test = df[window(*TEST_MONTHS)]
    return train, val, test

def signed_log1p(y):
    y = np.asarray(y, dtype=float)
    return np.sign(y) * np.log1p(np.abs(y))

def signed_expm1(y):
    return np.sign(y) * np.expm1(np.abs(y))
"""

for cell in nb.get('cells', []):
    if cell.get('cell_type') == 'code':
        source = cell.get('source', [])
        for i, line in enumerate(source):
            if 'from training.utils import split_by_ym, signed_log1p, signed_expm1' in line:
                source[i] = line.replace('from training.utils import split_by_ym, signed_log1p, signed_expm1', util_code)

with open('Model_Training_All_Tasks.ipynb', 'w', encoding='utf-8') as f:
    json.dump(nb, f, indent=1)

print('Updated successfully')
