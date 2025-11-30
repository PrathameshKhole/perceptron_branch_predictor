echo "=============================================="
echo "    BRANCH PREDICTOR COMPARISON RESULTS"
echo "=============================================="
echo ""

for bp in perceptron local tournament ltage; do
    echo "--- $bp ---"
    if [ -f "m5out/$bp/stats.txt" ]; then
        predicted=$(grep "branchPred.condPredicted " m5out/$bp/stats.txt | awk '{print $2}')
        incorrect=$(grep "branchPred.condIncorrect " m5out/$bp/stats.txt | awk '{print $2}')
        insts=$(grep "simInsts " m5out/$bp/stats.txt | head -1 | awk '{print $2}')
        ticks=$(grep "simTicks " m5out/$bp/stats.txt | head -1 | awk '{print $2}')

        echo "  Conditional Branches: $predicted"
        echo "  Mispredictions: $incorrect"
        echo "  Instructions: $insts"
        echo "  Ticks: $ticks"

        if [ -n "$incorrect" ] && [ -n "$predicted" ] && [ "$predicted" -gt 0 ]; then
            accuracy=$(awk "BEGIN {printf \"%.2f\", 100 - ($incorrect * 100 / $predicted)}")
            mpki=$(awk "BEGIN {printf \"%.4f\", $incorrect * 1000 / $insts}")
            echo "  Accuracy: $accuracy%"
            echo "  MPKI: $mpki"
        fi
    else
        echo "  (no stats file found)"
    fi
    echo ""
done
