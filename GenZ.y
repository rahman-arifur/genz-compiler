%{
	#include <stdio.h>
	#include <stdlib.h>
	#include <string.h>

	extern FILE *yyin;

	void yyerror(char *s);
	int yylex();

	// ---------------------------------------------------------
	// SYMBOL TABLE (To store variables like 'x', 'y')
	// ---------------------------------------------------------
	struct Symbol {
		char *name;
		int value;
	} sym_table[100];

	int sym_count = 0;

	// Helper: Find or Create a variable
	int* get_var_ptr(char *name) {
		for(int i=0; i<sym_count; i++) {
			if(strcmp(sym_table[i].name, name) == 0) return &sym_table[i].value;
		}
		// Create new
		sym_table[sym_count].name = strdup(name);
		sym_table[sym_count].value = 0;
		return &sym_table[sym_count++].value;
	}

	// ---------------------------------------------------------
	// AST NODE (Abstract Syntax Tree)
	// This structure represents every command in our language.
	// ---------------------------------------------------------
	typedef struct Node {
		int type;           // Operation type (0=SEQ, 1=ASSIGN, 2=IF, 3=PRINT, etc)
		int int_val;        // For numbers (10, 20)
		char *str_val;      // For variable names ("x") or strings ("Hello")
		struct Node *left;  // Left child
		struct Node *right; // Right child
		struct Node *next;  // Next statement (for sequences)
	} Node;

	// Node Types
	enum { NODE_CONST=1, NODE_VAR, NODE_ADD, NODE_SUB, NODE_MUL, NODE_DIV, 
	       NODE_ASSIGN, NODE_IF, NODE_WHILE, NODE_FOR, NODE_PRINT, NODE_SCAN, 
           NODE_LT, NODE_GT, NODE_LE, NODE_GE, NODE_EQ, NODE_NEQ, NODE_AND, NODE_OR, NODE_NOT, NODE_SEQ,
           NODE_BREAK, NODE_CONTINUE };

    // Global Control Flow State (0=Normal, 1=Break, 2=Continue)
    int cf_state = 0;

	// Helper: Create a new Node
	Node* make_node(int type, Node *l, Node *r) {
		Node *n = (Node*)malloc(sizeof(Node));
		n->type = type; n->left = l; n->right = r; n->next = NULL;
		return n;
	}

	Node* make_leaf(int type, int val, char *str) {
		Node *n = (Node*)malloc(sizeof(Node));
		n->type = type; n->int_val = val; n->str_val = str; n->left = NULL; n->right = NULL; n->next = NULL;
		return n;
	}

	// ---------------------------------------------------------
	// EXECUTION ENGINE (Interpreter)
	// Recursively runs the AST derived from the code.
	// ---------------------------------------------------------
	int execute(Node *n) {
		if (!n) return 0;
        if (cf_state != 0) return 0; // Skip if flow altered (break/continue)

		// Execute Left and Right first for operations
		int v_left = 0, v_right = 0;

		switch(n->type) {
			case NODE_CONST:  return n->int_val;
			case NODE_VAR:    return *get_var_ptr(n->str_val);
			
            case NODE_BREAK: cf_state = 1; return 0;
            case NODE_CONTINUE: cf_state = 2; return 0;

			// Math
			case NODE_ADD:    return execute(n->left) + execute(n->right);
			case NODE_SUB:    return execute(n->left) - execute(n->right);
			case NODE_MUL:    return execute(n->left) * execute(n->right);
			case NODE_DIV:    return execute(n->left) / execute(n->right);
			case NODE_LT:     return execute(n->left) < execute(n->right);
			case NODE_GT:     return execute(n->left) > execute(n->right);
			case NODE_LE:     return execute(n->left) <= execute(n->right);
			case NODE_GE:     return execute(n->left) >= execute(n->right);
			case NODE_EQ:     return execute(n->left) == execute(n->right);
			case NODE_NEQ:    return execute(n->left) != execute(n->right);
			case NODE_AND:    return execute(n->left) && execute(n->right);
			case NODE_OR:     return execute(n->left) || execute(n->right);
			case NODE_NOT:    return !execute(n->left);

			// Logic
			case NODE_ASSIGN: 
				*get_var_ptr(n->str_val) = execute(n->right);
				return 0;
			
			case NODE_PRINT:
				if (n->str_val) printf("%s", n->str_val);
				else printf("%d\n", execute(n->left));
				return 0;

			case NODE_SCAN: { // gimme(x)
				int val;
				printf("Input: "); 
				scanf("%d", &val);
				*get_var_ptr(n->str_val) = val;
				return 0;
			}

			case NODE_IF:
				if (execute(n->left)) { // Condition
					execute(n->right);  // Then-Block
				} else if (n->next) {   // Else-Block (stored in next)
					execute(n->next);
				}
				return 0;

			case NODE_WHILE: // doomscroll
				while (execute(n->left)) {
                    if (cf_state != 0) { cf_state = 0; } // Clear previous
					execute(n->right);
                    if (cf_state == 1) { // Break
                        cf_state = 0;
                        break;
                    }
                    if (cf_state == 2) { // Continue
                        cf_state = 0;
                        continue;
                    }
				}
				return 0;

			case NODE_FOR: 
				// For loop is tricky in simple ASTs. We can structure it as:
				// [INIT] -> [WHILE COND] -> { [BODY] -> [INCREMENT] }
				// But our simple node structure doesn't support 4 children easily.
				// We'll skip complex 'for' implementation to keep it simple as requested.
				// We can just execute init, check condition once, run body.
				// (Proper for loop needs more complex structs)
				printf("Warning: iter8 (for) loop partial support in simple mode.\n");
				return 0;
			
			case NODE_SEQ:
				if (cf_state != 0) return 0; // Skip if flow altered
				execute(n->left);
				
				if (cf_state != 0) return 0; // Skip next if break/cont hit
				execute(n->right); // Recursively run next statement
				return 0;
		}
		return 0;
	}

%}

/* Bison Declarations */
%union {
	int num;
	char *str;
	struct Node *node;
}

%token <num> NUMBER
%token <str> ID STRING
%token TYPE_INT TYPE_BOOL TYPE_FLOAT TYPE_STRING 
%token MAIN PRINT SCAN IF ELSEIF ELSE RETURN WHILE FOR 
%token BREAK CONTINUE INC DEC
%token LBRACE RBRACE LPAREN RPAREN SEMICOLON
%token ASSIGN PLUS MINUS MULT DIV GT LT LE GE EQ NEQ AND OR NOT COMMA

%type <node> statement block expr program

/* Precedence */
%left COMMA
%right ASSIGN
%left OR
%left AND
%left EQ NEQ
%left LT GT LE GE
%left PLUS MINUS
%left MULT DIV
%right NOT

%%

/* Grammar Rules */

program:
	  /* catch all main syntax but only execute the block */
	  MAIN LPAREN RPAREN block { 
		printf("\n--- Starting Execution ---\n");
		execute($4); 
		printf("\n--- Execution Finished ---\n");
	  }
	;

block:
	  LBRACE statement RBRACE { $$ = $2; }
	;

statement:
	  statement statement { $$ = make_node(NODE_SEQ, $1, $2); }
	| expr SEMICOLON { $$ = $1; }  /* Just an expression */
	
	/* Assignments: rizz x = 10; or x = 10; */
	| TYPE_INT ID SEMICOLON { $$ = make_leaf(NODE_VAR, 0, $2); /* Declaration only */ }
	| TYPE_FLOAT ID SEMICOLON { $$ = make_leaf(NODE_VAR, 0, $2); }
	| TYPE_BOOL ID SEMICOLON { $$ = make_leaf(NODE_VAR, 0, $2); }
	| TYPE_STRING ID SEMICOLON { $$ = make_leaf(NODE_VAR, 0, $2); }
	
	| TYPE_INT ID ASSIGN expr SEMICOLON { 
		Node *var = make_leaf(NODE_VAR, 0, $2); 
		$$ = make_node(NODE_ASSIGN, NULL, $4); 
		$$->str_val = $2; 
	}
	| TYPE_FLOAT ID ASSIGN expr SEMICOLON { 
		// Treat float as int for now
		$$ = make_node(NODE_ASSIGN, NULL, $4); 
		$$->str_val = $2; 
	}
	| TYPE_BOOL ID ASSIGN expr SEMICOLON { 
		$$ = make_node(NODE_ASSIGN, NULL, $4); 
		$$->str_val = $2; 
	}
	| TYPE_STRING ID ASSIGN expr SEMICOLON { 
		$$ = make_node(NODE_ASSIGN, NULL, $4); 
		$$->str_val = $2; 
	}
	
	| ID ASSIGN expr SEMICOLON {
		$$ = make_node(NODE_ASSIGN, NULL, $3); 
		$$->str_val = $1;
	}

	/* IO: spill_tea */
	| PRINT LPAREN STRING RPAREN SEMICOLON {
		$$ = make_leaf(NODE_PRINT, 0, $3); 
	}
	| PRINT LPAREN expr RPAREN SEMICOLON {
		$$ = make_node(NODE_PRINT, $3, NULL);
	}
	
	/* IO: gimme("%d", &val); -> For simplicity: gimme(val); */
	| SCAN LPAREN ID RPAREN SEMICOLON {
		$$ = make_leaf(NODE_SCAN, 0, $3); 
	}
    
    /* Control Flow: yeet (break) / skrrrt (continue) */
    | BREAK SEMICOLON { 
        $$ = make_node(NODE_BREAK, NULL, NULL); 
    }
    | CONTINUE SEMICOLON { 
        $$ = make_node(NODE_CONTINUE, NULL, NULL); 
    }
    
    /* Operators as Statements: x++; */
    | ID INC SEMICOLON {
        Node *one = make_leaf(NODE_CONST, 1, NULL);
        Node *add = make_node(NODE_ADD, make_leaf(NODE_VAR, 0, $1), one); 
        $$ = make_node(NODE_ASSIGN, NULL, add);
        $$->str_val = $1;
    }
    | ID DEC SEMICOLON {
        Node *one = make_leaf(NODE_CONST, 1, NULL);
        Node *sub = make_node(NODE_SUB, make_leaf(NODE_VAR, 0, $1), one); 
        $$ = make_node(NODE_ASSIGN, NULL, sub);
        $$->str_val = $1;
    }

	/* Control Flow: vibe_check */
	| IF LPAREN expr RPAREN block {
		$$ = make_node(NODE_IF, $3, $5);
	}

	/* Control Flow: doomscroll (while) */
	| WHILE LPAREN expr RPAREN block {
		$$ = make_node(NODE_WHILE, $3, $5);
	}

	/* Control Flow: lowkey (else if) */
	| IF LPAREN expr RPAREN block ELSEIF LPAREN expr RPAREN block {
		Node *inner_if = make_node(NODE_IF, $8, $10);
		$$ = make_node(NODE_IF, $3, $5);
		$$->next = inner_if;
	}
	
	/* Control Flow: lowkey + canceled (if-elseif-else) */
	| IF LPAREN expr RPAREN block ELSEIF LPAREN expr RPAREN block ELSE block {
		Node *inner_if = make_node(NODE_IF, $8, $10);
		inner_if->next = $12; 
		$$ = make_node(NODE_IF, $3, $5);
		$$->next = inner_if;
	}

	/* Control Flow: canceled (else) */
	| IF LPAREN expr RPAREN block ELSE block {
		/* Store ELSE block in 'next' pointer */
		$$ = make_node(NODE_IF, $3, $5);
		$$->next = $7; 
	}

	/* Loops: iter8 (for loop) -> Treated as sequence for simplicity */
	/* iter8(i=0; i<10; i++) */
	| FOR LPAREN ID ASSIGN NUMBER SEMICOLON expr SEMICOLON ID INC RPAREN block {
		/* To implement 'for' fully, we need 4 children (Init, Cond, Inc, Body) */
		/* Reusing NODE_WHILE: Init -> While(Cond) { Body; Inc; } */
		
		/* 1. Initialization: i = 0 */
		// Ensure NUMBER is properly made into a CONST node (already happens in parser if $5 is int)
		Node *initVal = make_leaf(NODE_CONST, $5, NULL);
		Node *assign = make_node(NODE_ASSIGN, NULL, initVal);
		assign->str_val = $3; // Set loop var name

		/* 2. Increment: i++ -> i = i + 1 */
		/* Create separate variable read node */
		Node *varRead = make_leaf(NODE_VAR, 0, strdup($3)); 
		Node *one = make_leaf(NODE_CONST, 1, NULL);
		Node *incExpr = make_node(NODE_ADD, varRead, one);
		Node *incAssign = make_node(NODE_ASSIGN, NULL, incExpr);
		incAssign->str_val = strdup($3); 
		
		/* 3. Body + Increment */
		/* Check if block ($12) is valid */
		Node *bodyWithInc;
		if ($12) bodyWithInc = make_node(NODE_SEQ, $12, incAssign);
		else bodyWithInc = incAssign;

		/* 4. While Loop */
		Node *loop = make_node(NODE_WHILE, $7, bodyWithInc);

		/* 5. Sequence: Init -> Loop */
		$$ = make_node(NODE_SEQ, assign, loop);
	}
	
	| RETURN NUMBER SEMICOLON { $$ = NULL; /* Ignore return val */ }
	| RETURN SEMICOLON { $$ = NULL; /* Void return */ }
	;

expr:
	  expr PLUS expr { $$ = make_node(NODE_ADD, $1, $3); }
	| expr MINUS expr { $$ = make_node(NODE_SUB, $1, $3); }
	| expr MULT expr { $$ = make_node(NODE_MUL, $1, $3); }
	| expr DIV expr { $$ = make_node(NODE_DIV, $1, $3); }
	| expr GT expr { $$ = make_node(NODE_GT, $1, $3); }
	| expr LT expr { $$ = make_node(NODE_LT, $1, $3); }
	| expr EQ expr { $$ = make_node(NODE_EQ, $1, $3); }
	| expr NEQ expr { $$ = make_node(NODE_NEQ, $1, $3); }
	| expr LE expr { $$ = make_node(NODE_LE, $1, $3); }
	| expr GE expr { $$ = make_node(NODE_GE, $1, $3); }
	| expr AND expr { $$ = make_node(NODE_AND, $1, $3); }
	| expr OR expr { $$ = make_node(NODE_OR, $1, $3); }
	| NOT expr { $$ = make_node(NODE_NOT, $2, NULL); }
	| LPAREN expr RPAREN { $$ = $2; }
	| NUMBER { $$ = make_leaf(NODE_CONST, $1, NULL); }
	| ID { $$ = make_leaf(NODE_VAR, 0, $1); }
	;

%%

void yyerror(char *s) {
	fprintf(stderr, "Error: %s\n", s);
}

int main(int argc, char *argv[]) {
	if (argc > 1) {
		yyin = fopen(argv[1], "r");
		if (!yyin) {
			perror("Error opening file");
			return 1;
		}
	} else {
		// Fallback to stdin
		yyin = stdin;
	}
	yyparse();
	if (argc > 1) fclose(yyin);
	return 0;
}
