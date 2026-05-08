# Expect: Success
# Output: c b a 4 3 2 1 0 o l l e h

for v in reversed(["a", "b", "c"]):
    print(v)

for v in reversed(range(5)):
    print(v)

for v in reversed("hello"):
    print(v)
