# Expect: Success
# Output: 1 2 3 4 5 apple banana cherry

for v in sorted([3, 1, 4, 5, 2]):
    print(v)

for v in sorted(["cherry", "apple", "banana"]):
    print(v)
