NVIM ?= nvim
MINI_PATH ?= .tests/mini.nvim
MINI_REPO ?= https://github.com/echasnovski/mini.nvim
# .tests/bin/stylua があればそれを使う
STYLUA ?= $(if $(wildcard .tests/bin/stylua),.tests/bin/stylua,stylua)
# make test FILE=tests/test_kana.lua で 1 ファイルだけ動かす
FILE ?=

.PHONY: test deps lint fmt difftest

test: deps
	MINI_PATH=$(MINI_PATH) $(NVIM) --headless --noplugin -u tests/minimal_init.lua \
		-c "lua MiniTest.run$(if $(FILE),_file('$(FILE)'),())"

deps: $(MINI_PATH)

$(MINI_PATH):
	git clone --depth 1 --filter=blob:none $(MINI_REPO) $(MINI_PATH)

lint:
	$(STYLUA) --check lua plugin tests

fmt:
	$(STYLUA) lua plugin tests

# denops 版（upstream）との差分テスト。deno と denops.vim が要る（無ければ skip）。
# make difftest ARGS="--random 50 --filter Kan" のように絞れる
ARGS ?=
difftest: deps
	MINI_PATH=$(MINI_PATH) $(NVIM) --headless -u NONE -i NONE -l tests/diff/run.lua $(ARGS)
