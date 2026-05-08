# Expect: Success
# Output: 1 1 2 2 3

def counter():
    n = 0
    def inc():
        nonlocal n
        n = n + 1
        return n
    return inc

c1 = counter()
c2 = counter()
print(c1())
print(c2())
print(c1())
print(c2())
print(c1())
