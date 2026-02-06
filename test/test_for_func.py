# Expect: Success
# Output: 55

def sum_range(start, stop):
    total = 0
    for i in range(start, stop):
        total += i
    return total

print(sum_range(1, 11))
