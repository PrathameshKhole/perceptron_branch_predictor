# CSE 220 – Perceptron-Based Branch Prediction in gem5

This project adds two perceptron-based branch predictors to gem5 and compares them against the built-in predictors on a small X86 benchmark suite. Scripts are included to run predictors, extract statistics, export CSV summaries, and generate visualizations.

Predictors compared (X86):
- LocalBP
- TournamentBP
- LTAGE
- PerceptronLocalBP
- HybridPerceptronBP

---

## 1. Code Added

Predictor C++ files:
- src/cpu/pred/perceptron_local.hh
- src/cpu/pred/perceptron_local.cc
- src/cpu/pred/hybrid_perceptron.hh
- src/cpu/pred/hybrid_perceptron.cc

SimObject registration:
- src/cpu/pred/BranchPredictor.py  
  adds:
  - PerceptronLocalBP
  - HybridPerceptronBP

SCons configuration:
- src/cpu/pred/SConscript  
  must contain:
  - Source('perceptron_local.cc')
  - Source('hybrid_perceptron.cc')

---

## 2. Building gem5 for X86

From the gem5 root:

scons build/X86/gem5.opt -j6

Predictor names accepted by --bp-type:

LocalBP  
TournamentBP  
LTAGE  
PerceptronLocalBP  
HybridPerceptronBP

---

## 3. Simple Tests Using baseline Hello-World

Runs use:  
tests/test-progs/hello/bin/x86/linux/hello

./build/X86/gem5.opt -d m5out/local \
  configs/deprecated/example/se.py \
  --cpu-type=O3CPU --caches --l2cache --bp-type=LocalBP \
  -c tests/test-progs/hello/bin/x86/linux/hello

./build/X86/gem5.opt -d m5out/tournament \
  configs/deprecated/example/se.py \
  --cpu-type=O3CPU --caches --l2cache --bp-type=TournamentBP \
  -c tests/test-progs/hello/bin/x86/linux/hello

./build/X86/gem5.opt -d m5out/ltage \
  configs/deprecated/example/se.py \
  --cpu-type=O3CPU --caches --l2cache --bp-type=LTAGE \
  -c tests/test-progs/hello/bin/x86/linux/hello

./build/X86/gem5.opt -d m5out/perceptron \
  configs/deprecated/example/se.py \
  --cpu-type=O3CPU --caches --l2cache --bp-type=PerceptronLocalBP \
  -c tests/test-progs/hello/bin/x86/linux/hello

./build/X86/gem5.opt -d m5out/hybrid \
  configs/deprecated/example/se.py \
  --cpu-type=O3CPU --caches --l2cache --bp-type=HybridPerceptronBP \
  -c tests/test-progs/hello/bin/x86/linux/hello

Outputs:

m5out/local/stats.txt  
m5out/tournament/stats.txt  
m5out/ltage/stats.txt  
m5out/perceptron/stats.txt  
m5out/hybrid/stats.txt

---

## 4. Plotting and Visualization

Dependencies:

pip install pandas numpy matplotlib

Main plotting script: plot_results.py

Basic usage:

python3 plot_results.py \
  --dir benchmark_results \
  --hello-dir m5out \
  --output plots

This expects:

benchmark_results/results.csv  
m5out/*/stats.txt

The script generates PNGs in plots/:

Per-benchmark comparisons:

mpki_comparison_x86.png  
accuracy_comparison_x86.png  
mpki_heatmap_x86.png  

Predictor-centric views:

predictor_summary.png  
execution_time_x86.png  
overall_ranking_x86.png  
summary_table.png  

Benchmark-centric:

benchmark_difficulty_x86.png  

Radar visualization:

predictor_radar_x86.png  

Hello vs realistic comparisons:

hello_vs_realistic_mpki_x86.png  
hello_vs_realistic_accuracy_x86.png  

These compare each predictor on hello-world vs realistic workloads.

---

## Optional: CPU-Configuration Comparison Mode

If results are organized by CPU config, layout:

benchmark_results/  
  X86/  
    O3_default/  
      LocalBP/binary_search/stats.txt  
      LocalBP/quicksort/stats.txt  
      HybridPerceptronBP/quicksort/stats.txt  
      ...  
    O3_wide/  
    O3_narrow/  
    Minor_inorder/

Run:

python3 plot_results.py \
  --dir benchmark_results \
  --output plots_cpu \
  --cpu-compare

Generated images:

cpu_comparison_mpki.png  
cpu_comparison_accuracy.png  
cpu_impact_heatmap.png  
predictor_ranking_<cpu>.png
