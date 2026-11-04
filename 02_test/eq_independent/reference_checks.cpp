#include "reference_model.hpp"
#include <iostream>

static void check(bool condition, const char *message) {
    if (!condition) throw std::runtime_error(message);
}
int main() {
    try {
        using namespace reference;
        check(floor_shift(-1,12) == -1, "negative product arithmetic shift");
        check(round_shift(128,8) == 1 && round_shift(-128,8) == -1,
              "MATLAB halfway rounding");
        check(visible(127) == 0 && visible(-127) == 0, "sub-half-LSB conversion");
        check(sat(32768,16) == 32767 && sat(-32769,16) == -32768, "signed saturation");
        check(delta(32,4096,4096) == 512, "Q16 mu -> Q20 increment");
        Row r{0,4096,0,0,1,32,4096,2048,-1024,2048};
        Ffe impulse(r);
        check(impulse.step(r).y == 4096, "FFE impulse tap 0");
        r.input = 0;
        check(impulse.step(r).y == 2048, "FFE impulse tap 1");
        check(impulse.step(r).y == -1024, "FFE impulse tap 2");
        check(impulse.step(r).y == 0, "FFE impulse flush");
        // Per-product saturation: clip(+8), clip(-8), then sum = -1 LSB.
        r.w0 = 8192; r.w1 = -8192; r.w2 = 0; r.input = 16384;
        Ffe clipping(r); clipping.step(r);
        check(clipping.step(r).y == -1, "FFE saturates each product before sum");
        r = Row{0,4096,4096,1,1,32,0,0,0,2048};
        Ffe positive(r); Dfe negative(r);
        check(positive.step(r).weights[0] == 2, "FFE positive LMS update");
        const Result d = negative.step(r);
        check(d.y == 2048 && d.weights[0] == 2046, "DFE pre-update output and subtract update");
        r.input = 256; r.error = 4096;
        Ffe accumulate(r);
        for (int i = 0; i < 8; ++i) accumulate.step(r);
        check(accumulate.step(r).weights[0] == 1, "Q20 retains sub-LSB increments");
        std::cout << "PASS C++ reference arithmetic contracts\n";
    } catch (const std::exception &e) { std::cerr << "FAIL " << e.what() << '\n'; return 1; }
}
