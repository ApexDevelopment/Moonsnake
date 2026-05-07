# Expect: Success
# Output: [3, 9, 10, 27, 38, 43, 82]

def merge(left, right):
    result = []
    i = 0
    j = 0
    while i < len(left) and j < len(right):
        if left[i] <= right[j]:
            result.append(left[i])
            i = i + 1
        else:
            result.append(right[j])
            j = j + 1
    while i < len(left):
        result.append(left[i])
        i = i + 1
    while j < len(right):
        result.append(right[j])
        j = j + 1
    return result

def merge_sort(lst):
    if len(lst) <= 1:
        return lst
    mid = len(lst) // 2
    left = []
    right = []
    for i in range(mid):
        left.append(lst[i])
    for i in range(mid, len(lst)):
        right.append(lst[i])
    return merge(merge_sort(left), merge_sort(right))

print(merge_sort([38, 27, 43, 3, 9, 82, 10]))
