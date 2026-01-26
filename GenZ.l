%{
#include <stdio.h>
%}

%%

"collab_with"       { printf("#include"); }
"main_character"    { printf("main"); }
"rizz"              { printf("int"); }
"spill_tea"         { printf("printf"); }
"gimme"             { printf("scanf"); }
"vibe_check"        { printf("if"); }
"lowkey"            { printf("else if"); }
"canceled"          { printf("else"); }
"peace_out"         { printf("return 0"); }
"sus"               { printf("!"); }
"same_energy"       { printf("=="); }

.                   { printf("%s", yytext); }
\n                  { printf("\n"); }

%%

int main() {
    yylex();
    return 0;
}

int yywrap() {
    return 1;
}
