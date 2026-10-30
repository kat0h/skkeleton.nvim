NVIM ?= nvim
MINI_PATH ?= .tests/mini.nvim
MINI_REPO ?= https://github.com/echasnovski/mini.nvim
# make test FILE=tests/test_kana.lua で 1 ファイルだけ動かす
FILE ?=

.PHONY: test deps lint fmt bench

test: deps
	MINI_PATH=$(MINI_PATH) $(NVIM) --headless --noplugin -u tests/minimal_init.lua \
		-c "lua MiniTest.run$(if $(FILE),_file('$(FILE)'),())"

deps: $(MINI_PATH)

$(MINI_PATH):
	git clone --depth 1 --filter=blob:none $(MINI_REPO) $(MINI_PATH)

lint:
	stylua --check lua plugin tests

fmt:
	stylua lua plugin tests

bench:
	bench/run_all.sh 1
