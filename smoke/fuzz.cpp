// libFuzzer with ASan and UBSan, the way the framework's fuzz targets are
// built: -fsanitize=fuzzer,address,undefined. Run for a fixed number of
// inputs, which only finishes if the fuzzer's own runtime works.
#include <cstddef>
#include <cstdint>

extern "C" int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size) {
    unsigned sum = 0;
    for (size_t i = 0; i < size; ++i) {
        sum += data[i];
    }
    return sum == 0xFFFFFFFFu ? 1 : 0;
}
