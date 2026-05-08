# Expect: Success
# Output: 5 50 10 100

def make_pair(base):
    def get_base():
        return base
    def get_double():
        return base * 10
    return get_base, get_double

a, b = make_pair(5)
c, d = make_pair(10)
print(a(), b(), c(), d())
