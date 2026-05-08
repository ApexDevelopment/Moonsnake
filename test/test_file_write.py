# Expect: Success
# Output: done hello world

f = open("test/fixtures/temp_write.txt", "w")
f.write("hello world\n")
f.close()

f = open("test/fixtures/temp_write.txt", "r")
data = f.read()
f.close()
print("done", data.strip())
