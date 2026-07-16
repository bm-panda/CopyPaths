class JSON {
    static Parse(text) {
        text := Trim(text)
        if !text {
            return ""
        }
        p := _JSONParser(text)
        val := p.ParseValue()
        p.SkipWS()
        if p.pos <= p.len {
            throw Error("JSON.Parse: unexpected trailing content at position " . p.pos)
        }
        return val
    }

    static Stringify(value, indent := "") {
        return _JSONStringify(value, indent, 0)
    }
}

; ─── Parser ───

class _JSONParser {
    __New(text) {
        this.text := text
        this.pos := 1
        this.len := StrLen(text)
    }

    SkipWS() {
        while this.pos <= this.len && SubStr(this.text, this.pos, 1) ~= "[ \t\r\n]" {
            this.pos++
        }
    }

    Peek() {
        if this.pos > this.len {
            return ""
        }
        return SubStr(this.text, this.pos, 1)
    }

    Next() {
        ch := SubStr(this.text, this.pos, 1)
        this.pos++
        return ch
    }

    Expect(ch) {
        this.SkipWS()
        got := this.Next()
        if got != ch {
            throw Error("JSON.Parse: expected '" . ch . "' at position " . (this.pos - 1) . ", got '" . got . "'")
        }
    }

    ParseValue() {
        this.SkipWS()
        if this.pos > this.len {
            throw Error("JSON.Parse: unexpected end of input")
        }
        ch := this.Peek()
        switch ch {
            case "{": return this.ParseObject()
            case "[": return this.ParseArray()
            case '"': return this.ParseString()
            case "t": return this.ParseLiteral("true", true)
            case "f": return this.ParseLiteral("false", false)
            case "n": return this.ParseLiteral("null", "")
            default:
                if ch ~= "[-0-9.]" {
                    return this.ParseNumber()
                }
                throw Error("JSON.Parse: unexpected character '" . ch . "' at position " . this.pos)
        }
    }

    ParseString() {
        this.Expect('"')
        result := ""
        while this.pos <= this.len {
            ch := this.Next()
            if ch == '"' {
                return result
            }
            if ch == "\" {
                if this.pos > this.len {
                    throw Error("JSON.Parse: unterminated string escape")
                }
                esc := this.Next()
                switch esc {
                    case '"':  result .= '"'
                    case "\": result .= "\"
                    case "/":  result .= "/"
                    case "b":  result .= "`b"
                    case "f":  result .= "`f"
                    case "n":  result .= "`n"
                    case "r":  result .= "`r"
                    case "t":  result .= "`t"
                    case "u":
                        hex := SubStr(this.text, this.pos, 4)
                        if StrLen(hex) < 4 {
                            throw Error("JSON.Parse: incomplete unicode escape")
                        }
                        this.pos += 4
                        codePoint := Integer("0x" . hex)
                        ; Handle surrogate pairs
                        if codePoint >= 0xD800 && codePoint <= 0xDBFF {
                            ; High surrogate — expect \uXXXX low surrogate
                            if SubStr(this.text, this.pos, 2) == "\u" {
                                hex2 := SubStr(this.text, this.pos + 2, 4)
                                if StrLen(hex2) == 4 {
                                    low := Integer("0x" . hex2)
                                    if low >= 0xDC00 && low <= 0xDFFF {
                                        this.pos += 6
                                        codePoint := 0x10000 + ((codePoint - 0xD800) << 10) + (low - 0xDC00)
                                    }
                                }
                            }
                        }
                        result .= Chr(codePoint)
                    default:
                        throw Error("JSON.Parse: invalid escape character '\" . esc . "'")
                }
            } else {
                result .= ch
            }
        }
        throw Error("JSON.Parse: unterminated string")
    }

    ParseNumber() {
        this.SkipWS()
        start := this.pos
        if this.Peek() == "-" {
            this.Next()
        }
        if this.Peek() == "0" {
            this.Next()
        } else if this.Peek() ~= "[1-9]" {
            this.Next()
            while this.Peek() ~= "[0-9]" {
                this.Next()
            }
        }
        if this.Peek() == "." {
            this.Next()
            if !(this.Peek() ~= "[0-9]") {
                throw Error("JSON.Parse: expected digit after decimal point")
            }
            while this.Peek() ~= "[0-9]" {
                this.Next()
            }
        }
        if this.Peek() ~= "[eE]" {
            this.Next()
            if this.Peek() ~= "[+-]" {
                this.Next()
            }
            if !(this.Peek() ~= "[0-9]") {
                throw Error("JSON.Parse: expected digit in exponent")
            }
            while this.Peek() ~= "[0-9]" {
                this.Next()
            }
        }
        numStr := SubStr(this.text, start, this.pos - start)
        if InStr(numStr, ".") || InStr(numStr, "e") || InStr(numStr, "E") {
            return Float(numStr)
        }
        return Integer(numStr)
    }

    ParseObject() {
        this.Expect("{")
        obj := Map()
        this.SkipWS()
        if this.Peek() == "}" {
            this.Next()
            return obj
        }
        loop {
            this.SkipWS()
            key := this.ParseString()
            this.Expect(":")
            val := this.ParseValue()
            obj[key] := val
            this.SkipWS()
            ch := this.Peek()
            if ch == "}" {
                this.Next()
                return obj
            }
            if ch == "," {
                this.Next()
                continue
            }
            throw Error("JSON.Parse: expected ',' or '}' in object at position " . this.pos)
        }
    }

    ParseArray() {
        this.Expect("[")
        arr := []
        this.SkipWS()
        if this.Peek() == "]" {
            this.Next()
            return arr
        }
        loop {
            arr.Push(this.ParseValue())
            this.SkipWS()
            ch := this.Peek()
            if ch == "]" {
                this.Next()
                return arr
            }
            if ch == "," {
                this.Next()
                continue
            }
            throw Error("JSON.Parse: expected ',' or ']' in array at position " . this.pos)
        }
    }

    ParseLiteral(expected, value) {
        len := StrLen(expected)
        literal := SubStr(this.text, this.pos, len)
        if literal != expected {
            throw Error("JSON.Parse: expected '" . expected . "' at position " . this.pos)
        }
        this.pos += len
        return value
    }
}

; ─── Stringifier ───

_JSONStringify(value, indent, depth) {
    if IsObject(value) {
        if Type(value) == "Array" {
            return _JSONStringifyArray(value, indent, depth)
        }
        if Type(value) == "Map" {
            return _JSONStringifyMap(value, indent, depth)
        }
        return _JSONStringifyMap(value, indent, depth)
    }
    t := Type(value)
    if t == "String" {
        return '"' . _JSONEscape(value) . '"'
    }
    if t == "Integer" || t == "Float" {
        return value
    }
    if value == true {
        return "true"
    }
    if value == false {
        return "false"
    }
    return "null"
}

_JSONStringifyArray(arr, indent, depth) {
    if arr.Length == 0 {
        return "[]"
    }
    if indent == "" {
        s := "["
        for i, v in arr {
            if i > 1 {
                s .= ","
            }
            s .= _JSONStringify(v, "", depth + 1)
        }
        return s . "]"
    }
    pad := ""
    Loop depth + 1 {
        pad .= indent
    }
    closingPad := ""
    Loop depth {
        closingPad .= indent
    }
    s := ""
    for i, v in arr {
        if i > 1 {
            s .= ",`n"
        }
        s .= pad . _JSONStringify(v, indent, depth + 1)
    }
    return "[" . "`n" . s . "`n" . closingPad . "]"
}

_JSONStringifyMap(map, indent, depth) {
    count := 0
    for k, v in map {
        count++
        if count > 1 {
            break
        }
    }
    if count == 0 {
        return "{}"
    }
    if indent == "" {
        s := "{"
        first := true
        for k, v in map {
            if !first {
                s .= ","
            }
            first := false
            s .= '"' . _JSONEscape(k) . '":' . _JSONStringify(v, "", depth + 1)
        }
        return s . "}"
    }
    pad := ""
    Loop depth + 1 {
        pad .= indent
    }
    closingPad := ""
    Loop depth {
        closingPad .= indent
    }
    s := ""
    first := true
    for k, v in map {
        if !first {
            s .= ",`n"
        }
        first := false
        s .= pad . '"' . _JSONEscape(k) . '": ' . _JSONStringify(v, indent, depth + 1)
    }
    return "{" . "`n" . s . "`n" . closingPad . "}"
}

_JSONEscape(s) {
    result := ""
    Loop Parse s {
        c := A_LoopField
        switch c {
            case '"':  result .= '\"'
            case "\": result .= '\\'
            case "`b": result .= '\b'
            case "`f": result .= '\f'
            case "`n": result .= '\n'
            case "`r": result .= '\r'
            case "`t": result .= '\t'
            default:
                code := Ord(c)
                if code < 0x20 {
                    result .= Format("\u{:04X}", code)
                } else {
                    result .= c
                }
        }
    }
    return result
}
