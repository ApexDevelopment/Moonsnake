# Expect: Success
# Output: a b c a:1 b:2 c:3

d = {"a": 1, "b": 2, "c": 3}
for k in d:
    print(k)
for k in d:
    print(f"{k}:{d[k]}")
