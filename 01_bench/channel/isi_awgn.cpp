#include "Vchannel_top.h"
#include "verilated.h"
#include "verilated_vcd_c.h"
#include <array>
#include <cmath>
#include <cstdint>
#include <cstdio>
#include <deque>
#include <fstream>
#include <stdexcept>
#include <string>
#include <vector>
#include "psd_check.h"

static int sat(int64_t x) { return int(x > 32767 ? 32767 : x < -32768 ? -32768 : x); }
// Explicit floor division: independent of implementation-defined signed C++ shift.
static int64_t qfloor(int64_t x) { return x >= 0 ? x/4096 : -((-x+4095)/4096); }
static uint32_t mix(uint32_t x) { x ^= x<<13; x ^= x>>17; return x^(x<<5); }
struct Noise {
    std::array<std::array<uint32_t,3>,12> state{};
    Noise() {
        for (unsigned j=0;j<12;j++) {
            const unsigned factors[3]={101,211,307}, biases[3]={1,3,7}, minima[3]={2,8,16};
            for (unsigned k=0;k<3;k++) {
                auto x=mix(0xa5b+factors[k]*(j+1)+biases[k]);
                state[j][k]=x<minima[k]?x+minima[k]:x;
            }
        }
    }
    int next() {
        int sum=0;
        const unsigned a[3]={13,2,3}, b[3]={19,25,11}, c[3]={12,4,17};
        const uint32_t masks[3]={0xfffffffeu,0xfffffff8u,0xfffffff0u};
        for (unsigned j=0;j<12;j++) {
            uint32_t word=0;
            for (unsigned k=0;k<3;k++) {
                uint32_t x=state[j][k];
                uint32_t feedback=(uint32_t(uint64_t(x)<<a[k])^x)>>b[k];
                state[j][k]=uint32_t(uint64_t(x&masks[k])<<c[k])^feedback;
                word^=state[j][k];
            }
            uint32_t rotated=uint32_t(uint64_t(word)<<11)|(word>>21);
            sum+=((word^(word>>7)^rotated)>>((4*j)%21))&4095;
        }
        return sum-24570;
    }
};
struct Expected { uint64_t due; int clean, noise, out, tx; bool measure; };
static uint64_t reference_power(int h,bool isi) {
    return 5*((uint64_t(1)<<24)+(isi?int64_t(h)*h:0));
}
static int sigma_for_snr(unsigned snr,int h,bool isi) {
    const uint64_t power=reference_power(h,isi);
    uint64_t rms=uint64_t(std::sqrt(double(power)));
    while((rms+1)*(rms+1)<=power)++rms;
    while(rms*rms>power)--rms;
    const uint64_t gain=uint64_t(std::llround(std::pow(10.,-double(std::min(snr,40u))/20)*(1<<24)));
    return int(std::min(uint64_t(32767),(rms*gain+(1<<23))>>24));
}

int main(int argc,char** argv) {
    try {
        Verilated::commandArgs(argc,argv);
        Verilated::traceEverOn(true);
        Vchannel_top dut;
        VerilatedVcdC trace;
        dut.trace(&trace,99);
        trace.set_time_unit("1ns");
        trace.set_time_resolution("1ns");
        trace.open("isi0_awgn.vcd");
        std::ofstream csv("isi0_awgn_samples.csv");
        std::ofstream raw_noise("awgn_noise_q12.bin",std::ios::binary);
        std::ofstream raw_channel("channel_output_q12.bin",std::ios::binary);
        if(!csv || !raw_noise || !raw_channel)throw std::runtime_error("Cannot open capture files");
        csv<<"sample,tx_q12,clean_q12,noise_q12,channel_q12\n";
        uint64_t time=0,cycle=0,checked=0,count=0;
        uint64_t trace_until=1000000;
        Noise rng;
        int previous=0;
        std::deque<Expected> pending;
        std::vector<int> prefix;
        std::vector<double> psd_samples;
        std::ofstream sweep_capture;
        psd_samples.reserve(1000000);
        double sum=0,sum2=0,sum3=0,sum4=0,lag=0,first=0,last=0;
        unsigned active_snr=20;
        int active_sigma=916;
        uint64_t active_power=5ull<<24;
        auto tick=[&](bool dump) {
            dut.i_clk=0; dut.eval(); if(dump)trace.dump(time); time+=5;
            dut.i_clk=1; dut.eval(); if(dump)trace.dump(time); time+=5;
        };
        auto reset=[&]() {
            dut.i_rstn=0; dut.i_valid=0; dut.i_tx_data=0;
            dut.i_cfg_isi_en=0; dut.i_cfg_isi_coeff=0;
            dut.i_cfg_awgn_en=0; dut.i_cfg_snr_db=0;
            dut.i_cfg_snr_load=0;
            for(int i=0;i<5;i++)tick(time<trace_until);
            dut.i_rstn=1; rng=Noise(); previous=0; cycle=0; pending.clear();
            active_snr=20; active_sigma=916; active_power=5ull<<24;
            if(dut.o_cfg_snr_db!=20 || int16_t(dut.o_cfg_sigma_q12)!=916)
                throw std::runtime_error("SNR reset/readback mismatch");
        };
        auto send=[&](bool valid,int tx,int h,bool isi,bool awgn,unsigned snr,bool measure=false,bool load=false) {
            dut.i_valid=valid; dut.i_tx_data=uint16_t(tx);
            dut.i_cfg_isi_en=isi; dut.i_cfg_isi_coeff=uint16_t(h);
            dut.i_cfg_awgn_en=awgn; dut.i_cfg_snr_db=uint16_t(snr);
            dut.i_cfg_snr_load=load;
            if(valid) {
                const int clean=sat(tx+(isi?qfloor(int64_t(previous)*h):0));
                previous=tx;
                const int z=rng.next(); // advances for all accepted symbols, even when muted
                const int noise=awgn?sat(qfloor(int64_t(z)*active_sigma)):0;
                pending.push_back({cycle+4,clean,noise,sat(clean+noise),tx,measure});
            }
            tick(time<trace_until);
            if(load) {
                active_snr=std::min(snr,40u);
                active_sigma=sigma_for_snr(snr,h,isi);
                active_power=reference_power(h,isi);
            }
            if(dut.o_cfg_snr_db!=active_snr || int16_t(dut.o_cfg_sigma_q12)!=active_sigma
                || dut.o_cfg_signal_power_q24!=active_power)
                throw std::runtime_error("SNR latch/gain/power readback mismatch");
            const bool expected_valid=!pending.empty()&&pending.front().due==cycle;
            if(bool(dut.o_valid)!=expected_valid)
                throw std::runtime_error("valid/latency mismatch at cycle "+std::to_string(cycle));
            if(expected_valid) {
                auto e=pending.front(); pending.pop_front();
                const int clean=int16_t(dut.o_clean_isi_data), noise=int16_t(dut.o_awgn_noise);
                if(clean!=e.clean || noise!=e.noise || int16_t(dut.o_channel_data)!=e.out)
                    throw std::runtime_error("sample mismatch at cycle "+std::to_string(cycle));
                checked++;
                if(sweep_capture.is_open()) {
                    for(uint16_t bits: {uint16_t(clean),uint16_t(noise),uint16_t(dut.o_channel_data)}) {
                        const char pair[2]={char(bits&255),char(bits>>8)};
                        sweep_capture.write(pair,2);
                    }
                }
                if(e.measure) {
                    psd_samples.push_back(noise/4096.0);
                    // Explicit little-endian int16 capture, all one million samples.
                    const uint16_t bits=uint16_t(noise);
                    const char bytes[2]={char(bits&255),char(bits>>8)};
                    raw_noise.write(bytes,2);
                    const uint16_t output_bits=dut.o_channel_data;
                    const char output_bytes[2]={char(output_bits&255),char(output_bits>>8)};
                    raw_channel.write(output_bytes,2);
                    const double z=noise/916.0; // main SNR=20 dB, sigma_Q12=916
                    if(count<4096)csv<<count<<','<<e.tx<<','<<clean<<','<<noise<<','<<e.out<<'\n';
                    if(count<64)prefix.push_back(noise);
                    if(count)lag+=last*z; else first=z;
                    last=z; sum+=z; sum2+=z*z; sum3+=z*z*z; sum4+=z*z*z*z; count++;
                }
            }
            cycle++;
        };
        auto drain=[&]() { for(int i=0;i<5;i++)send(false,0,0,false,false,0); };
        reset();
        // Exhaustive LUT/calibration readback: all supported dB values and
        // several ISI coefficients. No valid input, so RNG state is unchanged.
        for(int h: {0,2048,-2048,32767,-32768})
            for(unsigned db=0;db<=40;db++)send(false,0,h,true,false,db,false,true);
        reset();
        send(false,0,0,true,false,20,false,true);
        // Input changes without a load must leave the active register unchanged.
        send(false,0,0,true,false,37);
        // Main run: ISI enabled with h1=0, AWGN enabled, configured SNR=20 dB.
        // Uniformly distributed random PAM4; independent PRNG from the noise lanes.
        uint32_t txstate=0x12345678;
        const int levels[4]={-12288,-4096,4096,12288};
        trace_until=time+41000;
        for(unsigned i=0;i<1000000;i++) {
            txstate=mix(txstate);
            send(true,levels[txstate&3],0,true,true,20,true);
        }
        drain();
        const double mean=sum/count, raw2=sum2/count;
        const double variance=raw2-mean*mean, sd=std::sqrt(variance);
        const double m3=sum3/count-3*mean*raw2+2*mean*mean*mean;
        const double m4=sum4/count-4*mean*sum3/count+6*mean*mean*raw2-3*std::pow(mean,4);
        const double excess=m4/(variance*variance)-3;
        const double acf=(lag/(count-1)-mean*((sum-first)/(count-1)+(sum-last)/(count-1))+mean*mean)/variance;
        if(std::abs(mean)>.01 || sd<.98 || sd>1.02 || std::abs(acf)>.01 || excess<-.2 || excess>0)
            throw std::runtime_error("noise statistical smoke checks failed");
        std::printf("ISI=0 AWGN=ON SNR=20 dB sigma_Q12=916: %llu exact samples checked\n",(unsigned long long)count);
        std::printf("Normalized noise: mean=%.9f std=%.9f skew=%.9f excess_kurtosis=%.9f lag1_acf=%.9f\n",
                    mean,sd,m3/std::pow(sd,3),excess,acf);
        raw_noise.close();
        raw_channel.close();
        if(!raw_noise || !raw_channel)throw std::runtime_error("Binary capture write failed");
        channel_psd::check(psd_samples);
        std::ofstream metadata("capture_config.json");
        metadata<<"{\"snr_db\":20,\"sigma_q12\":916,\"reference_power\":5,\"sample_period_ns\":10,\"samples\":1000000}\n";
        metadata.close();

        // Independent actual-output captures for SNR monitoring, no reference regeneration.
        std::ofstream manifest("snr_cases.csv");
        manifest<<"case_id,requested_db,active_db,isi_en,h1_q12,sigma_q12,reference_power_q24,samples,first_output_time_ns,path\n";
        struct SnrCase { unsigned db; int h; bool isi; };
        const SnrCase cases[]={{10,0,true},{15,0,true},{20,0,true},{25,0,true},
            {30,0,true},{35,0,true},{40,0,true},{20,2048,true},{30,2048,true},
            {20,-2048,true},{20,2048,false},{99,0,true}};
        unsigned case_index=0;
        for(const auto& c:cases) {
            reset();
            send(false,0,c.h,c.isi,false,c.db,false,true);
            const std::string filename="snr_case_"+std::to_string(case_index)+".bin";
            sweep_capture.open(filename,std::ios::binary);
            if(!sweep_capture)throw std::runtime_error("Cannot open SNR capture");
            constexpr unsigned n=200000;
            manifest<<case_index<<','<<c.db<<','<<active_snr<<','<<c.isi<<','<<c.h<<','<<active_sigma
                <<','<<active_power<<','<<n<<','<<time+45<<','<<filename<<'\n';
            uint32_t symbol_seed=0x5c12ab73;
            for(unsigned i=0;i<n;i++) {
                symbol_seed=mix(symbol_seed);
                send(true,levels[symbol_seed&3],c.h,c.isi,true,c.db);
            }
            drain(); sweep_capture.close();
            if(!sweep_capture)throw std::runtime_error("SNR capture write failed");
            ++case_index;
        }
        manifest.close();
        // Reset must replay the same noise, independent of input data.
        reset();
        for(unsigned i=0;i<64;i++) {
            send(true,0,0,true,true,20);
            if(i>=4 && int16_t(dut.o_awgn_noise)!=prefix[i-4])
                throw std::runtime_error("reset replay mismatch");
        }
        drain();
        // Directed ISI, sign/floor arithmetic, bypass, saturation and bubbles.
        reset();
        for(int tx: {-12288,-4096,4096,12288,-12288})send(true,tx,2048,true,false,0);
        for(int tx: {4096,0,0,0})send(true,tx,-2048,true,false,0);
        for(int i=0;i<256;i++) {
            int tx=(i&1)?32767:-32768;
            send(i%7!=0,tx,(i&2)?32767:-32768,true,i%3!=0,unsigned(i%50),false,i%13==0);
        }
        for(int i=0;i<128;i++)
            send(i%5!=0,-1-i,2049,i%2!=0,i%3!=0,(i&1)?30:10,false,i%11==0);
        drain();
        // Reset while samples are still in flight must discard the old pipeline.
        send(true,1234,2048,true,true,1024);
        reset(); drain();
        dut.final(); trace.close(); csv.close();
        std::printf("PASS: %llu total outputs; ISI, saturation, config alignment, valid gaps, reset/replay.\n",
                    (unsigned long long)checked);
        std::printf("Waveform: isi0_awgn.vcd (first ~4096 clocks); CSV: isi0_awgn_samples.csv\n");
        return 0;
    } catch(const std::exception& e) { std::fprintf(stderr,"FAIL: %s\n",e.what()); return 1; }
}
