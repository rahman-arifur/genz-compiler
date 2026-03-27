%{
	#include <stdio.h>
	#include "GenZ.tab.h"
	#include <stdlib.h>
	#include <string.h>

	extern int yylineno;

    // Function to handle errors
	void yyerror(char *s);
%}

%option yylineno

%%
"collab_with"[ ]+<[^>]+>  { /* Ignore headers */ }
"tbh"[^\n]*               { /* Ignore single-line comment */ }
"//"[^\n]*                { /* Ignore standard single-line comment */ }
"story_time"(.|\n)*"end_story" { /* Ignore GenZ multi-line comment */ }
"/*"([^*]|\*+[^*/])*\*+"/" { /* Ignore standard multi-line comment */ }

"rizz"                    { return TYPE_INT; }
"bet"                     { return TYPE_BOOL; }
"ish"                     { return TYPE_FLOAT; }
"bigish"                  { return TYPE_DOUBLE; }
"yap"                     { return TYPE_STRING; }

"main_character"          { return MAIN; }
"spill_tea"               { return PRINT; }
"gimme"                   { return SCAN; }

"vibe_check"              { return IF; }
"lowkey"                  { return ELSEIF; }
"canceled"                { return ELSE; }
"doomscroll"              { return WHILE; }
"iter8"                   { return FOR; }
"yeet"                    { return BREAK; }
"skrrrt"                  { return CONTINUE; }
"peace_out"               { return RETURN; }

"sus"                     { return NOT; }
"same_energy"             { return EQ; }
"diff_energy"             { return NEQ; }
"flash_forward"           { return INC; }
"flash_back"              { return DEC; }
"cap"                     { yylval.num = 0; return NUMBER; }
"no_cap"                  { yylval.num = 1; return NUMBER; }

[a-zA-Z_][a-zA-Z0-9_]*    { yylval.str = strdup(yytext); return ID; }
[0-9]+\.[0-9]+([eE][+-]?[0-9]+)? { yylval.fnum = atof(yytext); return FNUMBER; }
[0-9]+                    { yylval.num = atoi(yytext); return NUMBER; }
\"[^"]*\"                 { 
    yylval.str = strdup(yytext+1); 
    if (yylval.str[strlen(yylval.str)-1] == '"')
        yylval.str[strlen(yylval.str)-1] = 0;
    return STRING; 
}

"{"                       { return LBRACE; }
"}"                       { return RBRACE; }
"("                       { return LPAREN; }
")"                       { return RPAREN; }
";"                       { return SEMICOLON; }
"="                       { return ASSIGN; }
"+"                       { return PLUS; }
"-"                       { return MINUS; }
"*"                       { return MULT; }
"%"                       { return MOD; }
"/"                       { return DIV; }
">"                       { return GT; }
"<"                       { return LT; }
">="                      { return GE; }
"<="                      { return LE; }
"++"                      { return INC; }
"--"                      { return DEC; }
"=="                      { return EQ; }
"!="                      { return NEQ; }
"&&"                      { return AND; }
"||"                      { return OR; }
"!"                       { return NOT; }
","                       { return COMMA; }

[ \t\n]+                  { /* Skip whitespace */ }
.                         {
	fprintf(stderr, "Lexical error at line %d: invalid token '%s'\n", yylineno, yytext);
}

%%

int yywrap() { return 1; }
