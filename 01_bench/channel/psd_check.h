#pragma once
// Welch PSD of actual RTL noise, not regenerated reference samples.
// Periodic Hann, 2048 samples/segment, 50% overlap, one-sided density.
// Scaling follows https://docs.scipy.org/doc/scipy/reference/generated/scipy.signal.welch.html
#include <algorithm>
#include <complex>
#include <iomanip>
#include <numeric>

namespace channel_psd {
constexpr unsigned length=2048, hop=1024;
constexpr double fs=100e6, target_variance=5.0/100; // configured SNR=20 dB
constexpr double pi=3.14159265358979323846;

inline void fft(std::vector<std::complex<double>>& x) {
    const unsigned n=x.size();
    for(unsigned i=1,j=0;i<n;i++) {
        unsigned bit=n>>1;
        for(;j&bit;bit>>=1)j^=bit;
        j^=bit;
        if(i<j)std::swap(x[i],x[j]);
    }
    for(unsigned size=2;size<=n;size<<=1) {
        const auto step=std::polar(1.0,-2*pi/size);
        for(unsigned start=0;start<n;start+=size) {
            std::complex<double> phase=1;
            for(unsigned j=0;j<size/2;j++) {
                auto a=x[start+j], b=phase*x[start+j+size/2];
                x[start+j]=a+b; x[start+j+size/2]=a-b; phase*=step;
            }
        }
    }
}
struct Result {
    std::vector<double> density;
    unsigned segments=0;
    double power=0, variance=0, max_bin_db=0, max_band_db=0, flatness=0;
    bool passes() const {
        return std::abs(power/target_variance-1)<.02
            && std::abs(power/variance-1)<.02
            && max_bin_db<1.5 && max_band_db<.35 && flatness>.98;
    }
};
inline Result analyze(const std::vector<double>& samples) {
    if(samples.size()<length)throw std::runtime_error("Too few PSD samples");
    Result r;
    r.density.assign(length/2+1,0);
    const double mean=std::accumulate(samples.begin(),samples.end(),0.0)/samples.size();
    std::vector<double> window(length);
    double energy=0;
    for(unsigned i=0;i<length;i++) {
        window[i]=.5-.5*std::cos(2*pi*i/length); energy+=window[i]*window[i];
    }
    for(double x:samples)r.variance+=(x-mean)*(x-mean)/samples.size();
    std::vector<std::complex<double>> spectrum(length);
    for(size_t start=0;start+length<=samples.size();start+=hop) {
        for(unsigned j=0;j<length;j++)spectrum[j]=(samples[start+j]-mean)*window[j];
        fft(spectrum);
        for(unsigned k=0;k<=length/2;k++)
            r.density[k]+=std::norm(spectrum[k])/(fs*energy)*((k==0||k==length/2)?1:2);
        r.segments++;
    }
    for(double& p:r.density) { p/=r.segments; r.power+=p*fs/length; }
    const double ideal=2*target_variance/fs;
    // Exclude DC/Nyquist and their nearby bins from whiteness tests. DC is
    // deliberately affected by mean removal, and endpoint bins are not doubled.
    constexpr unsigned low=8, high=length/2-8;
    double arithmetic=0, logarithmic=0;
    for(unsigned k=low;k<high;k++) {
        double ratio=std::max(r.density[k]/ideal,1e-300);
        r.max_bin_db=std::max(r.max_bin_db,std::abs(10*std::log10(ratio)));
        arithmetic+=ratio; logarithmic+=std::log(ratio);
    }
    r.flatness=std::exp(logarithmic/(high-low))/(arithmetic/(high-low));
    for(unsigned band=0;band<16;band++) {
        unsigned begin=low+(high-low)*band/16, end=low+(high-low)*(band+1)/16;
        double power=0;
        for(unsigned k=begin;k<end;k++)power+=r.density[k];
        r.max_band_db=std::max(r.max_band_db,std::abs(10*std::log10(power/(end-begin)/ideal)));
    }
    return r;
}
inline void check(const std::vector<double>& samples) {
    const auto r=analyze(samples);
    std::ofstream csv("awgn_psd.csv");
    csv<<"frequency_hz,psd_amplitude2_per_hz,white_reference_amplitude2_per_hz\n"<<std::setprecision(17);
    for(unsigned k=0;k<r.density.size();k++)
        csv<<k*fs/length<<','<<r.density[k]<<','
           <<target_variance/fs*((k==0||k==length/2)?1:2)<<'\n';
    if(!csv)throw std::runtime_error("Cannot write awgn_psd.csv");
    std::printf("PSD Welch: N=%zu Fs=100MHz nperseg=%u overlap=%u segments=%u\n",
                samples.size(),length,length-hop,r.segments);
    std::printf("PSD: integral=%.9f target=%.9f time_variance=%.9f max_bin=%.6fdB max_band=%.6fdB flatness=%.9f\n",
                r.power,target_variance,r.variance,r.max_bin_db,r.max_band_db,r.flatness);
    if(!r.passes())throw std::runtime_error("RTL AWGN failed PSD acceptance bounds");
    // A deterministic tone validates FFT placement and density normalization.
    std::vector<double> tone(length*8);
    for(size_t i=0;i<tone.size();i++)tone[i]=.5*std::sin(2*pi*i/8);
    const auto tone_psd=analyze(tone);
    const auto peak=std::max_element(tone_psd.density.begin(),tone_psd.density.end())-tone_psd.density.begin();
    if(peak!=length/8 || std::abs(tone_psd.power-.125)>1e-10)
        throw std::runtime_error("PSD estimator tone calibration failed");
    // Same-power colored-noise negative control: a power-only test would pass.
    std::vector<double> colored(samples.size());
    double power=0;
    for(size_t i=0;i<samples.size();i++) {
        colored[i]=samples[i]+(i?.8*samples[i-1]:0); power+=colored[i]*colored[i];
    }
    const double gain=std::sqrt(target_variance*samples.size()/power);
    for(double& x:colored)x*=gain;
    const auto colored_psd=analyze(colored);
    if(colored_psd.passes() || colored_psd.max_band_db<=.35)
        throw std::runtime_error("PSD checker failed to reject colored noise");
    std::printf("PASS PSD: white-noise bounds; calibrated Fs/8 tone; equal-power colored noise rejected (band %.3fdB).\n",
                colored_psd.max_band_db);
}
} // namespace channel_psd
