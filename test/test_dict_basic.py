# Expect: Success
# Output: 1 2 3 3 True False

d = {"a": 1, "b": 2}
print(d["a"])
print(d["b"])
d["c"] = 3
print(d["c"])
print(len(d))
print("a" in d)
print("z" in d)
