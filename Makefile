TESTS = $(wildcard tests/*.js)

%.actual: %.js interpreter.coffee
	@coffee interpreter.coffee $< > $@

%.expected: %.js
	@node $? > $@

%.result: %.actual %.expected
	@diff $?
	@echo "$? passed"

test: $(TESTS:.js=.result)
