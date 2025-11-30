#!/usr/bin/env bash
#
# run_benchmarks.sh - Run branch predictor benchmarks with realistic workloads
#
# Usage: ./run_benchmarks.sh [--build] [--quick]
#   --build: Rebuild gem5 before running
#   --quick: Run only quick tests (smaller iteration counts)

set -e

# Parse arguments
BUILD=false
QUICK=false
for arg in "$@"; do
    case $arg in
        --build) BUILD=true ;;
        --quick) QUICK=true ;;
    esac
done

# Configuration
SE_SCRIPT="configs/deprecated/example/se.py"
RESULTS_DIR="benchmark_results"
BENCHMARK_DIR="/tmp/bp_benchmarks"

# Create directories
mkdir -p "$RESULTS_DIR"
mkdir -p "$BENCHMARK_DIR"

# Build if requested
if [ "$BUILD" = true ]; then
    echo "Building X86 gem5.opt..."
    scons build/X86/gem5.opt -j$(nproc)
    echo "Building ARM gem5.opt..."
    scons build/ARM/gem5.opt -j$(nproc)
fi

# Set iteration counts based on mode
if [ "$QUICK" = true ]; then
    LOOP_ITERS=100000
    MATRIX_SIZE=50
    SORT_SIZE=1000
    echo "Running in QUICK mode (smaller workloads)"
else
    LOOP_ITERS=5000000
    MATRIX_SIZE=150
    SORT_SIZE=10000
    echo "Running in FULL mode (larger workloads)"
fi

echo ""
echo "=============================================="
echo "  CREATING BENCHMARK PROGRAMS"
echo "=============================================="

# Benchmark 1: Branch-heavy loop with complex patterns
cat > "$BENCHMARK_DIR/branch_loop.c" << EOF
#include <stdio.h>
#include <stdlib.h>

int main() {
    long sum = 0;
    int iterations = $LOOP_ITERS;

    for (int i = 0; i < iterations; i++) {
        // Pattern 1: Alternating
        if (i % 2 == 0) sum += i;
        else sum -= i;

        // Pattern 2: Less frequent
        if (i % 7 == 0) sum *= 2;

        // Pattern 3: Nested conditions
        if (i % 3 == 0) {
            if (i % 9 == 0) sum += 100;
            else sum += 10;
        }

        // Pattern 4: Data-dependent (harder to predict)
        if (sum % 5 == 0) sum++;
    }

    printf("Result: %ld\\n", sum);
    return 0;
}
EOF

# Benchmark 2: Sorting (data-dependent branches)
cat > "$BENCHMARK_DIR/quicksort.c" << EOF
#include <stdio.h>
#include <stdlib.h>
#include <time.h>

void swap(int* a, int* b) {
    int t = *a;
    *a = *b;
    *b = t;
}

int partition(int arr[], int low, int high) {
    int pivot = arr[high];
    int i = (low - 1);

    for (int j = low; j <= high - 1; j++) {
        if (arr[j] < pivot) {  // Data-dependent branch!
            i++;
            swap(&arr[i], &arr[j]);
        }
    }
    swap(&arr[i + 1], &arr[high]);
    return (i + 1);
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

    // Initialize with pseudo-random values
    unsigned int seed = 12345;
    for (int i = 0; i < n; i++) {
        seed = seed * 1103515245 + 12345;
        arr[i] = (seed >> 16) & 0x7fff;
    }

    quicksort(arr, 0, n - 1);

    printf("Sorted %d elements. First: %d, Last: %d\\n",
           n, arr[0], arr[n-1]);

    free(arr);
    return 0;
}
EOF

# Benchmark 3: Matrix operations (regular patterns)
cat > "$BENCHMARK_DIR/matrix.c" << EOF
#include <stdio.h>
#include <stdlib.h>

int main() {
    int n = $MATRIX_SIZE;

    // Allocate matrices
    int** A = malloc(n * sizeof(int*));
    int** B = malloc(n * sizeof(int*));
    int** C = malloc(n * sizeof(int*));

    for (int i = 0; i < n; i++) {
        A[i] = malloc(n * sizeof(int));
        B[i] = malloc(n * sizeof(int));
        C[i] = malloc(n * sizeof(int));
    }

    // Initialize
    for (int i = 0; i < n; i++) {
        for (int j = 0; j < n; j++) {
            A[i][j] = i + j;
            B[i][j] = i - j;
            C[i][j] = 0;
        }
    }

    // Matrix multiply (predictable loop patterns)
    for (int i = 0; i < n; i++) {
        for (int j = 0; j < n; j++) {
            for (int k = 0; k < n; k++) {
                C[i][j] += A[i][k] * B[k][j];
            }
        }
    }

    printf("Matrix %dx%d multiply done. C[0][0]=%d\\n", n, n, C[0][0]);

    // Cleanup
    for (int i = 0; i < n; i++) {
        free(A[i]); free(B[i]); free(C[i]);
    }
    free(A); free(B); free(C);

    return 0;
}
EOF

# Benchmark 4: Binary search (hard to predict)
cat > "$BENCHMARK_DIR/binary_search.c" << EOF
#include <stdio.h>
#include <stdlib.h>

int binary_search(int arr[], int n, int target) {
    int left = 0, right = n - 1;

    while (left <= right) {
        int mid = left + (right - left) / 2;

        if (arr[mid] == target)      // Hard to predict!
            return mid;
        else if (arr[mid] < target)  // ~50/50 probability
            left = mid + 1;
        else
            right = mid - 1;
    }
    return -1;
}

int main() {
    int n = 100000;
    int* arr = malloc(n * sizeof(int));

    // Create sorted array
    for (int i = 0; i < n; i++) {
        arr[i] = i * 2;
    }

    // Perform many searches
    int found = 0;
    unsigned int seed = 54321;

    for (int i = 0; i < $LOOP_ITERS / 10; i++) {
        seed = seed * 1103515245 + 12345;
        int target = (seed >> 16) % (n * 2);

        if (binary_search(arr, n, target) >= 0) {
            found++;
        }
    }

    printf("Found %d out of %d searches\\n", found, $LOOP_ITERS / 10);

    free(arr);
    return 0;
}
EOF

# Benchmark 5: Linked list traversal (pointer-chasing, hard patterns)
cat > "$BENCHMARK_DIR/linked_list.c" << EOF
#include <stdio.h>
#include <stdlib.h>

typedef struct Node {
    int value;
    struct Node* next;
} Node;

int main() {
    int n = 10000;

    // Create nodes
    Node* nodes = malloc(n * sizeof(Node));
    for (int i = 0; i < n; i++) {
        nodes[i].value = i;
        nodes[i].next = NULL;
    }

    // Shuffle to create random traversal pattern
    unsigned int seed = 99999;
    for (int i = 0; i < n - 1; i++) {
        seed = seed * 1103515245 + 12345;
        int j = i + (seed >> 16) % (n - i);
        // Swap
        Node tmp = nodes[i];
        nodes[i] = nodes[j];
        nodes[j] = tmp;
    }

    // Create linked structure
    for (int i = 0; i < n - 1; i++) {
        nodes[i].next = &nodes[i + 1];
    }
    Node* head = &nodes[0];

    // Traverse multiple times
    long sum = 0;
    for (int iter = 0; iter < $LOOP_ITERS / 1000; iter++) {
        Node* curr = head;
        while (curr != NULL) {
            if (curr->value % 2 == 0) sum += curr->value;  // Data-dependent
            curr = curr->next;
        }
    }

    printf("Sum: %ld\\n", sum);
    free(nodes);
    return 0;
}
EOF

echo ""
echo "=============================================="
echo "  COMPILING BENCHMARKS"
echo "=============================================="

# Compile for X86
echo "Compiling for X86..."
gcc -O2 -static -o "$BENCHMARK_DIR/branch_loop_x86" "$BENCHMARK_DIR/branch_loop.c"
gcc -O2 -static -o "$BENCHMARK_DIR/quicksort_x86" "$BENCHMARK_DIR/quicksort.c"
gcc -O2 -static -o "$BENCHMARK_DIR/matrix_x86" "$BENCHMARK_DIR/matrix.c"
gcc -O2 -static -o "$BENCHMARK_DIR/binary_search_x86" "$BENCHMARK_DIR/binary_search.c"
gcc -O2 -static -o "$BENCHMARK_DIR/linked_list_x86" "$BENCHMARK_DIR/linked_list.c"

# Compile for ARM (if cross-compiler available)
if command -v arm-linux-gnueabi-gcc &> /dev/null; then
    echo "Compiling for ARM..."
    arm-linux-gnueabi-gcc -O2 -static -o "$BENCHMARK_DIR/branch_loop_arm" "$BENCHMARK_DIR/branch_loop.c"
    arm-linux-gnueabi-gcc -O2 -static -o "$BENCHMARK_DIR/quicksort_arm" "$BENCHMARK_DIR/quicksort.c"
    arm-linux-gnueabi-gcc -O2 -static -o "$BENCHMARK_DIR/matrix_arm" "$BENCHMARK_DIR/matrix.c"
    arm-linux-gnueabi-gcc -O2 -static -o "$BENCHMARK_DIR/binary_search_arm" "$BENCHMARK_DIR/binary_search.c"
    arm-linux-gnueabi-gcc -O2 -static -o "$BENCHMARK_DIR/linked_list_arm" "$BENCHMARK_DIR/linked_list.c"
    ARM_AVAILABLE=true
else
    echo "ARM cross-compiler not found, skipping ARM benchmarks"
    ARM_AVAILABLE=false
fi

echo ""
echo "=============================================="
echo "  RUNNING BENCHMARKS"
echo "=============================================="

PREDICTORS="HybridPerceptronBP PerceptronLocalBP LocalBP TournamentBP LTAGE"
BENCHMARKS="branch_loop quicksort matrix binary_search linked_list"

# Function to run a single benchmark
run_benchmark() {
    local arch=$1
    local bp=$2
    local bench=$3
    local binary=$4
    local outdir="$RESULTS_DIR/${arch}/${bp}/${bench}"

    mkdir -p "$outdir"

    echo "  Running $arch $bp on $bench..."

    if [ "$arch" = "X86" ]; then
        ./build/X86/gem5.opt -d "$outdir" $SE_SCRIPT \
            --cpu-type=O3CPU --caches --l2cache \
            --bp-type=$bp \
            -c "$binary" 2>&1 | tail -1
    else
        ./build/ARM/gem5.opt -d "$outdir" $SE_SCRIPT \
            --cpu-type=O3CPU --caches --l2cache \
            --bp-type=$bp \
            -c "$binary" 2>&1 | tail -1
    fi
}

# Run X86 benchmarks
echo ""
echo "--- X86 Benchmarks ---"
for bp in $PREDICTORS; do
    echo "Predictor: $bp"
    for bench in $BENCHMARKS; do
        run_benchmark "X86" "$bp" "$bench" "$BENCHMARK_DIR/${bench}_x86"
    done
    echo ""
done

# Run ARM benchmarks if available
if [ "$ARM_AVAILABLE" = true ]; then
    echo ""
    echo "--- ARM Benchmarks ---"
    for bp in $PREDICTORS; do
        echo "Predictor: $bp"
        for bench in $BENCHMARKS; do
            run_benchmark "ARM" "$bp" "$bench" "$BENCHMARK_DIR/${bench}_arm"
        done
        echo ""
    done
fi

echo ""
echo "=============================================="
echo "  BENCHMARKS COMPLETE"
echo "=============================================="
echo "Results saved in: $RESULTS_DIR/"
echo ""
echo "Run './analyze_benchmarks.sh' to see comparison"
echo "Run 'python3 plot_results.py' to generate plots"
