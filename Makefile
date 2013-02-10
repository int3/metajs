TESTS = $(wildcard tests/*.js)
INTERPRETER = interpreter.coffee

%.actual: %.js $(INTERPRETER)
	@echo "testing $< with $(INTERPRETER)... \c"
	@./$(INTERPRETER) $< > $@

%.expected: %.js
	@node $? > $@

%.result: %.actual %.expected
	@diff $?
	@echo "passed"

test: $(TESTS:.js=.result)

test-all:
	@make test INTERPRETER=interpreter.coffee
	@make test INTERPRETER=cps-interpreter.coffee
