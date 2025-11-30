#!/usr/bin/env bash

set -e

# Build X86 and ARM gem5 binaries (comment out if already built)
echo "Building X86 gem5.opt..."
scons build/X86/gem5.opt -j6

echo "Building ARM gem5.opt..."
scons build/ARM/gem5.opt -j6

# Common options
SE_SCRIPT="configs/deprecated/example/se.py"

X86_HELLO="tests/test-progs/hello/bin/x86/linux/hello"
ARM_HELLO="tests/test-progs/hello/bin/arm/linux/hello"

if [ ! -f "$X86_HELLO" ]; then
    echo "Error: X86 hello binary not found at $X86_HELLO"
    exit 1
fi

if [ ! -f "$ARM_HELLO" ]; then
    echo "Error: ARM hello binary not found at $ARM_HELLO"
    exit 1
fi

echo "=============================================="
echo "    RUNNING BRANCH PREDICTORS (X86 + ARM)"
echo "=============================================="
echo ""

# ----- X86 runs (your original ones, using m5out/<bp>) -----

echo "Running X86 HybridPerceptronBP..."
./build/X86/gem5.opt -d m5out/hybrid $SE_SCRIPT \
    --cpu-type=O3CPU --caches --l2cache \
    --bp-type=HybridPerceptronBP \
    -c "$X86_HELLO"

echo "Running X86 LocalBP..."
./build/X86/gem5.opt -d m5out/local $SE_SCRIPT \
    --cpu-type=O3CPU --caches --l2cache \
    --bp-type=LocalBP \
    -c "$X86_HELLO"

echo "Running X86 TournamentBP..."
./build/X86/gem5.opt -d m5out/tournament $SE_SCRIPT \
    --cpu-type=O3CPU --caches --l2cache \
    --bp-type=TournamentBP \
    -c "$X86_HELLO"

echo "Running X86 LTAGE..."
./build/X86/gem5.opt -d m5out/ltage $SE_SCRIPT \
    --cpu-type=O3CPU --caches --l2cache \
    --bp-type=LTAGE \
    -c "$X86_HELLO"

echo "Running X86 PerceptronLocalBP..."
./build/X86/gem5.opt -d m5out/perceptron $SE_SCRIPT \
    --cpu-type=O3CPU --caches --l2cache \
    --bp-type=PerceptronLocalBP \
    -c "$X86_HELLO"


# ----- ARM runs (parallel dirs under m5out_arm/<bp>) -----

echo "Running ARM HybridPerceptronBP..."
./build/ARM/gem5.opt -d m5out_arm/hybrid $SE_SCRIPT \
    --cpu-type=O3CPU --caches --l2cache \
    --bp-type=HybridPerceptronBP \
    -c "$ARM_HELLO"

echo "Running ARM LocalBP..."
./build/ARM/gem5.opt -d m5out_arm/local $SE_SCRIPT \
    --cpu-type=O3CPU --caches --l2cache \
    --bp-type=LocalBP \
    -c "$ARM_HELLO"

echo "Running ARM TournamentBP..."
./build/ARM/gem5.opt -d m5out_arm/tournament $SE_SCRIPT \
    --cpu-type=O3CPU --caches --l2cache \
    --bp-type=TournamentBP \
    -c "$ARM_HELLO"

echo "Running ARM LTAGE..."
./build/ARM/gem5.opt -d m5out_arm/ltage $SE_SCRIPT \
    --cpu-type=O3CPU --caches --l2cache \
    --bp-type=LTAGE \
    -c "$ARM_HELLO"

echo "Running ARM PerceptronLocalBP..."
./build/ARM/gem5.opt -d m5out_arm/perceptron $SE_SCRIPT \
    --cpu-type=O3CPU --caches --l2cache \
    --bp-type=PerceptronLocalBP \
    -c "$ARM_HELLO"

echo ""
echo "All X86 and ARM runs completed."

