# Expect: Success
# Output: hello world

f = open("test/fixtures/hello.txt", "r")
data = f.read()
f.close()
print(data.strip())
