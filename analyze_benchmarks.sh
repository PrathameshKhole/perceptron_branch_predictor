#!/usr/bin/env bash
#
# analyze_benchmarks.sh - Analyze and display benchmark results
#

RESULTS_DIR="benchmark_results"

echo "=============================================="
echo "    BRANCH PREDICTOR BENCHMARK ANALYSIS"
echo "=============================================="
echo ""

# Function to extract stats
get_stats() {
    local stats_file="$1"

    if [ ! -f "$stats_file" ]; then
        echo "NA NA NA NA"
        return
    fi

    local predicted incorrect insts ticks

    predicted=$(grep "branchPred.condPredicted " "$stats_file" 2>/dev/null | awk '{print $2}')
    incorrect=$(grep "branchPred.condIncorrect " "$stats_file" 2>/dev/null | awk '{print $2}')
    insts=$(grep "simInsts " "$stats_file" 2>/dev/null | head -1 | awk '{print $2}')
    ticks=$(grep "simTicks " "$stats_file" 2>/dev/null | head -1 | awk '{print $2}')

    if [ -z "$predicted" ] || [ -z "$incorrect" ] || [ -z "$insts" ] || [ -z "$ticks" ]; then
        echo "NA NA NA NA"
        return
    fi

    echo "$predicted $incorrect $insts $ticks"
}

# Print header
printf "%-20s %-15s %-12s %-12s %-10s %-10s\n" \
    "Benchmark" "Predictor" "Branches" "Mispreds" "Accuracy" "MPKI"
echo "--------------------------------------------------------------------------------"

# Process each architecture
for arch in X86 ARM; do
    if [ ! -d "$RESULTS_DIR/$arch" ]; then
        continue
    fi

    echo ""
    echo "=== $arch ==="
    echo ""

    # Get list of benchmarks and predictors
    for bench_dir in "$RESULTS_DIR/$arch"/*/; do
        bp=$(basename "$bench_dir")

        for stats_dir in "$bench_dir"*/; do
            bench=$(basename "$stats_dir")
            stats_file="$stats_dir/stats.txt"

            read predicted incorrect insts ticks <<< $(get_stats "$stats_file")

            if [ "$predicted" = "NA" ]; then
                printf "%-20s %-15s %-12s %-12s %-10s %-10s\n" \
                    "$bench" "$bp" "N/A" "N/A" "N/A" "N/A"
            else
                accuracy=$(awk "BEGIN {printf \"%.2f\", 100 - ($incorrect * 100 / $predicted)}")
                mpki=$(awk "BEGIN {printf \"%.2f\", $incorrect * 1000 / $insts}")

                printf "%-20s %-15s %-12s %-12s %-10s %-10s\n" \
                    "$bench" "$bp" "$predicted" "$incorrect" "${accuracy}%" "$mpki"
            fi
        done
    done
done

echo ""
echo "=============================================="
echo "    SUMMARY BY PREDICTOR (Average MPKI)"
echo "=============================================="
echo ""

# Calculate averages per predictor
for arch in X86 ARM; do
    if [ ! -d "$RESULTS_DIR/$arch" ]; then
        continue
    fi

    echo "=== $arch ==="

    for bp_dir in "$RESULTS_DIR/$arch"/*/; do
        bp=$(basename "$bp_dir")

        total_mpki=0
        count=0

        for stats_dir in "$bp_dir"*/; do
            stats_file="$stats_dir/stats.txt"
            read predicted incorrect insts ticks <<< $(get_stats "$stats_file")

            if [ "$predicted" != "NA" ] && [ "$insts" -gt 0 ]; then
                mpki=$(awk "BEGIN {print $incorrect * 1000 / $insts}")
                total_mpki=$(awk "BEGIN {print $total_mpki + $mpki}")
                count=$((count + 1))
            fi
        done

        if [ $count -gt 0 ]; then
            avg_mpki=$(awk "BEGIN {printf \"%.2f\", $total_mpki / $count}")
            printf "  %-25s Average MPKI: %s\n" "$bp" "$avg_mpki"
        fi
    done
    echo ""
done

# Export to CSV for plotting
echo "Exporting results to CSV..."

CSV_FILE="$RESULTS_DIR/results.csv"
echo "arch,predictor,benchmark,branches,mispredictions,instructions,ticks,accuracy,mpki" > "$CSV_FILE"

for arch in X86 ARM; do
    if [ ! -d "$RESULTS_DIR/$arch" ]; then
        continue
    fi

    for bp_dir in "$RESULTS_DIR/$arch"/*/; do
        bp=$(basename "$bp_dir")

        for stats_dir in "$bp_dir"*/; do
            bench=$(basename "$stats_dir")
            stats_file="$stats_dir/stats.txt"

            read predicted incorrect insts ticks <<< $(get_stats "$stats_file")

            if [ "$predicted" != "NA" ]; then
                accuracy=$(awk "BEGIN {printf \"%.4f\", 100 - ($incorrect * 100 / $predicted)}")
                mpki=$(awk "BEGIN {printf \"%.4f\", $incorrect * 1000 / $insts}")

                echo "$arch,$bp,$bench,$predicted,$incorrect,$insts,$ticks,$accuracy,$mpki" >> "$CSV_FILE"
            fi
        done
    done
done

echo "Results exported to: $CSV_FILE"
