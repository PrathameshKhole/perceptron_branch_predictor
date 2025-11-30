#!/usr/bin/env bash

echo "======================================================="
echo "    BRANCH PREDICTOR COMPARISON: X86 vs ARM (Hello)"
echo "======================================================="
echo ""

get_stats() {
    local stats_file="$1"

    if [ ! -f "$stats_file" ]; then
        echo "NA NA NA NA"
        return
    fi

    local predicted incorrect insts ticks

    predicted=$(grep "branchPred.condPredicted " "$stats_file" | awk '{print $2}')
    incorrect=$(grep "branchPred.condIncorrect " "$stats_file" | awk '{print $2}')
    insts=$(grep "simInsts " "$stats_file" | head -1 | awk '{print $2}')
    ticks=$(grep "simTicks " "$stats_file" | head -1 | awk '{print $2}')

    if [ -z "$predicted" ] || [ -z "$incorrect" ] || [ -z "$insts" ] || [ -z "$ticks" ]; then
        echo "NA NA NA NA"
        return
    fi

    echo "$predicted $incorrect $insts $ticks"
}

print_line() {
    local label="$1"
    local predicted="$2"
    local incorrect="$3"
    local insts="$4"
    local ticks="$5"

    if [ "$predicted" = "NA" ]; then
        printf "  %-6s: %-12s %-12s %-12s %-12s %-12s %-12s\n" \
            "$label" "NA" "NA" "NA" "NA" "NA" "NA"
        return
    fi

    local accuracy mpki

    accuracy=$(awk "BEGIN {printf \"%.2f\", 100 - ($incorrect * 100 / $predicted)}")
    mpki=$(awk "BEGIN {printf \"%.4f\", $incorrect * 1000 / $insts}")

    printf "  %-6s: %-12s %-12s %-12s %-12s %-12s %-12s\n" \
        "$label" \
        "$predicted" \
        "$incorrect" \
        "$insts" \
        "$ticks" \
        "${accuracy}%" \
        "$mpki"
}

for bp in perceptron local tournament ltage hybrid; do
    echo "-------------------------------------------------------"
    echo "Predictor: $bp"
    echo "-------------------------------------------------------"

    x86_vals=$(get_stats "m5out/$bp/stats.txt")
    arm_vals=$(get_stats "m5out_arm/$bp/stats.txt")

    read x86_pred x86_inc x86_insts x86_ticks <<< "$x86_vals"
    read arm_pred arm_inc arm_insts arm_ticks <<< "$arm_vals"

    printf "  %-6s  %-12s %-12s %-12s %-12s %-12s %-12s\n" \
        "ISA" "Branches" "Mispreds" "Insts" "Ticks" "Accuracy" "MPKI"

    print_line "X86" "$x86_pred" "$x86_inc" "$x86_insts" "$x86_ticks"
    print_line "ARM" "$arm_pred" "$arm_inc" "$arm_insts" "$arm_ticks"

    echo ""
done

