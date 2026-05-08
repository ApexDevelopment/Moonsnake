# Expect: Success
# Output: before hello after

def trace(func):
    def wrapper():
        print("before")
        func()
        print("after")
    return wrapper

@trace
def greet():
    print("hello")

greet()
