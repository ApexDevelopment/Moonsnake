# Expect: Success
# Output: positive zero negative

def classify(n):
    if n > 0:
        return "positive"
    if n == 0:
        return "zero"
    return "negative"

print(classify(5))
print(classify(0))
print(classify(-3))
