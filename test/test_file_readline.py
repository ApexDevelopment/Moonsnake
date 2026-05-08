# Expect: Success
# Output: hello world

with open("test/fixtures/hello.txt", "r") as f:
    line1 = f.readline()
    line2 = f.readline()
print(line1.strip() + " " + line2.strip())
