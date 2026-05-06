# Expect: Success
# Output: hello-world a|b|c stripped

words = "hello world".split()
print("-".join(words))
print("|".join(["a", "b", "c"]))
print("  stripped  ".strip())
