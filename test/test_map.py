# Expect: Success
# Output: 1 4 9 16 4 6 8

def square(x):
    return x * x

for v in map(square, [1, 2, 3, 4]):
    print(v)

def add(a, b):
    return a + b

for v in map(add, [1, 2, 3], [3, 4, 5]):
    print(v)
