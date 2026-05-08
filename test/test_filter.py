# Expect: Success
# Output: 2 4 6 a b

def is_even(x):
    return x % 2 == 0

for v in filter(is_even, [1, 2, 3, 4, 5, 6]):
    print(v)

# filter(None, ...) keeps truthy items
for v in filter(None, ["a", "", "b", ""]):
    print(v)
