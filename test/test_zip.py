# Expect: Success
# Output: 1-a 2-b 3-c short:1-x

for x, y in zip([1, 2, 3], ["a", "b", "c"]):
    print(f"{x}-{y}")

# zip stops at shortest
for x, y in zip([1, 2, 3], ["x"]):
    print(f"short:{x}-{y}")
