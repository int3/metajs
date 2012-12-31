TESTS = $(wildcard tests/*.js)

%.actual: %.js interpreter.coffee
	@echo "testing $<... \c"
	@coffee interpreter.coffee $< > $@

%.expected: %.js
	@node $? > $@

%.result: %.actual %.expected
	@diff $?
	@echo "passed"

test: $(TESTS:.js=.result)
