# Expect: Success
# Output: 1 0 99 {'a': 1, 'b': 2, 'c': 3} 1

d = {"a": 1, "b": 2}
print(d.get("a"))
print(d.get("z", 0))
d.setdefault("c", 99)
print(d["c"])
d["c"] = 3
print(d)
removed = d.pop("a")
print(removed)
