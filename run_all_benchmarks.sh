#!/usr/bin/env bash
#
# run_x86_benchmarks.sh - Run X86 benchmarks with optional CPU comparison
#
# Usage: 
#   ./run_x86_benchmarks.sh              # Default O3CPU only
#   ./run_x86_benchmarks.sh --quick      # Smaller workloads
#   ./run_x86_benchmarks.sh --cpu-compare # Compare different CPU configs
#   ./run_x86_benchmarks.sh --build      # Build first
#   ./run_x86_benchmarks.sh --hello-only # Just hello world
#   ./run_x86_benchmarks.sh --real-only  # Just realistic benchmarks

set -e

# Parse arguments
BUILD=false
QUICK=false
HELLO_ONLY=false
REAL_ONLY=false
CPU_COMPARE=false

for arg in "$@"; do
    case $arg in
        --build) BUILD=true ;;
        --quick) QUICK=true ;;
        --hello-only) HELLO_ONLY=true ;;
        --real-only) REAL_ONLY=true ;;
        --cpu-compare) CPU_COMPARE=true ;;
    esac
done

# Configuration
SE_SCRIPT="configs/deprecated/example/se.py"
BENCHMARK_DIR="/tmp/bp_benchmarks"
X86_HELLO="tests/test-progs/hello/bin/x86/linux/hello"

PREDICTORS="HybridPerceptronBP PerceptronLocalBP LocalBP TournamentBP LTAGE"

# CPU configurations to test
# Format: "name|cpu-type|extra-params"
if [ "$CPU_COMPARE" = true ]; then
    CPU_CONFIGS=(
        "O3_default|O3CPU|"
        "O3_wide|O3CPU|--param system.cpu[:].fetchWidth=6 --param system.cpu[:].decodeWidth=6 --param system.cpu[:].issueWidth=6"
        "O3_narrow|O3CPU|--param system.cpu[:].fetchWidth=2 --param system.cpu[:].decodeWidth=2 --param system.cpu[:].issueWidth=2"
        "Minor_inorder|MinorCPU|"
    )
    echo "Mode: CPU COMPARISON (testing multiple CPU configurations)"
else
    CPU_CONFIGS=(
        "O3_default|O3CPU|"
    )
fi

# Set iteration counts based on mode
if [ "$QUICK" = true ]; then
    LOOP_ITERS=100000
    MATRIX_SIZE=50
    SORT_SIZE=1000
    echo "Mode: QUICK (smaller workloads)"
else
    LOOP_ITERS=5000000
    MATRIX_SIZE=150
    SORT_SIZE=10000
    echo "Mode: FULL (larger workloads)"
fi

# ============================================================================
# BUILD
# ============================================================================

if [ "$BUILD" = true ]; then
    echo ""
    echo "=============================================="
    echo "  BUILDING GEM5 (X86)"
    echo "=============================================="
    scons build/X86/gem5.opt -j$(nproc)
fi

# ============================================================================
# HELLO WORLD BENCHMARKS
# ============================================================================

run_hello_world() {
    echo ""
    echo "=============================================="
    echo "  HELLO WORLD BENCHMARKS (X86)"
    echo "=============================================="
    
    if [ ! -f "$X86_HELLO" ]; then
        echo "Error: X86 hello binary not found at $X86_HELLO"
        return 1
    fi
    
    for config in "${CPU_CONFIGS[@]}"; do
        IFS='|' read -r cpu_name cpu_type cpu_params <<< "$config"
        
        echo ""
        echo "--- CPU: $cpu_name ($cpu_type) ---"
        
        for bp in $PREDICTORS; do
            case $bp in
                HybridPerceptronBP) bp_short="hybrid" ;;
                PerceptronLocalBP) bp_short="perceptron" ;;
                LocalBP) bp_short="local" ;;
                TournamentBP) bp_short="tournament" ;;
                LTAGE) bp_short="ltage" ;;
                *) bp_short=$(echo "$bp" | tr '[:upper:]' '[:lower:]') ;;
            esac
            
            if [ "$CPU_COMPARE" = true ]; then
                outdir="m5out/${cpu_name}/${bp_short}"
            else
                outdir="m5out/${bp_short}"
            fi
            
            mkdir -p "$outdir"
            echo "  Running $bp..."
            
            if [ -n "$cpu_params" ]; then
                ./build/X86/gem5.opt -d "$outdir" $SE_SCRIPT \
                    --cpu-type=$cpu_type --caches --l2cache \
                    --bp-type=$bp \
                    $cpu_params \
                    -c "$X86_HELLO" 2>&1 | tail -1
            else
                ./build/X86/gem5.opt -d "$outdir" $SE_SCRIPT \
                    --cpu-type=$cpu_type --caches --l2cache \
                    --bp-type=$bp \
                    -c "$X86_HELLO" 2>&1 | tail -1
            fi
        done
    done
}

# ============================================================================
# REALISTIC BENCHMARKS
# ============================================================================

create_benchmarks() {
    echo ""
    echo "=============================================="
    echo "  CREATING BENCHMARK PROGRAMS"
    echo "=============================================="
    
    mkdir -p "$BENCHMARK_DIR"
    
    # Benchmark 1: Branch-heavy loop
    cat > "$BENCHMARK_DIR/branch_loop.c" << EOF
#include <stdio.h>
#include <stdlib.h>

int main() {
    long sum = 0;
    int iterations = $LOOP_ITERS;
    
    for (int i = 0; i < iterations; i++) {
        if (i % 2 == 0) sum += i;
        else sum -= i;
        if (i % 7 == 0) sum *= 2;
        if (i % 3 == 0) {
            if (i % 9 == 0) sum += 100;
            else sum += 10;
        }
        if (sum % 5 == 0) sum++;
    }
    printf("Result: %ld\n", sum);
    return 0;
}
EOF

    # Benchmark 2: Quicksort
    cat > "$BENCHMARK_DIR/quicksort.c" << EOF
#include <stdio.h>
#include <stdlib.h>

void swap(int* a, int* b) { int t = *a; *a = *b; *b = t; }

int partition(int arr[], int low, int high) {
    int pivot = arr[high], i = low - 1;
    for (int j = low; j <= high - 1; j++) {
        if (arr[j] < pivot) { i++; swap(&arr[i], &arr[j]); }
    }
    swap(&arr[i + 1], &arr[high]);
    return i + 1;
}

void quicksort(int arr[], int low, int high) {
    if (low < high) {
        int pi = partition(arr, low, high);
        quicksort(arr, low, pi - 1);
        quicksort(arr, pi + 1, high);
    }
}

int main() {
    int n = $SORT_SIZE;
    int* arr = malloc(n * sizeof(int));
    unsigned int seed = 12345;
    for (int i = 0; i < n; i++) {
        seed = seed * 1103515245 + 12345;
        arr[i] = (seed >> 16) & 0x7fff;
    }
    quicksort(arr, 0, n - 1);
    printf("Sorted %d elements. First: %d, Last: %d\n", n, arr[0], arr[n-1]);
    free(arr);
    return 0;
}
EOF

    # Benchmark 3: Matrix multiply
    cat > "$BENCHMARK_DIR/matrix.c" << EOF
#include <stdio.h>
#include <stdlib.h>

int main() {
    int n = $MATRIX_SIZE;
    int** A = malloc(n * sizeof(int*));
    int** B = malloc(n * sizeof(int*));
    int** C = malloc(n * sizeof(int*));
    
    for (int i = 0; i < n; i++) {
        A[i] = malloc(n * sizeof(int));
        B[i] = malloc(n * sizeof(int));
        C[i] = malloc(n * sizeof(int));
    }
    
    for (int i = 0; i < n; i++)
        for (int j = 0; j < n; j++) {
            A[i][j] = i + j; B[i][j] = i - j; C[i][j] = 0;
        }
    
    for (int i = 0; i < n; i++)
        for (int j = 0; j < n; j++)
            for (int k = 0; k < n; k++)
                C[i][j] += A[i][k] * B[k][j];
    
    printf("Matrix %dx%d done. C[0][0]=%d\n", n, n, C[0][0]);
    for (int i = 0; i < n; i++) { free(A[i]); free(B[i]); free(C[i]); }
    free(A); free(B); free(C);
    return 0;
}
EOF

    # Benchmark 4: Binary search
    cat > "$BENCHMARK_DIR/binary_search.c" << EOF
#include <stdio.h>
#include <stdlib.h>

int binary_search(int arr[], int n, int target) {
    int left = 0, right = n - 1;
    while (left <= right) {
        int mid = left + (right - left) / 2;
        if (arr[mid] == target) return mid;
        else if (arr[mid] < target) left = mid + 1;
        else right = mid - 1;
    }
    return -1;
}

int main() {
    int n = 100000;
    int* arr = malloc(n * sizeof(int));
    for (int i = 0; i < n; i++) arr[i] = i * 2;
    
    int found = 0;
    unsigned int seed = 54321;
    int searches = $LOOP_ITERS / 10;
    
    for (int i = 0; i < searches; i++) {
        seed = seed * 1103515245 + 12345;
        int target = (seed >> 16) % (n * 2);
        if (binary_search(arr, n, target) >= 0) found++;
    }
    
    printf("Found %d out of %d searches\n", found, searches);
    free(arr);
    return 0;
}
EOF

    # Benchmark 5: Linked list
    cat > "$BENCHMARK_DIR/linked_list.c" << EOF
#include <stdio.h>
#include <stdlib.h>

typedef struct Node { int value; struct Node* next; } Node;

int main() {
    int n = 10000;
    Node* nodes = malloc(n * sizeof(Node));
    for (int i = 0; i < n; i++) { nodes[i].value = i; nodes[i].next = NULL; }
    
    unsigned int seed = 99999;
    for (int i = 0; i < n - 1; i++) {
        seed = seed * 1103515245 + 12345;
        int j = i + (seed >> 16) % (n - i);
        Node tmp = nodes[i]; nodes[i] = nodes[j]; nodes[j] = tmp;
    }
    
    for (int i = 0; i < n - 1; i++) nodes[i].next = &nodes[i + 1];
    Node* head = &nodes[0];
    
    long sum = 0;
    int iters = $LOOP_ITERS / 1000;
    for (int iter = 0; iter < iters; iter++) {
        Node* curr = head;
        while (curr != NULL) {
            if (curr->value % 2 == 0) sum += curr->value;
            curr = curr->next;
        }
    }
    
    printf("Sum: %ld\n", sum);
    free(nodes);
    return 0;
}
EOF

    echo "Created 5 benchmark programs"
}

compile_benchmarks() {
    echo ""
    echo "=============================================="
    echo "  COMPILING BENCHMARKS (X86)"
    echo "=============================================="
    
    gcc -O2 -static -o "$BENCHMARK_DIR/branch_loop_x86" "$BENCHMARK_DIR/branch_loop.c"
    gcc -O2 -static -o "$BENCHMARK_DIR/quicksort_x86" "$BENCHMARK_DIR/quicksort.c"
    gcc -O2 -static -o "$BENCHMARK_DIR/matrix_x86" "$BENCHMARK_DIR/matrix.c"
    gcc -O2 -static -o "$BENCHMARK_DIR/binary_search_x86" "$BENCHMARK_DIR/binary_search.c"
    gcc -O2 -static -o "$BENCHMARK_DIR/linked_list_x86" "$BENCHMARK_DIR/linked_list.c"
    
    echo "Compiled all benchmarks"
}

run_realistic_benchmarks() {
    echo ""
    echo "=============================================="
    echo "  REALISTIC BENCHMARKS (X86)"
    echo "=============================================="
    
    BENCHMARKS="branch_loop quicksort matrix binary_search linked_list"
    
    for config in "${CPU_CONFIGS[@]}"; do
        IFS='|' read -r cpu_name cpu_type cpu_params <<< "$config"
        
        echo ""
        echo "========== CPU: $cpu_name ($cpu_type) =========="
        
        for bp in $PREDICTORS; do
            echo ""
            echo "Predictor: $bp"
            
            for bench in $BENCHMARKS; do
                if [ "$CPU_COMPARE" = true ]; then
                    outdir="benchmark_results/X86/${cpu_name}/${bp}/${bench}"
                else
                    outdir="benchmark_results/X86/${bp}/${bench}"
                fi
                
                mkdir -p "$outdir"
                echo "  $bench..."
                
                if [ -n "$cpu_params" ]; then
                    ./build/X86/gem5.opt -d "$outdir" $SE_SCRIPT \
                        --cpu-type=$cpu_type --caches --l2cache \
                        --bp-type=$bp \
                        $cpu_params \
                        -c "$BENCHMARK_DIR/${bench}_x86" 2>&1 | tail -1
                else
                    ./build/X86/gem5.opt -d "$outdir" $SE_SCRIPT \
                        --cpu-type=$cpu_type --caches --l2cache \
                        --bp-type=$bp \
                        -c "$BENCHMARK_DIR/${bench}_x86" 2>&1 | tail -1
                fi
            done
        done
    done
}

# ============================================================================
# EXPORT RESULTS TO CSV
# ============================================================================

export_results() {
    echo ""
    echo "=============================================="
    echo "  EXPORTING RESULTS TO CSV"
    echo "=============================================="
    
    CSV_FILE="benchmark_results/results.csv"
    
    if [ "$CPU_COMPARE" = true ]; then
        echo "cpu_config,predictor,benchmark,branches,mispredictions,instructions,ticks,accuracy,mpki" > "$CSV_FILE"
    else
        echo "arch,predictor,benchmark,branches,mispredictions,instructions,ticks,accuracy,mpki" > "$CSV_FILE"
    fi
    
    for config in "${CPU_CONFIGS[@]}"; do
        IFS='|' read -r cpu_name cpu_type cpu_params <<< "$config"
        
        if [ "$CPU_COMPARE" = true ]; then
            base_dir="benchmark_results/X86/${cpu_name}"
        else
            base_dir="benchmark_results/X86"
        fi
        
        if [ ! -d "$base_dir" ]; then
            continue
        fi
        
        for bp_dir in "$base_dir"/*/; do
            bp=$(basename "$bp_dir")
            
            for bench_dir in "$bp_dir"*/; do
                bench=$(basename "$bench_dir")
                stats_file="${bench_dir}stats.txt"
                
                if [ ! -f "$stats_file" ]; then
                    continue
                fi
                
                predicted=$(grep "branchPred.condPredicted " "$stats_file" 2>/dev/null | awk '{print $2}')
                incorrect=$(grep "branchPred.condIncorrect " "$stats_file" 2>/dev/null | awk '{print $2}')
                insts=$(grep "simInsts " "$stats_file" 2>/dev/null | head -1 | awk '{print $2}')
                ticks=$(grep "simTicks " "$stats_file" 2>/dev/null | head -1 | awk '{print $2}')
                
                if [ -n "$predicted" ] && [ -n "$incorrect" ] && [ -n "$insts" ] && [ -n "$ticks" ]; then
                    accuracy=$(awk "BEGIN {printf \"%.4f\", 100 - ($incorrect * 100 / $predicted)}")
                    mpki=$(awk "BEGIN {printf \"%.4f\", $incorrect * 1000 / $insts}")
                    
                    if [ "$CPU_COMPARE" = true ]; then
                        echo "$cpu_name,$bp,$bench,$predicted,$incorrect,$insts,$ticks,$accuracy,$mpki" >> "$CSV_FILE"
                    else
                        echo "X86,$bp,$bench,$predicted,$incorrect,$insts,$ticks,$accuracy,$mpki" >> "$CSV_FILE"
                    fi
                fi
            done
        done
    done
    
    echo "Results exported to: $CSV_FILE"
}

# ============================================================================
# MAIN
# ============================================================================

echo "=============================================="
echo "  X86 BRANCH PREDICTOR BENCHMARK SUITE"
echo "=============================================="

if [ "$CPU_COMPARE" = true ]; then
    echo ""
    echo "CPU Configurations to test:"
    for config in "${CPU_CONFIGS[@]}"; do
        IFS='|' read -r cpu_name cpu_type cpu_params <<< "$config"
        echo "  - $cpu_name ($cpu_type)"
    done
fi

if [ "$REAL_ONLY" = false ]; then
    run_hello_world
fi

if [ "$HELLO_ONLY" = false ]; then
    create_benchmarks
    compile_benchmarks
    run_realistic_benchmarks
    export_results
fi

echo ""
echo "=============================================="
echo "  COMPLETE"
echo "=============================================="
echo ""
echo "Results:"
if [ "$CPU_COMPARE" = true ]; then
    echo "  Hello world: m5out/<cpu_config>/<predictor>/stats.txt"
    echo "  Realistic:   benchmark_results/X86/<cpu_config>/<predictor>/<benchmark>/stats.txt"
    echo ""
    echo "Generate plots: python3 plot_results_v3.py --cpu-compare --output plots"
else
    echo "  Hello world: m5out/<predictor>/stats.txt"
    echo "  Realistic:   benchmark_results/X86/<predictor>/<benchmark>/stats.txt"
    echo ""
    echo "Generate plots: python3 plot_results_v3.py --output plots"
fi