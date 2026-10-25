#include "Vber_block_test.h"
#include "verilated.h"
#include <algorithm>
#include <cstdint>
#include <iostream>
#include <random>
#include <stdexcept>
#include <string>
#include <vector>

constexpr int N = TEST_N;
static_assert(N >= 1 && N <= 16, "Test driver supports 1..16 lanes");
constexpr int RX_PIPE = TEST_FF + TEST_DF + TEST_SL;
constexpr int PATH = TEST_CH + RX_PIPE;
constexpr int MAX_DELAY = PATH + (TEST_D + N - 1) / N;
constexpr int SETTLE = MAX_DELAY > 0 ? MAX_DELAY : 1;
constexpr uint64_t COUNTER_MAX = UINT64_MAX >> (64 - TEST_CW);
constexpr uint64_t WORD_MASK = (uint64_t(1) << (2 * N)) - 1;

struct Test {
    Vber_block_test d;
    std::mt19937 random{2026};
    std::vector<unsigned> transmitted;
    int64_t age = 0, last_config = -100000000;
    uint64_t expected_errors = 0, expected_total = 0;
    uint64_t compared_blocks = 0;
    bool bypass = false, previous_noise = false, previous_adapt = false;
    void require(bool value, const std::string& text) {
        if (!value) throw std::runtime_error(text + " at clock " + std::to_string(age));
    }
    Test() {
        d.i_clk=0; d.i_rst_n=0; d.enabled=1; d.clear=0;
        d.cfg_load=0; d.noise_load=0; d.noise_en=0; d.adapt_en=0;
        d.bp_f=0; d.bp_d=0; d.error_mask=0;
    }
    void edge() {
        d.i_clk=0; d.eval(); d.i_clk=1; d.eval(); d.i_clk=0; d.eval();
    }
    void reset() {
        d.i_rst_n=0;
        for (int k=0;k<3;++k) edge();
        age=0; last_config=-100000000; bypass=false;
        previous_noise=false; previous_adapt=false;
        expected_errors=0; expected_total=0; transmitted.clear();
        require(d.errors==0 && d.total==0 && !d.ready,"Reset values");
        d.i_rst_n=1;
    }
    void step(uint64_t injection=0) {
        d.error_mask=injection & WORD_MASK; d.i_clk=0; d.eval();
        const bool config = d.cfg_load || d.noise_load ||
                            d.noise_en!=previous_noise || d.adapt_en!=previous_adapt;
        const int delay_symbols = bypass ? 0 : TEST_D;
        require(d.latency==unsigned(PATH+(delay_symbols+N-1)/N),"Reported maximum reference age");
        for(int k=0;k<N;++k) transmitted.push_back((uint64_t(d.tx_bits)>>(2*k))&3);
        unsigned good_lanes=0, bit_errors=0;
        const bool settled = age > last_config + SETTLE;
        for(int k=0;k<N;++k) {
            // Absolute chronological symbol indices, independent of RTL quotient/remainder taps.
            const int64_t tx_index = (age-TEST_TX-PATH)*N+k-delay_symbols;
            const int64_t training_index = (age-(TEST_TX+TEST_CH+RX_PIPE))*N+k;
            const bool valid = tx_index>=0 && training_index>=(TEST_SKIP ? TEST_TRAIN : 0);
            if(!valid) continue;
            ++good_lanes;
            const int64_t reference_slot = (age-PATH)*N+k-delay_symbols;
            require(reference_slot>=0 && reference_slot<int64_t(transmitted.size()),"Reference bounds");
            const unsigned expected_gray=transmitted[size_t(reference_slot)];
            const unsigned observed_gray=(uint64_t(d.rx_bits)>>(2*k))&3;
            const unsigned injected=(injection>>(2*k))&3;
            if(settled && !config && !d.clear) {
                require(observed_gray==(expected_gray^injected),"Fixture/reference chronology lane "+std::to_string(k));
            }
            const unsigned difference=observed_gray^expected_gray;
            bit_errors+=(difference&1)+((difference>>1)&1);
        }
        const bool ready=good_lanes>0 && settled && !config && !d.clear;
        require(bool(d.ready)==ready,"Ready/partial training qualification");
        if(config || d.clear) {
            expected_errors=0; expected_total=0;
        } else if(d.enabled && ready) {
            const uint64_t increment=2*good_lanes;
            if(expected_total<=COUNTER_MAX-increment) {
                expected_errors+=bit_errors; expected_total+=increment; ++compared_blocks;
            }
        }
        if(config) last_config=age;
        if(d.cfg_load) bypass=d.bp_f;
        previous_noise=d.noise_en; previous_adapt=d.adapt_en;
        edge();
        require(d.errors==expected_errors,"Incorrect error total: expected "+std::to_string(expected_errors)+", actual "+std::to_string(d.errors));
        require(d.total==expected_total,"Incorrect bit total: expected "+std::to_string(expected_total)+", actual "+std::to_string(d.total));
        require(d.errors<=d.total && !(uint64_t(d.total)&1),"Counter invariants");
        ++age;
    }
    void run(int cycles,bool inject=false) {
        for(int k=0;k<cycles;++k) step(inject ? random() : 0);
    }
    void clear() {d.clear=1;step();d.clear=0;}
    void exercise() {
        reset();
        run((TEST_SKIP ? TEST_TRAIN/N+1 : 1)+TEST_TX+PATH+MAX_DELAY+30);
        require(d.total>0 && d.errors==0,"Initial training and zero-error block stream");
        clear();
        for(int k=0;k<9;++k) step(uint64_t(3)<<(2*(N-1)));
        require(d.errors>0,"Highest lane must be counted");
        clear();
        for(int k=0;k<9;++k) step(WORD_MASK);
        require(d.errors==d.total && d.total>0,"All lanes two-bit errors");
        d.enabled=0; const uint64_t held=d.total; run(17,true);
        require(d.total==held,"Pause counter");clear();run(7,true);
        require(d.total==0,"Clear while paused");d.enabled=1;run(500,true);
        for(int mode=0;mode<4;++mode) {
            d.bp_f=(mode>>1)&1; d.bp_d=mode&1; d.cfg_load=1;step();d.cfg_load=0;
            run(SETTLE+20,true);
            d.bp_f=!d.bp_f; d.bp_d=!d.bp_d;run(9,true); // no load: mode must hold
        }
        d.cfg_load=1;run(3,true);d.cfg_load=0;run(SETTLE+20,true);
        d.noise_load=1;step();d.noise_load=0;run(SETTLE+20,true);
        d.noise_en=!d.noise_en;step();run(SETTLE+20,true);
        d.adapt_en=!d.adapt_en;step();run(SETTLE+20,true);
        clear();run(20,true);
        reset();run((TEST_SKIP ? TEST_TRAIN/N+1 : 1)+TEST_TX+PATH+MAX_DELAY+30,true);
        require(compared_blocks>0,"No measured blocks");
    }
};
int main(int argc,char** argv) {
    Verilated::commandArgs(argc,argv);
    try {
        Test test;test.exercise();
        std::cout<<"PASS block BER N="<<N<<" TX="<<TEST_TX<<" PATH="<<PATH
                 <<" D="<<TEST_D<<" TRAIN="<<TEST_TRAIN<<" SKIP="<<TEST_SKIP
                 <<" CW="<<TEST_CW<<"\n";
    }catch(const std::exception& e) {std::cerr<<e.what()<<"\n";return 1;}
}
