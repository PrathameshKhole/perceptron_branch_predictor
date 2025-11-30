/*
 * Hybrid Global-Local Perceptron Branch Predictor
 *
 * Novel Features:
 * 1. Combines global history (correlation between branches) with
 *    local history (per-branch patterns)
 * 2. Adaptive threshold that adjusts based on misprediction rate
 * 3. Confidence-based prediction with bias toward more confident source
 *
 * For CSE 220 Class Project
 */

#ifndef __CPU_PRED_HYBRID_PERCEPTRON_HH__
#define __CPU_PRED_HYBRID_PERCEPTRON_HH__

#include <vector>

#include "base/types.hh"
#include "cpu/pred/bpred_unit.hh"
#include "params/HybridPerceptronBP.hh"

namespace gem5
{
namespace branch_prediction
{

class HybridPerceptronBP : public BPredUnit
{
  public:
    HybridPerceptronBP(const HybridPerceptronBPParams &params);

    bool lookup(ThreadID tid, Addr pc, void * &bp_history) override;

    void updateHistories(ThreadID tid, Addr pc, bool uncond, bool taken,
                         Addr target, const StaticInstPtr &inst,
                         void * &bp_history) override;

    void update(ThreadID tid, Addr pc, bool taken,
                void * &bp_history, bool squashed,
                const StaticInstPtr &inst, Addr target) override;

    void squash(ThreadID tid, void * &bp_history) override;

  private:
    struct BPHistory
    {
        unsigned localHistoryIdx;
        unsigned localHistory;
        unsigned globalHistory;
        bool predTaken;
        int localOutput;
        int globalOutput;
        int combinedOutput;
        bool usedGlobal;  // Track which predictor was dominant
    };

    /** Perceptron for local history */
    struct LocalPerceptron
    {
        std::vector<int> weights;
        int bias;

        LocalPerceptron(unsigned len) : weights(len, 0), bias(0) {}
    };

    /** Perceptron for global history */
    struct GlobalPerceptron
    {
        std::vector<int> weights;
        int bias;

        GlobalPerceptron(unsigned len) : weights(len, 0), bias(0) {}
    };

    unsigned getLocalIndex(Addr pc) const;
    unsigned getGlobalIndex(Addr pc) const;

    int computeLocalOutput(const LocalPerceptron &p, unsigned history) const;
    int computeGlobalOutput(const GlobalPerceptron &p, unsigned history) const;

    void trainLocal(LocalPerceptron &p, unsigned history, bool taken, int output);
    void trainGlobal(GlobalPerceptron &p, unsigned history, bool taken, int output);

    /** Combine local and global predictions */
    int combinePredictions(int localOut, int globalOut, Addr pc);

    // Local predictor components
    std::vector<LocalPerceptron> localPerceptrons;
    std::vector<unsigned> localHistoryTable;
    unsigned localTableSize;
    unsigned localHistoryLength;
    unsigned localHistoryMask;

    // Global predictor components
    std::vector<GlobalPerceptron> globalPerceptrons;
    unsigned globalHistory;          // Single global history register
    unsigned globalTableSize;
    unsigned globalHistoryLength;
    unsigned globalHistoryMask;

    // Hybrid parameters
    int baseThreshold;
    int adaptiveThreshold;           // Adjusts based on performance
    int weightMax;
    int weightMin;

    // Confidence/chooser mechanism
    std::vector<int> chooserCounters;  // Per-PC: positive = trust global, negative = trust local
    unsigned chooserSize;

    // Adaptive threshold tracking
    int mispredictionCounter;
    int predictionCounter;
    static const int THRESHOLD_ADJUST_INTERVAL = 1024;
};

} // namespace branch_prediction
} // namespace gem5

#endif // __CPU_PRED_HYBRID_PERCEPTRON_HH__
