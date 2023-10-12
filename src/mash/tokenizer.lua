mash.token = {
    type = "",
    lexeme = "",
    pos = { line = 0, column = 0 },
}

mash.tokens = {
    "T_IDENT",

    -- math
    "T_PLUS",    -- +
    "T_MINUS",   -- -
    "T_PERCENT", -- %
    "T_SLASH",   -- /
    "T_STAR",    -- *

    -- assignation
    "T_EQ",        -- =
    "T_PLUSEQ",    -- +=
    "T_MINUSEQ",   -- -=
    "T_PERCENTEQ", -- %=
    "T_SLASHEQ",   -- /=
    "T_STAREQ",    -- *=
    "T_AMPEQ",     -- &=
    "T_CARETEQ",   -- ^=
    "T_PIPEEQ",    -- |=
    "T_TILDEEQ",   -- ~=

    -- bitwise operators
    "T_AMP",   -- &
    "T_CARET", -- ^
    "T_PIPE",  -- |
    "T_TILDE", -- ~

    -- logical operators
    "T_AMPAMP",   -- &&
    "T_PIPEPIPE", -- ||
    "T_BANG",     -- !

    -- punctuation
    "T_DOT",        -- .
    "T_COMMA",      -- ,
    "T_SEMICOLON",  -- ;
    "T_COLON",      -- :
    "T_LBRACKET",   -- [
    "T_RBRACKET",   -- ]
    "T_LBRACE",     -- {
    "T_RBRACE",     -- }
    "T_LPAREN",     -- (
    "T_RPAREN",     -- )
    "T_SLASHSLASH", -- //
    "T_HASH",       -- #
    "T_DOLLAR",     -- $

    -- keywords
    "KW_FOR",      -- for
    "KW_WHILE",    -- while
    "KW_DO",       -- do
    "KW_BREAK",    -- break
    "KW_CONTINUE", -- continue
    "KW_LOOP",     -- loop
    "KW_IF",       -- if
    "KW_ELSE",     -- else
    "KW_LET",      -- let
    "KW_CONST",    -- const
    "KW_RETURN",   -- return
    "KW_DEF",      -- func
}
