/*
 * Simple Perceptron Branch Predictor for gem5
 * Adapted for modern gem5 API
 */

#ifndef __CPU_PRED_PERCEPTRON_LOCAL_HH__
#define __CPU_PRED_PERCEPTRON_LOCAL_HH__

#include <vector>

#include "base/types.hh"
#include "cpu/pred/bpred_unit.hh"
#include "params/PerceptronLocalBP.hh"

namespace gem5
{
namespace branch_prediction
{

/**
 * Simple perceptron-based local branch predictor.
 * Uses a table of perceptrons indexed by branch PC.
 * Each perceptron has weights for local history bits.
 */
class PerceptronLocalBP : public BPredUnit
{
  public:
    PerceptronLocalBP(const PerceptronLocalBPParams &params);

    // Required interface methods
    bool lookup(ThreadID tid, Addr pc, void * &bp_history) override;
    
    void updateHistories(ThreadID tid, Addr pc, bool uncond, bool taken,
                         Addr target, const StaticInstPtr &inst,
                         void * &bp_history) override;
    
    void update(ThreadID tid, Addr pc, bool taken,
                void * &bp_history, bool squashed,
                const StaticInstPtr &inst, Addr target) override;
    
    void squash(ThreadID tid, void * &bp_history) override;

  private:
    /** Structure to store branch history for recovery */
    struct BPHistory
    {
        unsigned localHistoryIdx;
        unsigned localHistory;
        bool predTaken;
        int perceptronOutput;
    };

    /** Single perceptron unit */
    struct Perceptron
    {
        std::vector<int> weights;  // Weights for history bits
        int bias;                   // Bias weight
        
        Perceptron(unsigned historyLength) 
            : weights(historyLength, 0), bias(0) {}
    };

    /** Calculate index into perceptron table */
    unsigned getIndex(Addr pc) const;

    /** Compute perceptron output */
    int computeOutput(const Perceptron &p, unsigned history) const;

    /** Train perceptron */
    void train(Perceptron &p, unsigned history, bool taken, int output);

    /** Table of perceptrons */
    std::vector<Perceptron> perceptronTable;

    /** Local history table */
    std::vector<unsigned> localHistoryTable;

    /** Number of entries in perceptron table */
    unsigned perceptronTableSize;

    /** Length of local history (number of weights per perceptron) */
    unsigned localHistoryLength;

    /** Mask for local history */
    unsigned localHistoryMask;

    /** Training threshold */
    int threshold;

    /** Maximum weight value */
    int weightMax;

    /** Minimum weight value */
    int weightMin;
};

} // namespace branch_prediction
} // namespace gem5

#endif // __CPU_PRED_PERCEPTRON_LOCAL_HH__
