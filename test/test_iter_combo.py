# Expect: Success
# Output: 0:a-x 1:b-y 2:c-z 1 9 25

# enumerate over a zip
for i, pair in enumerate(zip(["a", "b", "c"], ["x", "y", "z"])):
    a, b = pair
    print(f"{i}:{a}-{b}")

# map over a filter
def is_odd(x):
    return x % 2 == 1

def square(x):
    return x * x

for v in map(square, filter(is_odd, [1, 2, 3, 4, 5])):
    print(v)
