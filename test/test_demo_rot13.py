# Expect: Success
# Output: Uryyb, Jbeyq! Hello, World!

def rot13(text):
    upper = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
    lower = "abcdefghijklmnopqrstuvwxyz"
    result = ""
    for ch in text:
        if ch in upper:
            i = upper.find(ch)
            result = result + upper[(i + 13) % 26]
        elif ch in lower:
            i = lower.find(ch)
            result = result + lower[(i + 13) % 26]
        else:
            result = result + ch
    return result

print(rot13("Hello, World!"))
print(rot13("Uryyb, Jbeyq!"))
