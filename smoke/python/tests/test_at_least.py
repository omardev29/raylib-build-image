# The example test never compares two equal numbers, so it cannot tell `>=`
# from `>`. Only the Hypothesis property can, by finding a == b. So mutmut
# reports its one mutant KILLED only if pytest, Hypothesis and mutmut all
# work; with any of them missing it is "survived", or no result at all.
from hypothesis import given, strategies as st

from at_least import at_least


def test_examples():
    assert at_least(3, 2)
    assert not at_least(1, 2)


@given(st.integers(), st.integers())
def test_one_of_two_is_at_least_the_other(a, b):
    assert at_least(a, b) or at_least(b, a)
