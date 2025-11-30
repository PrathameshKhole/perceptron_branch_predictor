/*
 * Hybrid Global-Local Perceptron Branch Predictor Implementation
 *
 * Key Innovation: Combines the strengths of both local and global history
 * - Local history captures loop patterns and branch-specific behavior
 * - Global history captures inter-branch correlations
 * - Adaptive chooser learns which predictor to trust for each branch
 * - Dynamic threshold adjustment improves accuracy over time
 */

#include "cpu/pred/hybrid_perceptron.hh"

#include <cmath>

#include "base/intmath.hh"
#include "base/logging.hh"
#include "base/trace.hh"
#include "debug/Branch.hh"

namespace gem5
{
namespace branch_prediction
{

HybridPerceptronBP::HybridPerceptronBP(const HybridPerceptronBPParams &params)
    : BPredUnit(params),
      localTableSize(params.localTableSize),
      localHistoryLength(params.localHistoryLength),
      globalTableSize(params.globalTableSize),
      globalHistoryLength(params.globalHistoryLength),
      baseThreshold(params.threshold),
      adaptiveThreshold(params.threshold),
      weightMax(params.weightMax),
      weightMin(params.weightMin),
      chooserSize(params.chooserSize),
      mispredictionCounter(0),
      predictionCounter(0)
{
    // Validate parameters
    if (!isPowerOf2(localTableSize)) {
        fatal("HybridPerceptronBP: localTableSize must be power of 2!\n");
    }
    if (!isPowerOf2(globalTableSize)) {
        fatal("HybridPerceptronBP: globalTableSize must be power of 2!\n");
    }

    // Initialize local perceptrons
    for (unsigned i = 0; i < localTableSize; ++i) {
        localPerceptrons.emplace_back(localHistoryLength);
    }
    localHistoryTable.resize(localTableSize, 0);
    localHistoryMask = (1ULL << localHistoryLength) - 1;

    // Initialize global perceptrons
    for (unsigned i = 0; i < globalTableSize; ++i) {
        globalPerceptrons.emplace_back(globalHistoryLength);
    }
    globalHistory = 0;
    globalHistoryMask = (1ULL << globalHistoryLength) - 1;

    // Initialize chooser counters (start neutral)
    chooserCounters.resize(chooserSize, 0);

    DPRINTF(Branch, "HybridPerceptronBP: localTable=%u, globalTable=%u, "
            "localHist=%u, globalHist=%u, threshold=%d\n",
            localTableSize, globalTableSize, localHistoryLength,
            globalHistoryLength, baseThreshold);
}

unsigned
HybridPerceptronBP::getLocalIndex(Addr pc) const
{
    return (pc >> instShiftAmt) & (localTableSize - 1);
}

unsigned
HybridPerceptronBP::getGlobalIndex(Addr pc) const
{
    // XOR PC with global history for better distribution
    return ((pc >> instShiftAmt) ^ globalHistory) & (globalTableSize - 1);
}

int
HybridPerceptronBP::computeLocalOutput(const LocalPerceptron &p,
                                        unsigned history) const
{
    int output = p.bias;

    for (unsigned i = 0; i < localHistoryLength; ++i) {
        if ((history >> i) & 1) {
            output += p.weights[i];
        } else {
            output -= p.weights[i];
        }
    }

    return output;
}

int
HybridPerceptronBP::computeGlobalOutput(const GlobalPerceptron &p,
                                         unsigned history) const
{
    int output = p.bias;

    for (unsigned i = 0; i < globalHistoryLength; ++i) {
        if ((history >> i) & 1) {
            output += p.weights[i];
        } else {
            output -= p.weights[i];
        }
    }

    return output;
}

int
HybridPerceptronBP::combinePredictions(int localOut, int globalOut, Addr pc)
{
    // Get chooser counter for this PC
    unsigned chooserIdx = (pc >> instShiftAmt) & (chooserSize - 1);
    int chooser = chooserCounters[chooserIdx];

    // Compute confidence of each prediction
    int localConf = std::abs(localOut);
    int globalConf = std::abs(globalOut);

    // If chooser strongly favors one predictor, use it
    if (chooser >= 2) {
        // Trust global more
        return globalOut;
    } else if (chooser <= -2) {
        // Trust local more
        return localOut;
    }

    // Otherwise, weighted combination based on confidence
    // Higher confidence prediction gets more weight
    if (localConf + globalConf == 0) {
        return localOut;  // Default to local if both zero
    }

    // Weighted average favoring more confident predictor
    int combined = (localOut * localConf + globalOut * globalConf) /
                   (localConf + globalConf + 1);

    return combined;
}

void
HybridPerceptronBP::trainLocal(LocalPerceptron &p, unsigned history,
                                bool taken, int output)
{
    int t = taken ? 1 : -1;

    // Train if wrong or not confident enough
    if ((output >= 0) != taken || std::abs(output) <= adaptiveThreshold) {
        p.bias += t;
        p.bias = std::max(weightMin, std::min(weightMax, p.bias));

        for (unsigned i = 0; i < localHistoryLength; ++i) {
            int xi = ((history >> i) & 1) ? 1 : -1;
            p.weights[i] += t * xi;
            p.weights[i] = std::max(weightMin, std::min(weightMax, p.weights[i]));
        }
    }
}

void
HybridPerceptronBP::trainGlobal(GlobalPerceptron &p, unsigned history,
                                 bool taken, int output)
{
    int t = taken ? 1 : -1;

    if ((output >= 0) != taken || std::abs(output) <= adaptiveThreshold) {
        p.bias += t;
        p.bias = std::max(weightMin, std::min(weightMax, p.bias));

        for (unsigned i = 0; i < globalHistoryLength; ++i) {
            int xi = ((history >> i) & 1) ? 1 : -1;
            p.weights[i] += t * xi;
            p.weights[i] = std::max(weightMin, std::min(weightMax, p.weights[i]));
        }
    }
}

bool
HybridPerceptronBP::lookup(ThreadID tid, Addr pc, void * &bp_history)
{
    unsigned localIdx = getLocalIndex(pc);
    unsigned globalIdx = getGlobalIndex(pc);
    unsigned localHist = localHistoryTable[localIdx];

    // Compute both predictions
    int localOut = computeLocalOutput(localPerceptrons[localIdx], localHist);
    int globalOut = computeGlobalOutput(globalPerceptrons[globalIdx], globalHistory);

    // Combine predictions
    int combinedOut = combinePredictions(localOut, globalOut, pc);
    bool taken = (combinedOut >= 0);

    // Determine which predictor was dominant for stats/training
    bool usedGlobal = (std::abs(globalOut) > std::abs(localOut));

    // Create history for recovery
    BPHistory *history = new BPHistory;
    history->localHistoryIdx = localIdx;
    history->localHistory = localHist;
    history->globalHistory = globalHistory;
    history->predTaken = taken;
    history->localOutput = localOut;
    history->globalOutput = globalOut;
    history->combinedOutput = combinedOut;
    history->usedGlobal = usedGlobal;
    bp_history = static_cast<void*>(history);

    DPRINTF(Branch, "HybridPerceptronBP lookup: PC=%#x, localOut=%d, "
            "globalOut=%d, combined=%d, pred=%s\n",
            pc, localOut, globalOut, combinedOut,
            taken ? "taken" : "not taken");

    return taken;
}

void
HybridPerceptronBP::updateHistories(ThreadID tid, Addr pc, bool uncond,
                                     bool taken, Addr target,
                                     const StaticInstPtr &inst,
                                     void * &bp_history)
{
    unsigned localIdx = getLocalIndex(pc);

    // Speculatively update local history
    localHistoryTable[localIdx] = ((localHistoryTable[localIdx] << 1) | taken)
                                   & localHistoryMask;

    // Speculatively update global history
    globalHistory = ((globalHistory << 1) | taken) & globalHistoryMask;

    if (bp_history == nullptr) {
        BPHistory *history = new BPHistory;
        history->localHistoryIdx = localIdx;
        history->localHistory = localHistoryTable[localIdx];
        history->globalHistory = globalHistory;
        history->predTaken = taken;
        history->localOutput = 0;
        history->globalOutput = 0;
        history->combinedOutput = 0;
        history->usedGlobal = false;
        bp_history = static_cast<void*>(history);
    }
}

void
HybridPerceptronBP::update(ThreadID tid, Addr pc, bool taken,
                            void * &bp_history, bool squashed,
                            const StaticInstPtr &inst, Addr target)
{
    if (bp_history == nullptr) {
        return;
    }

    BPHistory *history = static_cast<BPHistory*>(bp_history);
    unsigned localIdx = history->localHistoryIdx;
    unsigned globalIdx = getGlobalIndex(pc);

    if (squashed) {
        // Restore histories
        localHistoryTable[localIdx] = ((history->localHistory << 1) | taken)
                                       & localHistoryMask;
        globalHistory = ((history->globalHistory << 1) | taken)
                        & globalHistoryMask;
    }

    // Train both perceptrons
    trainLocal(localPerceptrons[localIdx], history->localHistory, taken,
               history->localOutput);
    trainGlobal(globalPerceptrons[globalIdx], history->globalHistory, taken,
                history->globalOutput);

    // Update chooser based on which predictor was correct
    bool localCorrect = ((history->localOutput >= 0) == taken);
    bool globalCorrect = ((history->globalOutput >= 0) == taken);
    unsigned chooserIdx = (pc >> instShiftAmt) & (chooserSize - 1);

    if (globalCorrect && !localCorrect) {
        // Global was right, local was wrong - trust global more
        if (chooserCounters[chooserIdx] < 3) {
            chooserCounters[chooserIdx]++;
        }
    } else if (localCorrect && !globalCorrect) {
        // Local was right, global was wrong - trust local more
        if (chooserCounters[chooserIdx] > -3) {
            chooserCounters[chooserIdx]--;
        }
    }

    // Adaptive threshold adjustment
    predictionCounter++;
    if ((history->combinedOutput >= 0) != taken) {
        mispredictionCounter++;
    }

    // Periodically adjust threshold
    if (predictionCounter >= THRESHOLD_ADJUST_INTERVAL) {
        float mispredRate = (float)mispredictionCounter / predictionCounter;

        // If misprediction rate is high, increase threshold (train more)
        // If low, decrease threshold (train less, preserve learning)
        if (mispredRate > 0.25f && adaptiveThreshold < baseThreshold * 2) {
            adaptiveThreshold++;
        } else if (mispredRate < 0.15f && adaptiveThreshold > baseThreshold / 2) {
            adaptiveThreshold--;
        }

        DPRINTF(Branch, "HybridPerceptronBP: Adjusted threshold to %d "
                "(mispred rate: %.2f%%)\n",
                adaptiveThreshold, mispredRate * 100);

        mispredictionCounter = 0;
        predictionCounter = 0;
    }

    delete history;
    bp_history = nullptr;
}

void
HybridPerceptronBP::squash(ThreadID tid, void * &bp_history)
{
    if (bp_history == nullptr) {
        return;
    }

    BPHistory *history = static_cast<BPHistory*>(bp_history);

    // Restore both histories
    localHistoryTable[history->localHistoryIdx] = history->localHistory;
    globalHistory = history->globalHistory;

    DPRINTF(Branch, "HybridPerceptronBP squash: restored localHist=%#x, "
            "globalHist=%#x\n", history->localHistory, history->globalHistory);

    delete history;
    bp_history = nullptr;
}

} // namespace branch_prediction
} // namespace gem5
