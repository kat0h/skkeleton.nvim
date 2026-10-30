NVIM ?= nvim
MINI_PATH ?= .tests/mini.nvim
MINI_REPO ?= https://github.com/echasnovski/mini.nvim
# .tests/bin/stylua があればそれを使う
STYLUA ?= $(if $(wildcard .tests/bin/stylua),.tests/bin/stylua,stylua)
# make test FILE=tests/test_kana.lua で 1 ファイルだけ動かす
FILE ?=

.PHONY: test deps lint fmt bench difftest bench-keys verify

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

# denops 版（upstream）との差分テスト。deno と denops.vim が要る（無ければ skip）。
# make difftest ARGS="--random 50 --filter Kan" のように絞れる
ARGS ?=
difftest: deps
	MINI_PATH=$(MINI_PATH) $(NVIM) --headless -u NONE -i NONE -l tests/diff/run.lua $(ARGS)

# キー 1 回ごとの処理時間を測る
bench-keys: deps
	MINI_PATH=$(MINI_PATH) $(NVIM) --headless -u NONE -i NONE -l bench/keys.lua $(ARGS)

# 形式検証の PoC: 実装の状態空間を幅優先でなめて、tests/formal/spec.lua の性質を確かめる。
# make verify ARGS="--depth 5 --jobs 8"、make verify ARGS="--random 1000 --length 25"、
# make verify ARGS="--mutate no-stale-check"（直したバグを戻して見つかるか）
verify: deps
	MINI_PATH=$(MINI_PATH) $(NVIM) --headless -u NONE -i NONE -l tests/formal/check.lua $(ARGS)
