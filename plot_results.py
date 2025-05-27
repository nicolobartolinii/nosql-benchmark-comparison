import os
import re
import pandas as pd
import matplotlib.pyplot as plt
import seaborn as sns
from datetime import datetime
import numpy as np # For mean/median calculations and inf handling

# Define the base directory for results
BASE_RESULTS_DIR = "results"
BASE_PLOT_DIR = "plots" # Define where plots are saved
SUMMARY_PLOT_DIR = os.path.join(BASE_PLOT_DIR, "summary")

# --- Descriptive Mappings ---
USER_CPU_MAP = {
    'nick': 'Nicolò (Apple M2 Pro)',
    'nicola': 'Nicola (Intel Core i9 13th Gen)',
    'andrea': 'Andrea (Apple M1 Pro)'
}

# Updated scenario definitions including threads
SCENARIO_PARAMS_TO_NAME_MAP = {
    # (recordcount, operationcount, fieldcount, fieldlength, readallfields, threads): ("Short Name for Legend", "Full Description for Titles")
    (10000, 10000, 10, 100, True, 1):  ("S1: Baseline (1T)", "S1: Baseline (RC10k, OC10k, FC10, FL100, RAF, 1 Thread)"),
    (100000, 10000, 10, 100, True, 1): ("S2: Dataset Medio (1T)", "S2: Dataset Medio (RC100k, OC10k, FC10, FL100, RAF, 1 Thread)"),
    (250000, 10000, 10, 100, True, 1): ("S3: Dataset Grande (1T)", "S3: Dataset Grande (RC250k, OC10k, FC10, FL100, RAF, 1 Thread)"),
    (10000, 10000, 1, 1000, True, 1): ("S4: Campo Singolo Grande (1T)", "S4: Campo Singolo Grande (RC10k, OC10k, FC1, FL1k, RAF, 1 Thread)"),
    (10000, 10000, 10, 100, False, 1):("S5: Lettura Selettiva (1T)", "S5: Lettura Selettiva (RC10k, OC10k, FC10, FL100, !RAF, 1 Thread)"),
    (10000, 10000, 10, 100, True, 8):  ("S6: Baseline (8T)", "S6: Baseline (RC10k, OC10k, FC10, FL100, RAF, 8 Threads)"),
    (250000, 10000, 10, 100, True, 8): ("S7: Dataset Grande (8T)", "S7: Dataset Grande (RC250k, OC10k, FC10, FL100, RAF, 8 Threads)")
}

WORKLOAD_DESCRIPTION_MAP = {
    'workloada': "Workload A (Update Heavy)",
    'workloadb': "Workload B (Read Mostly)",
    'workloadc': "Workload C (Read Only)",
    'workloadd': "Workload D (Read Latest)",
    'workloade': "Workload E (Short Ranges)",
    'workloadf': "Workload F (Read-Modify-Write)"
}

DB_ORDER = ['mongo', 'cassandra', 'redis']
WORKLOAD_ORDER = ['workloada', 'workloadb', 'workloadc', 'workloadd', 'workloade', 'workloadf']
# Generate SCENARIO_ORDER based on the new map keys to ensure correctness
# Sort keys by their tuple representation to maintain a logical order for S1-S7
SORTED_SCENARIO_KEYS = sorted(SCENARIO_PARAMS_TO_NAME_MAP.keys())
SCENARIO_ORDER = [SCENARIO_PARAMS_TO_NAME_MAP[k][0] for k in SORTED_SCENARIO_KEYS]


# Regex to parse scenario parameters from the directory name, now including threads
SCENARIO_PATTERN = re.compile(
    r"rc(?P<recordcount>\d+)_"
    r"oc(?P<operationcount>\d+)_"
    r"fc(?P<fieldcount>\d+)_"
    r"fl(?P<fieldlength>\d+)_"
    r"raf(?P<readallfields>true|false)_"
    r"th(?P<threads>\d+)" # Added threads part
)

FILE_PATTERN = re.compile(
    r"(?P<phase>load|run)_rep(?P<repetition>\d+)_" 
    r"(?P<timestamp>\d{4}-\d{2}-\d{2}_\d{2}-\d{2}-\d{2})\.txt"
)

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
    # Key now includes threads
    key = (row['recordcount'], row['operationcount'], row['fieldcount'], 
           row['fieldlength'], row['readallfields'], row['threads'])
    short_label, full_label = SCENARIO_PARAMS_TO_NAME_MAP.get(key, ("Unknown Scenario", "Unknown Scenario Config"))
    return pd.Series([short_label, full_label])

def discover_and_parse_results():
    all_results = []
    if not os.path.exists(BASE_RESULTS_DIR): return pd.DataFrame()
    for user_dir in os.listdir(BASE_RESULTS_DIR):
        user_path = os.path.join(BASE_RESULTS_DIR, user_dir)
        if user_dir.lower() not in USER_CPU_MAP.keys(): continue
        if not os.path.isdir(user_path) or user_dir.startswith('.'): continue
        user_name_norm = user_dir.lower().replace('ò', 'o').replace(' ', '_')
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
                    if not scenario_match:
                        # print(f"Warning: Could not parse scenario from dir: {scenario_dir_name} in {workload_path}")
                        continue
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
        df[['scenario_short_label', 'scenario_full_descr']] = df.apply(get_scenario_labels_from_row, axis=1)
        df['cpu_description'] = df['user'].map(USER_CPU_MAP)
    return df

# --- Plotting Functions (show_values_on_bars, plot_throughput_comparison, etc. remain largely the same but will use updated labels)
# Minor adjustments might be needed in titles or legend handling if threads are explicitly shown.

# Helper function (already provided, ensure it's in your script)
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

# Existing detailed plotting functions will now use the updated SCENARIO_ORDER 
# and scenario_short_label which includes thread info.

def plot_throughput_comparison(df_to_plot, current_user_id, current_workload_id):
    user_descr = USER_CPU_MAP.get(current_user_id, current_user_id)
    workload_descr = WORKLOAD_DESCRIPTION_MAP.get(current_workload_id, current_workload_id)
    df_to_plot['database'] = pd.Categorical(df_to_plot['database'], categories=DB_ORDER, ordered=True)
    # Ensure scenario_short_label is categorical for correct ordering in plot
    df_to_plot['scenario_short_label'] = pd.Categorical(df_to_plot['scenario_short_label'], categories=SCENARIO_ORDER, ordered=True)
    df_to_plot = df_to_plot.sort_values('scenario_short_label')

    fig, ax = plt.subplots(figsize=(17, 9)) # Wider for more scenarios
    sns.barplot(x='database', y='overall_throughput', hue='scenario_short_label', data=df_to_plot, palette='viridis', dodge=True, ax=ax)
    show_values_on_bars(ax, val_format="{:,.0f}")
    ax.set_ylim(0, df_to_plot['overall_throughput'].max() * 1.20 if not df_to_plot.empty and df_to_plot['overall_throughput'].max() > 0 else 100) 
    ax.set_title(f'Throughput: {workload_descr}\nUser: {user_descr}', fontsize=16, weight='bold')
    ax.set_ylabel('Mean Overall Throughput (ops/sec)', fontsize=13); ax.set_xlabel('Database', fontsize=13)
    ax.tick_params(axis='x', labelsize=11); ax.tick_params(axis='y', labelsize=11)
    ax.legend(title='Scenario (Threads)', bbox_to_anchor=(1.02, 1), loc='upper left', fontsize=9, title_fontsize=11)
    ax.grid(True, which='major', linestyle='--', linewidth=0.5); fig.tight_layout(rect=[0, 0, 0.78, 1]) # Adjust rect for wider legend
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
        ax.set_ylim(0, current_metric_df[metric_col].max() * 1.20 if not current_metric_df.empty and current_metric_df[metric_col].max() > 0 else 100)
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

        fig, ax = plt.subplots(figsize=(13, 7)) # Wider for scenario labels
        title_str = f'{metric_name_pretty} Percentiles: {workload_descr}\nUser: {user_descr}, Database: {current_database.capitalize()}'
        lines_plotted = False; max_val = 0
        if avg_col in current_metric_df.columns and current_metric_df[avg_col].notna().any():
             sns.lineplot(x='scenario_short_label', y=avg_col, data=current_metric_df, marker='o', label='Mean', linewidth=2, errorbar=None, ax=ax); lines_plotted = True
             if not current_metric_df[avg_col].empty: max_val = max(max_val, current_metric_df[avg_col].max())
        if p95_col and p95_col in current_metric_df.columns and current_metric_df[p95_col].notna().any():
            sns.lineplot(x='scenario_short_label', y=p95_col, data=current_metric_df, marker='s', label='95th Pctl', linestyle='--', linewidth=2, errorbar=None, ax=ax); lines_plotted = True
            if not current_metric_df[p95_col].empty: max_val = max(max_val, current_metric_df[p95_col].max())
        if p99_col and p99_col in current_metric_df.columns and current_metric_df[p99_col].notna().any():
            sns.lineplot(x='scenario_short_label', y=p99_col, data=current_metric_df, marker='^', label='99th Pctl', linestyle=':', linewidth=2, errorbar=None, ax=ax); lines_plotted = True
            if not current_metric_df[p99_col].empty: max_val = max(max_val, current_metric_df[p99_col].max())
        if not lines_plotted: plt.close(fig); continue
        ax.set_ylim(0, max_val * 1.15 if max_val > 0 else 100) # Increased padding
        ax.set_title(title_str, fontsize=15, weight='bold'); ax.set_ylabel(f'{metric_name_pretty}', fontsize=13); ax.set_xlabel('Scenario (Threads)', fontsize=13)
        ax.tick_params(axis='x', rotation=45, labelsize=10); ax.tick_params(axis='y', labelsize=10)
        ax.legend(title='Metric', fontsize=10, title_fontsize=11)
        ax.grid(True, which='major', linestyle='--', linewidth=0.5); fig.tight_layout()
        user_plot_dir = os.path.join(BASE_PLOT_DIR, current_user_id)
        os.makedirs(user_plot_dir, exist_ok=True)
        filename_metric_suffix = avg_col.replace('_avg_latency_us','').replace('_latency_us','').replace('_','-')
        filename = os.path.join(user_plot_dir, f"{current_workload_id}_{current_database}_{filename_metric_suffix}_latency_percentiles.png")
        fig.savefig(filename, dpi=150); plt.close(fig)

# --- Summary Plotting Functions ---
def plot_cpu_throughput_comparison(mean_data):
    os.makedirs(SUMMARY_PLOT_DIR, exist_ok=True)
    cpu_comp_data = mean_data.groupby(['user', 'cpu_description', 'database', 'workload'], as_index=False)['overall_throughput'].mean()
    for (db_id, workload_id), group_data in cpu_comp_data.groupby(['database', 'workload']):
        if group_data.empty or group_data['overall_throughput'].isna().all(): continue
        fig, ax = plt.subplots(figsize=(11, 7))
        sns.barplot(x='cpu_description', y='overall_throughput', data=group_data, palette='cubehelix', hue='cpu_description', dodge=False, legend=False, ax=ax)
        show_values_on_bars(ax, val_format="{:,.0f}")
        ax.set_ylim(0, group_data['overall_throughput'].max() * 1.20 if not group_data.empty else 100)
        workload_descr = WORKLOAD_DESCRIPTION_MAP.get(workload_id, workload_id)
        ax.set_title(f'CPU Throughput Comparison: {db_id.capitalize()} - {workload_descr}', fontsize=15, weight='bold')
        ax.set_xlabel('CPU (User)', fontsize=13); ax.set_ylabel('Mean Throughput (ops/sec, Avg over Scenarios)', fontsize=13)
        ax.tick_params(axis='x', rotation=15, labelsize=10); ax.tick_params(axis='y', labelsize=10)
        ax.grid(True, axis='y', linestyle='--', linewidth=0.5); fig.tight_layout()
        filename = os.path.join(SUMMARY_PLOT_DIR, f"cpu_throughput_{db_id}_{workload_id}.png")
        fig.savefig(filename, dpi=150); plt.close(fig)

def plot_workload_profile_per_cpu_db(mean_data_baseline):
    os.makedirs(SUMMARY_PLOT_DIR, exist_ok=True)
    for (user_id, db_id), group_data in mean_data_baseline.groupby(['user', 'database']):
        if group_data.empty or group_data['overall_throughput'].isna().all(): continue
        group_data['workload_label'] = group_data['workload'].map(WORKLOAD_DESCRIPTION_MAP)
        workload_label_order = [WORKLOAD_DESCRIPTION_MAP[w] for w in WORKLOAD_ORDER if w in group_data['workload'].unique()]
        group_data['workload_label'] = pd.Categorical(group_data['workload_label'], categories=workload_label_order, ordered=True)
        group_data = group_data.sort_values('workload_label')
        fig, ax = plt.subplots(figsize=(13, 7))
        sns.barplot(x='workload_label', y='overall_throughput', data=group_data, palette='magma', hue='workload_label', dodge=False, legend=False, ax=ax)
        show_values_on_bars(ax, val_format="{:,.0f}")
        ax.set_ylim(0, group_data['overall_throughput'].max() * 1.20 if not group_data.empty else 100)
        user_descr = USER_CPU_MAP.get(user_id, user_id)
        ax.set_title(f'Workload Throughput Profile (S1 Baseline: 1 Thread)\n{db_id.capitalize()} on {user_descr}', fontsize=15, weight='bold')
        ax.set_xlabel('Workload Type', fontsize=13); ax.set_ylabel('Mean Throughput (ops/sec, S1 Baseline)', fontsize=13)
        ax.tick_params(axis='x', rotation=30, ha='right', labelsize=10); ax.tick_params(axis='y', labelsize=10)
        ax.grid(True, axis='y', linestyle='--', linewidth=0.5); fig.tight_layout()
        filename = os.path.join(SUMMARY_PLOT_DIR, f"workload_profile_{user_id}_{db_id}.png")
        fig.savefig(filename, dpi=150); plt.close(fig)

def plot_aggregated_db_performance_per_cpu(mean_data):
    os.makedirs(SUMMARY_PLOT_DIR, exist_ok=True)
    agg_db_data = mean_data.groupby(['user', 'cpu_description', 'database'], as_index=False)['overall_throughput'].mean()
    agg_db_data['database'] = pd.Categorical(agg_db_data['database'], categories=DB_ORDER, ordered=True)
    agg_db_data = agg_db_data.sort_values('database')
    for user_id, group_data in agg_db_data.groupby('user'):
        if group_data.empty or group_data['overall_throughput'].isna().all(): continue
        fig, ax = plt.subplots(figsize=(11, 7))
        sns.barplot(x='database', y='overall_throughput', data=group_data, palette='crest', hue='database', dodge=False, legend=False, ax=ax)
        show_values_on_bars(ax, val_format="{:,.0f}")
        ax.set_ylim(0, group_data['overall_throughput'].max() * 1.20 if not group_data.empty else 100)
        user_descr = USER_CPU_MAP.get(user_id, user_id)
        ax.set_title(f'Aggregated Database Performance on {user_descr}', fontsize=15, weight='bold')
        ax.set_xlabel('Database', fontsize=13); ax.set_ylabel('Overall Mean Throughput (ops/sec)\n(Avg All Workloads & Scenarios)', fontsize=12)
        ax.tick_params(axis='x', labelsize=11); ax.tick_params(axis='y', labelsize=11)
        ax.grid(True, axis='y', linestyle='--', linewidth=0.5); fig.tight_layout()
        filename = os.path.join(SUMMARY_PLOT_DIR, f"aggregated_db_performance_{user_id}.png")
        fig.savefig(filename, dpi=150); plt.close(fig)

def plot_scenario_impact_detailed(mean_data):
    for (user_id, db_id, workload_id), group_data in mean_data.groupby(['user', 'database', 'workload']):
        if group_data.empty or group_data['overall_throughput'].isna().all(): continue
        group_data['scenario_short_label'] = pd.Categorical(group_data['scenario_short_label'], categories=SCENARIO_ORDER, ordered=True)
        group_data = group_data.sort_values('scenario_short_label')
        fig, ax = plt.subplots(figsize=(13, 7))
        sns.lineplot(x='scenario_short_label', y='overall_throughput', data=group_data, marker='o', errorbar=None, linewidth=2.5, ax=ax)
        ax.set_ylim(0, group_data['overall_throughput'].max() * 1.15 if not group_data.empty and group_data['overall_throughput'].max() > 0 else 100)
        user_descr = USER_CPU_MAP.get(user_id, user_id)
        workload_descr = WORKLOAD_DESCRIPTION_MAP.get(workload_id, workload_id)
        ax.set_title(f'Scenario Impact on Throughput: {db_id.capitalize()} - {workload_descr}\nUser: {user_descr}', fontsize=15, weight='bold')
        ax.set_xlabel('Scenario (Threads)', fontsize=13); ax.set_ylabel('Mean Throughput (ops/sec)', fontsize=13)
        ax.tick_params(axis='x', rotation=45, labelsize=10); ax.tick_params(axis='y', labelsize=10)
        ax.grid(True, linestyle='--', linewidth=0.5); fig.tight_layout()
        user_plot_dir = os.path.join(BASE_PLOT_DIR, user_id)
        os.makedirs(user_plot_dir, exist_ok=True)
        filename = os.path.join(user_plot_dir, f"{db_id}_{workload_id}_scenario_impact.png")
        fig.savefig(filename, dpi=150); plt.close(fig)

# --- Presentation Plotting Functions ---
def plot_presentation_overall_db_winner(mean_data):
    os.makedirs(os.path.join(SUMMARY_PLOT_DIR, "presentation"), exist_ok=True)
    overall_avg = mean_data.groupby('database', as_index=False)['overall_throughput'].mean()
    overall_avg['database'] = pd.Categorical(overall_avg['database'], categories=DB_ORDER, ordered=True)
    overall_avg = overall_avg.sort_values('database')
    if overall_avg.empty or overall_avg['overall_throughput'].isna().all(): return
    fig, ax = plt.subplots(figsize=(10,7))
    sns.barplot(x='database', y='overall_throughput', data=overall_avg, palette='viridis', hue='database', dodge=False, legend=False, ax=ax)
    show_values_on_bars(ax, val_format="{:,.0f}")
    ax.set_ylim(0, overall_avg['overall_throughput'].max() * 1.20 if not overall_avg.empty else 100)
    ax.set_title('Overall Database Performance (Grand Mean Throughput)', fontsize=16, weight='bold')
    ax.set_xlabel('Database', fontsize=13); ax.set_ylabel('Mean Throughput (ops/sec)\n(Avg. all Users, Workloads, Scenarios)', fontsize=13)
    ax.tick_params(axis='x', labelsize=11); ax.tick_params(axis='y', labelsize=11)
    ax.grid(True, axis='y', linestyle='--', linewidth=0.5); fig.tight_layout()
    filename = os.path.join(SUMMARY_PLOT_DIR, "presentation", "P1_overall_db_winner.png")
    fig.savefig(filename, dpi=150); plt.close(fig)

def plot_presentation_cpu_impact_on_dbs(mean_data):
    os.makedirs(os.path.join(SUMMARY_PLOT_DIR, "presentation"), exist_ok=True)
    cpu_db_avg = mean_data.groupby(['cpu_description', 'database'], as_index=False)['overall_throughput'].mean()
    cpu_db_avg['database'] = pd.Categorical(cpu_db_avg['database'], categories=DB_ORDER, ordered=True)
    cpu_order = [USER_CPU_MAP[user_id] for user_id in sorted(USER_CPU_MAP.keys()) if USER_CPU_MAP[user_id] in cpu_db_avg['cpu_description'].unique()]
    cpu_db_avg['cpu_description'] = pd.Categorical(cpu_db_avg['cpu_description'], categories=cpu_order, ordered=True)
    cpu_db_avg = cpu_db_avg.sort_values(['database', 'cpu_description'])
    if cpu_db_avg.empty or cpu_db_avg['overall_throughput'].isna().all(): return
    fig, ax = plt.subplots(figsize=(12,7))
    sns.barplot(x='database', y='overall_throughput', hue='cpu_description', data=cpu_db_avg, palette='Set2', ax=ax)
    show_values_on_bars(ax, val_format="{:,.0f}")
    ax.set_ylim(0, cpu_db_avg['overall_throughput'].max() * 1.20 if not cpu_db_avg.empty else 100)
    ax.set_title('CPU Impact on Database Throughput', fontsize=16, weight='bold')
    ax.set_xlabel('Database', fontsize=13); ax.set_ylabel('Mean Throughput (ops/sec)\n(Avg. all Workloads & Scenarios)', fontsize=13)
    ax.tick_params(axis='x', labelsize=11); ax.tick_params(axis='y', labelsize=11)
    ax.legend(title='CPU (User)', fontsize=10, title_fontsize=11)
    ax.grid(True, axis='y', linestyle='--', linewidth=0.5); fig.tight_layout()
    filename = os.path.join(SUMMARY_PLOT_DIR, "presentation", "P2_cpu_impact_on_dbs.png")
    fig.savefig(filename, dpi=150); plt.close(fig)

def plot_presentation_workload_sensitivity_by_db(mean_data):
    os.makedirs(os.path.join(SUMMARY_PLOT_DIR, "presentation"), exist_ok=True)
    db_workload_avg = mean_data.groupby(['database', 'workload'], as_index=False)['overall_throughput'].mean()
    db_workload_avg['database'] = pd.Categorical(db_workload_avg['database'], categories=DB_ORDER, ordered=True)
    db_workload_avg['workload_label'] = db_workload_avg['workload'].map(WORKLOAD_DESCRIPTION_MAP)
    workload_label_order = [WORKLOAD_DESCRIPTION_MAP[w] for w in WORKLOAD_ORDER if w in db_workload_avg['workload'].unique()]
    db_workload_avg['workload_label'] = pd.Categorical(db_workload_avg['workload_label'], categories=workload_label_order, ordered=True)
    db_workload_avg = db_workload_avg.sort_values(['database', 'workload_label'])
    if db_workload_avg.empty or db_workload_avg['overall_throughput'].isna().all(): return
    fig, ax = plt.subplots(figsize=(13,7))
    sns.lineplot(x='workload_label', y='overall_throughput', hue='database', data=db_workload_avg, style='database', markers=True, dashes=False, linewidth=2.5, errorbar=None, ax=ax)
    max_val = db_workload_avg['overall_throughput'].max()
    ax.set_ylim(0, max_val * 1.15 if max_val > 0 else 100)
    ax.set_title('Database Throughput by Workload Type', fontsize=16, weight='bold')
    ax.set_xlabel('Workload Type', fontsize=13); ax.set_ylabel('Mean Throughput (ops/sec)\n(Avg. all Users & Scenarios)', fontsize=13)
    ax.tick_params(axis='x', rotation=45, labelsize=10); ax.tick_params(axis='y', labelsize=11)
    ax.legend(title='Database', fontsize=10, title_fontsize=11)
    ax.grid(True, linestyle='--', linewidth=0.5); fig.tight_layout()
    filename = os.path.join(SUMMARY_PLOT_DIR, "presentation", "P3_workload_sensitivity_by_db.png")
    fig.savefig(filename, dpi=150); plt.close(fig)

def plot_presentation_scenario_scalability_by_db(mean_data):
    os.makedirs(os.path.join(SUMMARY_PLOT_DIR, "presentation"), exist_ok=True)
    db_scenario_avg = mean_data.groupby(['database', 'scenario_short_label'], as_index=False)['overall_throughput'].mean()
    db_scenario_avg['database'] = pd.Categorical(db_scenario_avg['database'], categories=DB_ORDER, ordered=True)
    db_scenario_avg['scenario_short_label'] = pd.Categorical(db_scenario_avg['scenario_short_label'], categories=SCENARIO_ORDER, ordered=True)
    db_scenario_avg = db_scenario_avg.sort_values(['database', 'scenario_short_label'])
    if db_scenario_avg.empty or db_scenario_avg['overall_throughput'].isna().all(): return
    fig, ax = plt.subplots(figsize=(13,7))
    sns.lineplot(x='scenario_short_label', y='overall_throughput', hue='database', data=db_scenario_avg, style='database', markers=True, dashes=False, linewidth=2.5, errorbar=None, ax=ax)
    max_val = db_scenario_avg['overall_throughput'].max()
    ax.set_ylim(0, max_val * 1.15 if max_val > 0 else 100)
    ax.set_title('Database Throughput by Scenario', fontsize=16, weight='bold')
    ax.set_xlabel('Scenario (Threads)', fontsize=13); ax.set_ylabel('Mean Throughput (ops/sec)\n(Avg. all Users & Workloads)', fontsize=13)
    ax.tick_params(axis='x', rotation=45, labelsize=10); ax.tick_params(axis='y', labelsize=11)
    ax.legend(title='Database', fontsize=10, title_fontsize=11)
    ax.grid(True, linestyle='--', linewidth=0.5); fig.tight_layout()
    filename = os.path.join(SUMMARY_PLOT_DIR, "presentation", "P4_scenario_scalability_by_db.png")
    fig.savefig(filename, dpi=150); plt.close(fig)

def main():
    plt.style.use('seaborn-v0_8')
    print("Parsing results...")
    results_df = discover_and_parse_results()
    if results_df.empty: print("No results found. Exiting."); return

    run_df = results_df[results_df['phase'] == 'run'].copy()
    if run_df.empty: print("No 'run' phase data. Exiting."); return

    group_cols = ['user', 'cpu_description', 'database', 'workload', 'scenario_short_label', 'scenario_full_descr',
                  'recordcount', 'operationcount', 'fieldcount', 'fieldlength', 'readallfields', 'threads']
    metric_cols = [col for col in METRICS_PATTERNS.keys() if col in run_df.columns]
    agg_functions = {metric: 'mean' for metric in metric_cols} # Mean of repetitions
    mean_run_df = run_df.groupby(group_cols, as_index=False).agg(agg_functions)
    mean_run_df = mean_run_df.sort_values(by=['user', 'workload', 'database', 'scenario_short_label'])
    print(f"Data prepared. Mean run data shape: {mean_run_df.shape}")

    print("\n--- Generating Detailed Plots ---")
    unique_users = sorted(mean_run_df['user'].unique())
    for user_id in unique_users:
        print(f"\n>>> Detailed plots for USER: {USER_CPU_MAP.get(user_id, user_id)} <<<")
        user_data = mean_run_df[mean_run_df['user'] == user_id]
        if user_data.empty: continue
        for workload_id in WORKLOAD_ORDER:
            workload_data = user_data[user_data['workload'] == workload_id]
            if workload_data.empty: continue
            # print(f"  --- Detailed Workload: {WORKLOAD_DESCRIPTION_MAP.get(workload_id, workload_id)} ---")
            throughput_plot_data = workload_data[workload_data['overall_throughput'].notna()]
            if not throughput_plot_data.empty:
                 plot_throughput_comparison(throughput_plot_data, user_id, workload_id)
            plot_latency_comparison(workload_data, user_id, workload_id)
            for db_id in DB_ORDER:
                db_workload_data = workload_data[workload_data['database'] == db_id]
                if db_workload_data.empty: continue
                plot_latency_percentiles(db_workload_data, user_id, workload_id, db_id)
    
    print("\n--- Generating Summary Plots (from previous step) ---")
    os.makedirs(SUMMARY_PLOT_DIR, exist_ok=True)
    if not mean_run_df.empty:
        plot_cpu_throughput_comparison(mean_run_df)
        baseline_scenario_key = (10000, 10000, 10, 100, True, 1) # Includes threads for key
        baseline_scenario_label = SCENARIO_PARAMS_TO_NAME_MAP.get(baseline_scenario_key)[0] 
        mean_run_df_baseline_s1 = mean_run_df[mean_run_df['scenario_short_label'] == baseline_scenario_label]
        if not mean_run_df_baseline_s1.empty:
            plot_workload_profile_per_cpu_db(mean_run_df_baseline_s1)
        else: print("  INFO: No S1 Baseline data for Workload Profiles.")
        plot_aggregated_db_performance_per_cpu(mean_run_df)
        plot_scenario_impact_detailed(mean_run_df)
    else: print("INFO: mean_run_df is empty, skipping summary plots.")

    print("\n--- Generating New Presentation Plots ---")
    os.makedirs(os.path.join(SUMMARY_PLOT_DIR, "presentation"), exist_ok=True)
    if not mean_run_df.empty:
        plot_presentation_overall_db_winner(mean_run_df)
        plot_presentation_cpu_impact_on_dbs(mean_run_df)
        plot_presentation_workload_sensitivity_by_db(mean_run_df)
        plot_presentation_scenario_scalability_by_db(mean_run_df)
    else: print("INFO: mean_run_df is empty, skipping presentation plots.")

    print("\n--- All plot generation tasks complete. ---")

if __name__ == "__main__":
    main() 