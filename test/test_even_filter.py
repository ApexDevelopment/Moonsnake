# Expect: Success
# Output: 0 0 2 0 4 0 6 0 8

for i in range(9):
    if i % 2 == 0:
        print(i)
    else:
        print(0)
