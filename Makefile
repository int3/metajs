TESTS = $(wildcard tests/*.js)

%.actual: %.js interpreter.coffee
	@echo "testing $<... \c"
	@iced interpreter.coffee $< > $@
#	@node interpreter.js $< > $@

%.expected: %.js
	@node $? > $@

%.result: %.actual %.expected
	@diff $?
	@echo "passed"

test: $(TESTS:.js=.result)
