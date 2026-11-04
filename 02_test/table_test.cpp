// Three modes; stdout is the sole result log. Real RTL, independent C++ arithmetic.
#include <verilated.h>
#include <verilated_vcd_c.h>
#if defined(TEST_FFE)
#include "Vrx_ffe.h"
using Dut = Vrx_ffe;
#elif defined(TEST_DFE)
#include "Vrx_dfe.h"
using Dut = Vrx_dfe;
#else
#include "Vchain_tb.h"
using Dut = Vchain_tb;
#endif
#include "eq_independent/reference_model.hpp"
#include <deque>
#include <iomanip>
#include <iostream>
#include <sstream>
#include <stdexcept>
#include <string>

using reference::I;
static I signed16(unsigned value) { return int16_t(value); }
static I slice(I y) { return y<=-8192 ? -12288 : y<=0 ? -4096 : y<=8192 ? 4096 : 12288; }
struct Clock {
    Dut &dut;
    VerilatedVcdC wave;
    bool tracing;
    uint64_t time=0, cycle=0;
    Clock(Dut &d,const char *path):dut(d),tracing(path!=nullptr) {
        if(tracing) { dut.trace(&wave,99); wave.open(path); }
    }
    void tick() {
        dut.i_clk=0; dut.eval(); if(tracing)wave.dump(time); time+=5000;
        dut.i_clk=1; dut.eval(); if(tracing)wave.dump(time); time+=5000;
        ++cycle;
    }
    ~Clock() { if(tracing)wave.close(); }
};
static std::string fixed_value(I value) {
    std::ostringstream text;
    text<<std::fixed<<std::setprecision(12)<<double(value)/4096;
    std::string decimal=text.str();
    while(decimal.back()=='0')decimal.pop_back();
    if(decimal.back()=='.')decimal.pop_back();
    return std::to_string(value)+" ("+decimal+")";
}
static void row(uint64_t cycle,I cpp,I sv) {
    std::cout<<"| "<<std::setw(10)<<cycle<<" | "<<std::setw(30)<<fixed_value(cpp)<<" | "<<std::setw(30)<<fixed_value(sv)<<" |\n";
}
static void border() { std::cout<<"+------------+--------------------------------+--------------------------------+\n"; }

#if defined(TEST_CHAIN)
struct Model {
    bool adapt;
    std::array<I,3> x{{0,0,0}},wa{{1048576,0,0}};
    I ba,previous_decision=0,previous_tx=0;
    int sample=0;
    struct Output { I channel,y,decision,error; std::array<I,4> taps; };
    explicit Model(bool lms):adapt(lms),ba(lms ? 0 : 524288) {}
    Output step(I tx) {
        const I channel=reference::sat(tx+reference::floor_shift(2048*previous_tx,12),16);
        previous_tx=tx;
        x={{channel,x[0],x[1]}};
        I sum=0;
        for(int k=0;k<3;++k)sum+=reference::sat(reference::floor_shift(reference::visible(wa[k])*x[k],12),16);
        const I feedback=reference::sat(reference::floor_shift(reference::visible(ba)*previous_decision,12),16);
        const I y=reference::sat(reference::sat(sum,16)-feedback,16),decision=slice(y);
        const I desired=sample<3000 ? tx : decision;
        const I error=reference::sat((adapt ? desired : decision)-y,16);
        const std::array<I,4> taps{{reference::visible(wa[0]),reference::visible(wa[1]),reference::visible(wa[2]),reference::visible(ba)}};
        if(adapt) {
            for(int k=0;k<3;++k)wa[k]=reference::sat(wa[k]+reference::delta(32,error,x[k]),40);
            ba=reference::sat(ba-reference::delta(32,error,previous_decision),40);
        }
        previous_decision=decision; ++sample;
        return {channel,y,decision,error,taps};
    }
};
#endif

int main(int argc,char **argv) {
    Verilated::commandArgs(argc,argv);
    try {
        if(argc<3 || argc>4)throw std::runtime_error("usage: TEST N [wave.vcd]");
        const std::string test=argv[1];
        if(test!="FIXED" && test!="LMS")throw std::runtime_error("TEST must be FIXED or LMS");
        const bool lms=test=="LMS";
        size_t used=0;
        const int samples=std::stoi(argv[2],&used);
        if(used!=std::string(argv[2]).size() || samples<1 || samples>10000000)
            throw std::runtime_error("N must be 1..10000000");
        Verilated::traceEverOn(argc==4);
        Dut d; Clock clock(d,argc==4 ? argv[3] : nullptr);
        size_t mismatches=0,outputs=0;
        const auto check=[&](I cpp,I sv) { if(cpp!=sv)++mismatches; };
        d.i_clk=0; d.i_rstn=0;
#if defined(TEST_FFE) || defined(TEST_DFE)
#if defined(TEST_FFE)
        constexpr bool ffe=true;
        const char *mode="FFE_ONLY";
#else
        constexpr bool ffe=false;
        const char *mode="DFE_ONLY";
#endif
        auto stimulus=reference::stimulus(lms ? "adapt_small" : "fixed_basic",ffe);
        const auto cfg=stimulus.front();
        d.i_valid=0; d.i_error=0; d.i_cfg_lms_en=lms; d.i_learning_rate=cfg.mu;
#if defined(TEST_FFE)
        d.i_r_in=0; d.i_cfg_ffe_en=1;
        d.i_cfg_ffe_w0=cfg.w0; d.i_cfg_ffe_w1=cfg.w1; d.i_cfg_ffe_w2=cfg.w2;
        reference::Ffe model(cfg);
#else
        d.i_sliced_data=0; d.i_error_valid=0; d.i_cfg_dfe_en=1; d.i_cfg_dfe_b0=cfg.b0;
        reference::Dfe model(cfg);
#endif
        clock.tick(); clock.tick(); d.i_rstn=1;
        std::cout<<"MODE="<<mode<<" TEST="<<test<<" N="<<samples<<" mu_Q16="<<cfg.mu<<'\n';
#if defined(TEST_FFE)
        std::cout<<"Initial w_Q12=[1024,3072,-512]; input: deterministic signed sample pattern.\n";
#else
        std::cout<<"Initial b_Q12=2048; input: previous decision [-12288,-4096,4096,12288].\n";
#endif
        std::cout<<"LMS uses supplied error [1,-1,2048,-2048,8192,-8192,0]; no convergence measurement.\n";
#else
        const char *mode="FFE_DFE";
        d.i_tx_en=0; d.i_isi_en=1; d.i_ffe_en=1; d.i_dfe_en=1;
        d.i_lms_en=lms; d.i_mu=32; d.i_h=2048;
        d.i_w0=4096; d.i_w1=0; d.i_w2=0; d.i_b0=lms ? 0 : 2048;
        clock.tick(); clock.tick(); clock.tick(); clock.tick(); d.i_rstn=1;
        Model model(lms);
        std::cout<<"MODE="<<mode<<" TEST="<<test<<" N="<<samples<<" mu_Q16=32\n"
                 <<"Initial w_Q12=[4096,0,0] b_Q12="<<(lms ? 0 : 2048)<<"; ISI_Q12=2048; AWGN=off.\n"
                 <<"TX: [-4096,4096,12288,-12288]; "
                 <<(lms ? "3000 valid outputs training, then decision-directed LMS.\n" : "Coefficients held fixed.\n");
#endif
        std::cout<<"Outputs: signed 16-bit Q4.12 raw integers followed by decimal value in parentheses (raw / 4096).\n"
                 <<"cycle = rising-edge count from simulation start, including reset; only valid outputs shown.\n";
#if defined(TEST_DFE)
        std::cout<<"DFE output is feedback=b0*previous_decision.\n";
#elif defined(TEST_CHAIN)
        std::cout<<"Output is FFE minus DFE feedback, before slicer.\n";
#endif
        border();
        std::cout<<"| "<<std::setw(10)<<"cycle"<<" | "<<std::setw(30)<<"output C++ (Q12 / real)"
                 <<" | "<<std::setw(30)<<"output SV (Q12 / real)"<<" |\n";
        border();
#if defined(TEST_FFE) || defined(TEST_DFE)
        reference::Result previous{};
        for(int n=0;n<=samples;++n) {
            const auto r=stimulus[n%stimulus.size()];
            d.i_valid=n<samples;
            d.i_error=n ? stimulus[(n-1)%stimulus.size()].error : 0;
#if defined(TEST_FFE)
            d.i_r_in=n<samples ? r.input : 0;
#else
            d.i_sliced_data=n<samples ? r.input : 0;
            d.i_error_valid=n>0;
#endif
            clock.tick();
            if(n) {
#if defined(TEST_FFE)
                check(previous.weights[0],signed16(d.o_curr_w0));
                check(previous.weights[1],signed16(d.o_curr_w1));
                check(previous.weights[2],signed16(d.o_curr_w2));
#else
                check(previous.weights[0],signed16(d.o_curr_b0));
#endif
            }
            check(n<samples,d.o_valid);
            if(n==samples)break;
            const auto expected=model.step(r);
#if defined(TEST_FFE)
            const I actual=signed16(d.o_ffe_data);
#else
            const I actual=signed16(d.o_dfe_data);
#endif
            check(expected.y,actual);
            row(clock.cycle,expected.y,actual); ++outputs;
            previous=expected;
        }
#else
        std::deque<Model::Output> cq,rq;
        Model::Output current{};
        int launched=0,generated=0,channels=0;
        bool previous_tx_valid=false;
        for(int n=0;n<samples+16;++n) {
            d.i_clk=0; d.i_tx_en=launched<samples; launched+=d.i_tx_en; d.eval();
            const bool tv=d.o_tx_valid,cv=d.o_channel_valid;
            if(tv) {
                const I levels[4]={-12288,-4096,4096,12288};
                const I tx=signed16(d.o_tx);
                check(levels[(generated+1)%4],tx); ++generated;
                cq.push_back(model.step(tx));
            }
            if(cv)rq.push_back(current);
            clock.tick();
            check(previous_tx_valid,d.o_channel_valid); check(cv,d.o_rx_valid);
            previous_tx_valid=tv;
            if(d.o_channel_valid) {
                if(cq.empty())throw std::runtime_error("unexpected channel output");
                current=cq.front(); cq.pop_front(); ++channels;
                check(current.channel,signed16(d.o_channel));
                check(0,signed16(d.o_noise));
            }
            if(!d.o_rx_valid)continue;
            if(rq.empty())throw std::runtime_error("unexpected RX output");
            const auto expected=rq.front(); rq.pop_front();
            const I actual=signed16(d.o_y);
            check(expected.y,actual); check(expected.decision,signed16(d.o_decision));
            check(expected.error,signed16(d.o_error));
            check(lms && outputs<3000,d.o_training);
            const I actual_taps[4]={signed16(d.o_w0),signed16(d.o_w1),signed16(d.o_w2),signed16(d.o_b0)};
            for(int k=0;k<4;++k)check(expected.taps[k],actual_taps[k]);
            row(clock.cycle,expected.y,actual); ++outputs;
        }
        check(samples,generated); check(samples,channels); check(0,cq.size()); check(0,rq.size());
#endif
        check(samples,outputs);
        border();
        d.final();
        std::cout<<(mismatches ? "FAIL" : "PASS")<<" outputs="<<outputs<<" mismatches="<<mismatches
                 <<" (output, valid, coefficients; chain also checks channel, decision, error, training)\n";
        return mismatches ? 1 : 0;
    }catch(const std::exception &e) { std::cerr<<"ERROR: "<<e.what()<<'\n'; return 2; }
}
