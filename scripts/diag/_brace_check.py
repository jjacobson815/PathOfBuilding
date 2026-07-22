src = open("app/qml/main.qml", encoding="utf-8").read()
depth = 0
in_str = False
in_line = False
in_block = False
i = 0
line_no = 1
stack = []
n = len(src)
while i < n:
    ch = src[i]
    if ch == '\n':
        line_no += 1
        in_line = False
    elif in_line:
        pass
    elif in_block:
        if ch == '*' and i + 1 < n and src[i+1] == '/':
            in_block = False
            i += 1
    elif in_str:
        if ch == '\\':
            i += 1
        elif ch == '"':
            in_str = False
    else:
        if ch == '/':
            if i + 1 < n and src[i+1] == '/':
                in_line = True
            elif i + 1 < n and src[i+1] == '*':
                in_block = True
        elif ch == '"':
            in_str = True
        elif ch == '{':
            depth += 1
            stack.append(line_no)
        elif ch == '}':
            depth -= 1
            if depth < 0:
                print(f"NEGATIVE depth near line {line_no}")
                depth = 0
            else:
                stack.pop()
    i += 1
print("final depth:", depth)
if depth > 0:
    print("unclosed { at lines (oldest first):", stack)
