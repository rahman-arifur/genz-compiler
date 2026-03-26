%{
	#include <stdio.h>
	#include <stdlib.h>
	#include <string.h>

	extern FILE *yyin;
	extern int yylineno;

	void yyerror(char *s);
	int yylex();

	// ---------------------------------------------------------
	// SYMBOL TABLE (To store variables like 'x', 'y')
	// ---------------------------------------------------------
	enum VarType { V_INT=1, V_BOOL, V_FLOAT, V_STRING };

	struct Symbol {
		char *name;
		int declared;
		int type;
		int int_value;
		char *str_value;
	} sym_table[100];

	int sym_count = 0;

	int semantic_errors = 0;

	int find_symbol(const char *name) {
		for (int i = 0; i < sym_count; i++) {
			if (strcmp(sym_table[i].name, name) == 0) return i;
		}
		return -1;
	}

	int ensure_symbol(const char *name) {
		int idx = find_symbol(name);
		if (idx >= 0) return idx;
		sym_table[sym_count].name = strdup(name);
		sym_table[sym_count].declared = 0;
		sym_table[sym_count].type = V_INT;
		sym_table[sym_count].int_value = 0;
		sym_table[sym_count].str_value = NULL;
		return sym_count++;
	}

	void declare_symbol(const char *name, int type) {
		int idx = ensure_symbol(name);
		sym_table[idx].declared = 1;
		sym_table[idx].type = type;
		if (type != V_STRING && sym_table[idx].str_value) {
			free(sym_table[idx].str_value);
			sym_table[idx].str_value = NULL;
		}
	}

	void semantic_error(const char *msg, const char *name) {
		fprintf(stderr, "Semantic error at line %d: %s (%s)\n", yylineno, msg, name ? name : "-");
		semantic_errors++;
	}

	void assign_numeric(const char *name, int value) {
		int idx = ensure_symbol(name);
		if (!sym_table[idx].declared) {
			// Keep backward compatibility for undeclared IDs in old tests.
			declare_symbol(name, V_INT);
		}
		if (sym_table[idx].type == V_STRING) {
			semantic_error("cannot assign numeric value to string variable", name);
			return;
		}
		if (sym_table[idx].type == V_BOOL) {
			sym_table[idx].int_value = value ? 1 : 0; // implicit numeric->bool conversion
			return;
		}
		sym_table[idx].int_value = value;
	}

	void assign_string(const char *name, const char *value) {
		int idx = ensure_symbol(name);
		if (!sym_table[idx].declared) {
			declare_symbol(name, V_STRING);
		}
		if (sym_table[idx].type != V_STRING) {
			semantic_error("cannot assign string value to numeric variable", name);
			return;
		}
		if (sym_table[idx].str_value) free(sym_table[idx].str_value);
		sym_table[idx].str_value = strdup(value ? value : "");
	}

	int get_numeric(const char *name) {
		int idx = ensure_symbol(name);
		if (sym_table[idx].type == V_STRING) {
			semantic_error("cannot use string variable in numeric expression", name);
			return 0;
		}
		return sym_table[idx].int_value;
	}

	const char* get_string(const char *name) {
		int idx = ensure_symbol(name);
		if (sym_table[idx].type != V_STRING) {
			semantic_error("cannot use numeric variable as string", name);
			return "";
		}
		return sym_table[idx].str_value ? sym_table[idx].str_value : "";
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
	enum { NODE_CONST=1, NODE_VAR, NODE_ADD, NODE_SUB, NODE_MUL, NODE_DIV, NODE_MOD,
	       NODE_ASSIGN, NODE_ASSIGN_STR, NODE_IF, NODE_WHILE, NODE_FOR, NODE_PRINT, NODE_PRINT_VAR, NODE_SCAN,
	       NODE_LT, NODE_GT, NODE_LE, NODE_GE, NODE_EQ, NODE_NEQ, NODE_AND, NODE_OR, NODE_NOT, NODE_SEQ,
	       NODE_BREAK, NODE_CONTINUE, NODE_STRCONST };

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

	Node* optimize_ast(Node *n) {
		if (!n) return NULL;
		n->left = optimize_ast(n->left);
		n->right = optimize_ast(n->right);
		n->next = optimize_ast(n->next);

		// Constant folding for pure numeric expressions.
		if (n->left && n->right && n->left->type == NODE_CONST && n->right->type == NODE_CONST) {
			int a = n->left->int_val;
			int b = n->right->int_val;
			int out;
			switch (n->type) {
				case NODE_ADD: out = a + b; break;
				case NODE_SUB: out = a - b; break;
				case NODE_MUL: out = a * b; break;
				case NODE_DIV: if (b == 0) return n; out = a / b; break;
				case NODE_MOD: if (b == 0) return n; out = a % b; break;
				case NODE_LT: out = a < b; break;
				case NODE_GT: out = a > b; break;
				case NODE_LE: out = a <= b; break;
				case NODE_GE: out = a >= b; break;
				case NODE_EQ: out = a == b; break;
				case NODE_NEQ: out = a != b; break;
				case NODE_AND: out = a && b; break;
				case NODE_OR: out = a || b; break;
				default: return n;
			}
			return make_leaf(NODE_CONST, out, NULL);
		}

		if (n->type == NODE_NOT && n->left && n->left->type == NODE_CONST) {
			return make_leaf(NODE_CONST, !n->left->int_val, NULL);
		}

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
			case NODE_VAR:    return get_numeric(n->str_val);
			
            case NODE_BREAK: cf_state = 1; return 0;
            case NODE_CONTINUE: cf_state = 2; return 0;

			// Math
			case NODE_ADD:    return execute(n->left) + execute(n->right);
			case NODE_SUB:    return execute(n->left) - execute(n->right);
			case NODE_MUL:    return execute(n->left) * execute(n->right);
			case NODE_DIV:    return execute(n->left) / execute(n->right);
			case NODE_MOD:    return execute(n->left) % execute(n->right);
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
				assign_numeric(n->str_val, execute(n->right));
				return 0;

			case NODE_ASSIGN_STR:
				assign_string(n->str_val, n->right ? n->right->str_val : "");
				return 0;
			
			case NODE_PRINT:
				if (n->str_val) printf("%s", n->str_val);
				else printf("%d\n", execute(n->left));
				return 0;

			case NODE_PRINT_VAR: {
				int idx = find_symbol(n->str_val);
				if (idx >= 0 && sym_table[idx].type == V_STRING) {
					printf("%s", get_string(n->str_val));
				} else {
					printf("%d\n", get_numeric(n->str_val));
				}
				return 0;
			}

			case NODE_SCAN: { // gimme(x)
				int val;
				printf("Input: "); 
				scanf("%d", &val);
				assign_numeric(n->str_val, val);
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
%token ASSIGN PLUS MINUS MULT DIV MOD GT LT LE GE EQ NEQ AND OR NOT COMMA

%type <node> statement block expr program

/* Precedence */
%left COMMA
%right ASSIGN
%left OR
%left AND
%left EQ NEQ
%left LT GT LE GE
%left PLUS MINUS
%left MULT DIV MOD
%right NOT

%%

/* Grammar Rules */

program:
	  /* catch all main syntax but only execute the block */
	  MAIN LPAREN RPAREN block { 
		Node *optimized = optimize_ast($4);
		printf("\n--- Starting Execution ---\n");
		execute(optimized);
		if (semantic_errors > 0) {
			printf("\n[Semantic checks] %d issue(s) detected.\n", semantic_errors);
		}
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
	| TYPE_INT ID SEMICOLON { declare_symbol($2, V_INT); $$ = NULL; }
	| TYPE_FLOAT ID SEMICOLON { declare_symbol($2, V_FLOAT); $$ = NULL; }
	| TYPE_BOOL ID SEMICOLON { declare_symbol($2, V_BOOL); $$ = NULL; }
	| TYPE_STRING ID SEMICOLON { declare_symbol($2, V_STRING); $$ = NULL; }
	
	| TYPE_INT ID ASSIGN expr SEMICOLON { 
		declare_symbol($2, V_INT);
		$$ = make_node(NODE_ASSIGN, NULL, $4); 
		$$->str_val = $2; 
	}
	| TYPE_FLOAT ID ASSIGN expr SEMICOLON { 
		declare_symbol($2, V_FLOAT);
		$$ = make_node(NODE_ASSIGN, NULL, $4); 
		$$->str_val = $2; 
	}
	| TYPE_BOOL ID ASSIGN expr SEMICOLON { 
		declare_symbol($2, V_BOOL);
		$$ = make_node(NODE_ASSIGN, NULL, $4); 
		$$->str_val = $2; 
	}
	| TYPE_STRING ID ASSIGN STRING SEMICOLON {
		declare_symbol($2, V_STRING);
		$$ = make_node(NODE_ASSIGN_STR, NULL, make_leaf(NODE_STRCONST, 0, $4));
		$$->str_val = $2; 
	}
	
	| ID ASSIGN expr SEMICOLON {
		$$ = make_node(NODE_ASSIGN, NULL, $3); 
		$$->str_val = $1;
	}
	| ID ASSIGN STRING SEMICOLON {
		$$ = make_node(NODE_ASSIGN_STR, NULL, make_leaf(NODE_STRCONST, 0, $3));
		$$->str_val = $1;
	}

	/* IO: spill_tea */
	| PRINT LPAREN STRING RPAREN SEMICOLON {
		$$ = make_leaf(NODE_PRINT, 0, $3); 
	}
	| PRINT LPAREN expr RPAREN SEMICOLON {
		$$ = make_node(NODE_PRINT, $3, NULL);
	}
	| PRINT LPAREN ID RPAREN SEMICOLON {
		$$ = make_leaf(NODE_PRINT_VAR, 0, $3);
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
	| expr MOD expr { $$ = make_node(NODE_MOD, $1, $3); }
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
