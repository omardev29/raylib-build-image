// Source-based coverage, end to end: compiled with -fprofile-instr-generate
// -fcoverage-mapping, run, merged with llvm-profdata and reported with
// llvm-cov. Each step fails on its own if a piece is missing: the link needs
// compiler-rt's profile runtime, the merge needs the .profraw the run wrote,
// and the report needs a profile that matches the binary.
static int bigger_than_two(int x) {
    if (x > 2) {
        return 1;
    }
    return 0;
}

int main(void) { return bigger_than_two(1); }
