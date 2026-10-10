// cppcheck has to ACCEPT this, and with the C++20 the framework is written in:
// designated initialisers, a requires clause and a requires expression. A
// syntaxError or internalAstError on any of them fails --error-exitcode=1.
#include <type_traits>

struct Options {
    int width = 0;
    int height = 0;
};

template <typename T>
    requires std::is_arithmetic_v<T>
T twice(T value) {
    return value + value;
}

template <typename T>
int area(const T &shape) {
    if constexpr (requires(const T &s) { s.width * s.height; }) {
        return shape.width * shape.height;
    }
    return 0;
}

int main() {
    const Options options{.width = 4, .height = 3};
    return area(options) == twice(6) ? 0 : 1;
}
