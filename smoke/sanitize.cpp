// ASan + UBSan (+ LSan, which ASan enables on x86_64 Linux).
//
// With no argument it is a correct program and has to exit 0. With one, it
// makes the mistake named and has to be STOPPED: a sanitizer that links but
// does not fire would pass the clean run just as well, so the clean run alone
// proves nothing.
#include <climits>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <vector>

void *kept;

int main(int argc, char **argv) {
    if (argc < 2) {
        std::vector<int> v(4, 1);
        int sum = 0;
        for (int x : v) {
            sum += x;
        }
        std::printf("sum=%d\n", sum);
        return sum == 4 ? 0 : 1;
    }
    if (std::strcmp(argv[1], "heap") == 0) {
        int *p = static_cast<int *>(std::malloc(4 * sizeof(int)));
        int r = p[argc + 2];  // one past the end
        std::free(p);
        return r;
    }
    if (std::strcmp(argv[1], "int") == 0) {
        int x = INT_MAX;
        x += argc - 1;  // INT_MAX + 1
        return x == 0;
    }
    if (std::strcmp(argv[1], "leak") == 0) {
        kept = std::malloc(7);
        kept = nullptr;
        return 0;
    }
    return 2;
}
