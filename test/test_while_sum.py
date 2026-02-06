# Expect: Success
# Output: 5050

def sum_to(n):
    total = 0
    i = 1
    while i <= n:
        total += i
        i += 1
    return total

print(sum_to(100))
