# Expect: Success
# Output: None is none not none

x = None
if x is None:
    print("None is none")
x = 42
if x is not None:
    print("not none")
