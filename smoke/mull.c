// Mull: compiled through its clang pass plugin, then mutated and run by
// mull-runner. The test below never compares two equal numbers, so exactly
// one of the four mutants of `>=` survives -- `>` -- and the expected report
// is "Mutation score: 75%" naming that survivor. A plugin that did not load
// leaves no mutants and no score; a runner that did not run kills nothing.
// mull-runner exits 1 when a mutant survives, so the smoke check runs it with
// --allow-surviving and reads the score instead.
#include <stdio.h>

static int at_least(int a, int b) { return a >= b; }

int main(void) {
    int ok = at_least(3, 2) == 1 && at_least(1, 2) == 0;
    puts(ok ? "pass" : "fail");
    return ok ? 0 : 1;
}
