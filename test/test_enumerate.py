# Expect: Success
# Output: 0:a 1:b 2:c 10:x 11:y

for i, v in enumerate(["a", "b", "c"]):
    print(f"{i}:{v}")

for i, v in enumerate(["x", "y"], 10):
    print(f"{i}:{v}")
