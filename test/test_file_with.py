# Expect: Success
# Output: hello world

with open("test/fixtures/hello.txt", "r") as f:
    data = f.read()
print(data.strip())
