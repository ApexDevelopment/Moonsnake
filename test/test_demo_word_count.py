# Expect: Success
# Output: brown:1 dog:1 fox:2 jumps:1 lazy:1 over:1 quick:1 the:3

words = "the quick brown fox jumps over the lazy dog the fox".split()
counts = {}
for w in words:
    if w in counts:
        counts[w] = counts[w] + 1
    else:
        counts[w] = 1

keys = []
for k in counts:
    keys.append(k)
keys.sort()
for k in keys:
    print(f"{k}:{counts[k]}")
