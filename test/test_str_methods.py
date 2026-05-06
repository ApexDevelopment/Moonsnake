# Expect: Success
# Output: HELLO hello True False 3 2 heXlo

s = "hello"
print(s.upper())
print(s.lower())
print(s.startswith("hel"))
print(s.endswith("xyz"))
print(s.find("lo"))
print(s.count("l"))
print(s.replace("l", "X", 1))
