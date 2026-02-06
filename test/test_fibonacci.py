# Expect: Success
# Output: 1 2 3 5 8 13

def fib(n):
    a = 0
    b = 1
    for i in range(n):
        a, b = b, a + b
    return a

print(fib(1))
print(fib(3))
print(fib(4))
print(fib(5))
print(fib(6))
print(fib(7))
