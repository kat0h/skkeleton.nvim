NVIM ?= nvim
MINI_PATH ?= .tests/mini.nvim
MINI_REPO ?= https://github.com/echasnovski/mini.nvim
# .tests/bin/stylua があればそれを使う
STYLUA ?= $(if $(wildcard .tests/bin/stylua),.tests/bin/stylua,stylua)
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
	$(STYLUA) --check lua plugin tests bench

fmt:
	$(STYLUA) lua plugin tests bench

bench:
	bench/run_all.sh 1
