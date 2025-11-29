/*
 * Simple Perceptron Branch Predictor Implementation
 */

#include "cpu/pred/perceptron_local.hh"

#include <cmath>

#include "base/intmath.hh"
#include "base/logging.hh"
#include "base/trace.hh"
#include "debug/Branch.hh"

namespace gem5
{
namespace branch_prediction
{

PerceptronLocalBP::PerceptronLocalBP(const PerceptronLocalBPParams &params)
    : BPredUnit(params),
      perceptronTableSize(params.perceptronTableSize),
      localHistoryLength(params.localHistoryLength),
      threshold(params.threshold),
      weightMax(params.weightMax),
      weightMin(params.weightMin)
{
    if (!isPowerOf2(perceptronTableSize)) {
        fatal("Perceptron table size must be power of 2!\n");
    }

    // Initialize perceptron table
    for (unsigned i = 0; i < perceptronTableSize; ++i) {
        perceptronTable.emplace_back(localHistoryLength);
    }

    // Initialize local history table (one per entry)
    localHistoryTable.resize(perceptronTableSize, 0);

    // Calculate local history mask
    localHistoryMask = (1 << localHistoryLength) - 1;

    DPRINTF(Branch, "PerceptronLocalBP: tableSize=%u, histLength=%u, "
            "threshold=%d\n", perceptronTableSize, localHistoryLength, 
            threshold);
}

unsigned
PerceptronLocalBP::getIndex(Addr pc) const
{
    return (pc >> instShiftAmt) & (perceptronTableSize - 1);
}

int
PerceptronLocalBP::computeOutput(const Perceptron &p, unsigned history) const
{
    int output = p.bias;
    
    for (unsigned i = 0; i < localHistoryLength; ++i) {
        // If bit i of history is 1, add weight; otherwise subtract
        if ((history >> i) & 1) {
            output += p.weights[i];
        } else {
            output -= p.weights[i];
        }
    }
    
    return output;
}

void
PerceptronLocalBP::train(Perceptron &p, unsigned history, 
                         bool taken, int output)
{
    int t = taken ? 1 : -1;
    
    // Only train if prediction was wrong or output is weak
    if ((output >= 0) != taken || std::abs(output) <= threshold) {
        // Update bias
        p.bias += t;
        if (p.bias > weightMax) p.bias = weightMax;
        if (p.bias < weightMin) p.bias = weightMin;
        
        // Update weights
        for (unsigned i = 0; i < localHistoryLength; ++i) {
            int xi = ((history >> i) & 1) ? 1 : -1;
            p.weights[i] += t * xi;
            
            // Saturate weights
            if (p.weights[i] > weightMax) p.weights[i] = weightMax;
            if (p.weights[i] < weightMin) p.weights[i] = weightMin;
        }
    }
}

bool
PerceptronLocalBP::lookup(ThreadID tid, Addr pc, void * &bp_history)
{
    unsigned idx = getIndex(pc);
    unsigned localHistory = localHistoryTable[idx];
    
    // Compute perceptron output
    int output = computeOutput(perceptronTable[idx], localHistory);
    bool taken = (output >= 0);
    
    // Create history for recovery
    BPHistory *history = new BPHistory;
    history->localHistoryIdx = idx;
    history->localHistory = localHistory;
    history->predTaken = taken;
    history->perceptronOutput = output;
    bp_history = static_cast<void*>(history);
    
    DPRINTF(Branch, "PerceptronLocalBP lookup: PC=%#x, idx=%u, "
            "localHist=%#x, output=%d, pred=%s\n",
            pc, idx, localHistory, output, taken ? "taken" : "not taken");
    
    return taken;
}

void
PerceptronLocalBP::updateHistories(ThreadID tid, Addr pc, bool uncond,
                                   bool taken, Addr target,
                                   const StaticInstPtr &inst,
                                   void * &bp_history)
{
    // For unconditional branches, we still update history
    unsigned idx = getIndex(pc);
    
    // Speculatively update local history
    localHistoryTable[idx] = ((localHistoryTable[idx] << 1) | taken) 
                              & localHistoryMask;
    
    // If no history exists (unconditional branch), create one
    if (bp_history == nullptr) {
        BPHistory *history = new BPHistory;
        history->localHistoryIdx = idx;
        history->localHistory = localHistoryTable[idx];
        history->predTaken = taken;
        history->perceptronOutput = 0;
        bp_history = static_cast<void*>(history);
    }
}

void
PerceptronLocalBP::update(ThreadID tid, Addr pc, bool taken,
                          void * &bp_history, bool squashed,
                          const StaticInstPtr &inst, Addr target)
{
    if (bp_history == nullptr) {
        return;
    }
    
    BPHistory *history = static_cast<BPHistory*>(bp_history);
    unsigned idx = history->localHistoryIdx;
    
    DPRINTF(Branch, "PerceptronLocalBP update: PC=%#x, idx=%u, "
            "taken=%s, squashed=%s\n",
            pc, idx, taken ? "true" : "false", 
            squashed ? "true" : "false");
    
    if (squashed) {
        // Restore local history on squash
        localHistoryTable[idx] = ((history->localHistory << 1) | taken) 
                                  & localHistoryMask;
    }
    
    // Train the perceptron
    train(perceptronTable[idx], history->localHistory, taken, 
          history->perceptronOutput);
    
    // Clean up
    delete history;
    bp_history = nullptr;
}

void
PerceptronLocalBP::squash(ThreadID tid, void * &bp_history)
{
    if (bp_history == nullptr) {
        return;
    }
    
    BPHistory *history = static_cast<BPHistory*>(bp_history);
    
    // Restore local history
    localHistoryTable[history->localHistoryIdx] = history->localHistory;
    
    DPRINTF(Branch, "PerceptronLocalBP squash: idx=%u, restored hist=%#x\n",
            history->localHistoryIdx, history->localHistory);
    
    delete history;
    bp_history = nullptr;
}

} // namespace branch_prediction
} // namespace gem5