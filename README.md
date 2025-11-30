# CSE 220 – Perceptron-Based Branch Prediction in gem5

This project adds two perceptron-based branch predictors to gem5 and compares them against the built-in predictors on a small X86 benchmark suite. Scripts are included to run predictors, extract statistics, export CSV summaries, and generate visualizations.

Predictors compared (X86):
- LocalBP
- TournamentBP
- LTAGE
- PerceptronLocalBP
- HybridPerceptronBP

---

## 1. Clone and Basic Setup

Clone this repository (with submodules), install Python packages, install gem5 build dependencies, and build the X86 binary:

git clone https://github.com/PrathameshKhole/perceptron_branch_predictor.git --recursive
cd perceptron_branch_predictor/

# Python dependencies for plotting / scripts
pip install -r requirements.txt
pip install pydot

# System dependencies for gem5 (Ubuntu/Debian)
sudo apt install -y \
  build-essential git m4 scons zlib1g zlib1g-dev \
  libprotobuf-dev protobuf-compiler libprotoc-dev \
  libgoogle-perftools-dev python3-dev python3-pybind11 \
  libboost-all-dev pkg-config

# Make sure Python's lib directory is visible to the linker
export LD_LIBRARY_PATH=$(python3 -c "import sysconfig; print(sysconfig.get_config_var('LIBDIR'))"):$LD_LIBRARY_PATH

# Build gem5 (X86 only)
scons build/X86/gem5.opt -j"$(nproc)"

# Run simple test with hello world to check working of build
./build/X86/gem5.opt \
  configs/deprecated/example/se.py \
  --cpu-type=O3CPU --caches --l2cache \
  --bp-type=PerceptronLocalBP \
  -c tests/test-progs/hello/bin/x86/linux/hello

---

## 2. Code Added

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

## 3. Building gem5 for X86

From the gem5 root:

scons build/X86/gem5.opt -j6

Predictor names accepted by --bp-type:

LocalBP  
TournamentBP  
LTAGE  
PerceptronLocalBP  
HybridPerceptronBP

---

## 4. Simple Tests Using baseline Hello-World

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

## 5. Plotting and Visualization

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

