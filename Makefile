all:
	bison -d GenZ.y

	flex GenZ.l

	gcc lex.yy.c GenZ.tab.c -o genz

	./genz test.genz

clean:
	rm -f lex.yy.c GenZ.tab.c GenZ.tab.h genz
