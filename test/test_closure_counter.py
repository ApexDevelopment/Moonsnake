# Expect: Success
# Output: 1 2 3

def counter():
    n = 0
    def inc():
        nonlocal n
        n = n + 1
        return n
    return inc

c = counter()
print(c())
print(c())
print(c())
