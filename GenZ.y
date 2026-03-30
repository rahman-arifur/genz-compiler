%{
	#include <stdio.h>
	#include <stdlib.h>
	#include <string.h>

	extern FILE *yyin;
	extern int yylineno;

	void yyerror(char *s);
	int yylex();
	void semantic_error(const char *msg, const char *name);

	// ---------------------------------------------------------
	// SYMBOL TABLE
	// ---------------------------------------------------------
	enum VarType { V_INT=1, V_BOOL, V_FLOAT, V_DOUBLE, V_STRING };

	struct Symbol {
		char *name;
		int declared;
		int type;
		double num_value;
		char *str_value;
		int is_array;
		int array_size;
		double *num_array;
	} sym_table[100];

	int sym_count = 0;
	int semantic_errors = 0;
	int lexical_errors = 0;
	int runtime_line = 0;

	int find_symbol(const char *name) {
		for (int i = 0; i < sym_count; i++)
			if (strcmp(sym_table[i].name, name) == 0) return i;
		return -1;
	}

	int ensure_symbol(const char *name) {
		int idx = find_symbol(name);
		if (idx >= 0) return idx;
		if (sym_count >= 100) { semantic_error("symbol table overflow", name); return 0; }
		sym_table[sym_count].name = strdup(name);
		sym_table[sym_count].declared = 0;
		sym_table[sym_count].type = V_INT;
		sym_table[sym_count].num_value = 0.0;
		sym_table[sym_count].str_value = NULL;
		sym_table[sym_count].is_array = 0;
		sym_table[sym_count].array_size = 0;
		sym_table[sym_count].num_array = NULL;
		return sym_count++;
	}

	void declare_symbol(const char *name, int type) {
		int idx = ensure_symbol(name);
		if (sym_table[idx].num_array) {
			free(sym_table[idx].num_array);
			sym_table[idx].num_array = NULL;
		}
		sym_table[idx].is_array = 0;
		sym_table[idx].array_size = 0;
		sym_table[idx].declared = 1;
		sym_table[idx].type = type;
		if (type != V_STRING && sym_table[idx].str_value) {
			free(sym_table[idx].str_value);
			sym_table[idx].str_value = NULL;
		}
	}

	void declare_array(const char *name, int type, int size) {
		int idx = ensure_symbol(name);
		if (size <= 0) {
			semantic_error("array size must be positive", name);
			return;
		}
		if (type == V_STRING) {
			semantic_error("string arrays are not supported yet", name);
			return;
		}
		if (sym_table[idx].str_value) {
			free(sym_table[idx].str_value);
			sym_table[idx].str_value = NULL;
		}
		if (sym_table[idx].num_array) {
			free(sym_table[idx].num_array);
			sym_table[idx].num_array = NULL;
		}
		sym_table[idx].declared = 1;
		sym_table[idx].type = type;
		sym_table[idx].is_array = 1;
		sym_table[idx].array_size = size;
		sym_table[idx].num_array = (double*)calloc((size_t)size, sizeof(double));
		if (!sym_table[idx].num_array) {
			semantic_error("array allocation failed", name);
			sym_table[idx].is_array = 0;
			sym_table[idx].array_size = 0;
		}
	}

	void semantic_error_at(int line, const char *msg, const char *name) {
		int report_line = line > 0 ? line : (runtime_line > 0 ? runtime_line : yylineno);
		fprintf(stdout, "Semantic error at line %d: %s (%s)\n",
		        report_line, msg, name ? name : "-");
		semantic_errors++;
	}

	void semantic_error(const char *msg, const char *name) {
		semantic_error_at(0, msg, name);
	}

	int is_whole_number(double v) {
		long long iv = (long long)v;
		return v == (double)iv;
	}

	double coerce_numeric_for_type(int type, double value) {
		if (type == V_BOOL) return value != 0.0 ? 1.0 : 0.0;
		if (type == V_INT)  return (double)((long long)value);
		return value;
	}

	int array_index_or_error(const char *name, int idx, double index_value) {
		if (!is_whole_number(index_value)) {
			semantic_error("array index must be an integer", name);
			return -1;
		}
		long long i = (long long)index_value;
		if (i < 0 || i >= sym_table[idx].array_size) {
			semantic_error("array index out of bounds", name);
			return -1;
		}
		return (int)i;
	}

	void assign_array_numeric(const char *name, double index_value, double value) {
		int idx = find_symbol(name);
		if (idx < 0 || !sym_table[idx].declared) {
			semantic_error("array variable not declared", name);
			return;
		}
		if (!sym_table[idx].is_array) {
			semantic_error("cannot index a non-array variable", name);
			return;
		}
		if (sym_table[idx].type == V_STRING) {
			semantic_error("string arrays are not supported yet", name);
			return;
		}
		int i = array_index_or_error(name, idx, index_value);
		if (i < 0) return;
		sym_table[idx].num_array[i] = coerce_numeric_for_type(sym_table[idx].type, value);
	}

	double get_array_numeric(const char *name, double index_value) {
		int idx = find_symbol(name);
		if (idx < 0 || !sym_table[idx].declared) {
			semantic_error("array variable not declared", name);
			return 0;
		}
		if (!sym_table[idx].is_array) {
			semantic_error("cannot index a non-array variable", name);
			return 0;
		}
		if (sym_table[idx].type == V_STRING) {
			semantic_error("string arrays are not supported yet", name);
			return 0;
		}
		int i = array_index_or_error(name, idx, index_value);
		if (i < 0) return 0;
		return sym_table[idx].num_array[i];
	}

	void assign_numeric(const char *name, double value) {
		int idx = ensure_symbol(name);
		if (!sym_table[idx].declared) declare_symbol(name, V_INT);
		if (sym_table[idx].is_array) {
			semantic_error("cannot assign scalar value to array variable", name);
			return;
		}
		if (sym_table[idx].type == V_STRING) {
			semantic_error("cannot assign numeric value to string variable", name);
			return;
		}
		sym_table[idx].num_value = coerce_numeric_for_type(sym_table[idx].type, value);
	}

	void assign_string(const char *name, const char *value) {
		int idx = ensure_symbol(name);
		if (!sym_table[idx].declared) declare_symbol(name, V_STRING);
		if (sym_table[idx].is_array) {
			semantic_error("cannot assign scalar string to array variable", name);
			return;
		}
		if (sym_table[idx].type != V_STRING) {
			semantic_error("cannot assign string value to numeric variable", name);
			return;
		}
		if (sym_table[idx].str_value) free(sym_table[idx].str_value);
		sym_table[idx].str_value = strdup(value ? value : "");
	}

	double get_numeric(const char *name) {
		int idx = ensure_symbol(name);
		if (sym_table[idx].is_array) {
			semantic_error("cannot use array variable without index", name);
			return 0;
		}
		if (sym_table[idx].type == V_STRING) {
			semantic_error("cannot use string variable in numeric expression", name);
			return 0;
		}
		return sym_table[idx].num_value;
	}

	const char* get_string(const char *name) {
		int idx = ensure_symbol(name);
		if (sym_table[idx].is_array) {
			semantic_error("cannot use array variable as string", name);
			return "";
		}
		if (sym_table[idx].type != V_STRING) {
			semantic_error("cannot use numeric variable as string", name);
			return "";
		}
		return sym_table[idx].str_value ? sym_table[idx].str_value : "";
	}

	// ---------------------------------------------------------
	// AST NODE
	// ---------------------------------------------------------
	typedef struct Node {
		int type;
		int line;
		double num_val;
		char *str_val;
		struct Node *left;
		struct Node *right;
		struct Node *next;  // else-block for IF; increment for FOR; arg chain for FUNC_CALL
	} Node;

	// Node Types
	enum {
		NODE_CONST=1, NODE_VAR,
		NODE_ARRAY_GET, NODE_ARRAY_SET,
		NODE_ADD, NODE_SUB, NODE_MUL, NODE_DIV, NODE_MOD,
		NODE_ASSIGN, NODE_ASSIGN_STR,
		NODE_IF, NODE_WHILE, NODE_FOR,
		NODE_PRINT, NODE_PRINT_VAR, NODE_SCAN,
		NODE_LT, NODE_GT, NODE_LE, NODE_GE, NODE_EQ, NODE_NEQ,
		NODE_AND, NODE_OR, NODE_NOT,
		NODE_SEQ,
		NODE_BREAK, NODE_CONTINUE,
		NODE_STRCONST,
		NODE_FUNC_CALL,   // str_val=name, left=first arg (chained via ->next)
		NODE_RETURN        // left=return expression (or NULL for void)
	};

	// ---------------------------------------------------------
	// FUNCTION TABLE
	// ---------------------------------------------------------
	#define MAX_PARAMS 20
	#define MAX_FUNCS  50

	typedef struct {
		char *name;
		int   param_count;
		char *param_names[MAX_PARAMS];
		int   param_types[MAX_PARAMS];
		Node *body;
	} GenZFunc;

	GenZFunc func_table[MAX_FUNCS];
	int func_count = 0;

	// Temporaries used while parsing a parameter list
	char *tmp_param_names[MAX_PARAMS];
	int   tmp_param_types[MAX_PARAMS];
	int   tmp_param_count = 0;

	int find_function(const char *name) {
		for (int i = 0; i < func_count; i++)
			if (strcmp(func_table[i].name, name) == 0) return i;
		return -1;
	}

	// ---------------------------------------------------------
	// CONTROL FLOW STATE
	// 0=Normal  1=Break  2=Continue
	// ---------------------------------------------------------
	int cf_state = 0;

	// Return state
	double return_val = 0.0;
	int    returning  = 0;   // set by NODE_RETURN, cleared by NODE_FUNC_CALL

	// ---------------------------------------------------------
	// NODE HELPERS
	// ---------------------------------------------------------
	Node* make_node(int type, Node *l, Node *r) {
		Node *n  = (Node*)malloc(sizeof(Node));
		n->type  = type; n->line = yylineno; n->left = l; n->right = r; n->next = NULL;
		n->num_val = 0;  n->str_val = NULL;
		return n;
	}

	Node* make_leaf(int type, double val, char *str) {
		Node *n  = (Node*)malloc(sizeof(Node));
		n->type  = type; n->line = yylineno; n->num_val = val; n->str_val = str;
		n->left  = NULL; n->right = NULL; n->next = NULL;
		return n;
	}

	// ---------------------------------------------------------
	// CONSTANT FOLDING OPTIMIZER
	// ---------------------------------------------------------
	Node* optimize_ast(Node *n) {
		if (!n) return NULL;
		n->left  = optimize_ast(n->left);
		n->right = optimize_ast(n->right);
		n->next  = optimize_ast(n->next);

		if (n->left && n->right &&
		    n->left->type == NODE_CONST && n->right->type == NODE_CONST) {
			double a = n->left->num_val, b = n->right->num_val, out;
			switch (n->type) {
				case NODE_ADD: out = a + b; break;
				case NODE_SUB: out = a - b; break;
				case NODE_MUL: out = a * b; break;
				case NODE_DIV: if (b == 0) return n; out = a / b; break;
				case NODE_MOD:
					if (b == 0 || !is_whole_number(a) || !is_whole_number(b)) return n;
					out = (double)((long long)a % (long long)b); break;
				case NODE_LT:  out = a <  b; break;
				case NODE_GT:  out = a >  b; break;
				case NODE_LE:  out = a <= b; break;
				case NODE_GE:  out = a >= b; break;
				case NODE_EQ:  out = a == b; break;
				case NODE_NEQ: out = a != b; break;
				case NODE_AND: out = a && b; break;
				case NODE_OR:  out = a || b; break;
				default: return n;
			}
			// IMPORTANT: carry ->next so function arg chains are not broken.
			// e.g. foo(3+5, x) — the folded arg must still point to x.
			Node *folded = make_leaf(NODE_CONST, out, NULL);
			folded->line = n->line;
			folded->next = n->next;
			return folded;
		}
		if (n->type == NODE_NOT && n->left && n->left->type == NODE_CONST) {
			Node *folded = make_leaf(NODE_CONST, !n->left->num_val, NULL);
			folded->line = n->line;
			folded->next = n->next;
			return folded;
		}

		return n;
	}

	// ---------------------------------------------------------
	// OUTPUT HELPERS
	// ---------------------------------------------------------
	void print_escaped(const char *s) {
		if (!s) return;
		for (size_t i = 0; s[i] != '\0'; i++) {
			if (s[i] == '\\' && s[i+1] != '\0') {
				switch (s[i+1]) {
					case 'n':  putchar('\n'); i++; continue;
					case 't':  putchar('\t'); i++; continue;
					case 'r':  putchar('\r'); i++; continue;
					case '\\': putchar('\\'); i++; continue;
					case '"':  putchar('"');  i++; continue;
					default: break;
				}
			}
			putchar(s[i]);
		}
	}

	void print_number_line(double v) {
		long long iv = (long long)v;
		if (v == (double)iv) printf("%lld\n", iv);
		else printf("%g\n", v);
	}

	// ---------------------------------------------------------
	// EXECUTION ENGINE
	// ---------------------------------------------------------
	double execute(Node *n);   // forward declaration

	// Save / restore the whole symbol table around a function call
	// so local params don't clobber the caller's variables.
	void sym_table_save(struct Symbol *saved, int *saved_n) {
		*saved_n = sym_count;
		for (int i = 0; i < sym_count; i++) {
			saved[i] = sym_table[i];
			saved[i].name      = sym_table[i].name      ? strdup(sym_table[i].name)      : NULL;
			saved[i].str_value = sym_table[i].str_value ? strdup(sym_table[i].str_value) : NULL;
			saved[i].num_array = NULL;
			if (sym_table[i].num_array && sym_table[i].array_size > 0) {
				saved[i].num_array = (double*)malloc((size_t)sym_table[i].array_size * sizeof(double));
				if (saved[i].num_array)
					memcpy(saved[i].num_array, sym_table[i].num_array,
					       (size_t)sym_table[i].array_size * sizeof(double));
			}
		}
	}

	void sym_table_restore(struct Symbol *saved, int saved_n) {
		// Free current heap strings
		for (int i = 0; i < sym_count; i++) {
			if (sym_table[i].name)      free(sym_table[i].name);
			if (sym_table[i].str_value) free(sym_table[i].str_value);
			if (sym_table[i].num_array) free(sym_table[i].num_array);
		}
		sym_count = saved_n;
		for (int i = 0; i < saved_n; i++)
			sym_table[i] = saved[i];
	}

	double execute(Node *n) {
		if (!n) return 0;
		runtime_line = n->line;
		if (cf_state != 0 || returning) return 0;  // honour break / continue / return

		switch (n->type) {
			// ---- Leaf values ----
			case NODE_CONST:  return n->num_val;
			case NODE_VAR:    return get_numeric(n->str_val);
			case NODE_ARRAY_GET:
				return get_array_numeric(n->str_val, execute(n->left));

			// ---- Control flow signals ----
			case NODE_BREAK:    cf_state = 1; return 0;
			case NODE_CONTINUE: cf_state = 2; return 0;

			case NODE_RETURN:
				return_val = n->left ? execute(n->left) : 0.0;
				returning  = 1;
				return return_val;

			// ---- Arithmetic ----
			case NODE_ADD: return execute(n->left) + execute(n->right);
			case NODE_SUB: return execute(n->left) - execute(n->right);
			case NODE_MUL: return execute(n->left) * execute(n->right);
			case NODE_DIV: {
				double lhs = execute(n->left), rhs = execute(n->right);
				if (rhs == 0) { semantic_error("division by zero", NULL); return 0; }
				return lhs / rhs;
			}
			case NODE_MOD: {
				double lhs = execute(n->left), rhs = execute(n->right);
				if (rhs == 0) { semantic_error("modulo by zero", NULL); return 0; }
				if (!is_whole_number(lhs) || !is_whole_number(rhs)) {
					semantic_error("modulo requires integer operands", NULL); return 0;
				}
				return (double)((long long)lhs % (long long)rhs);
			}
			// ---- Comparison / Logic ----
			case NODE_LT:  return execute(n->left) <  execute(n->right);
			case NODE_GT:  return execute(n->left) >  execute(n->right);
			case NODE_LE:  return execute(n->left) <= execute(n->right);
			case NODE_GE:  return execute(n->left) >= execute(n->right);
			case NODE_EQ:  return execute(n->left) == execute(n->right);
			case NODE_NEQ: return execute(n->left) != execute(n->right);
			case NODE_AND: return execute(n->left) && execute(n->right);
			case NODE_OR:  return execute(n->left) || execute(n->right);
			case NODE_NOT: return !execute(n->left);

			// ---- Assignment ----
			case NODE_ASSIGN:
				assign_numeric(n->str_val, execute(n->right));
				return 0;
			case NODE_ASSIGN_STR:
				assign_string(n->str_val, n->right ? n->right->str_val : "");
				return 0;
			case NODE_ARRAY_SET:
				assign_array_numeric(n->str_val, execute(n->left), execute(n->right));
				return 0;

			// ---- I/O ----
			case NODE_PRINT:
				if (n->str_val) { print_escaped(n->str_val); putchar('\n'); }
				else            print_number_line(execute(n->left));
				return 0;
			case NODE_PRINT_VAR: {
				int idx = find_symbol(n->str_val);
				if (idx >= 0 && sym_table[idx].type == V_STRING)
					{ print_escaped(get_string(n->str_val)); putchar('\n'); }
				else if(idx != -1)
					print_number_line(get_numeric(n->str_val));
				else semantic_error("undefined variable", n->str_val);
				return 0;
			}
			case NODE_SCAN: {
				double val;
				printf("Input: ");
				scanf("%lf", &val);
				assign_numeric(n->str_val, val);
				return 0;
			}

			// ---- Sequence ----
			case NODE_SEQ:
				execute(n->left);
				if (cf_state != 0 || returning) return 0;
				execute(n->right);
				return 0;

			// ---- Conditionals ----
			case NODE_IF:
				if (execute(n->left)) {  // condition
					execute(n->right);   // then-block
				} else if (n->next) {    // else / else-if block
					execute(n->next);
				}
				return 0;

			// ---- doomscroll (while) ----
			case NODE_WHILE:
				while (execute(n->left)) {
					cf_state = 0;
					execute(n->right);
					if (cf_state == 1) { cf_state = 0; break;    }  // break
					if (cf_state == 2) { cf_state = 0; continue; }  // continue
					if (returning)     break;
				}
				return 0;

			// ---- iter8 (for) ----
			// n->left  = condition
			// n->right = body
			// n->next  = increment (ALWAYS runs, even on continue)
			case NODE_FOR:
				while (execute(n->left)) {
					cf_state = 0;
					execute(n->right);          // body

					if (cf_state == 1) {        // break  → skip increment, exit
						cf_state = 0;
						break;
					}
					cf_state = 0;               // clear continue (if set) before increment
					execute(n->next);           // increment — always runs
					if (returning) break;
				}
				return 0;

			// ---- Function call ----
			case NODE_FUNC_CALL: {
				int fidx = find_function(n->str_val);
				if (fidx < 0) {
					semantic_error("call to undefined function", n->str_val);
					return 0;
				}
				GenZFunc *f = &func_table[fidx];

				// 1. Evaluate arguments BEFORE touching the symbol table
				double arg_vals[MAX_PARAMS] = {0};
				Node  *arg = n->left;
				int    argc = 0;
				while (arg && argc < MAX_PARAMS) {
					// Each arg node's ->next points to the next arg (chain)
					// We save next, evaluate, then advance
					Node *nxt = arg->next;
					arg->next = NULL;           // temporarily sever so execute doesn't skip
					arg_vals[argc++] = execute(arg);
					arg->next = nxt;            // restore
					arg = nxt;
				}
				if (argc != f->param_count) {
					semantic_error("wrong number of arguments for function", n->str_val);
					return 0;
				}

				// 2. Save current symbol table (caller's scope)
				struct Symbol saved[100];
				int saved_n;
				sym_table_save(saved, &saved_n);

				// 3. Bind parameters in a fresh scope
				//    (restore wipes the table, so we start fresh by resetting count)
				sym_count = 0;
				for (int i = 0; i < f->param_count; i++) {
					declare_symbol(f->param_names[i], f->param_types[i]);
					int idx = find_symbol(f->param_names[i]);
					sym_table[idx].num_value = arg_vals[i];
				}

				// 4. Execute function body
				int saved_cf = cf_state;
				cf_state   = 0;
				returning  = 0;
				return_val = 0.0;
				execute(f->body);
				returning  = 0;   // clear so caller continues normally
				cf_state   = saved_cf;
				double result = return_val;
				return_val = 0.0;

				// 5. Restore caller's symbol table
				sym_table_restore(saved, saved_n);

				return result;
			}
		}
		return 0;
	}

%}

/* --------------------------------------------------------- */
/* Bison Declarations                                        */
/* --------------------------------------------------------- */
%union {
	int    num;
	double fnum;
	char  *str;
	struct Node *node;
}

%token <num> NUMBER
%token <fnum> FNUMBER
%token <str>  ID STRING

%token TYPE_INT TYPE_BOOL TYPE_FLOAT TYPE_DOUBLE TYPE_STRING
%token MAIN NGL
%token PRINT SCAN IF ELSEIF ELSE RETURN WHILE FOR
%token BREAK CONTINUE INC DEC
%token LBRACE RBRACE LPAREN RPAREN LBRACKET RBRACKET SEMICOLON
%token ASSIGN PLUS MINUS MULT DIV MOD GT LT LE GE EQ NEQ AND OR NOT COMMA
%token INVALID

%type <node> statement block expr program arg_list_opt arg_list for_inc

/* Operator precedence (low → high) */
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

/* --------------------------------------------------------- */
/* Grammar                                                   */
/* --------------------------------------------------------- */

program:
	  /* Functions may be defined before main_character */
	  func_defs MAIN LPAREN RPAREN block {
		Node *optimized = optimize_ast($5);
		printf("\n--- Starting Execution ---\n");
		execute(optimized);
		if (semantic_errors > 0)
			printf("\n[Semantic checks] %d issue(s) detected.\n", semantic_errors);
		printf("\n--- Execution Finished ---\n");
	  }
	| MAIN LPAREN RPAREN block {
		Node *optimized = optimize_ast($4);
		printf("\n--- Starting Execution ---\n");
		execute(optimized);
		if (semantic_errors > 0)
			printf("\n[Semantic checks] %d issue(s) detected.\n", semantic_errors);
		printf("\n--- Execution Finished ---\n");
	  }
	;

/* One or more function definitions before main */
func_defs:
	  func_def
	| func_defs func_def
	;

/*
 * Function definition syntax:
 *   ngl funcname(rizz x, ish y) { ... }
 *   ngl funcname() { ... }
 *
 * The body is stored in func_table; it is NOT executed here.
 */
func_def:
	  NGL ID LPAREN param_list_opt RPAREN block {
		if (find_function($2) >= 0) {
			semantic_error("function already defined", $2);
		} else if (func_count >= MAX_FUNCS) {
			semantic_error("too many functions", $2);
		} else {
			GenZFunc *f = &func_table[func_count++];
			f->name        = strdup($2);
			f->param_count = tmp_param_count;
			for (int i = 0; i < tmp_param_count; i++) {
				f->param_names[i] = tmp_param_names[i]; /* already strdup'd */
				f->param_types[i] = tmp_param_types[i];
			}
			f->body = $6;
		}
		tmp_param_count = 0;   /* reset for next function */
	  }
	;

param_list_opt:
	  /* empty */  { tmp_param_count = 0; }
	| param_list
	;

param_list:
	  param
	| param_list COMMA param
	;

/*
 * Each param rule just appends to the tmp_param_* arrays.
 * No %type needed — these rules carry no semantic value.
 */
param:
	  TYPE_INT    ID { tmp_param_names[tmp_param_count] = strdup($2); tmp_param_types[tmp_param_count++] = V_INT;    }
	| TYPE_FLOAT  ID { tmp_param_names[tmp_param_count] = strdup($2); tmp_param_types[tmp_param_count++] = V_FLOAT;  }
	| TYPE_DOUBLE ID { tmp_param_names[tmp_param_count] = strdup($2); tmp_param_types[tmp_param_count++] = V_DOUBLE; }
	| TYPE_BOOL   ID { tmp_param_names[tmp_param_count] = strdup($2); tmp_param_types[tmp_param_count++] = V_BOOL;   }
	| TYPE_STRING ID { tmp_param_names[tmp_param_count] = strdup($2); tmp_param_types[tmp_param_count++] = V_STRING; }
	;

block:
	  LBRACE statement RBRACE { $$ = $2; }
	| LBRACE RBRACE           { $$ = NULL; }   /* allow empty blocks {} */
	;

statement:
	  statement statement { $$ = make_node(NODE_SEQ, $1, $2); }
	| expr SEMICOLON { $$ = $1; }

	/* Type declarations without initialiser */
	| TYPE_INT    ID SEMICOLON { declare_symbol($2, V_INT);    $$ = NULL; }
	| TYPE_FLOAT  ID SEMICOLON { declare_symbol($2, V_FLOAT);  $$ = NULL; }
	| TYPE_DOUBLE ID SEMICOLON { declare_symbol($2, V_DOUBLE); $$ = NULL; }
	| TYPE_BOOL   ID SEMICOLON { declare_symbol($2, V_BOOL);   $$ = NULL; }
	| TYPE_STRING ID SEMICOLON { declare_symbol($2, V_STRING); $$ = NULL; }
	| TYPE_INT    ID LBRACKET NUMBER RBRACKET SEMICOLON { declare_array($2, V_INT,    $4); $$ = NULL; }
	| TYPE_FLOAT  ID LBRACKET NUMBER RBRACKET SEMICOLON { declare_array($2, V_FLOAT,  $4); $$ = NULL; }
	| TYPE_DOUBLE ID LBRACKET NUMBER RBRACKET SEMICOLON { declare_array($2, V_DOUBLE, $4); $$ = NULL; }
	| TYPE_BOOL   ID LBRACKET NUMBER RBRACKET SEMICOLON { declare_array($2, V_BOOL,   $4); $$ = NULL; }
	| TYPE_STRING ID LBRACKET NUMBER RBRACKET SEMICOLON {
		semantic_error("string arrays are not supported yet", $2); $$ = NULL;
	}

	/* Type declarations with initialiser */
	| TYPE_INT    ID ASSIGN expr SEMICOLON {
		declare_symbol($2, V_INT);
		$$ = make_node(NODE_ASSIGN, NULL, $4); $$->str_val = $2;
	}
	| TYPE_FLOAT  ID ASSIGN expr SEMICOLON {
		declare_symbol($2, V_FLOAT);
		$$ = make_node(NODE_ASSIGN, NULL, $4); $$->str_val = $2;
	}
	| TYPE_DOUBLE ID ASSIGN expr SEMICOLON {
		declare_symbol($2, V_DOUBLE);
		$$ = make_node(NODE_ASSIGN, NULL, $4); $$->str_val = $2;
	}
	| TYPE_BOOL   ID ASSIGN expr SEMICOLON {
		declare_symbol($2, V_BOOL);
		$$ = make_node(NODE_ASSIGN, NULL, $4); $$->str_val = $2;
	}
	| TYPE_STRING ID ASSIGN STRING SEMICOLON {
		declare_symbol($2, V_STRING);
		$$ = make_node(NODE_ASSIGN_STR, NULL, make_leaf(NODE_STRCONST, 0, $4));
		$$->str_val = $2;
	}

	/* Plain assignment */
	| ID ASSIGN expr SEMICOLON {
		$$ = make_node(NODE_ASSIGN, NULL, $3); $$->str_val = $1;
	}
	| ID ASSIGN STRING SEMICOLON {
		$$ = make_node(NODE_ASSIGN_STR, NULL, make_leaf(NODE_STRCONST, 0, $3));
		$$->str_val = $1;
	}
	| ID LBRACKET expr RBRACKET ASSIGN expr SEMICOLON {
		$$ = make_node(NODE_ARRAY_SET, $3, $6); $$->str_val = $1;
	}

	/* I/O: spill_tea */
	| PRINT LPAREN STRING RPAREN SEMICOLON { $$ = make_leaf(NODE_PRINT, 0, $3); }
	| PRINT LPAREN expr   RPAREN SEMICOLON { $$ = make_node(NODE_PRINT, $3, NULL); }
	| PRINT LPAREN ID     RPAREN SEMICOLON { $$ = make_leaf(NODE_PRINT_VAR, 0, $3); }

	/* I/O: gimme */
	| SCAN LPAREN ID RPAREN SEMICOLON { $$ = make_leaf(NODE_SCAN, 0, $3); }

	/* Control: yeet / skrrrt */
	| BREAK    SEMICOLON { $$ = make_node(NODE_BREAK,    NULL, NULL); }
	| CONTINUE SEMICOLON { $$ = make_node(NODE_CONTINUE, NULL, NULL); }

	/* peace_out (return) */
	| RETURN expr SEMICOLON { $$ = make_node(NODE_RETURN, $2,   NULL); }
	| RETURN      SEMICOLON { $$ = make_node(NODE_RETURN, NULL, NULL); }

	/* Postfix ++/-- as statements */
	| ID INC SEMICOLON {
		Node *add = make_node(NODE_ADD, make_leaf(NODE_VAR, 0, $1), make_leaf(NODE_CONST, 1, NULL));
		$$ = make_node(NODE_ASSIGN, NULL, add); $$->str_val = $1;
	}
	| ID DEC SEMICOLON {
		Node *sub = make_node(NODE_SUB, make_leaf(NODE_VAR, 0, $1), make_leaf(NODE_CONST, 1, NULL));
		$$ = make_node(NODE_ASSIGN, NULL, sub); $$->str_val = $1;
	}

	/* vibe_check (if) */
	| IF LPAREN expr RPAREN block {
		$$ = make_node(NODE_IF, $3, $5);
	}
	| IF LPAREN expr RPAREN block ELSE block {
		$$ = make_node(NODE_IF, $3, $5); $$->next = $7;
	}
	| IF LPAREN expr RPAREN block ELSEIF LPAREN expr RPAREN block {
		Node *inner = make_node(NODE_IF, $8, $10);
		$$ = make_node(NODE_IF, $3, $5); $$->next = inner;
	}
	| IF LPAREN expr RPAREN block ELSEIF LPAREN expr RPAREN block ELSE block {
		Node *inner = make_node(NODE_IF, $8, $10); inner->next = $12;
		$$ = make_node(NODE_IF, $3, $5); $$->next = inner;
	}

	/* doomscroll (while) */
	| WHILE LPAREN expr RPAREN block {
		$$ = make_node(NODE_WHILE, $3, $5);
	}

	/*
	 * iter8 (for) — uses NODE_FOR so the increment ALWAYS runs,
	 * even when 'skrrrt' (continue) is hit.
	 *
	 * Accepts any expression as the init value and any for_inc
	 * form as the step:
	 *   iter8(i = 0   ; i < 10 ; i++)          ← i++
	 *   iter8(i = 10  ; i > 0  ; i--)          ← i--
	 *   iter8(i = 0   ; i < 20 ; i = i + 2)    ← arbitrary assignment
	 *
	 * Structure built:
	 *   NODE_SEQ
	 *     left  = init assignment
	 *     right = NODE_FOR
	 *                left  = condition
	 *                right = body
	 *                next  = increment node  ← always runs
	 */
	| FOR LPAREN ID ASSIGN expr SEMICOLON expr SEMICOLON for_inc RPAREN block {
		/* Init: id = expr */
		Node *initNode    = make_node(NODE_ASSIGN, NULL, $5);
		initNode->str_val = strdup($3);

		/* NODE_FOR: left=cond, right=body, next=increment */
		Node *forNode  = make_node(NODE_FOR, $7, $11);
		forNode->next  = $9;   /* for_inc produces the increment node */

		$$ = make_node(NODE_SEQ, initNode, forNode);
	}
	;

/*
 * for_inc — the third clause of iter8(...).
 * Produces a Node* that is executed as the increment step.
 * No trailing semicolon — the RPAREN closes the for header.
 *
 * Supported forms:
 *   i++              → i = i + 1
 *   i--              → i = i - 1
 *   i = i + 2        → arbitrary numeric assignment
 *   i = i * factor   → any expr on the right-hand side
 */
for_inc:
	  ID INC {
		Node *add = make_node(NODE_ADD, make_leaf(NODE_VAR, 0, strdup($1)),
		                                make_leaf(NODE_CONST, 1, NULL));
		$$ = make_node(NODE_ASSIGN, NULL, add);
		$$->str_val = $1;
	}
	| ID DEC {
		Node *sub = make_node(NODE_SUB, make_leaf(NODE_VAR, 0, strdup($1)),
		                                make_leaf(NODE_CONST, 1, NULL));
		$$ = make_node(NODE_ASSIGN, NULL, sub);
		$$->str_val = $1;
	}
	| ID ASSIGN expr {
		$$ = make_node(NODE_ASSIGN, NULL, $3);
		$$->str_val = $1;
	}
	;

/* ---- Expressions ---- */
expr:
	  expr PLUS  expr { $$ = make_node(NODE_ADD, $1, $3); }
	| expr MINUS expr { $$ = make_node(NODE_SUB, $1, $3); }
	| expr MULT  expr { $$ = make_node(NODE_MUL, $1, $3); }
	| expr DIV   expr { $$ = make_node(NODE_DIV, $1, $3); }
	| expr MOD   expr { $$ = make_node(NODE_MOD, $1, $3); }
	| expr GT    expr { $$ = make_node(NODE_GT,  $1, $3); }
	| expr LT    expr { $$ = make_node(NODE_LT,  $1, $3); }
	| expr EQ    expr { $$ = make_node(NODE_EQ,  $1, $3); }
	| expr NEQ   expr { $$ = make_node(NODE_NEQ, $1, $3); }
	| expr LE    expr { $$ = make_node(NODE_LE,  $1, $3); }
	| expr GE    expr { $$ = make_node(NODE_GE,  $1, $3); }
	| expr AND   expr { $$ = make_node(NODE_AND, $1, $3); }
	| expr OR    expr { $$ = make_node(NODE_OR,  $1, $3); }
	| NOT expr        { $$ = make_node(NODE_NOT, $2, NULL); }
	| LPAREN expr RPAREN { $$ = $2; }
	| NUMBER  { $$ = make_leaf(NODE_CONST, $1,  NULL); }
	| FNUMBER { $$ = make_leaf(NODE_CONST, $1,  NULL); }
	| ID LBRACKET expr RBRACKET {
		$$ = make_node(NODE_ARRAY_GET, $3, NULL); $$->str_val = $1;
	}
	| ID      { $$ = make_leaf(NODE_VAR,   0,   $1);   }

	/*
	 * Function call as expression: funcname(arg1, arg2, ...)
	 * Arguments are chained through their ->next pointers.
	 */
	| ID LPAREN arg_list_opt RPAREN {
		$$ = make_node(NODE_FUNC_CALL, $3, NULL);
		$$->str_val = $1;
	}
	;

arg_list_opt:
	  /* empty */ { $$ = NULL; }
	| arg_list    { $$ = $1;   }
	;

/*
 * Build a singly-linked list of argument nodes using ->next.
 * We append to the tail so arguments stay in order.
 */
arg_list:
	  expr {
		$$ = $1; $$->next = NULL;
	  }
	| arg_list COMMA expr {
		/* Find the tail of the current list and append */
		Node *tail = $1;
		while (tail->next) tail = tail->next;
		tail->next = $3;
		$3->next   = NULL;
		$$ = $1;
	  }
	;

%%

void yyerror(char *s) {
	fprintf(stdout, "Error at line %d: %s\n", yylineno, s);
}

int main(int argc, char *argv[]) {
	int parse_status;
	if (argc > 1) {
		yyin = fopen(argv[1], "r");
		if (!yyin) { perror("Error opening file"); return 1; }
	} else {
		yyin = stdin;
	}
	parse_status = yyparse();
	if (lexical_errors > 0 && parse_status == 0) parse_status = 1;
	if (argc > 1) fclose(yyin);
	return parse_status;
}
