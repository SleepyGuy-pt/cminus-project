-- The C- language.
-- The compiler's/languages keywords.

local KEYWORDS = {
    ["set"] = "SET", ["if"] = "IF", ["else"] = "ELSE", ["void"] = "VOID", ["while"] = "WHILE", ["for"] = "FOR", ["list"] = "LIST", ["do"] = "DO", ["then"] = "THEN", ["end"] = "END", ["false"] = "FALSE", ["true"] = "TRUE", ["null"] = "NULL", ["log"] = "LOG"
}

-- The Token Class
local Token = {}
Token.__index = Token
function Token:new(type, value)
    return setmetatable({ type = type, value = value }, Token)
end

--  The Scanner Class
local Scanner = {}
Scanner.__index = Scanner
function Scanner:new(source)
    return setmetatable({ source = source, pos = 1 }, Scanner)
end

function Scanner:next_token()
    
    while self.pos <= #self.source and self.source:sub(self.pos, self.pos):match("%s") do
        self.pos = self.pos + 1
    end

    if self.pos > #self.source then return Token:new("EOF", nil) end

    local cur = self.source:sub(self.pos)

    local hex = cur:match("^(0x%x+)")
    if hex then
        self.pos = self.pos + #hex
        return Token:new("HEX", hex)
    end
    
    local num = cur:match("^(%d+)")
    if num then
        self.pos = self.pos + #num
        return Token:new("NUMBER", num)
    end

    -- 3. WORDS & KEYWORDS
    local word = cur:match("^([%a%_][%w%_]*)")
    if word then
        self.pos = self.pos + #word
        local type = KEYWORDS[word] or "VARIABLE"
        return Token:new(type, word)
    end

    -- 4. SYMBOLS
    local symbol = cur:match("^([%(%)%[%]%=%;])")
    if symbol then
        self.pos = self.pos + 1
        return Token:new("SYMBOL", symbol)
    end

    error("Unknown character: " .. cur:sub(1,1))
end

-- The Parser Class.
local Parser = {}
Parser.__index = Parser
function Parser:new(scanner)
    return setmetatable({ scanner = scanner, currentToken = nil }, Parser)
end
-- Helper to move to the next token and verify its type
function Parser:consume(expectedType)
    if self.currentToken and self.currentToken.type == expectedType then
        self.currentToken = self.scanner:next_token()
    else
        local actual = "EOF"
        if self.currentToken then actual = self.currentToken.type end
        error("Syntax Error: Expected " .. expectedType .. " but got " .. actual)
    end
end

-- The logic for 'set x 10;' or 'set vga 0xB8000;'
function Parser:parse_set()
    self:consume("SET") -- Skip the word 'set'
    
    local name = self.currentToken.value
    self:consume("VARIABLE") 
    
    local valToken = self.currentToken
    local line = ""

    if valToken.type == "HEX" then
        -- Pointer Logic.
        line = "    int* " .. name .. " = (int*)" .. valToken.value .. ";"
    else
        -- Standard number logic
        line = "    int " .. name .. " = " .. valToken.value .. ";"
    end

    self.currentToken = self.scanner:next_token() -- Move past the value
    self:consume("SYMBOL") -- Skip the ';'
    
    return line
end
-- The logic for 'while condition then'
function Parser:parse_while()
    self:consume("WHILE")
    
    local condition = self.currentToken.value
    -- This handles 'while true' or 'while x'
    if self.currentToken.type == "VARIABLE" or self.currentToken.type == "TRUE" then
        self.currentToken = self.scanner:next_token()
    else
        error("Expected condition after while")
    end
    
    self:consume("THEN") 
    self:consume("SYMBOL")
    -- Translates C- to C: 'while (condition) {'
    return "    while (" .. condition .. ") {\n"
end
-- Line 121: The logic for 'end'
function Parser:parse_end()
    self:consume("END")
    self:consume("SYMBOL")
    return "    }\n"
end
-- Line 121 (new): The logic for 'if condition then'
function Parser:parse_if()
    self:consume("IF")
    local condition = self.currentToken.value
    self:consume("VARIABLE")
    self:consume("THEN")
    self:consume("SYMBOL")
    return "    if (" .. condition .. ") {\n"
end

-- Line 128 (new): The logic for 'else'
function Parser:parse_else()
    self:consume("ELSE")
    return "    } else {\n"
end
-- The logic for 'log(x);'
function Parser:parse_log()
    self:consume("LOG")    -- Skip 'log'
    self:consume("SYMBOL") -- Skip '('
    
    local name = self.currentToken.value
    self:consume("VARIABLE")     -- Get the variable name to print
    
    self:consume("SYMBOL") -- Skip ')'
    self:consume("SYMBOL") -- Skip ';'
    
    -- This turns it into a C print command
    return '    printf("%d\\n", ' .. name .. ');'
end
-- The logic for 'list my_array = [10];'
function Parser:parse_list()
    self:consume("LIST")
    
    local name = self.currentToken.value
    self:consume("VARIABLE")
    
    self:consume("SYMBOL") -- skip =
    self:consume("SYMBOL") -- skip [
    
    local size = self.currentToken.value
    self:consume("NUMBER")
    
    self:consume("SYMBOL") -- skip ]
    self:consume("SYMBOL") -- skip ;
    
    -- Turns C- into a C array: int my_array[10];
    return "    int " .. name .. "[" .. size .. "];\n"
end
-- Line 156 (new): The logic for 'func my_task() then' or 'void main() then'
function Parser:parse_func()
    local typeToken = self.currentToken.type -- This is "FUNC" or "VOID"
    self.currentToken = self.scanner:next_token() -- Skip the keyword
    
    local name = self.currentToken.value
    self:consume("VOID")
    self:consume("VARIABLE")
    self:consume("FUNC") -- Get the function name
    self:consume("SYMBOL") -- Skip (
    self:consume("SYMBOL")
    self:consume("SYMBOL")-- Skip )
    
    -- Check for 'then' or 'do' to open the function
    if self.currentToken.type == "THEN" or self.currentToken.type == "DO" then
        self.currentToken = self.scanner:next_token()
    end
    
    -- Translates to C: void name() {
    return "\nvoid " .. name .. "() {\n"
end

function Parser:translate()
    self.currentToken = self.scanner:next_token()
    -- Output for C
    local output = "#include <stdio.h>\n\nint main() {\n"

    while self.currentToken and self.currentToken.type ~= "EOF" do
        local t = self.currentToken.type

        if t == "SET" then
            output = output .. self:parse_set()
        elseif t == "LOG" then
            output = output .. self:parse_log()
        elseif t == "IF" then
            output = output .. self:parse_if()
        elseif t == "ELSE" then
            output = output .. self:parse_else()
        elseif t == "WHILE" then
            output = output .. self:parse_while()
        elseif t == "FOR" then
            output = output .. self:parse_for()
        elseif t == "FUNC" or t == "VOID" then
            output = output .. self:parse_func()
        elseif t == "LIST" then
            output = output .. self:parse_list()
        elseif t == "END" then
            output = output .. self:parse_end()
        elseif t == "DO" or t == "THEN" then
            output = output .. " {\n"
            self.currentToken = self.scanner:next_token()
        elseif t == "NULL" or t == "TRUE" or t == "FALSE" then
            -- These are values, usually handled inside other functions
            self.currentToken = self.scanner:next_token()
        else
            -- If we don't recognize it, skip to avoid infinite loops
            self.currentToken = self.scanner:next_token()
        end
    end

    return output .. "\n    return 0;\n}"
end
local function save_to_file(filename, content)
    local file = io.open(filename, "w")
    if file then
        file:write(content)
        file:close()
        print("Success! File saved as: " .. filename)
    else
        print("Error: Could not save file.")
    end
end
-- Get the filename from the command line
local filename = arg[1]

if not filename then
    print("Usage: lua base.lua <yourfile.cm>")
    return
end

local f = io.open(filename, "r")
if f then
    local input_code = f:read("*all")
    f:close()

    local s = Scanner:new(input_code)
    local p = Parser:new(s)
    
    local status, translatedCode = pcall(function() return p:translate() end)

    if status then
        -- This creates an output file with the same name, but .c extension
        local out_name = filename:gsub("%.cm$", "") .. ".c"
        save_to_file(out_name, translatedCode)
        print("Successfully compiled " .. filename .. " to " .. out_name)
    else
        print("SYNTAX ERROR in " .. filename .. ": " .. tostring(translatedCode))
    end
else
    print("Error: Could not find file '" .. filename .. "'")
end
