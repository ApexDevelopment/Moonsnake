# Expect: Success
# Output: 10

def outer():
    x = 10
    def inner():
        return x
    return inner

f = outer()
print(f())
