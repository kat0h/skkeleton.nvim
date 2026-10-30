# skkeleton.nvim: skkeleton を Neovim 専用の Lua プラグインとして再実装する

## Context
今の skkeleton は denops（Deno）の上で動いている。キーを押すたびに Vim script → RPC → Deno → RPC → feedkeys と往復するので、遅延が出やすい。また Deno ランタイムが要るので、入れられる環境が限られる。そこで、Neovim の LuaJIT だけで完結するプラグインを別リポジトリに作る。

決まっていること:
- 対象は Neovim 専用（手元は v0.12.5）。設定は Lua API だけ（`require("skkeleton").setup{}`）
- 新しいリポジトリ: `~/ghq/github.com/kat0h/skkeleton.nvim`
- v1 の範囲: コアの変換、SKK 辞書、ユーザー辞書、**Deno KV に相当する DB**、**skkeleton_indicator.nvim の機能の内蔵**
- v1 の範囲外: skkserv、Google 日本語入力、補完、rank file
- ライセンスは zlib。skkeleton（© kuuote）と skkeleton_indicator（© Yasushi Jinnouchi）の著作権表示を残す

**この計画で今回やるのは Phase 0（リポジトリを作って計画を記録する）と Phase 1（KV 相当が Lua で実用的な速度になるかの検証）だけ。** 本体の開発は、Phase 1 の結果を見てユーザーが判断してから始める。

---

## Phase 0: リポジトリを作り、計画を記録する
1. `mkdir -p ~/ghq/github.com/kat0h/skkeleton.nvim && git init`（ブランチは main）
2. この計画を `docs/PLAN.md` として置く。README は最小限、LICENSE は zlib で両方の著作権表示を入れる。`.gitignore` も置く
3. コミットは 1 つ: `docs: add implementation plan`
- コミットの粒度の方針（`docs/PLAN.md` にも書く）: 1 コミット = 1 つの意味のある単位（1 つの機能、1 つの修正、1 回のベンチ結果）。必ずテストが通る状態でコミットする。メッセージは Conventional Commits 風（`feat:`、`fix:`、`test:`、`bench:`、`docs:`）

## Phase 1: KV 相当の実現可能性を検証する（最優先）
### 何を確かめるか
今の設定は `sources = {"deno_kv"}` と SKK-JISYO.L（4.5MB、17.6 万行、EUC-JP）の組み合わせ。Deno KV の役割は「巨大な辞書を毎回パースせずに、起動直後から引ける」こと。これを Lua で、以下の目標を満たして実現できるかを測る。

| 指標 | 目標 |
|---|---|
| 準備済みの状態での起動（open からの初回検索まで） | ≤ 10ms |
| 完全一致の検索 1 回（okuri-nasi/ari） | p50 ≤ 0.1ms、p99 ≤ 1ms |
| 前方一致の検索（将来の補完用。「か」「かん」など） | ≤ 5ms（先頭 100 件） |
| キャッシュの初回生成（L 辞書） | ≤ 2s（1 回きりなので緩くてよい） |
| 常駐メモリの増加 | L 辞書 1 つで ≤ 20MB |
| 複数辞書（L + jinmei + geo + station + propernoun） | 上記を大きく崩さない |

### 比べる実装（`bench/` 以下に置く。本体のコードとは分ける）
- **A. 素朴な table 化（基準）**: ファイル全体を読み、`vim.iconv` で変換し、全行を `{[読み]=候補文字列}` に入れる。denops 版の skk_dictionary と同じ方式
- **B. メモリ上の文字列とオフセット配列**: UTF-8 に変換した文字列を 1 本だけ保持する。読みをキーにしてソートしたオフセット配列で二分探索し、候補は引いたときに切り出す
- **C. 永続キャッシュと pread（本命）**: 初回に `stdpath("cache")/skkeleton/<hash>.db` を作る。中身は「ヘッダ（マジック、バージョン、元辞書のパス・mtime・サイズ）＋ UTF-8 の okuri-ari/okuri-nasi をそれぞれバイト順にソートしたデータ部＋固定長（u32）のオフセット表」。起動時は `fs_open` してヘッダとオフセット表だけ読む。検索は二分探索で、比較するたびに `fs_read(fd, len, offset)` する。ページキャッシュに乗るので実際は速いはず
- **C'. C を LuaJIT FFI の mmap で読む**: Windows 対応は捨て、Linux/macOS で `mmap` して `ffi.string` で比較する。C の pread が遅かったときの代案
- **D（参考）. Deno KV の実測**: 今の skkeleton で `getCandidates` の RPC の往復時間を測り、比較の基準にする（denops.vim と skkeleton が `~/.local/share/nvim/lazy` にあるので測れる）

### ベンチマークの作り
- `bench/run.lua`: `nvim --headless -u NONE -l bench/run.lua <impl> <dict...>` で動かす
  - 時間は `vim.uv.hrtime()`、メモリは `collectgarbage("count")` と `/proc/self/statm` の RSS で測る
  - 検索する語: 辞書からランダムに 1 万語（seed は固定）＋ 存在しない語 1000 個 ＋ 前方一致用の 100 個
  - キャッシュの状態: 生成直後（warm）と、`echo 3 > drop_caches` は権限が要るので、代わりに「別プロセスでの初回」を cold に近い値として記録する
  - 結果は `bench/results/<date>.md` に表で書き出す
- **正しさの検証**: B/C/C' の検索結果が A と全語で一致することを `bench/verify.lua` で確かめる（全見出し語とランダムな前方一致）。速くても結果が違えば失格
- 辞書は `/usr/share/skk/SKK-JISYO.{L,jinmei,geo,station,propernoun}` を使う（リポジトリには入れない）

### 結論の出し方
- 採用は「目標を満たす実装のうち、いちばん単純でポータブルなもの」。たぶん C、C の検索が遅ければ C'
- `bench/results/` と `docs/PLAN.md` に結論と DB の形式（v1）を書いてコミットする（`bench: ...`、`docs: decide db format`）
- **ここで止めて、ユーザーに結果を報告する**

### Phase 1 の結果（2026-10-30）
詳しくは [bench/results/2026-10-30.md](../bench/results/2026-10-30.md)。

- **C（永続キャッシュ＋ `vim.uv.fs_read` による pread）を採用する。** SKK-JISYO.L で、起動 3.1ms、検索 p50 0.011ms・p99 0.087ms、前方一致の max 0.40ms、キャッシュの生成 0.44 秒、RSS の増加 0.7MB。すべての目標を満たした。5 辞書でも、起動 3.3ms・検索 p99 0.26ms
- 今の Deno KV と比べると、起動は約 150 倍、前方一致は 100 倍以上速い。DB の生成は 4.75 秒から 0.44 秒に、サイズは 37MB から 6.9MB になる
- C'（FFI の mmap）は C より約 10 倍速いが、C に十分な余裕があるので v1 では入れない
- 結果が A と一致することは、約 37 万件の照合（`bench/verify.lua`）で確かめた

### DB の形式 v1（`lua/skkeleton/dictionary/db.lua` で実装する）
`bench/lib/cache.lua` のとおり。
- 置き場所: `stdpath("cache")/skkeleton/<元の辞書の正規化した絶対パスの sha256 の先頭 16 文字>.db`（設定の `databasePath` があればそのディレクトリ）
- `[0,128)` のヘッダは ASCII で `SKKDB <ver> <nari> <nnasi> <src_size> <src_mtime_sec> <src_mtime_nsec>\n` を空白で埋めたもの。ヘッダのサイズと mtime が元の辞書と合わなければ作り直す
- `[128,…)` の索引: u32 LE の行頭オフセット。okuri-ari が nari 個＋終端、okuri-nasi が nnasi 個＋終端。行の長さはオフセットの差でわかる
- データ部: UTF-8 の `読み 候補\n` を、種類ごとにバイト順（LuaJIT の文字列比較と同じ）でソートしたもの
- 書き込みは `.tmp` に書いてから rename する。同じ読みが 2 回あれば先のものを使う
- 本体に入れるときに足すもの: 生成を `vim.uv` の work/スレッドかコルーチンで小分けにして UI を止めないこと。エンコーディングの指定。複数の Neovim が同時に作ろうとしたときの扱い（rename なので壊れはしない）

---

## Phase 2 以降（参考。Phase 1 のあとで判断する）
### 自律して開発するためのテスト基盤（Phase 2 の最初に作る）
人が実際に打たなくても、入力した結果を自動で確かめられるようにする。
- **ランナー**: mini.test を使う（手元に mini.nvim がある）。`make test` で `nvim --headless -u tests/minimal_init.lua` を起動し、子の nvim で動かす（`MiniTest.new_child_neovim()`）。1 ケースごとに別プロセスにするので状態が漏れない
- **入力ドライバ** `tests/helpers.lua`: `type("iKanji<Space><CR>")` で `nvim_input` に流し、処理が終わるまで待ってから `buffer()`（確定した行）、`preedit()`（extmark の virt_text）、`mode()`、`popup()`（候補ウィンドウの中身）、`indicator()`（インジケータの文字列とハイライト）を返す。ケースは「打つキー → 期待する状態」の表で書く
- **移植するテストケース**: denops 版の `function/*_test.ts`、`kana_test.ts`、`okuri_test.ts`、`dictionary_test.ts`、`preedit_test.ts` の入出力を表形式にする。`testdata/*Jisyo` もコピーする
- **差分テスト（オラクル）**: 手元の denops 版 skkeleton を同じキー列で動かし、確定したバッファの中身を比べる `tests/diff/`。キー列はシナリオ集とランダム生成（seed 固定）から作る。denops 版と挙動が違ったものを自動で拾える。CI では Deno がないので `make difftest` として手元だけで動かす
- **ベンチ**: `make bench` で Phase 1 のベンチと、キー 1 回の処理時間（hrtime）を測る。遅くなったら気づける
- **CI**: GitHub Actions で nvim stable と nightly を使い、`make test` と `make lint`（stylua --check、lua-language-server --check）を回す

### アーキテクチャの要点
- pre-edit はバッファに書かず、`virt_text_pos="inline"` の extmark で表示する。確定した文字列だけを `nvim_buf_set_text` で書く。cmdline と terminal だけは BS で消して書き直す旧方式にフォールバックする。これで denops 版の `prevInput` 不一致の検出、pending kakutei、restorePoint が不要になる
- かなテーブルは前方一致用の trie にする（denops 版は毎回 `filter(startsWith)` で線形走査している）
- 構成: `lua/skkeleton/{init,config,context,state,keymap,notation,preedit,okuri,candidate,popup}.lua`、`kana/`、`function/{common,input,henkan,mode,disable,dictionary}.lua`、`dictionary/{init,numeral,skk,json,user,db}.lua`、`indicator/{init,modes}.lua`、`plugin/skkeleton.lua`
- 移植元: `denops/skkeleton/` の各ファイル（関数の対応は 1 対 1）、`autoload/skkeleton.vim`（マッピングと自動で無効化する処理）、`autoload/skkeleton/popup.vim`
- インジケータ: `~/.local/share/nvim/lazy/skkeleton_indicator.nvim/lua/skkeleton_indicator/` を移植し、`setup{ indicator = {...} }` の下に元と同じキーで置く（`indicator = false` で無効）。モードは Context から直接読む

### 実装する順序（各ステップの最後にテストを付けてコミットする）
1. テスト基盤 → 2. config/notation/kana の trie/state → 3. input の関数群と preedit（ひらがなの直接入力）→ 4. enable/disable とキーマップ → 5. 辞書（db/skk/user）、henkan、popup、数値変換 → 6. モード、abbrev、辞書登録、kakuteiUndo、purgeCandidate → 7. cmdline/terminal → 8. indicator → 9. doc と CI

## 確認の方法（Phase 0/1）
- Phase 0: `git -C ~/ghq/github.com/kat0h/skkeleton.nvim log --oneline` で計画のコミットが 1 つあること
- Phase 1: `nvim --headless -u NONE -l bench/verify.lua` がすべての実装で 0 件不一致になること、`bench/run.lua` の結果の表が目標と並べて `bench/results/` に保存されていること。その表を使ってユーザーに報告する

## Phase 2 の進め方（2026-10-30）
- モジュールの担当とインターフェースは [docs/ARCHITECTURE.md](ARCHITECTURE.md) に決めた。実装はサブエージェントに分けて渡し、タスクは GitHub の issue で管理する
- 計画からの変更: 確定した文字列は `nvim_buf_set_text` ではなく、upstream と同じく `feedkeys` で流す。autoindent（upstream の「new line」のテスト）、`<C-g>u` の undo point、`.` のリピート、略語の展開を保つため。pre-edit を extmark で表示する点は変えない
- upstream のこの版には kakuteiUndo が無いので、v1 の範囲から外す
