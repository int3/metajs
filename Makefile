TESTS = $(wildcard tests/*.js)
ES6TESTS = $(wildcard tests/es6/*.js)
LIB_COFFEE = $(wildcard lib/*.coffee)
LIB_JS = $(LIB_COFFEE:.coffee=.js)
BROWSER_COFFEE = $(wildcard browser/*.coffee)

browser: $(BROWSER_COFFEE:.coffee=.js) browser/bundle.js

test: $(TESTS:.js=.result) $(ES6TESTS:.js=.result) $(LIB_JS)
	echo $(LIB_JS)

%.actual: %.js $(LIB_JS) repl.js
	@echo "testing $<... \c"
	@node repl.js $< > $@

%.expected: %.js
	@node $? > $@

%.result: %.actual %.expected
	@diff $?
	@echo "passed"

browser/bundle.js: $(LIB_JS)
	browserify $^ -o browser/bundle.js --exports require

%.js: %.coffee
	iced -c -I browserify $<

.SECONDARY: $(LIB_JS)
.PHONY: browser
