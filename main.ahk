#Requires AutoHotkey v2.0
#SingleInstance Force
#Include "JSON.ahk"

; ─── Entry ───

if A_Args.Length == 0 {
    ShowSettingsGui()
} else {
    Main(A_Args[1])
}
ExitApp 0

; ─── Main ───

Main(paramPath) {
    config := LoadConfig()
    param := ReadParamFile(paramPath)
    if param is String {
        ExitApp 1
    }

    paths := param["data"]["target_paths"]
    if !(paths is Array && paths.Length > 0) {
        ShowHintNotification()
        ExitApp 1
    }

    processed := ProcessPaths(paths, config)
    sorted := SortFileItems(processed, config["sort_method"], config["sort_order"])

    sep := GetLineSeparator(config["line_separator"])
    text := ""
    for item in sorted {
        text .= item["display"] . sep
    }
    text := SubStr(text, 1, -StrLen(sep))

    A_Clipboard := text
    if !ClipWait(0.5) {
        A_Clipboard := text
    }

    SendNotification(sorted.Length)
    OutputResult(sorted)
}

; ─── ProcessPaths ───

ProcessPaths(paths, config) {
    result := []
    for p in paths {
        trimmed := Trim(p)
        if !FileExist(trimmed) {
            continue
        }

        display := trimmed

        ; separator normalization
        display := NormalizeSeparator(display, config["path_separator"])

        ; path scope: full path or filename only
        if config["path_scope"] == "filename_only" {
            SplitPath display, &name, , &ext, &nameNoExt
            display := config["include_extension"] ? name : nameNoExt
        } else {
            ; full path: optionally strip extension
            if !config["include_extension"] {
                SplitPath display, , , &ext, &nameNoExt
                display := SubStr(display, 1, StrLen(display) - StrLen(ext) - 1)
            }
        }

        ; quoting
        if config["smart_quotes"] {
            if InStr(display, " ") {
                display := "'" . display . "'"
            }
        } else {
            switch config["quote_style"] {
                case "single":
                    display := "'" . display . "'"
                case "double":
                    display := '"' . display . '"'
            }
        }

        result.Push(Map("original", p, "display", display))
    }
    return result
}

; ─── NormalizeSeparator ───

NormalizeSeparator(path, style) {
    switch style {
        case "backslash":
            return StrReplace(path, "/", "\")
        case "forward":
            newPath := StrReplace(path, "\", "/")
            ; preserve drive colon (C:/ not C:)
            return RegExReplace(newPath, "^([a-zA-Z]):/", "$1:/")
        case "double_backslash":
            tmp := StrReplace(path, "/", "\")
            return StrReplace(tmp, "\", "\\")
    }
    return path
}

; ─── GetLineSeparator ───

GetLineSeparator(style) {
    switch style {
        case "lf":       return "`n"
        case "space":    return " "
        case "comma":    return ","
        case "semicolon": return ";"
        default:         return "`r`n"
    }
}

; ─── LoadConfig / WriteConfig ───

LoadConfig() {
    config := Map(
        "quote_style", "none",
        "path_separator", "backslash",
        "path_scope", "full",
        "include_extension", true,
        "line_separator", "crlf",
        "sort_method", "name",
        "sort_order", "asc",
        "smart_quotes", false
    )
    cfgFile := A_ScriptDir "\config.json"
    if FileExist(cfgFile) {
        try {
            parsed := JSON.Parse(FileRead(cfgFile))
            if parsed is Map {
                for key in ["quote_style", "path_separator", "path_scope",
                            "include_extension", "line_separator",
                            "sort_method", "sort_order",
                            "smart_quotes"] {
                    if parsed.Has(key) {
                        config[key] := parsed[key]
                    }
                }
            }
        }
    }
    return config
}

WriteConfig(cfg) {
    try {
        FileOpen(A_ScriptDir "\config.json", "w").Write(JSON.Stringify(cfg, "  "))
    }
}

; ─── ReadParamFile ───

ReadParamFile(path) {
    if !FileExist(path) {
        errorOut := JSON.Stringify(Map("error", "参数文件不存在", "detail", path))
        FileOpen("*", "w").Write(errorOut)
        return ""
    }
    rawText := FileRead(path, "UTF-8")
    if !rawText {
        errorOut := JSON.Stringify(Map("error", "参数文件为空", "detail", path))
        FileOpen("*", "w").Write(errorOut)
        return ""
    }
    targetPaths := FastExtractPaths(rawText)
    if targetPaths.Length > 0 {
        return Map("data", Map("target_paths", targetPaths))
    }
    try {
        return JSON.Parse(rawText)
    } catch as err {
        errorOut := JSON.Stringify(Map("error", "JSON 解析失败", "detail", err.Message))
        FileOpen("*", "w").Write(errorOut)
        return ""
    }
}

; ─── FastExtractPaths ───

FastExtractPaths(rawText) {
    result := []
    marker := '"target_paths":['
    startPos := InStr(rawText, marker)
    if !startPos {
        return result
    }
    pos := startPos + StrLen(marker)
    len := StrLen(rawText)
    buf := ""
    while pos <= len {
        ch := SubStr(rawText, pos, 1)
        if ch == '"' {
            strEnd := pos + 1
            strVal := ""
            loop {
                if strEnd > len {
                    break 2
                }
                c := SubStr(rawText, strEnd, 1)
                if c == "\" {
                    strEnd++
                    esc := SubStr(rawText, strEnd, 1)
                    switch esc {
                        case '"', "\", '/': strVal .= esc
                        case 'n': strVal .= "`n"
                        case 'r': strVal .= "`r"
                        case 't': strVal .= "`t"
                        case 'u':
                            hex := SubStr(rawText, strEnd + 1, 4)
                            codepoint := Integer("0x" . hex)
                            if codepoint >= 0xD800 && codepoint <= 0xDBFF {
                                strEnd += 4
                                if SubStr(rawText, strEnd, 2) == '\u' {
                                    hex2 := SubStr(rawText, strEnd + 2, 4)
                                    low := Integer("0x" . hex2)
                                    codepoint := 0x10000 + ((codepoint - 0xD800) << 10) + (low - 0xDC00)
                                    strEnd += 6
                                }
                            }
                            strVal .= Chr(codepoint)
                            strEnd--
                        default:
                            strVal .= esc
                    }
                    strEnd++
                } else if c == '"' {
                    strEnd++
                    break
                } else {
                    strVal .= c
                    strEnd++
                }
            }
            result.Push(strVal)
            pos := strEnd
        } else if ch == ']' {
            break
        } else if ch == ',' {
            pos++
        } else {
            pos++
        }
    }
    return result
}

; ─── SortFileItems ───

SortFileItems(items, method, order) {
    count := items.Length
    if count <= 1 {
        return items
    }
    sortList := ""
    for idx, item in items {
        key := GetSortKey(item["display"], method)
        sortList .= key . Chr(0x1F) . idx . "`n"
    }
    flags := order == "desc" ? "R" : ""
    sortList := Trim(sortList, "`n")
    Sort sortList, flags

    result := []
    for line in StrSplit(sortList, "`n") {
        parts := StrSplit(line, Chr(0x1F))
        origIdx := Integer(parts[2])
        result.Push(items[origIdx])
    }
    return result
}

GetSortKey(item, method) {
    switch method {
        case "name":
            return "n" . StrLower(item)
        case "extension":
            SplitPath item, , , &ext
            return "e" . StrLower(ext) . "n" . StrLower(item)
        case "date":
            if FileExist(item) {
                modTime := FileGetTime(item, "M")
                return "d" . modTime . "n" . StrLower(item)
            }
            return "d00000000000000n" . StrLower(item)
        case "size":
            if FileExist(item) {
                size := FileGetSize(item)
                return "s" . Format("{:020}", size) . "n" . StrLower(item)
            }
            return "s00000000000000000000n" . StrLower(item)
    }
    return "n" . StrLower(item)
}

; ─── Notification ───

SendNotification(count) {
    msg := "已复制 " . count . " 个文件路径到剪贴板"
    try {
        body := JSON.Stringify(Map("notify_type", "success", "message", msg))
        req := ComObject("WinHttp.WinHttpRequest.5.1")
        req.Open("POST", "http://127.0.0.1:9527/api/notify", false)
        req.SetRequestHeader("Content-Type", "application/json")
        req.Send(body)
    } catch {
        TrayTip "复制文件路径", msg
    }
}

ShowHintNotification() {
    TrayTip "复制文件路径", "未获取到有效的文件路径"
}

; ─── OutputResult ───

OutputResult(items) {
    result := Map(
        "summary", Map("total", items.Length, "success", items.Length, "failed", 0),
        "details", []
    )
    details := []
    for item in items {
        details.Push(item["display"])
    }
    result["details"] := details
    FileOpen("*", "w").Write(JSON.Stringify(result))
}

; ─── GUI Settings ───

ShowSettingsGui() {
    cfg := LoadConfig()
    myGui := Gui("+AlwaysOnTop +ToolWindow +Owner", "复制文件路径 - 设置")
    myGui.SetFont("s9", "Microsoft YaHei UI")

    y := 10
    gap := 28

    ; 引号样式
    myGui.Add("Text", "x12 y" . y . " w90 h23", "引号样式")
    myGui.Add("DropDownList", "x110 y" . (y - 3) . " w150 vddQuote", ["无引号", "单引号", "双引号"])
    myGui["ddQuote"].Value := QuoteStyleToIdx(cfg["quote_style"])
    y += gap

    ; 路径分隔符
    myGui.Add("Text", "x12 y" . y . " w90 h23", "路径分隔符")
    myGui.Add("DropDownList", "x110 y" . (y - 3) . " w150 vddSep", ["反斜杠 \", "正斜杠 /", "双反斜杠 \\"])
    myGui["ddSep"].Value := SepStyleToIdx(cfg["path_separator"])
    y += gap

    ; 路径范围
    myGui.Add("Text", "x12 y" . y . " w90 h23", "路径范围")
    myGui.Add("DropDownList", "x110 y" . (y - 3) . " w150 vddScope", ["完整路径", "仅文件名"])
    myGui["ddScope"].Value := ScopeToIdx(cfg["path_scope"])
    y += gap

    ; 包含扩展名
    myGui.Add("CheckBox", "x110 y" . (y - 1) . " w150 vcbExt", "包含扩展名")
    myGui["cbExt"].Value := cfg["include_extension"]
    y += gap

    ; 换行符
    myGui.Add("Text", "x12 y" . y . " w90 h23", "换行符")
    myGui.Add("DropDownList", "x110 y" . (y - 3) . " w150 vddLine", ["换行（Windows）", "换行（Unix）", "空格", "逗号", "分号"])
    myGui["ddLine"].Value := LineSepToIdx(cfg["line_separator"])
    y += gap

    ; 排序方式
    myGui.Add("Text", "x12 y" . y . " w90 h23", "排序方式")
    myGui.Add("DropDownList", "x110 y" . (y - 3) . " w150 vddSortMethod", ["名称", "修改日期", "大小", "扩展名"])
    myGui["ddSortMethod"].Value := MethodToIdx(cfg["sort_method"])
    y += gap

    ; 排序顺序
    myGui.Add("Text", "x12 y" . y . " w90 h23", "排序顺序")
    myGui.Add("DropDownList", "x110 y" . (y - 3) . " w150 vddSortOrder", ["升序", "降序"])
    myGui["ddSortOrder"].Value := OrderToIdx(cfg["sort_order"])
    y += gap

    ; 智能引号
    myGui.Add("CheckBox", "x110 y" . (y - 1) . " w150 vcbSmart", "智能引号（路径含空格时自动加引号）")
    myGui["cbSmart"].Value := cfg["smart_quotes"]
    y += gap

    ; 提示文字
    myGui.Add("Text", "x12 y" . y . " w250 c888888", "保存配置后，后续用右键直接复制文件路径即可")
    y += gap + 5

    ; 按钮
    btnSave := myGui.Add("Button", "x74 y" . y . " w70 h25", "保存")
    btnCancel := myGui.Add("Button", "x156 y" . y . " w70 h25", "取消")

    btnSave.OnEvent("Click", (*) => OnSave(myGui))
    btnCancel.OnEvent("Click", (*) => ExitApp(0))
    myGui.OnEvent("Close", (*) => ExitApp(0))
    myGui.OnEvent("Escape", (*) => ExitApp(0))

    myGui.Show("w280 h" . (y + 40))
    WinWaitClose(myGui)
}

OnSave(myGui) {
    cfg := Map(
        "quote_style", IdxToQuoteStyle(myGui["ddQuote"].Value),
        "path_separator", IdxToSepStyle(myGui["ddSep"].Value),
        "path_scope", IdxToScope(myGui["ddScope"].Value),
        "include_extension", !!myGui["cbExt"].Value,
        "line_separator", IdxToLineSep(myGui["ddLine"].Value),
        "sort_method", IdxToMethod(myGui["ddSortMethod"].Value),
        "sort_order", IdxToOrder(myGui["ddSortOrder"].Value),
        "smart_quotes", !!myGui["cbSmart"].Value
    )
    WriteConfig(cfg)
    TrayTip "复制文件路径", "配置已保存"
    Sleep 1500
    ExitApp 0
}

; ─── Index helpers ───

QuoteStyleToIdx(val) {
    switch val {
        case "none":   return 1
        case "single": return 2
        case "double": return 3
        default:       return 1
    }
}
IdxToQuoteStyle(idx) {
    switch idx {
        case 1: return "none"
        case 2: return "single"
        case 3: return "double"
        default: return "none"
    }
}

SepStyleToIdx(val) {
    switch val {
        case "backslash":        return 1
        case "forward":          return 2
        case "double_backslash": return 3
        default:                 return 1
    }
}
IdxToSepStyle(idx) {
    switch idx {
        case 1: return "backslash"
        case 2: return "forward"
        case 3: return "double_backslash"
        default: return "backslash"
    }
}

ScopeToIdx(val) {
    switch val {
        case "full":          return 1
        case "filename_only": return 2
        default:              return 1
    }
}
IdxToScope(idx) {
    switch idx {
        case 1: return "full"
        case 2: return "filename_only"
        default: return "full"
    }
}

LineSepToIdx(val) {
    switch val {
        case "crlf":      return 1
        case "lf":        return 2
        case "space":     return 3
        case "comma":     return 4
        case "semicolon": return 5
        default:          return 1
    }
}
IdxToLineSep(idx) {
    switch idx {
        case 1: return "crlf"
        case 2: return "lf"
        case 3: return "space"
        case 4: return "comma"
        case 5: return "semicolon"
        default: return "crlf"
    }
}

MethodToIdx(val) {
    switch val {
        case "name":      return 1
        case "date":      return 2
        case "size":      return 3
        case "extension": return 4
        default:          return 1
    }
}
IdxToMethod(idx) {
    switch idx {
        case 1: return "name"
        case 2: return "date"
        case 3: return "size"
        case 4: return "extension"
        default: return "name"
    }
}

OrderToIdx(val) {
    switch val {
        case "asc":  return 1
        case "desc": return 2
        default:     return 1
    }
}
IdxToOrder(idx) {
    switch idx {
        case 1: return "asc"
        case 2: return "desc"
        default: return "asc"
    }
}
