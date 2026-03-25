# GenZ Compiler Project

A fully functional compiler/interpreter for the "GenZ" programming language, built using Flex and Bison.

## Features Implemented
- **Data Types**: `rizz` (integer), `yap` (string).
- **Control Flow**:
    - `vibe_check` (if)
    - `doomscroll` (while)
    - `iter8` (for loop)
    - `fun` (functions - main_character only)
- **I/O**:
    - `spill_tea` (print)
    - `gimme` (scan/input)
- **Operators**: Standard arithmetic (+, -, *, /) and logic defined in proposal.
- **Comments**: Supports `tbh` (//), `story_time` (/* */), and standard C comments.

## How to Build & Run

### Prerequisites
You need `flex`, `bison`, and `gcc` installed.
```bash
sudo apt install flex bison gcc
```

### Compile the Compiler
Run the following command in this directory:
```bash
make
```
This will generate the `genz_compiler` executable and automatically run `test.genz`.

### Run Interactive Mode
To run your own code or test input interactively:
1. Create a file (e.g., `mycode.genz`).
2. Run:
   ```bash
   ./genz_compiler < mycode.genz
   ```
   *Note: If your code uses `gimme` (input), you might want to run the compiler without input redirection, but currently the compiler accepts source code via Stdin. To handle interactive input properly with source code files, you would need to modify main() to accept a filename argument (argv).*

## File Structure
- `GenZ.l`: Lexer rules (Token definitions).
- `GenZ.y`: Grammar rules (AST construction & Execution logic).
- `test.genz`: A comprehensive test suite demonstrating all features.
- `Makefile`: Build automation script.
