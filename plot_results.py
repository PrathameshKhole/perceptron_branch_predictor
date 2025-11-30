#!/usr/bin/env python3
"""
Branch Predictor Results Visualization (v3)
- Fixed label overlaps
- Better legend positioning
- X86 focused
- Deep pastel colors

Usage: python3 plot_results.py [--dir RESULTS_DIR] [--output OUTPUT_DIR]
"""

import os
import sys
import argparse
import pandas as pd
import numpy as np
import matplotlib.pyplot as plt
import matplotlib.patches as mpatches
from pathlib import Path

# ============================================================================
# COLOR SCHEME
# ============================================================================

COLORS = {
    'HybridPerceptronBP': '#7B9E89',      # Deep sage green
    'PerceptronLocalBP': '#8FA5B5',       # Deep steel blue
    'LocalBP': '#C4A484',                 # Deep tan/camel
    'TournamentBP': '#B784A7',            # Deep mauve
    'LTAGE': '#9B8AA5',                   # Deep lavender
}

SHORT_NAMES = {
    'HybridPerceptronBP': 'Hybrid',
    'PerceptronLocalBP': 'Perceptron',
    'LocalBP': 'Local',
    'TournamentBP': 'Tournament',
    'LTAGE': 'LTAGE',
}

BENCHMARK_LABELS = {
    'binary_search': 'Binary Search',
    'branch_loop': 'Branch Loop',
    'linked_list': 'Linked List',
    'matrix': 'Matrix Mult',
    'quicksort': 'Quicksort',
    'hello': 'Hello World',
}

BG_COLOR = '#FAFAFA'
GRID_COLOR = '#E0E0E0'
TEXT_COLOR = '#2C3E50'

# ============================================================================
# DATA LOADING
# ============================================================================

def parse_stats_file(filepath):
    stats = {}
    try:
        with open(filepath, 'r') as f:
            for line in f:
                if 'branchPred.condPredicted ' in line:
                    stats['branches'] = int(line.split()[1])
                elif 'branchPred.condIncorrect ' in line:
                    stats['mispredictions'] = int(line.split()[1])
                elif 'simInsts ' in line and 'instructions' not in stats:
                    stats['instructions'] = int(line.split()[1])
                elif 'simTicks ' in line and 'ticks' not in stats:
                    stats['ticks'] = int(line.split()[1])

        if all(k in stats for k in ['branches', 'mispredictions', 'instructions']):
            stats['accuracy'] = 100 - (stats['mispredictions'] * 100 / stats['branches'])
            stats['mpki'] = stats['mispredictions'] * 1000 / stats['instructions']
            return stats
    except Exception as e:
        print(f"Error parsing {filepath}: {e}")
    return None

def load_results_from_csv(csv_path):
    if os.path.exists(csv_path):
        return pd.read_csv(csv_path)
    return None

def load_results_from_dirs(results_dir, cpu_compare=False):
    data = []

    if cpu_compare:
        # CPU comparison mode: benchmark_results/X86/<cpu_config>/<predictor>/<benchmark>/
        x86_dir = os.path.join(results_dir, 'X86')
        if not os.path.exists(x86_dir):
            return None

        for cpu_config in os.listdir(x86_dir):
            cpu_dir = os.path.join(x86_dir, cpu_config)
            if not os.path.isdir(cpu_dir):
                continue

            for bp in os.listdir(cpu_dir):
                bp_dir = os.path.join(cpu_dir, bp)
                if not os.path.isdir(bp_dir):
                    continue

                for bench in os.listdir(bp_dir):
                    stats_file = os.path.join(bp_dir, bench, 'stats.txt')
                    if not os.path.exists(stats_file):
                        continue

                    stats = parse_stats_file(stats_file)
                    if stats:
                        stats['cpu_config'] = cpu_config
                        stats['predictor'] = bp
                        stats['benchmark'] = bench
                        data.append(stats)
    else:
        # Standard mode: benchmark_results/<arch>/<predictor>/<benchmark>/
        for arch in ['X86', 'ARM']:
            arch_dir = os.path.join(results_dir, arch)
            if not os.path.exists(arch_dir):
                continue
            for bp in os.listdir(arch_dir):
                bp_dir = os.path.join(arch_dir, bp)
                if not os.path.isdir(bp_dir):
                    continue
                for bench in os.listdir(bp_dir):
                    stats_file = os.path.join(bp_dir, bench, 'stats.txt')
                    if not os.path.exists(stats_file):
                        continue
                    stats = parse_stats_file(stats_file)
                    if stats:
                        stats['arch'] = arch
                        stats['predictor'] = bp
                        stats['benchmark'] = bench
                        data.append(stats)

    return pd.DataFrame(data) if data else None

def load_simple_results(m5out_dir='m5out'):
    data = []
    predictors = ['perceptron', 'local', 'tournament', 'ltage', 'hybrid']
    predictor_names = {
        'perceptron': 'PerceptronLocalBP',
        'local': 'LocalBP',
        'tournament': 'TournamentBP',
        'ltage': 'LTAGE',
        'hybrid': 'HybridPerceptronBP'
    }

    for bp_short in predictors:
        stats_file = os.path.join(m5out_dir, bp_short, 'stats.txt')
        if os.path.exists(stats_file):
            stats = parse_stats_file(stats_file)
            if stats:
                stats['arch'] = 'X86'
                stats['predictor'] = predictor_names.get(bp_short, bp_short)
                stats['benchmark'] = 'hello'
                data.append(stats)

    return pd.DataFrame(data) if data else None

# ============================================================================
# SETUP
# ============================================================================

def setup_style():
    plt.style.use('seaborn-v0_8-whitegrid')
    plt.rcParams.update({
        'font.family': 'sans-serif',
        'font.sans-serif': ['DejaVu Sans', 'Arial', 'Helvetica'],
        'font.size': 11,
        'axes.titlesize': 14,
        'axes.titleweight': 'bold',
        'axes.labelsize': 12,
        'axes.facecolor': BG_COLOR,
        'axes.edgecolor': GRID_COLOR,
        'axes.grid': True,
        'grid.color': GRID_COLOR,
        'grid.alpha': 0.7,
        'figure.facecolor': 'white',
        'figure.dpi': 150,
        'savefig.dpi': 300,
        'savefig.bbox': 'tight',
        'legend.framealpha': 0.95,
        'legend.edgecolor': GRID_COLOR,
    })

def get_color(predictor):
    return COLORS.get(predictor, '#888888')

def get_short_name(predictor):
    return SHORT_NAMES.get(predictor, predictor)

def get_bench_label(bench):
    return BENCHMARK_LABELS.get(bench, bench)

# ============================================================================
# PLOTTING FUNCTIONS
# ============================================================================

def plot_mpki_comparison(df, output_dir):
    fig, ax = plt.subplots(figsize=(14, 6))

    benchmarks = sorted(df['benchmark'].unique())
    predictors = sorted(df['predictor'].unique())

    x = np.arange(len(benchmarks))
    width = 0.15

    for i, predictor in enumerate(predictors):
        pred_data = df[df['predictor'] == predictor]
        mpki_values = []
        for bench in benchmarks:
            bench_data = pred_data[pred_data['benchmark'] == bench]
            mpki_values.append(bench_data['mpki'].values[0] if not bench_data.empty else 0)

        offset = width * (i - len(predictors)/2 + 0.5)
        ax.bar(
            x + offset,
            mpki_values,
            width,
            label=get_short_name(predictor),
            color=get_color(predictor),
            edgecolor='white',
            linewidth=0.5
        )

    ax.set_xlabel('Benchmark', fontweight='bold', color=TEXT_COLOR)
    ax.set_ylabel('MPKI (lower is better)', fontweight='bold', color=TEXT_COLOR)
    ax.set_title('Branch Predictor MPKI Comparison (X86)',
                 fontweight='bold', color=TEXT_COLOR, pad=15)
    ax.set_xticks(x)
    ax.set_xticklabels([get_bench_label(b) for b in benchmarks], rotation=30, ha='right')
    ax.set_ylim(bottom=0)
    ax.legend(loc='upper left', bbox_to_anchor=(1.02, 1), borderaxespad=0)

    plt.tight_layout()
    plt.savefig(os.path.join(output_dir, 'mpki_comparison_x86.png'))
    plt.close()
    print("Saved: mpki_comparison_x86.png")

def plot_accuracy_comparison(df, output_dir):
    fig, ax = plt.subplots(figsize=(14, 6))

    benchmarks = sorted(df['benchmark'].unique())
    predictors = sorted(df['predictor'].unique())

    x = np.arange(len(benchmarks))
    width = 0.15

    for i, predictor in enumerate(predictors):
        pred_data = df[df['predictor'] == predictor]
        acc_values = []
        for bench in benchmarks:
            bench_data = pred_data[pred_data['benchmark'] == bench]
            acc_values.append(bench_data['accuracy'].values[0] if not bench_data.empty else 0)

        offset = width * (i - len(predictors)/2 + 0.5)
        ax.bar(
            x + offset,
            acc_values,
            width,
            label=get_short_name(predictor),
            color=get_color(predictor),
            edgecolor='white',
            linewidth=0.5
        )

    ax.set_xlabel('Benchmark', fontweight='bold', color=TEXT_COLOR)
    ax.set_ylabel('Prediction Accuracy (%)', fontweight='bold', color=TEXT_COLOR)
    ax.set_title('Branch Predictor Accuracy Comparison (X86)',
                 fontweight='bold', color=TEXT_COLOR, pad=15)
    ax.set_xticks(x)
    ax.set_xticklabels([get_bench_label(b) for b in benchmarks], rotation=30, ha='right')

    min_acc = df['accuracy'].min()
    ax.set_ylim(max(85, min_acc - 2), 100.5)
    ax.legend(loc='lower left', bbox_to_anchor=(1.02, 0), borderaxespad=0)

    plt.tight_layout()
    plt.savefig(os.path.join(output_dir, 'accuracy_comparison_x86.png'))
    plt.close()
    print("Saved: accuracy_comparison_x86.png")

def plot_predictor_summary(df, output_dir):
    fig, ax = plt.subplots(figsize=(10, 6))

    avg_mpki = df.groupby('predictor')['mpki'].mean().sort_values()

    colors = [get_color(p) for p in avg_mpki.index]
    y_pos = np.arange(len(avg_mpki))

    bars = ax.barh(
        y_pos,
        avg_mpki.values,
        color=colors,
        edgecolor='white',
        linewidth=0.5,
        height=0.6
    )

    max_val = avg_mpki.max()
    min_val = avg_mpki.min()

    for bar, val in zip(bars, avg_mpki.values):
        if val == min_val:
            text_color = '#2E7D32'
        elif val == max_val:
            text_color = '#C62828'
        else:
            text_color = TEXT_COLOR

        ax.text(
            val + max_val * 0.02,
            bar.get_y() + bar.get_height() / 2,
            f'{val:.2f}',
            va='center',
            fontsize=11,
            color=text_color,
            fontweight='bold'
        )

    ax.set_yticks(y_pos)
    ax.set_yticklabels([get_short_name(p) for p in avg_mpki.index])
    ax.set_xlabel('Average MPKI (lower is better)', fontweight='bold', color=TEXT_COLOR)
    ax.set_title('X86 - Average MPKI by Predictor', fontweight='bold', color=TEXT_COLOR, pad=15)
    ax.set_xlim(0, max_val * 1.2)

    plt.tight_layout()
    plt.savefig(os.path.join(output_dir, 'predictor_summary.png'))
    plt.close()
    print("Saved: predictor_summary.png")

def plot_heatmap(df, output_dir):
    from matplotlib.colors import LinearSegmentedColormap

    pivot = df.pivot_table(values='mpki', index='predictor', columns='benchmark', aggfunc='mean')

    fig, ax = plt.subplots(figsize=(12, 7))

    colors_list = ['#7B9E89', '#F5F5F5', '#B784A7']
    cmap = LinearSegmentedColormap.from_list('deep_pastel', colors_list)

    im = ax.imshow(pivot.values, cmap=cmap, aspect='auto')

    cbar = plt.colorbar(im, ax=ax, shrink=0.8, pad=0.02)
    cbar.set_label('MPKI (lower is better)', fontweight='bold', fontsize=10)

    ax.set_xticks(np.arange(len(pivot.columns)))
    ax.set_yticks(np.arange(len(pivot.index)))
    ax.set_xticklabels([get_bench_label(b) for b in pivot.columns], rotation=35, ha='right')
    ax.set_yticklabels([get_short_name(p) for p in pivot.index])

    all_vals = pivot.values.flatten()
    all_vals = all_vals[~np.isnan(all_vals)]
    global_min = all_vals.min()
    global_max = all_vals.max()

    for i in range(len(pivot.index)):
        for j in range(len(pivot.columns)):
            val = pivot.values[i, j]
            if not np.isnan(val):
                if val == global_min:
                    text_color = '#2E7D32'
                elif val == global_max:
                    text_color = '#C62828'
                else:
                    median_val = np.nanmedian(pivot.values)
                    text_color = 'white' if abs(val - median_val) > median_val * 0.5 else TEXT_COLOR

                ax.text(
                    j,
                    i,
                    f'{val:.1f}',
                    ha='center',
                    va='center',
                    color=text_color,
                    fontsize=10,
                    fontweight='bold'
                )

    ax.set_title('MPKI Heatmap (X86)', fontweight='bold', color=TEXT_COLOR, pad=15)
    ax.set_xlabel('Benchmark', fontweight='bold', color=TEXT_COLOR)
    ax.set_ylabel('Predictor', fontweight='bold', color=TEXT_COLOR)

    plt.tight_layout()
    plt.savefig(os.path.join(output_dir, 'mpki_heatmap_x86.png'))
    plt.close()
    print("Saved: mpki_heatmap_x86.png")

def plot_execution_time(df, output_dir):
    fig, ax = plt.subplots(figsize=(10, 6))

    avg_ticks = df.groupby('predictor')['ticks'].mean().sort_values()
    normalized = (avg_ticks / avg_ticks.max()) * 100

    colors = [get_color(p) for p in normalized.index]
    y_pos = np.arange(len(normalized))

    bars = ax.barh(
        y_pos,
        normalized.values,
        color=colors,
        edgecolor='white',
        linewidth=0.5,
        height=0.6
    )

    min_ticks = avg_ticks.min()
    max_ticks = avg_ticks.max()

    for bar, val, ticks in zip(bars, normalized.values, avg_ticks.values):
        label = f'{ticks/1e6:.1f}M ticks'

        if ticks == min_ticks:
            text_color = '#2E7D32'
        elif ticks == max_ticks:
            text_color = '#C62828'
        else:
            text_color = TEXT_COLOR

        ax.text(
            val + 2,
            bar.get_y() + bar.get_height()/2,
            label,
            va='center',
            ha='left',
            fontsize=10,
            color=text_color,
            fontweight='bold'
        )

    ax.set_yticks(y_pos)
    ax.set_yticklabels([get_short_name(p) for p in normalized.index])
    ax.set_xlabel('Relative Execution Time (%)', fontweight='bold', color=TEXT_COLOR)
    ax.set_title('X86 - Execution Time Comparison (lower is better)',
                 fontweight='bold', color=TEXT_COLOR, pad=15)
    ax.set_xlim(0, 130)

    plt.tight_layout()
    plt.savefig(os.path.join(output_dir, 'execution_time_x86.png'))
    plt.close()
    print("Saved: execution_time_x86.png")

def plot_benchmark_difficulty(df, output_dir):
    fig, ax = plt.subplots(figsize=(12, 6))

    bench_difficulty = df.groupby('benchmark')['mpki'].mean().sort_values(ascending=False)
    median_diff = bench_difficulty.median()

    colors = ['#B784A7' if v > median_diff else '#7B9E89' for v in bench_difficulty.values]
    y_pos = np.arange(len(bench_difficulty))

    bars = ax.barh(
        y_pos,
        bench_difficulty.values,
        color=colors,
        edgecolor='white',
        height=0.6
    )

    max_val = bench_difficulty.max()
    min_val = bench_difficulty.min()

    for bar, val in zip(bars, bench_difficulty.values):
        if val == min_val:
            text_color = '#2E7D32'
        elif val == max_val:
            text_color = '#C62828'
        else:
            text_color = TEXT_COLOR

        ax.text(
            val + max_val * 0.02,
            bar.get_y() + bar.get_height()/2,
            f'{val:.1f}',
            va='center',
            fontsize=10,
            color=text_color,
            fontweight='bold'
        )

    ax.set_yticks(y_pos)
    ax.set_yticklabels([get_bench_label(b) for b in bench_difficulty.index])
    ax.set_xlabel('Average MPKI Across All Predictors', fontweight='bold')
    ax.set_title('X86 - Benchmark Difficulty (higher = harder to predict)',
                 fontweight='bold', pad=15)
    ax.set_xlim(0, max_val * 1.2)

    legend_elements = [
        mpatches.Patch(color='#B784A7', label='Hard (above median)'),
        mpatches.Patch(color='#7B9E89', label='Easy (below median)')
    ]
    ax.legend(
        handles=legend_elements,
        loc='upper left',
        bbox_to_anchor=(1.02, 1),
        borderaxespad=0,
        framealpha=0.95
    )

    plt.tight_layout()
    plt.savefig(os.path.join(output_dir, 'benchmark_difficulty_x86.png'))
    plt.close()
    print("Saved: benchmark_difficulty_x86.png")

def plot_overall_ranking(df, output_dir):
    fig, ax = plt.subplots(figsize=(12, 6))

    predictor_stats = df.groupby('predictor').agg({
        'mpki': 'mean',
        'ticks': 'mean',
        'accuracy': 'mean'
    })

    mpki_range = predictor_stats['mpki'].max() - predictor_stats['mpki'].min()
    ticks_range = predictor_stats['ticks'].max() - predictor_stats['ticks'].min()

    if mpki_range > 0:
        mpki_norm = (predictor_stats['mpki'] - predictor_stats['mpki'].min()) / mpki_range * 100
    else:
        mpki_norm = predictor_stats['mpki'] * 0

    if ticks_range > 0:
        ticks_norm = (predictor_stats['ticks'] - predictor_stats['ticks'].min()) / ticks_range * 100
    else:
        ticks_norm = predictor_stats['ticks'] * 0

    composite = 0.7 * mpki_norm + 0.3 * ticks_norm
    composite = composite.sort_values()

    colors = [get_color(p) for p in composite.index]
    y_pos = np.arange(len(composite))

    bars = ax.barh(
        y_pos,
        composite.values,
        color=colors,
        edgecolor='white',
        height=0.6
    )

    max_composite = composite.max()
    min_composite = composite.min()

    for bar, pred in zip(bars, composite.index):
        mpki = predictor_stats.loc[pred, 'mpki']
        acc = predictor_stats.loc[pred, 'accuracy']
        comp_val = composite[pred]

        if comp_val == min_composite:
            text_color = '#2E7D32'
        elif comp_val == max_composite:
            text_color = '#C62828'
        else:
            text_color = TEXT_COLOR

        label_x = bar.get_width() + max_composite * 0.03
        ax.text(
            label_x,
            bar.get_y() + bar.get_height()/2,
            f'MPKI: {mpki:.1f}, Acc: {acc:.1f}%',
            va='center',
            ha='left',
            fontsize=10,
            color=text_color,
            fontweight='bold'
        )

    ax.set_yticks(y_pos)
    ax.set_yticklabels([get_short_name(p) for p in composite.index])
    ax.set_xlabel(
        'Composite Score (lower is better)\n70% MPKI + 30% Execution Time',
        fontweight='bold'
    )
    ax.set_title('X86 - Overall Predictor Ranking', fontweight='bold', pad=15)
    ax.set_xlim(0, max_composite * 1.5)

    plt.tight_layout()
    plt.savefig(os.path.join(output_dir, 'overall_ranking_x86.png'))
    plt.close()
    print("Saved: overall_ranking_x86.png")

def plot_hello_vs_realistic(df_realistic, df_hello, output_dir):
    """
    Compare hello world vs realistic benchmarks.
    Now saves two separate images:
      - hello_vs_realistic_mpki_x86.png
      - hello_vs_realistic_accuracy_x86.png
    """
    if df_hello is None or df_hello.empty:
        print("No hello world data for comparison")
        return

    predictors = sorted(set(df_realistic['predictor'].unique()) &
                        set(df_hello['predictor'].unique()))

    if len(predictors) == 0:
        print("No common predictors for comparison")
        return

    x = np.arange(len(predictors))
    width = 0.35

    hello_mpki = [
        df_hello[df_hello['predictor'] == p]['mpki'].values[0]
        if not df_hello[df_hello['predictor'] == p].empty else 0
        for p in predictors
    ]
    real_mpki = [
        df_realistic[df_realistic['predictor'] == p]['mpki'].mean()
        for p in predictors
    ]

    hello_acc = [
        df_hello[df_hello['predictor'] == p]['accuracy'].values[0]
        if not df_hello[df_hello['predictor'] == p].empty else 0
        for p in predictors
    ]
    real_acc = [
        df_realistic[df_realistic['predictor'] == p]['accuracy'].mean()
        for p in predictors
    ]

    fig, ax = plt.subplots(figsize=(7, 6))

    bars1 = ax.bar(
        x - width/2,
        hello_mpki,
        width,
        label='Hello World',
        color='#A5C4D4',
        edgecolor='white'
    )
    bars2 = ax.bar(
        x + width/2,
        real_mpki,
        width,
        label='Realistic (avg)',
        color='#7B9E89',
        edgecolor='white'
    )

    for bars in [bars1, bars2]:
        for bar in bars:
            height = bar.get_height()
            ax.annotate(
                f'{height:.1f}',
                xy=(bar.get_x() + bar.get_width()/2, height),
                xytext=(0, 3),
                textcoords="offset points",
                ha='center',
                va='bottom',
                fontsize=9,
                fontweight='bold'
            )

    ax.set_xlabel('Predictor', fontweight='bold')
    ax.set_ylabel('MPKI (lower is better)', fontweight='bold')
    ax.set_title('MPKI: Hello World vs Realistic', fontweight='bold', pad=10)
    ax.set_xticks(x)
    ax.set_xticklabels([get_short_name(p) for p in predictors], rotation=30, ha='right')
    ax.legend(loc='upper right')
    ax.set_ylim(bottom=0)

    plt.tight_layout()
    mpki_path = os.path.join(output_dir, 'hello_vs_realistic_mpki_x86.png')
    plt.savefig(mpki_path)
    plt.close()
    print(f"Saved: {mpki_path}")

    fig, ax = plt.subplots(figsize=(7, 6))

    bars1 = ax.bar(
        x - width/2,
        hello_acc,
        width,
        label='Hello World',
        color='#A5C4D4',
        edgecolor='white'
    )
    bars2 = ax.bar(
        x + width/2,
        real_acc,
        width,
        label='Realistic (avg)',
        color='#7B9E89',
        edgecolor='white'
    )

    for bars in [bars1, bars2]:
        for bar in bars:
            height = bar.get_height()
            ax.annotate(
                f'{height:.1f}',
                xy=(bar.get_x() + bar.get_width()/2, height),
                xytext=(0, 3),
                textcoords="offset points",
                ha='center',
                va='bottom',
                fontsize=9,
                fontweight='bold'
            )

    ax.set_xlabel('Predictor', fontweight='bold')
    ax.set_ylabel('Accuracy (%)', fontweight='bold')
    ax.set_title('Accuracy: Hello World vs Realistic', fontweight='bold', pad=10)
    ax.set_xticks(x)
    ax.set_xticklabels([get_short_name(p) for p in predictors], rotation=30, ha='right')
    ax.legend(loc='lower right')

    min_acc = min(min(hello_acc), min(real_acc))
    ax.set_ylim(max(75, min_acc - 5), 101)

    plt.tight_layout()
    acc_path = os.path.join(output_dir, 'hello_vs_realistic_accuracy_x86.png')
    plt.savefig(acc_path)
    plt.close()
    print(f"Saved: {acc_path}")

def plot_radar(df, output_dir):
    benchmarks = sorted(df['benchmark'].unique())
    predictors = sorted(df['predictor'].unique())

    if len(benchmarks) < 3:
        return

    fig, ax = plt.subplots(figsize=(10, 8), subplot_kw=dict(polar=True))

    angles = np.linspace(0, 2 * np.pi, len(benchmarks), endpoint=False).tolist()
    angles += angles[:1]

    for predictor in predictors:
        pred_data = df[df['predictor'] == predictor]
        values = []
        for bench in benchmarks:
            bench_data = pred_data[pred_data['benchmark'] == bench]
            if not bench_data.empty:
                values.append(bench_data['accuracy'].values[0])
            else:
                values.append(0)
        values += values[:1]

        ax.plot(
            angles,
            values,
            'o-',
            linewidth=2,
            label=get_short_name(predictor),
            color=get_color(predictor)
        )
        ax.fill(angles, values, alpha=0.15, color=get_color(predictor))

    ax.set_xticks(angles[:-1])
    ax.set_xticklabels([get_bench_label(b) for b in benchmarks], size=10)
    ax.set_ylim(85, 100)
    ax.set_title('Predictor Accuracy by Benchmark', fontweight='bold', pad=20, size=14)
    ax.legend(loc='upper right', bbox_to_anchor=(1.3, 1.0))

    plt.tight_layout()
    plt.savefig(os.path.join(output_dir, 'predictor_radar_x86.png'))
    plt.close()
    print("Saved: predictor_radar_x86.png")

def plot_summary_table(df, output_dir):
    fig, ax = plt.subplots(figsize=(12, 5))
    ax.axis('off')

    summary_data = []
    for predictor in sorted(df['predictor'].unique()):
        pred_df = df[df['predictor'] == predictor]
        summary_data.append([
            get_short_name(predictor),
            f"{pred_df['mpki'].mean():.2f}",
            f"{pred_df['accuracy'].mean():.2f}%",
            f"{pred_df['ticks'].mean()/1e6:.1f}M",
            str(len(pred_df['benchmark'].unique()))
        ])

    summary_data.sort(key=lambda x: float(x[1]))

    columns = ['Predictor', 'Avg MPKI', 'Avg Accuracy', 'Avg Ticks', 'Benchmarks']

    table = ax.table(
        cellText=summary_data,
        colLabels=columns,
        cellLoc='center',
        loc='center',
        colColours=['#8FA5B5'] * len(columns)
    )

    table.auto_set_font_size(False)
    table.set_fontsize(12)
    table.scale(1.2, 2.0)

    for i in range(len(columns)):
        table[(0, i)].set_text_props(weight='bold', color='white')

    for i in range(1, len(summary_data) + 1):
        for j in range(len(columns)):
            if i % 2 == 0:
                table[(i, j)].set_facecolor('#F0F0F0')

    for j in range(len(columns)):
        table[(1, j)].set_facecolor('#C8E6C9')
    for j in range(len(columns)):
        table[(len(summary_data), j)].set_facecolor('#FFCDD2')

    ax.set_title(
        'Branch Predictor Summary (X86) - Sorted by MPKI',
        fontweight='bold',
        fontsize=14,
        color=TEXT_COLOR,
        y=0.9
    )

    plt.savefig(
        os.path.join(output_dir, 'summary_table.png'),
        facecolor='white',
        edgecolor='none'
    )
    plt.close()
    print("Saved: summary_table.png")

# ============================================================================
# CPU COMPARISON PLOTTING FUNCTIONS
# ============================================================================

CPU_CONFIG_COLORS = {
    'O3_default': '#7B9E89',
    'O3_wide': '#8FA5B5',
    'O3_narrow': '#C4A484',
    'Minor_inorder': '#B784A7',
}

CPU_CONFIG_LABELS = {
    'O3_default': 'O3 Default',
    'O3_wide': 'O3 Wide (6-wide)',
    'O3_narrow': 'O3 Narrow (2-wide)',
    'Minor_inorder': 'Minor (In-Order)',
}

def get_cpu_color(cpu_config):
    return CPU_CONFIG_COLORS.get(cpu_config, '#888888')

def get_cpu_label(cpu_config):
    return CPU_CONFIG_LABELS.get(cpu_config, cpu_config)

def plot_cpu_comparison_mpki(df, output_dir):
    fig, ax = plt.subplots(figsize=(14, 7))

    predictors = sorted(df['predictor'].unique())
    cpu_configs = sorted(df['cpu_config'].unique())

    x = np.arange(len(predictors))
    width = 0.2

    for i, cpu in enumerate(cpu_configs):
        cpu_data = df[df['cpu_config'] == cpu]
        mpki_values = []

        for pred in predictors:
            pred_data = cpu_data[cpu_data['predictor'] == pred]
            mpki_values.append(pred_data['mpki'].mean() if not pred_data.empty else 0)

        offset = width * (i - len(cpu_configs)/2 + 0.5)
        ax.bar(
            x + offset,
            mpki_values,
            width,
            label=get_cpu_label(cpu),
            color=get_cpu_color(cpu),
            edgecolor='white',
            linewidth=0.5
        )

    ax.set_xlabel('Branch Predictor', fontweight='bold', color=TEXT_COLOR)
    ax.set_ylabel('Average MPKI (lower is better)', fontweight='bold', color=TEXT_COLOR)
    ax.set_title('Branch Predictor MPKI Across CPU Configurations',
                 fontweight='bold', color=TEXT_COLOR, pad=15)
    ax.set_xticks(x)
    ax.set_xticklabels([get_short_name(p) for p in predictors], rotation=30, ha='right')
    ax.legend(loc='upper left', bbox_to_anchor=(1.02, 1), borderaxespad=0)
    ax.set_ylim(bottom=0)

    plt.tight_layout()
    plt.savefig(os.path.join(output_dir, 'cpu_comparison_mpki.png'))
    plt.close()
    print("Saved: cpu_comparison_mpki.png")

def plot_cpu_comparison_accuracy(df, output_dir):
    fig, ax = plt.subplots(figsize=(14, 7))

    predictors = sorted(df['predictor'].unique())
    cpu_configs = sorted(df['cpu_config'].unique())

    x = np.arange(len(predictors))
    width = 0.2

    for i, cpu in enumerate(cpu_configs):
        cpu_data = df[df['cpu_config'] == cpu]
        acc_values = []

        for pred in predictors:
            pred_data = cpu_data[cpu_data['predictor'] == pred]
            acc_values.append(pred_data['accuracy'].mean() if not pred_data.empty else 0)

        offset = width * (i - len(cpu_configs)/2 + 0.5)
        ax.bar(
            x + offset,
            acc_values,
            width,
            label=get_cpu_label(cpu),
            color=get_cpu_color(cpu),
            edgecolor='white',
            linewidth=0.5
        )

    ax.set_xlabel('Branch Predictor', fontweight='bold', color=TEXT_COLOR)
    ax.set_ylabel('Prediction Accuracy (%)', fontweight='bold', color=TEXT_COLOR)
    ax.set_title('Branch Predictor Accuracy Across CPU Configurations',
                 fontweight='bold', color=TEXT_COLOR, pad=15)
    ax.set_xticks(x)
    ax.set_xticklabels([get_short_name(p) for p in predictors], rotation=30, ha='right')
    ax.legend(loc='lower left', bbox_to_anchor=(1.02, 0), borderaxespad=0)

    min_acc = df['accuracy'].min()
    ax.set_ylim(max(85, min_acc - 2), 100.5)

    plt.tight_layout()
    plt.savefig(os.path.join(output_dir, 'cpu_comparison_accuracy.png'))
    plt.close()
    print("Saved: cpu_comparison_accuracy.png")

def plot_cpu_impact_heatmap(df, output_dir):
    from matplotlib.colors import LinearSegmentedColormap

    pivot = df.pivot_table(values='mpki', index='predictor',
                           columns='cpu_config', aggfunc='mean')

    fig, ax = plt.subplots(figsize=(12, 7))

    colors_list = ['#7B9E89', '#F5F5F5', '#B784A7']
    cmap = LinearSegmentedColormap.from_list('deep_pastel', colors_list)

    im = ax.imshow(pivot.values, cmap=cmap, aspect='auto')

    cbar = plt.colorbar(im, ax=ax, shrink=0.8, pad=0.02)
    cbar.set_label('MPKI (lower is better)', fontweight='bold', fontsize=10)

    ax.set_xticks(np.arange(len(pivot.columns)))
    ax.set_yticks(np.arange(len(pivot.index)))
    ax.set_xticklabels([get_cpu_label(c) for c in pivot.columns], rotation=35, ha='right')
    ax.set_yticklabels([get_short_name(p) for p in pivot.index])

    all_vals = pivot.values.flatten()
    all_vals = all_vals[~np.isnan(all_vals)]
    global_min = all_vals.min()
    global_max = all_vals.max()

    for i in range(len(pivot.index)):
        for j in range(len(pivot.columns)):
            val = pivot.values[i, j]
            if not np.isnan(val):
                if val == global_min:
                    text_color = '#2E7D32'
                elif val == global_max:
                    text_color = '#C62828'
                else:
                    median_val = np.nanmedian(pivot.values)
                    text_color = 'white' if abs(val - median_val) > median_val * 0.5 else TEXT_COLOR

                ax.text(
                    j,
                    i,
                    f'{val:.1f}',
                    ha='center',
                    va='center',
                    color=text_color,
                    fontsize=11,
                    fontweight='bold'
                )

    ax.set_title('MPKI: Predictor vs CPU Configuration', fontweight='bold',
                 color=TEXT_COLOR, pad=15)
    ax.set_xlabel('CPU Configuration', fontweight='bold', color=TEXT_COLOR)
    ax.set_ylabel('Branch Predictor', fontweight='bold', color=TEXT_COLOR)

    plt.tight_layout()
    plt.savefig(os.path.join(output_dir, 'cpu_impact_heatmap.png'))
    plt.close()
    print("Saved: cpu_impact_heatmap.png")

def plot_predictor_by_cpu(df, output_dir):
    """
    Show best predictor for each CPU configuration.
    One PNG per CPU configuration.
    """
    cpu_configs = sorted(df['cpu_config'].unique())

    for cpu in cpu_configs:
        fig, ax = plt.subplots(figsize=(10, 6))

        cpu_data = df[df['cpu_config'] == cpu]
        avg_mpki = cpu_data.groupby('predictor')['mpki'].mean().sort_values()

        colors = [get_color(p) for p in avg_mpki.index]
        y_pos = np.arange(len(avg_mpki))

        bars = ax.barh(
            y_pos,
            avg_mpki.values,
            color=colors,
            edgecolor='white',
            height=0.6
        )

        max_val = avg_mpki.max()
        min_val = avg_mpki.min()

        for bar, val in zip(bars, avg_mpki.values):
            if val == min_val:
                text_color = '#2E7D32'
            elif val == max_val:
                text_color = '#C62828'
            else:
                text_color = TEXT_COLOR

            ax.text(
                val + max_val * 0.02,
                bar.get_y() + bar.get_height()/2,
                f'{val:.2f}',
                va='center',
                fontsize=11,
                color=text_color,
                fontweight='bold'
            )

        ax.set_yticks(y_pos)
        ax.set_yticklabels([get_short_name(p) for p in avg_mpki.index])
        ax.set_xlabel('Average MPKI (lower is better)', fontweight='bold')
        ax.set_title(f'Predictor Ranking - {get_cpu_label(cpu)}', fontweight='bold', pad=15)
        ax.set_xlim(0, max_val * 1.25)

        plt.tight_layout()

        safe_cpu_name = cpu.replace(' ', '_').replace('(', '').replace(')', '').lower()
        filename = f'predictor_ranking_{safe_cpu_name}.png'
        plt.savefig(os.path.join(output_dir, filename))
        plt.close()
        print(f"Saved: {filename}")

# ============================================================================
# MAIN
# ============================================================================

def main():
    parser = argparse.ArgumentParser(description='Plot branch predictor results (v3)')
    parser.add_argument('--dir', default='benchmark_results',
                        help='Results directory for realistic benchmarks')
    parser.add_argument('--hello-dir', default='m5out',
                        help='Results directory for hello world tests')
    parser.add_argument('--output', default='plots',
                        help='Output directory for plots')
    parser.add_argument('--cpu-compare', action='store_true',
                        help='Enable CPU configuration comparison mode')
    args = parser.parse_args()

    setup_style()
    os.makedirs(args.output, exist_ok=True)

    print("="*60)
    print("  Branch Predictor Visualization (v3 - X86)")
    print("="*60)
    print()

    print("Loading data...")

    csv_path = os.path.join(args.dir, 'results.csv')
    df_realistic = load_results_from_csv(csv_path)
    if df_realistic is None:
        df_realistic = load_results_from_dirs(args.dir, args.cpu_compare)

    df_hello = load_simple_results(args.hello_dir)

    if df_realistic is not None and not df_realistic.empty and not args.cpu_compare:
        if 'arch' in df_realistic.columns:
            df_realistic = df_realistic[df_realistic['arch'] == 'X86']

    have_realistic = df_realistic is not None and not df_realistic.empty
    have_hello = df_hello is not None and not df_hello.empty

    if not have_realistic and not have_hello:
        print("\nNo results found!")
        sys.exit(1)

    df = df_realistic if have_realistic else df_hello

    print(f"  Realistic benchmarks: {len(df_realistic) if have_realistic else 0} results")
    print(f"  Hello world: {len(df_hello) if have_hello else 0} results")
    print(f"  Predictors: {list(df['predictor'].unique())}")
    print(f"  Benchmarks: {list(df['benchmark'].unique())}")
    if args.cpu_compare and 'cpu_config' in df.columns:
        print(f"  CPU Configs: {list(df['cpu_config'].unique())}")
    print()

    print("Generating plots...")
    print("-" * 40)

    if args.cpu_compare and 'cpu_config' in df.columns:
        plot_cpu_comparison_mpki(df, args.output)
        plot_cpu_comparison_accuracy(df, args.output)
        plot_cpu_impact_heatmap(df, args.output)
        plot_predictor_by_cpu(df, args.output)
    else:
        plot_mpki_comparison(df, args.output)
        plot_accuracy_comparison(df, args.output)
        plot_heatmap(df, args.output)

    plot_predictor_summary(df, args.output)
    plot_execution_time(df, args.output)
    plot_benchmark_difficulty(df, args.output)
    plot_overall_ranking(df, args.output)
    plot_summary_table(df, args.output)

    if len(df['benchmark'].unique()) >= 3:
        plot_radar(df, args.output)

    if have_realistic and have_hello and not args.cpu_compare:
        print("-" * 40)
        plot_hello_vs_realistic(df_realistic, df_hello, args.output)

    print()
    print("="*60)
    print(f"  All plots saved to: {args.output}/")
    print("="*60)

if __name__ == '__main__':
    main()
