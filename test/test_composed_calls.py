# Expect: Success
# Output: 8

def double(x):
    return x * 2

def add_one(x):
    return x + 1

print(double(add_one(3)))
