# Expect: Success
# Output: [1, 2, 3, 4] 4 [1, 2, 3] 1 ['a', 'b', 'c']

lst = [1, 2, 3]
lst.append(4)
print(lst)
print(lst.pop())
print(lst)
print(lst.count(2))
strs = ["a", "b", "c"]
print(strs)
