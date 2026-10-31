/* The image's C toolchains, each made to do its job: tcc builds and runs it on
   Linux, MinGW-w64 builds it for Windows, and Wine (amd64) runs that .exe. */
#include <stdio.h>

static int square(int x) { return x * x; }

int main(void) {
    printf("hello %d\n", square(7));
    return 0;
}
