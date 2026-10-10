// cppcheck has to REFUSE this: a write one past the end of a fixed array.
// --error-exitcode=1 must turn the arrayIndexOutOfBounds it reports into
// exit status 1. A cppcheck that cannot parse the file, or that is not really
// analysing, exits 0 here, which is why the clean file alone proves nothing.
int main() {
    int counts[4] = {};
    for (int i = 0; i <= 4; ++i) {
        counts[i] = i;
    }
    return counts[0];
}
