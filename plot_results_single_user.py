import os
import re
import pandas as pd
import matplotlib.pyplot as plt
import seaborn as sns
from datetime import datetime
import numpy as np

# --- Script Configuration ---
TARGET_USER_NORMALIZED = 'nick' # Focus on this user's data
BASE_RESULTS_DIR = "results"
BASE_PLOT_DIR = "plots"
SUMMARY_PLOT_DIR = os.path.join(BASE_PLOT_DIR, "summary") # For plots derived from TARGET_USER_NORMALIZED only

# --- Descriptive Mappings ---
USER_CPU_MAP = {
    'nick': 'Nicolò (Apple M2 Pro)', # Corrected key
    'nicola': 'Nicola (Intel Core i9 13th Gen)',
    'andrea': 'Andrea (Apple M1 Pro)'
}

SCENARIO_PARAMS_TO_NAME_MAP = {
    (10000, 10000, 10, 100, True, 1):  ("S1: Baseline (1T)", "S1: Baseline (RC10k, OC10k, FC10, FL100, RAF, 1 Thread)"),
    (100000, 10000, 10, 100, True, 1): ("S2: DS Medio (1T)", "S2: Dataset Medio (RC100k, OC10k, FC10, FL100, RAF, 1 Thread)"),
    (250000, 10000, 10, 100, True, 1): ("S3: DS Grande (1T)", "S3: Dataset Grande (RC250k, OC10k, FC10, FL100, RAF, 1 Thread)"),
    (10000, 10000, 1, 1000, True, 1): ("S4: Campo Singolo (1T)", "S4: Campo Singolo Grande (RC10k, OC10k, FC1, FL1k, RAF, 1 Thread)"),
    (10000, 10000, 10, 100, False, 1):("S5: Lett. Selettiva (1T)", "S5: Lettura Selettiva (RC10k, OC10k, FC10, FL100, !RAF, 1 Thread)"),
    (10000, 10000, 10, 100, True, 8):  ("S6: Baseline (8T)", "S6: Baseline (RC10k, OC10k, FC10, FL100, RAF, 8 Threads)"),
    (250000, 10000, 10, 100, True, 8): ("S7: DS Grande (8T)", "S7: Dataset Grande (RC250k, OC10k, FC10, FL100, RAF, 8 Threads)")
}

WORKLOAD_DESCRIPTION_MAP = {
    'workloada': "W_A: Update Heavy", 'workloadb': "W_B: Read Mostly", 'workloadc': "W_C: Read Only",
    'workloadd': "W_D: Read Latest", 'workloade': "W_E: Short Ranges", 'workloadf': "W_F: RMW"
}

DB_ORDER = ['mongo', 'cassandra', 'redis']
WORKLOAD_ORDER = ['workloada', 'workloadb', 'workloadc', 'workloadd', 'workloade', 'workloadf']

# Explicitly define SCENARIO_ORDER for correct plot ordering
SCENARIO_ORDER = [
    "S1: Baseline (1T)",
    "S2: DS Medio (1T)",
    "S3: DS Grande (1T)",
    "S4: Campo Singolo (1T)",
    "S5: Lett. Selettiva (1T)",
    "S6: Baseline (8T)",
    "S7: DS Grande (8T)"
]

SCENARIO_PATTERN = re.compile(r"rc(?P<recordcount>\d+)_oc(?P<operationcount>\d+)_fc(?P<fieldcount>\d+)_fl(?P<fieldlength>\d+)_raf(?P<readallfields>true|false)_th(?P<threads>\d+)")
FILE_PATTERN = re.compile(r"(?P<phase>load|run)_rep(?P<repetition>\d+)_"r"(?P<timestamp>\d{4}-\d{2}-\d{2}_\d{2}-\d{2}-\d{2})\.txt")

METRICS_PATTERNS = {
    "overall_throughput": re.compile(r"\[OVERALL\], Throughput\(ops/sec\), (?P<value>[\d\.]+)"),
    "read_avg_latency_us": re.compile(r"\[READ\], AverageLatency\(us\), (?P<value>[\d\.]+)"),
    "update_avg_latency_us": re.compile(r"\[UPDATE\], AverageLatency\(us\), (?P<value>[\d\.]+)"),
    "insert_avg_latency_us": re.compile(r"\[INSERT\], AverageLatency\(us\), (?P<value>[\d\.]+)"),
    "scan_avg_latency_us": re.compile(r"\[SCAN\], AverageLatency\(us\), (?P<value>[\d\.]+)"),
    "read_modify_write_avg_latency_us": re.compile(r"\[READ-MODIFY-WRITE\], AverageLatency\(us\), (?P<value>[\d\.]+)"),
    "read_95th_latency_us": re.compile(r"\[READ\], 95thPercentileLatency\(us\), (?P<value>[\d\.]+)"),
    "read_99th_latency_us": re.compile(r"\[READ\], 99thPercentileLatency\(us\), (?P<value>[\d\.]+)"),
    "update_95th_latency_us": re.compile(r"\[UPDATE\], 95thPercentileLatency\(us\), (?P<value>[\d\.]+)"),
    "update_99th_latency_us": re.compile(r"\[UPDATE\], 99thPercentileLatency\(us\), (?P<value>[\d\.]+)"),
    "insert_95th_latency_us": re.compile(r"\[INSERT\], 95thPercentileLatency\(us\), (?P<value>[\d\.]+)"),
    "insert_99th_latency_us": re.compile(r"\[INSERT\], 99thPercentileLatency\(us\), (?P<value>[\d\.]+)"),
    "scan_95th_latency_us": re.compile(r"\[SCAN\], 95thPercentileLatency\(us\), (?P<value>[\d\.]+)"),
    "scan_99th_latency_us": re.compile(r"\[SCAN\], 99thPercentileLatency\(us\), (?P<value>[\d\.]+)"),
    "read_modify_write_95th_latency_us": re.compile(r"\[READ-MODIFY-WRITE\], 95thPercentileLatency\(us\), (?P<value>[\d\.]+)"),
    "read_modify_write_99th_latency_us": re.compile(r"\[READ-MODIFY-WRITE\], 99thPercentileLatency\(us\), (?P<value>[\d\.]+)"),
}

WORKLOAD_PRIMARY_LATENCIES = {
    'workloada': [('Read Avg Latency (µs)', 'read_avg_latency_us'), ('Update Avg Latency (µs)', 'update_avg_latency_us')],
    'workloadb': [('Read Avg Latency (µs)', 'read_avg_latency_us')], 'workloadc': [('Read Avg Latency (µs)', 'read_avg_latency_us')],
    'workloadd': [('Read Avg Latency (µs)', 'read_avg_latency_us')], 'workloade': [('Scan Avg Latency (µs)', 'scan_avg_latency_us')],
    'workloadf': [('Read Avg Latency (µs)', 'read_avg_latency_us'), ('RMW Avg Latency (µs)', 'read_modify_write_avg_latency_us')]
}
WORKLOAD_LATENCY_PERCENTILES = {
    'workloada': [
        {'name': 'Read Latency (µs)', 'avg': 'read_avg_latency_us', 'p95': 'read_95th_latency_us', 'p99': 'read_99th_latency_us'},
        {'name': 'Update Latency (µs)', 'avg': 'update_avg_latency_us', 'p95': 'update_95th_latency_us', 'p99': 'update_99th_latency_us'}
    ],
    'workloadb': [{'name': 'Read Latency (µs)', 'avg': 'read_avg_latency_us', 'p95': 'read_95th_latency_us', 'p99': 'read_99th_latency_us'}],
    'workloadc': [{'name': 'Read Latency (µs)', 'avg': 'read_avg_latency_us', 'p95': 'read_95th_latency_us', 'p99': 'read_99th_latency_us'}],
    'workloadd': [
        {'name': 'Read Latency (µs)', 'avg': 'read_avg_latency_us', 'p95': 'read_95th_latency_us', 'p99': 'read_99th_latency_us'},
        {'name': 'Insert Latency (µs)', 'avg': 'insert_avg_latency_us', 'p95': 'insert_95th_latency_us', 'p99': 'insert_99th_latency_us'}
    ],
    'workloade': [{'name': 'Scan Latency (µs)', 'avg': 'scan_avg_latency_us', 'p95': 'scan_95th_latency_us', 'p99': 'scan_99th_latency_us'}],
    'workloadf': [
        {'name': 'Read Latency (µs)', 'avg': 'read_avg_latency_us', 'p95': 'read_95th_latency_us', 'p99': 'read_99th_latency_us'},
        {'name': 'RMW Latency (µs)', 'avg': 'read_modify_write_avg_latency_us', 'p95': 'read_modify_write_95th_latency_us', 'p99': 'read_modify_write_99th_latency_us'}
    ]
}

def parse_ycsb_output_file(file_path):
    metrics = {}
    try:
        with open(file_path, 'r') as f:
            content = f.read()
            for metric_name, pattern in METRICS_PATTERNS.items():
                match = pattern.search(content)
                metrics[metric_name] = float(match.group("value")) if match else None
    except IOError:
        print(f"Error reading file: {file_path}"); return None
    return metrics

def get_scenario_labels_from_row(row):
    key = (row['recordcount'], row['operationcount'], row['fieldcount'], 
           row['fieldlength'], row['readallfields'], row['threads'])
    short_label, full_label = SCENARIO_PARAMS_TO_NAME_MAP.get(key, ("Unknown Scenario", "Unknown Scenario Config"))
    return pd.Series([short_label, full_label])

def discover_and_parse_results(target_user_normalized=None):
    all_results = []
    if not os.path.exists(BASE_RESULTS_DIR): return pd.DataFrame()
    for user_dir_name in os.listdir(BASE_RESULTS_DIR):
        user_name_norm = user_dir_name.lower().replace('ò', 'o').replace(' ', '_')
        if target_user_normalized and user_name_norm != target_user_normalized:
            if user_name_norm in USER_CPU_MAP.keys(): # Only print warning if it was a known user we are intentionally skipping
                 print(f"INFO: Skipping user directory '{user_dir_name}' as it does not match target '{target_user_normalized}'.")
            continue 
        if not target_user_normalized and user_name_norm not in USER_CPU_MAP.keys():
            print(f"Warning: User directory '{user_dir_name}' (normalized: '{user_name_norm}') not in USER_CPU_MAP. Skipping for multi-user parse.")
            continue

        user_path = os.path.join(BASE_RESULTS_DIR, user_dir_name)
        if not os.path.isdir(user_path) or user_dir_name.startswith('.'): continue
        
        for db_dir in os.listdir(user_path):
            db_path = os.path.join(user_path, db_dir)
            if not os.path.isdir(db_path) or db_dir.startswith('.'): continue
            database_name = db_dir.lower()
            for workload_dir_name in os.listdir(db_path):
                workload_path = os.path.join(db_path, workload_dir_name)
                if not os.path.isdir(workload_path) or workload_dir_name.startswith('.'): continue
                for scenario_dir_name in os.listdir(workload_path):
                    scenario_path = os.path.join(workload_path, scenario_dir_name)
                    if not os.path.isdir(scenario_path) or scenario_dir_name.startswith('.'): continue
                    scenario_match = SCENARIO_PATTERN.match(scenario_dir_name)
                    if not scenario_match: continue
                    scenario_params = scenario_match.groupdict()
                    for filename in os.listdir(scenario_path):
                        if filename.startswith('.'): continue
                        file_match = FILE_PATTERN.match(filename)
                        if not file_match: continue
                        file_params = file_match.groupdict()
                        full_file_path = os.path.join(scenario_path, filename)
                        file_metrics = parse_ycsb_output_file(full_file_path)
                        if file_metrics:
                            record = { "user": user_name_norm, "database": database_name, "workload": workload_dir_name,
                                       "recordcount": int(scenario_params["recordcount"]),
                                       "operationcount": int(scenario_params["operationcount"]),
                                       "fieldcount": int(scenario_params["fieldcount"]),
                                       "fieldlength": int(scenario_params["fieldlength"]),
                                       "readallfields": scenario_params["readallfields"] == "true",
                                       "threads": int(scenario_params["threads"]),
                                       "phase": file_params["phase"],
                                       "repetition": int(file_params["repetition"]),
                                       "timestamp_str": file_params["timestamp"]}
                            record.update(file_metrics); all_results.append(record)
    df = pd.DataFrame(all_results)
    if not df.empty:
        required_scenario_key_cols = ['recordcount', 'operationcount', 'fieldcount', 'fieldlength', 'readallfields', 'threads']
        if all(col in df.columns for col in required_scenario_key_cols):
            df[['scenario_short_label', 'scenario_full_descr']] = df.apply(get_scenario_labels_from_row, axis=1)
        else:
            print("Warning: Not all columns required for scenario labels are present. Skipping label creation.")
            df['scenario_short_label'] = "Unknown"
            df['scenario_full_descr'] = "Unknown"
        df['cpu_description'] = df['user'].map(USER_CPU_MAP) 
    return df

def show_values_on_bars(axs, h_v="v", space=0.4, val_format="{:.0f}"):
    for p in axs.patches:
        _x = p.get_x() + p.get_width() / 2
        _y = p.get_y() + p.get_height()
        value = val_format.format(p.get_height())
        if h_v == "h":
            _x = p.get_x() + p.get_width() + float(space)
            _y = p.get_y() + p.get_height() / 2
            value = val_format.format(p.get_width())
        axs.text(_x, _y, value, ha="center", va="bottom" if h_v == "v" else "center", fontsize=8, color='dimgray')

def plot_throughput_comparison(df_to_plot, current_user_id, current_workload_id):
    user_descr = USER_CPU_MAP.get(current_user_id, current_user_id)
    workload_descr = WORKLOAD_DESCRIPTION_MAP.get(current_workload_id, current_workload_id)
    df_to_plot['database'] = pd.Categorical(df_to_plot['database'], categories=DB_ORDER, ordered=True)
    df_to_plot['scenario_short_label'] = pd.Categorical(df_to_plot['scenario_short_label'], categories=SCENARIO_ORDER, ordered=True)
    df_to_plot = df_to_plot.sort_values('scenario_short_label')
    fig, ax = plt.subplots(figsize=(17, 9))
    sns.barplot(x='database', y='overall_throughput', hue='scenario_short_label', data=df_to_plot, palette='viridis', dodge=True, ax=ax)
    show_values_on_bars(ax, val_format="{:,.0f}")
    max_y = df_to_plot['overall_throughput'].max()
    ax.set_ylim(0, max_y * 1.20 if pd.notna(max_y) and max_y > 0 else 100) 
    ax.set_title(f'Throughput: {workload_descr}\nUser: {user_descr}', fontsize=16, weight='bold')
    ax.set_ylabel('Mean Overall Throughput (ops/sec)', fontsize=13); ax.set_xlabel('Database', fontsize=13)
    ax.tick_params(axis='x', labelsize=11); ax.tick_params(axis='y', labelsize=11)
    ax.legend(title='Scenario (Threads)', bbox_to_anchor=(1.02, 1), loc='upper left', fontsize=9, title_fontsize=11)
    ax.grid(True, which='major', linestyle='--', linewidth=0.5); fig.tight_layout(rect=[0, 0, 0.78, 1])
    user_plot_dir = os.path.join(BASE_PLOT_DIR, current_user_id)
    os.makedirs(user_plot_dir, exist_ok=True)
    filename = os.path.join(user_plot_dir, f"{current_workload_id}_throughput_comparison.png")
    fig.savefig(filename, dpi=150); plt.close(fig)

def plot_latency_comparison(df_to_plot, current_user_id, current_workload_id):
    if current_workload_id not in WORKLOAD_PRIMARY_LATENCIES: return
    user_descr = USER_CPU_MAP.get(current_user_id, current_user_id)
    workload_descr = WORKLOAD_DESCRIPTION_MAP.get(current_workload_id, current_workload_id)
    for pretty_name, metric_col in WORKLOAD_PRIMARY_LATENCIES[current_workload_id]:
        if metric_col not in df_to_plot.columns or df_to_plot[metric_col].isna().all(): continue
        current_metric_df = df_to_plot[df_to_plot[metric_col].notna()].copy()
        if current_metric_df.empty: continue
        current_metric_df['database'] = pd.Categorical(current_metric_df['database'], categories=DB_ORDER, ordered=True)
        current_metric_df['scenario_short_label'] = pd.Categorical(current_metric_df['scenario_short_label'], categories=SCENARIO_ORDER, ordered=True)
        current_metric_df = current_metric_df.sort_values('scenario_short_label')
        fig, ax = plt.subplots(figsize=(17, 9))
        sns.barplot(x='database', y=metric_col, hue='scenario_short_label', data=current_metric_df, palette='plasma', dodge=True, ax=ax)
        show_values_on_bars(ax, val_format="{:,.0f}")
        max_y = current_metric_df[metric_col].max()
        ax.set_ylim(0, max_y * 1.20 if pd.notna(max_y) and max_y > 0 else 100)
        ax.set_title(f'{pretty_name}: {workload_descr}\nUser: {user_descr}', fontsize=16, weight='bold')
        ax.set_ylabel(f'Mean {pretty_name}', fontsize=13); ax.set_xlabel('Database', fontsize=13)
        ax.tick_params(axis='x', labelsize=11); ax.tick_params(axis='y', labelsize=11)
        ax.legend(title='Scenario (Threads)', bbox_to_anchor=(1.02, 1), loc='upper left', fontsize=9, title_fontsize=11)
        ax.grid(True, which='major', linestyle='--', linewidth=0.5); fig.tight_layout(rect=[0, 0, 0.78, 1])
        user_plot_dir = os.path.join(BASE_PLOT_DIR, current_user_id)
        os.makedirs(user_plot_dir, exist_ok=True)
        filename_metric_suffix = metric_col.replace('_avg_latency_us','_avg').replace('_latency_us','').replace('_','-')
        filename = os.path.join(user_plot_dir, f"{current_workload_id}_{filename_metric_suffix}_latency_comparison.png")
        fig.savefig(filename, dpi=150); plt.close(fig)

def plot_latency_percentiles(df_to_plot, current_user_id, current_workload_id, current_database):
    if current_workload_id not in WORKLOAD_LATENCY_PERCENTILES: return
    user_descr = USER_CPU_MAP.get(current_user_id, current_user_id)
    workload_descr = WORKLOAD_DESCRIPTION_MAP.get(current_workload_id, current_workload_id)
    for metric_group in WORKLOAD_LATENCY_PERCENTILES[current_workload_id]:
        metric_name_pretty, avg_col = metric_group['name'], metric_group['avg']
        p95_col, p99_col = metric_group.get('p95'), metric_group.get('p99')
        if avg_col not in df_to_plot.columns or df_to_plot[avg_col].isna().all(): continue
        current_metric_df = df_to_plot[df_to_plot[avg_col].notna()].copy()
        if current_metric_df.empty: continue
        current_metric_df['scenario_short_label'] = pd.Categorical(current_metric_df['scenario_short_label'], categories=SCENARIO_ORDER, ordered=True)
        current_metric_df = current_metric_df.sort_values('scenario_short_label')
        fig, ax = plt.subplots(figsize=(13, 7))
        title_str = f'{metric_name_pretty} Percentiles: {workload_descr}\nUser: {user_descr}, Database: {current_database.capitalize()}'
        lines_plotted = False; max_val = 0
        if avg_col in current_metric_df.columns and current_metric_df[avg_col].notna().any():
             sns.lineplot(x='scenario_short_label', y=avg_col, data=current_metric_df, marker='o', label='Mean', linewidth=2, errorbar=None, ax=ax); lines_plotted = True
             if not current_metric_df[avg_col].empty: max_val = max(max_val, current_metric_df[avg_col].max() if pd.notna(current_metric_df[avg_col].max()) else 0)
        if p95_col and p95_col in current_metric_df.columns and current_metric_df[p95_col].notna().any():
            sns.lineplot(x='scenario_short_label', y=p95_col, data=current_metric_df, marker='s', label='95th Pctl', linestyle='--', linewidth=2, errorbar=None, ax=ax); lines_plotted = True
            if not current_metric_df[p95_col].empty: max_val = max(max_val, current_metric_df[p95_col].max() if pd.notna(current_metric_df[p95_col].max()) else 0)
        if p99_col and p99_col in current_metric_df.columns and current_metric_df[p99_col].notna().any():
            sns.lineplot(x='scenario_short_label', y=p99_col, data=current_metric_df, marker='^', label='99th Pctl', linestyle=':', linewidth=2, errorbar=None, ax=ax); lines_plotted = True
            if not current_metric_df[p99_col].empty: max_val = max(max_val, current_metric_df[p99_col].max() if pd.notna(current_metric_df[p99_col].max()) else 0)
        if not lines_plotted: plt.close(fig); continue
        ax.set_ylim(0, max_val * 1.15 if max_val > 0 else 100)
        ax.set_title(title_str, fontsize=15, weight='bold'); ax.set_ylabel(f'{metric_name_pretty}', fontsize=13); ax.set_xlabel('Scenario (Threads)', fontsize=13)
        ax.tick_params(axis='x', rotation=45, labelsize=10); ax.tick_params(axis='y', labelsize=10)
        ax.legend(title='Metric', fontsize=10, title_fontsize=11)
        ax.grid(True, which='major', linestyle='--', linewidth=0.5); fig.tight_layout()
        user_plot_dir = os.path.join(BASE_PLOT_DIR, current_user_id)
        os.makedirs(user_plot_dir, exist_ok=True)
        filename_metric_suffix = avg_col.replace('_avg_latency_us','').replace('_latency_us','').replace('_','-')
        filename = os.path.join(user_plot_dir, f"{current_workload_id}_{current_database}_{filename_metric_suffix}_latency_percentiles.png")
        fig.savefig(filename, dpi=150); plt.close(fig)

# --- Single-User Focused Summary & Presentation Plotting Functions ---
def plot_workload_profile_per_db(mean_data_baseline, user_id, user_desc):
    target_plot_dir = os.path.join(BASE_PLOT_DIR, user_id, "summary_focused")
    os.makedirs(target_plot_dir, exist_ok=True)
    for db_id, group_data in mean_data_baseline.groupby('database'):
        if group_data.empty or group_data['overall_throughput'].isna().all(): continue
        group_data['workload_label'] = group_data['workload'].map(WORKLOAD_DESCRIPTION_MAP)
        workload_label_order = [WORKLOAD_DESCRIPTION_MAP[w] for w in WORKLOAD_ORDER if WORKLOAD_DESCRIPTION_MAP[w] in group_data['workload_label'].unique()]
        group_data['workload_label'] = pd.Categorical(group_data['workload_label'], categories=workload_label_order, ordered=True)
        group_data = group_data.sort_values('workload_label')
        fig, ax = plt.subplots(figsize=(13, 7))
        sns.barplot(x='workload_label', y='overall_throughput', data=group_data, palette='magma', hue='workload_label', dodge=False, legend=False, ax=ax)
        show_values_on_bars(ax, val_format="{:,.0f}")
        max_y = group_data['overall_throughput'].max()
        ax.set_ylim(0, max_y * 1.20 if pd.notna(max_y) and max_y > 0 else 100)
        ax.set_title(f'Workload Throughput Profile (S1 Baseline: 1 Thread)\n{db_id.capitalize()} for {user_desc}', fontsize=15, weight='bold')
        ax.set_xlabel('Workload Type', fontsize=13); ax.set_ylabel('Mean Throughput (ops/sec, S1 Baseline)', fontsize=13)
        ax.tick_params(axis='x', rotation=45, labelsize=10); ax.tick_params(axis='y', labelsize=10)
        ax.grid(True, axis='y', linestyle='--', linewidth=0.5); fig.tight_layout()
        filename = os.path.join(target_plot_dir, f"workload_profile_{user_id}_{db_id}.png")
        fig.savefig(filename, dpi=150); plt.close(fig)

def plot_aggregated_db_performance(user_data, user_id, user_desc):
    target_plot_dir = os.path.join(BASE_PLOT_DIR, user_id, "summary_focused")
    os.makedirs(target_plot_dir, exist_ok=True)
    agg_db_data = user_data.groupby('database', as_index=False)['overall_throughput'].mean()
    agg_db_data['database'] = pd.Categorical(agg_db_data['database'], categories=DB_ORDER, ordered=True)
    agg_db_data = agg_db_data.sort_values('database')
    if agg_db_data.empty or agg_db_data['overall_throughput'].isna().all(): return
    fig, ax = plt.subplots(figsize=(11, 7))
    sns.barplot(x='database', y='overall_throughput', data=agg_db_data, palette='crest', hue='database', dodge=False, legend=False, ax=ax)
    show_values_on_bars(ax, val_format="{:,.0f}")
    max_y = agg_db_data['overall_throughput'].max()
    ax.set_ylim(0, max_y * 1.20 if pd.notna(max_y) and max_y > 0 else 100)
    ax.set_title(f'Aggregated Database Performance for {user_desc}', fontsize=15, weight='bold')
    ax.set_xlabel('Database', fontsize=13); ax.set_ylabel('Overall Mean Throughput (ops/sec)\n(Avg All Workloads & Scenarios)', fontsize=12)
    ax.tick_params(axis='x', labelsize=11); ax.tick_params(axis='y', labelsize=11)
    ax.grid(True, axis='y', linestyle='--', linewidth=0.5); fig.tight_layout()
    filename = os.path.join(target_plot_dir, f"aggregated_db_performance_{user_id}.png")
    fig.savefig(filename, dpi=150); plt.close(fig)

def plot_scenario_impact_detailed(user_data, user_id):
    user_desc = USER_CPU_MAP.get(user_id, user_id)
    for (db_id, workload_id), group_data in user_data.groupby(['database', 'workload']):
        if group_data.empty or group_data['overall_throughput'].isna().all(): continue
        group_data['scenario_short_label'] = pd.Categorical(group_data['scenario_short_label'], categories=SCENARIO_ORDER, ordered=True)
        group_data = group_data.sort_values('scenario_short_label')
        fig, ax = plt.subplots(figsize=(13, 7))
        sns.lineplot(x='scenario_short_label', y='overall_throughput', data=group_data, marker='o', errorbar=None, linewidth=2.5, ax=ax)
        max_y = group_data['overall_throughput'].max()
        ax.set_ylim(0, max_y * 1.15 if pd.notna(max_y) and max_y > 0 else 100)
        workload_descr = WORKLOAD_DESCRIPTION_MAP.get(workload_id, workload_id)
        ax.set_title(f'Scenario Impact on Throughput: {db_id.capitalize()} - {workload_descr}\nUser: {user_desc}', fontsize=15, weight='bold')
        ax.set_xlabel('Scenario (Threads)', fontsize=13); ax.set_ylabel('Mean Throughput (ops/sec)', fontsize=13)
        ax.tick_params(axis='x', rotation=45, labelsize=10); ax.tick_params(axis='y', labelsize=10)
        ax.grid(True, linestyle='--', linewidth=0.5); fig.tight_layout()
        user_plot_dir = os.path.join(BASE_PLOT_DIR, user_id)
        os.makedirs(user_plot_dir, exist_ok=True)
        filename = os.path.join(user_plot_dir, f"{db_id}_{workload_id}_scenario_impact.png")
        fig.savefig(filename, dpi=150); plt.close(fig)

# --- New Single-User Analysis Plots ---
def plot_latency_heatmap(user_data, user_id, user_desc):
    target_plot_dir = os.path.join(BASE_PLOT_DIR, user_id, "analysis")
    os.makedirs(target_plot_dir, exist_ok=True)
    latency_cols = [m for m in METRICS_PATTERNS if 'avg_latency_us' in m]
    
    for db_id, db_data in user_data.groupby('database'):
        for wl_id, wl_data in db_data.groupby('workload'):
            heatmap_data_list = []
            for scen_short, scen_data in wl_data.groupby('scenario_short_label'):                
                for lat_col in latency_cols:
                    if lat_col in scen_data.columns and scen_data[lat_col].notna().any():
                        op_type = lat_col.split('_')[0].upper() # READ, UPDATE etc.
                        mean_lat = scen_data[lat_col].mean()
                        if pd.notna(mean_lat):
                            heatmap_data_list.append({'scenario': scen_short, 'operation': op_type, 'latency': mean_lat})
            
            if not heatmap_data_list: continue
            heatmap_df = pd.DataFrame(heatmap_data_list)
            if heatmap_df.empty: continue

            try:
                heatmap_pivot = heatmap_df.pivot(index="operation", columns="scenario", values="latency")
                heatmap_pivot = heatmap_pivot.reindex(columns=SCENARIO_ORDER).dropna(axis=1, how='all') # Ensure column order and drop empty scenarios
            except Exception as e:
                # print(f"Could not pivot for heatmap {db_id} {wl_id}: {e}")
                continue
            
            if heatmap_pivot.empty: continue

            fig, ax = plt.subplots(figsize=(14, 8))
            sns.heatmap(heatmap_pivot, annot=True, fmt=".0f", cmap="YlGnBu", linewidths=.5, ax=ax, annot_kws={"size":9})
            workload_descr = WORKLOAD_DESCRIPTION_MAP.get(wl_id, wl_id)
            ax.set_title(f'Mean Latency (µs) Heatmap: {db_id.capitalize()} - {workload_descr}\nUser: {user_desc}', fontsize=15, weight='bold')
            ax.set_xlabel("Scenario (Threads)", fontsize=12); ax.set_ylabel("Operation Type", fontsize=12)
            ax.tick_params(axis='x', rotation=45, labelsize=9); ax.tick_params(axis='y', rotation=0, labelsize=10)
            fig.tight_layout()
            filename = os.path.join(target_plot_dir, f"{db_id}_{wl_id}_latency_heatmap.png")
            fig.savefig(filename, dpi=150); plt.close(fig)

def plot_throughput_vs_latency(user_data, user_id, user_desc):
    target_plot_dir = os.path.join(BASE_PLOT_DIR, user_id, "analysis")
    os.makedirs(target_plot_dir, exist_ok=True)
    
    for (db_id, wl_id), group_data in user_data.groupby(['database', 'workload']):
        if group_data.empty: continue
        primary_lat_metrics = WORKLOAD_PRIMARY_LATENCIES.get(wl_id, [])
        if not primary_lat_metrics: continue
        lat_label, lat_col = primary_lat_metrics[0]
        
        if 'overall_throughput' not in group_data.columns or lat_col not in group_data.columns or \
           group_data['overall_throughput'].isna().all() or group_data[lat_col].isna().all():
            continue

        plot_df = group_data[group_data['overall_throughput'].notna() & group_data[lat_col].notna()].copy()
        if plot_df.empty: continue
        plot_df['scenario_short_label'] = pd.Categorical(plot_df['scenario_short_label'], categories=SCENARIO_ORDER, ordered=True)
        plot_df = plot_df.sort_values('scenario_short_label')

        fig, ax = plt.subplots(figsize=(12, 7))
        sns.scatterplot(x='overall_throughput', y=lat_col, hue='scenario_short_label', size='threads',
                        sizes=(50, 250), data=plot_df, ax=ax, palette='tab10', style='scenario_short_label', markers=True, hue_order=SCENARIO_ORDER)
        
        workload_descr = WORKLOAD_DESCRIPTION_MAP.get(wl_id, wl_id)
        ax.set_title(f'Throughput vs. {lat_label}: {db_id.capitalize()} - {workload_descr}\nUser: {user_desc}', fontsize=15, weight='bold')
        ax.set_xlabel('Mean Overall Throughput (ops/sec)', fontsize=12)
        ax.set_ylabel(f'Mean {lat_label}', fontsize=12)
        ax.tick_params(labelsize=10)
        ax.legend(title='Scenario (Threads)', bbox_to_anchor=(1.02, 1), loc='upper left', fontsize=9, title_fontsize=10)
        ax.grid(True, linestyle='--', linewidth=0.5); fig.tight_layout(rect=[0,0,0.80,1])
        filename = os.path.join(target_plot_dir, f"{db_id}_{wl_id}_throughput_vs_latency.png")
        fig.savefig(filename, dpi=150); plt.close(fig)

def plot_thread_scaling_throughput(user_data, user_id, user_desc):
    target_plot_dir = os.path.join(BASE_PLOT_DIR, user_id, "analysis")
    os.makedirs(target_plot_dir, exist_ok=True)

    s1_label = SCENARIO_PARAMS_TO_NAME_MAP.get((10000, 10000, 10, 100, True, 1))[0]
    s6_label = SCENARIO_PARAMS_TO_NAME_MAP.get((10000, 10000, 10, 100, True, 8))[0]
    s3_label = SCENARIO_PARAMS_TO_NAME_MAP.get((250000, 10000, 10, 100, True, 1))[0]
    s7_label = SCENARIO_PARAMS_TO_NAME_MAP.get((250000, 10000, 10, 100, True, 8))[0]

    scenarios_for_scaling = [s1_label, s6_label, s3_label, s7_label]
    scaling_df = user_data[user_data['scenario_short_label'].isin(scenarios_for_scaling)].copy()
    if scaling_df.empty: return

    scaling_df['base_scenario_group'] = np.where(scaling_df['scenario_short_label'].isin([s1_label, s6_label]), 'S1 vs S6 (Baseline Params)', 'S3 vs S7 (Large DS Params)')
    scaling_df['threads_cat'] = scaling_df['threads'].astype(str) + "T"
    scaling_df['workload_label'] = scaling_df['workload'].map(WORKLOAD_DESCRIPTION_MAP)
    workload_label_order = [WORKLOAD_DESCRIPTION_MAP[w] for w in WORKLOAD_ORDER if WORKLOAD_DESCRIPTION_MAP[w] in scaling_df['workload_label'].unique()]
    scaling_df['workload_label'] = pd.Categorical(scaling_df['workload_label'], categories=workload_label_order, ordered=True)
    scaling_df = scaling_df.sort_values('workload_label')

    for db_id, db_data in scaling_df.groupby('database'):
        if db_data.empty or db_data['overall_throughput'].isna().all(): continue
        
        g = sns.catplot(x='workload_label', y='overall_throughput', hue='threads_cat',
                        col='base_scenario_group', data=db_data, kind='bar', 
                        palette=['skyblue','steelblue'], dodge=True, hue_order=['1T','8T'],
                        height=6, aspect=1.2, legend=False, errorbar=None)

        g.set_axis_labels("Workload Type", "Mean Overall Throughput (ops/sec)")
        g.set_titles("{col_name}")
        for ax_col in g.axes.flatten():
            show_values_on_bars(ax_col, val_format="{:,.0f}")
            max_y_val = 0
            if not ax_col.patches:
                 max_y_val = 100 
            else:
                patch_heights = [p.get_height() for p in ax_col.patches if pd.notna(p.get_height())]
                if patch_heights: max_y_val = np.nanmax(patch_heights)
                else: max_y_val = 100 # default if all were NaN after filtering
            ax_col.set_ylim(0, max_y_val * 1.20 if max_y_val > 0 else 100)
            ax_col.grid(True, axis='y', linestyle='--', linewidth=0.5)
            ax_col.tick_params(axis='x', rotation=30, labelsize=9)
        
        g.fig.suptitle(f'Thread Scaling Impact on Throughput - {db_id.capitalize()}\nUser: {user_desc}', fontsize=16, weight='bold', y=1.03)
        g.add_legend(title='Threads', loc='upper right', bbox_to_anchor=(0.95, 0.95))
        g.tight_layout(rect=[0,0,1,0.97])
        
        filename = os.path.join(target_plot_dir, f"{db_id}_thread_scaling_throughput.png")
        g.savefig(filename, dpi=150); plt.close(g.fig)

def plot_latency_stability_boxplots(raw_run_data_user, user_id, user_desc):
    target_plot_dir = os.path.join(BASE_PLOT_DIR, user_id, "analysis")
    os.makedirs(target_plot_dir, exist_ok=True)
    s1_label = SCENARIO_PARAMS_TO_NAME_MAP.get((10000, 10000, 10, 100, True, 1))[0]
    s3_label = SCENARIO_PARAMS_TO_NAME_MAP.get((250000, 10000, 10, 100, True, 1))[0]
    s6_label = SCENARIO_PARAMS_TO_NAME_MAP.get((10000, 10000, 10, 100, True, 8))[0]
    s7_label = SCENARIO_PARAMS_TO_NAME_MAP.get((250000, 10000, 10, 100, True, 8))[0]
    scenarios_to_plot = [s1_label, s3_label, s6_label, s7_label]
    plot_data = raw_run_data_user[raw_run_data_user['scenario_short_label'].isin(scenarios_to_plot)].copy()
    if plot_data.empty: return

    for (db_id, wl_id, scen_label), group_data in plot_data.groupby(['database', 'workload', 'scenario_short_label']):
        primary_lat_metrics = WORKLOAD_PRIMARY_LATENCIES.get(wl_id, [])
        if not primary_lat_metrics: continue
        melted_data_list = []
        for pretty_name, metric_col in primary_lat_metrics:
            if metric_col in group_data.columns and group_data[metric_col].notna().any():
                for val in group_data[metric_col]: 
                    if pd.notna(val):
                        melted_data_list.append({'operation': pretty_name, 'latency': val})
        if not melted_data_list: continue
        melted_df = pd.DataFrame(melted_data_list)
        if melted_df.empty: continue
        fig, ax = plt.subplots(figsize=(10, 6))
        sns.boxplot(x='operation', y='latency', data=melted_df, hue='operation', palette='pastel', ax=ax, legend=False)
        workload_descr = WORKLOAD_DESCRIPTION_MAP.get(wl_id, wl_id)
        ax.set_title(f'Latency Stability: {db_id.capitalize()} - {workload_descr} - {scen_label}\nUser: {user_desc}', fontsize=14, weight='bold')
        ax.set_xlabel('Primary Operation', fontsize=12); ax.set_ylabel('Latency (µs) across Repetitions', fontsize=12)
        ax.tick_params(labelsize=10)
        ax.grid(True, axis='y', linestyle='--', linewidth=0.5); fig.tight_layout()
        filename_safe_scen_label = scen_label.replace(': ','_').replace('(','').replace(')','').replace(' ','_')
        filename = os.path.join(target_plot_dir, f"{db_id}_{wl_id}_{filename_safe_scen_label}_latency_stability.png")
        fig.savefig(filename, dpi=150); plt.close(fig)

# --- Presentation Plotting Functions (Modified for single user data) ---
def plot_presentation_overall_db_winner(user_mean_data, user_desc_title, out_dir):
    overall_avg = user_mean_data.groupby('database', as_index=False)['overall_throughput'].mean()
    overall_avg['database'] = pd.Categorical(overall_avg['database'], categories=DB_ORDER, ordered=True)
    overall_avg = overall_avg.sort_values('database')
    if overall_avg.empty or overall_avg['overall_throughput'].isna().all(): return
    fig, ax = plt.subplots(figsize=(10,7))
    sns.barplot(x='database', y='overall_throughput', data=overall_avg, palette='viridis', hue='database', dodge=False, legend=False, ax=ax)
    show_values_on_bars(ax, val_format="{:,.0f}")
    max_y = overall_avg['overall_throughput'].max()
    ax.set_ylim(0, max_y * 1.20 if pd.notna(max_y) and max_y > 0 else 100)
    ax.set_title(f'Overall Database Performance ({user_desc_title})\n(Avg. all Workloads & Scenarios)', fontsize=16, weight='bold')
    ax.set_xlabel('Database', fontsize=13); ax.set_ylabel('Mean Throughput (ops/sec)', fontsize=13)
    ax.tick_params(axis='x', labelsize=11); ax.tick_params(axis='y', labelsize=11)
    ax.grid(True, axis='y', linestyle='--', linewidth=0.5); fig.tight_layout()
    filename = os.path.join(out_dir, "P1_overall_db_performance.png")
    fig.savefig(filename, dpi=150); plt.close(fig)

def plot_presentation_workload_sensitivity_by_db(user_mean_data, user_desc_title, out_dir):
    db_workload_avg = user_mean_data.groupby(['database', 'workload'], as_index=False)['overall_throughput'].mean()
    db_workload_avg['database'] = pd.Categorical(db_workload_avg['database'], categories=DB_ORDER, ordered=True)
    db_workload_avg['workload_label'] = db_workload_avg['workload'].map(WORKLOAD_DESCRIPTION_MAP)
    workload_label_order = [WORKLOAD_DESCRIPTION_MAP[w] for w in WORKLOAD_ORDER if WORKLOAD_DESCRIPTION_MAP[w] in db_workload_avg['workload_label'].unique()]
    db_workload_avg['workload_label'] = pd.Categorical(db_workload_avg['workload_label'], categories=workload_label_order, ordered=True)
    db_workload_avg = db_workload_avg.sort_values(['database', 'workload_label'])
    if db_workload_avg.empty or db_workload_avg['overall_throughput'].isna().all(): return
    fig, ax = plt.subplots(figsize=(14,7))
    sns.lineplot(x='workload_label', y='overall_throughput', hue='database', data=db_workload_avg, style='database', markers=True, dashes=False, linewidth=2.5, errorbar=None, ax=ax)
    max_val = db_workload_avg['overall_throughput'].max()
    ax.set_ylim(0, max_val * 1.15 if pd.notna(max_val) and max_val > 0 else 100)
    ax.set_title(f'Database Throughput by Workload Type ({user_desc_title})\n(Avg. all Scenarios)', fontsize=16, weight='bold')
    ax.set_xlabel('Workload Type', fontsize=13); ax.set_ylabel('Mean Throughput (ops/sec)', fontsize=13)
    ax.tick_params(axis='x', rotation=45, labelsize=10); ax.tick_params(axis='y', labelsize=11)
    ax.legend(title='Database', fontsize=10, title_fontsize=11)
    ax.grid(True, linestyle='--', linewidth=0.5); fig.tight_layout()
    filename = os.path.join(out_dir, "P2_workload_sensitivity_by_db.png")
    fig.savefig(filename, dpi=150); plt.close(fig)

def plot_presentation_scenario_scalability_by_db(user_mean_data, user_desc_title, out_dir):
    db_scenario_avg = user_mean_data.groupby(['database', 'scenario_short_label'], as_index=False)['overall_throughput'].mean()
    db_scenario_avg['database'] = pd.Categorical(db_scenario_avg['database'], categories=DB_ORDER, ordered=True)
    db_scenario_avg['scenario_short_label'] = pd.Categorical(db_scenario_avg['scenario_short_label'], categories=SCENARIO_ORDER, ordered=True)
    db_scenario_avg = db_scenario_avg.sort_values(['database', 'scenario_short_label'])
    if db_scenario_avg.empty or db_scenario_avg['overall_throughput'].isna().all(): return
    fig, ax = plt.subplots(figsize=(14,7))
    sns.lineplot(x='scenario_short_label', y='overall_throughput', hue='database', data=db_scenario_avg, style='database', markers=True, dashes=False, linewidth=2.5, errorbar=None, ax=ax)
    max_val = db_scenario_avg['overall_throughput'].max()
    ax.set_ylim(0, max_val * 1.15 if pd.notna(max_val) and max_val > 0 else 100)
    ax.set_title(f'Database Throughput by Scenario ({user_desc_title})\n(Avg. all Workloads)', fontsize=16, weight='bold')
    ax.set_xlabel('Scenario (Threads)', fontsize=13); ax.set_ylabel('Mean Throughput (ops/sec)', fontsize=13)
    ax.tick_params(axis='x', rotation=45, labelsize=10); ax.tick_params(axis='y', labelsize=11)
    ax.legend(title='Database', fontsize=10, title_fontsize=11)
    ax.grid(True, linestyle='--', linewidth=0.5); fig.tight_layout()
    filename = os.path.join(out_dir, "P3_scenario_scalability_by_db.png")
    fig.savefig(filename, dpi=150); plt.close(fig)

# Modified main to adapt calls
if __name__ == "__main__":
    plt.style.use('seaborn-v0_8-whitegrid') # Apply style once
    print(f"Parsing results, focusing on user: '{TARGET_USER_NORMALIZED}'...")
    
    results_df = discover_and_parse_results(target_user_normalized=TARGET_USER_NORMALIZED)
    
    if results_df.empty:
        print(f"No results found for user '{TARGET_USER_NORMALIZED}'. Exiting."); exit()

    user_desc = USER_CPU_MAP.get(TARGET_USER_NORMALIZED, TARGET_USER_NORMALIZED)
    print(f"Processing data for: {user_desc}")

    run_df = results_df[results_df['phase'] == 'run'].copy() 
    if run_df.empty: print(f"No 'run' phase data for {user_desc}. Exiting."); exit()

    group_cols = ['user', 'cpu_description', 'database', 'workload', 
                  'scenario_short_label', 'scenario_full_descr',
                  'recordcount', 'operationcount', 'fieldcount', 'fieldlength', 'readallfields', 'threads']
    metric_cols = [col for col in METRICS_PATTERNS.keys() if col in run_df.columns]
    agg_functions = {metric: 'mean' for metric in metric_cols}
    mean_run_df = run_df.groupby(group_cols, as_index=False).agg(agg_functions)
    mean_run_df = mean_run_df.sort_values(by=['database', 'workload', 'scenario_short_label'])
    print(f"Mean run data prepared for {user_desc}. Shape: {mean_run_df.shape}")

    print(f"\n--- Generating Detailed Plots for {user_desc} ---")
    user_plot_dir = os.path.join(BASE_PLOT_DIR, TARGET_USER_NORMALIZED)
    analysis_plot_dir = os.path.join(user_plot_dir, "analysis")
    os.makedirs(user_plot_dir, exist_ok=True)
    os.makedirs(analysis_plot_dir, exist_ok=True)

    for workload_id in WORKLOAD_ORDER:
        workload_data_for_user = mean_run_df[mean_run_df['workload'] == workload_id]
        if workload_data_for_user.empty: continue
        print(f"  --- Detailed plots for Workload: {WORKLOAD_DESCRIPTION_MAP.get(workload_id, workload_id)} ---")
        
        throughput_plot_data = workload_data_for_user[workload_data_for_user['overall_throughput'].notna()]
        if not throughput_plot_data.empty:
             plot_throughput_comparison(throughput_plot_data, TARGET_USER_NORMALIZED, workload_id)
        
        plot_latency_comparison(workload_data_for_user, TARGET_USER_NORMALIZED, workload_id)
        
        for db_id in DB_ORDER:
            db_workload_data_for_user = workload_data_for_user[workload_data_for_user['database'] == db_id]
            if db_workload_data_for_user.empty: continue
            plot_latency_percentiles(db_workload_data_for_user, TARGET_USER_NORMALIZED, workload_id, db_id)
    
    summary_user_plot_dir = os.path.join(SUMMARY_PLOT_DIR, TARGET_USER_NORMALIZED)
    os.makedirs(summary_user_plot_dir, exist_ok=True)
    # Removed the nested "presentation" directory for single user summary plots to avoid confusion
    # os.makedirs(os.path.join(summary_user_plot_dir, "presentation"), exist_ok=True) 
    
    if not mean_run_df.empty:
        print(f"\n--- Generating User-Specific Summary Plots for {user_desc} ---")
        baseline_scenario_key = (10000, 10000, 10, 100, True, 1)
        if baseline_scenario_key in SCENARIO_PARAMS_TO_NAME_MAP: 
            baseline_scenario_label = SCENARIO_PARAMS_TO_NAME_MAP.get(baseline_scenario_key)[0]
            mean_run_df_baseline_s1 = mean_run_df[mean_run_df['scenario_short_label'] == baseline_scenario_label]
            if not mean_run_df_baseline_s1.empty:
                plot_workload_profile_per_db(mean_run_df_baseline_s1, TARGET_USER_NORMALIZED, user_desc) 
            else: print(f"  INFO: No S1 Baseline data for Workload Profiles for {user_desc}.")
        else: print("Warning: Baseline scenario key for S1 not found in SCENARIO_PARAMS_TO_NAME_MAP.")

        plot_aggregated_db_performance(mean_run_df, TARGET_USER_NORMALIZED, user_desc) 
        plot_scenario_impact_detailed(mean_run_df, TARGET_USER_NORMALIZED) 

        print(f"\n--- Generating New Analysis Plots for {user_desc} (saved in plots/{TARGET_USER_NORMALIZED}/analysis) ---")
        plot_latency_heatmap(mean_run_df, TARGET_USER_NORMALIZED, user_desc)
        plot_throughput_vs_latency(mean_run_df, TARGET_USER_NORMALIZED, user_desc)
        plot_thread_scaling_throughput(mean_run_df, TARGET_USER_NORMALIZED, user_desc)
        plot_latency_stability_boxplots(run_df, TARGET_USER_NORMALIZED, user_desc)

        print(f"\n--- Generating Presentation Plots for {user_desc} (saved in plots/summary/{TARGET_USER_NORMALIZED}/presentation) ---")
        # Corrected path for presentation plots for single user
        presentation_dir_user = os.path.join(summary_user_plot_dir, "presentation") 
        os.makedirs(presentation_dir_user, exist_ok=True)
        plot_presentation_overall_db_winner(mean_run_df, user_desc, presentation_dir_user)
        plot_presentation_workload_sensitivity_by_db(mean_run_df, user_desc, presentation_dir_user)
        plot_presentation_scenario_scalability_by_db(mean_run_df, user_desc, presentation_dir_user)
    else:
        print(f"INFO: mean_run_df for user '{TARGET_USER_NORMALIZED}' is empty, skipping summary/presentation plots.")

    print("\n--- All plot generation tasks complete. ---")

if __name__ == "__main__":
    main() 