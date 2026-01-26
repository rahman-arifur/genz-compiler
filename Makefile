all:
	flex GenZ.l
	gcc lex.yy.c -o genz_transpiler
	./genz_transpiler < demo.genz > out.c
	gcc out.c -o demo
	@echo "------------------------------------"
	@echo "Compilation Successful. Running Demo:"
	@echo "------------------------------------"
	./demo

clean:
	rm -f lex.yy.c genz_transpiler out.c demo_program
