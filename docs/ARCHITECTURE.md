# skkeleton.nvim の構成と取り決め

Phase 2 の実装を複数の担当に分けて進めるための取り決め。ここに書いたインターフェースは担当をまたいで使うので、変えるときはこのファイルも直す。

移植元は `~/.local/share/nvim/lazy/skkeleton/`（以下 upstream）と `~/.local/share/nvim/lazy/skkeleton_indicator.nvim/`。upstream の `denops/skkeleton/*.ts` と関数を 1 対 1 で対応させる。挙動に迷ったら upstream に合わせる。

## 全体の方針
- Neovim 専用、純粋な Lua（LuaJIT）。FFI と外部コマンドは使わない
- denops 版にあった非同期（`await`）はすべて同期の呼び出しにする
- **入力エンジン（core）は Neovim の UI に触らない**。UI が要る処理（モードの通知、無効化、候補の popup、`input()`、`confirm()`）は `skkeleton.host` を通して呼ぶ。テストでは host の関数を差し替えられる
- 表示: pre-edit（`▽かん` など）は**バッファに書かず**、`virt_text_pos = "inline"` の extmark で表示する。確定した文字列は upstream と同じく `nvim_feedkeys(str, "nit")` で流す（`\n` で autoindent、`\x07u` で undo point、`\b` で削除が効くようにするため）。cmdline と terminal だけは upstream と同じく BS で消して書き直す
- 設定のキーは upstream から移行しやすいように同じ camelCase（`markerHenkan` など）にする
- state などのテーブルのフィールドは snake_case。関数の登録名（キーマップやかなテーブルで文字列で指すもの）は upstream と同じ camelCase（`henkanFirst` など）

## モジュールと担当

| モジュール | 担当 | 中身 |
|---|---|---|
| `lua/skkeleton/util.lua` | 共通（作成済み） | `lazy(name)`（循環 require を避ける遅延プロキシ）、UTF-8 の文字操作 |
| `lua/skkeleton/config.lua` | K | 既定値、検証、正規化（`~` の展開） |
| `lua/skkeleton/notation.lua` | K | キー表記の正規化（`<C-j>` → `<nl>` など） |
| `lua/skkeleton/kana/{init,rom_hira,rom_zen,hira_kata,hira_hankata}.lua` | K | かなテーブル（trie）と変換 |
| `lua/skkeleton/{state,context,candidate,okuri,preedit,store,host}.lua` | K | 入力の状態、Context、確定文字列のバッファ |
| `lua/skkeleton/keymap.lua` | K | state ごとのキーマップと `handle_key` |
| `lua/skkeleton/function/{init,common,input,henkan,mode,disable,dictionary}.lua` | K | upstream の `function/*.ts` |
| `lua/skkeleton/dictionary/{init,skk,db,user,numeral}.lua` | D | 辞書（Library、SKK 辞書、DB キャッシュ、ユーザー辞書、数値変換） |
| `lua/skkeleton/indicator/{init,modes}.lua` | I | skkeleton_indicator.nvim の移植 |
| `lua/skkeleton/{init,main,render,popup,map}.lua`、`plugin/skkeleton.lua`、`autoload/skkeleton.vim`、`host.lua` の UI 部分 | U | Neovim との結合（第 2 波）。`main.lua` が enable/disable/toggle/handle と autocmd、`render.lua` が表示、`popup.lua` が候補の popup、`map.lua` がマッピングとオプションの退避 |
| `tests/helpers.lua` のキー入力ドライバ、E2E テスト | U | 第 2 波 |

担当は自分のファイルだけを作る・変える。他の担当のモジュールが要るときは、下のインターフェースだけを使い、テストでは差し替える。

## インターフェース

### state（K）
```lua
---@alias skkeleton.HenkanType "okuriari"|"okurinasi"
---@class skkeleton.InputState
---@field type "input"
---@field mode "direct"|skkeleton.HenkanType
---@field affix? "prefix"|"suffix"
---@field direct_input boolean
---@field table skkeleton.KanaTable
---@field converter? fun(s: string): string
---@field feed string
---@field henkan_feed string
---@field okuri_feed string
---@field previous_feed boolean
---@class skkeleton.HenkanState: skkeleton.InputState  -- type = "henkan"
---@field word string
---@field candidates string[]
---@field candidate_index integer   -- 0 起点（upstream と同じ数え方。-1 は未選択）
-- { type = "escape" } もある
state.initialize(st, ignore?)   -- upstream の initializeState
state.to_string(st)
```

### Context と store（K）
```lua
local ctx = require("skkeleton.context").new()
ctx.state, ctx.mode ("hira" など), ctx.preedit, ctx.vim_mode ("i"|"c"|"t"|""), ctx.last_candidate
ctx:kakutei(str); ctx:kakutei_with_undo_point(str); ctx:to_string()

local store = require("skkeleton.store")
store.context()        -- 今の Context（なければ作る）
store.init_context()   -- 作り直して返す
store.library()        -- 今の Library。未設定なら require("skkeleton.dictionary").load() で作る
store.set_library(lib) -- テスト用の差し替え
store.variables.last_mode
```

### PreEdit（K）
```lua
pe:do_kakutei(str)       -- 確定した文字列を貯める
pe:output(next) -> string -- upstream と同じ。BS*(前回の文字数) .. 確定 .. next を返す（cmdline/terminal とテスト用）
pe:take_kakutei() -> string -- 貯めた確定文字列を取り出して空にする（insert モードの表示用）
```

### host（K が既定の実装を書き、U が UI の部分を埋める）
core から UI へ出るところはすべてここを通す。
```lua
host.mode_changed(mode)          -- g:skkeleton#mode を設定して User skkeleton-mode-changed を発火（K が実装）
host.disable()                   -- skkeleton を無効化する（U）
host.show_candidates(lines)      -- 候補一覧の popup（U）。lines は "a: 候補" の配列
host.input(prompt) -> string?    -- 辞書登録の入力（U）。取り消しなら nil か ""
host.confirm(msg) -> boolean     -- purgeCandidate の確認（U）
host.keep_state_on_insert_enter()-- keepState の再有効化（U）
```

### KanaTable（K）
```lua
local kana = require("skkeleton.kana")
kana.get_table(name?) -> skkeleton.KanaTable  -- 既定は今のテーブル名
kana.current_name / kana.set_current(name)
kana.register(name, raw_table, create)        -- upstream の registerKanaTable
kana.load_file(name, path, encoding, create)
-- KanaTable の結果は { "あ", "" }（かなと次の feed）か、関数（function/ の関数）
tbl:find(from) -> result?
tbl:node(prefix) -> { count = 前方一致する件数, result = 完全一致の結果? }?  -- trie で O(len)
tbl:filter(pred) -> KanaTable
```

### Library（D）
```lua
local dictionary = require("skkeleton.dictionary")
dictionary.load() -> Library      -- config（globalDictionaries、userDictionary、databasePath など）から作る
dictionary.Library.new(dicts, user_dict)
lib:get_henkan_result(type, word) -> string[]   -- 候補（ユーザー辞書が先、重複を除く、数値変換を含む）
lib:register_henkan_result(type, word, candidate)
lib:purge_candidate(type, word, candidate)
lib:load(); lib:save()
-- 個々の辞書は :get_henkan_result(type, word) と :get_prefix(type, prefix, limit) を持つ
```
DB の形式は `docs/PLAN.md` の「DB の形式 v1」のとおり（`bench/lib/cache.lua` が参考実装）。

### indicator（I）
```lua
require("skkeleton.indicator").setup(opts)  -- opts は skkeleton_indicator と同じキー（camelCase）。false で無効
```
モードは `vim.g["skkeleton#mode"]` と `vim.g["skkeleton#enabled"]` から読み、upstream と同じ User イベント（`skkeleton-mode-changed`、`skkeleton-enable-post`、`skkeleton-disable-post`）で更新する。

### Neovim に見せるもの（U、upstream と互換）
- 変数: `g:skkeleton#enabled`、`g:skkeleton#mode`
- User イベント: `skkeleton-initialize-pre/post`、`skkeleton-enable-pre/post`、`skkeleton-disable-pre/post`、`skkeleton-mode-changed`、`skkeleton-handled`
- `<Plug>(skkeleton-enable)`、`<Plug>(skkeleton-disable)`、`<Plug>(skkeleton-toggle)`（i/c/t）
- Lua API: `require("skkeleton").setup(opts)`、`.enable()`、`.disable()`、`.toggle()`、`.mode()`、`.is_enabled()`、`.register_keymap(state, key, func)`、`.register_kanatable(name, tbl, create)`、`.register_kanatable_file(...)`、`.get_config()`、`.initialize()`、`.update_database(path, encoding, force)`
- pre-edit の extmark の namespace は `skkeleton-preedit`、ハイライトグループは `SkkeletonPreedit`（既定は何も指定しない）
- `g:skkeleton#state`（`{ phase, henkanFeed }`）は handle のたびに更新する
- `autoload/skkeleton.vim` には `skkeleton#mode()` と `skkeleton#is_enabled()` だけを置く

### 表示の流れ（render）
- insert モード: 確定した文字列は `nvim_feedkeys(…, "nit")` で流し、そのあとに `<Cmd>lua require('skkeleton.render').finish()<CR>` を続ける。`finish` が extmark を置き直し、候補の popup を開き、`User skkeleton-handled` を発火する。確定が無いときは `finish` をその場で呼ぶ
- 流す文字列の 0x80（「、」など）は `0x80 0xfe 'X'` に逃がす。`<Cmd>` だけを `nvim_replace_termcodes` して続ける
- pre-edit が残っているのにカーソルの位置か `changedtick` が描いたときと違えば、次の handle の最初で state を捨てる（extmark は `right_gravity = false`）
- cmdline と terminal は `ctx.preedit:output(ctx:to_string())` を流す
- モードだけが変わった（出力が無い）ときも `finish` を呼ぶので、upstream の `" \x08"` に当たる再描画は要らない
- `virtualedit` は変えない（pre-edit をバッファに書かないので）。`textwidth` だけ 0 にする

## テスト
- mini.test。`make test`（全部）、`make test FILE=tests/test_kana.lua`（1 ファイル）
- ファイルは `tests/test_<領域>.lua`。モジュールの状態（config やかなテーブル）を持つものは `require("helpers").child_set()` で子の nvim を使い、ケースごとに作り直す
- 辞書のテストデータは `tests/testdata/`（upstream の testdata の写し。EUC-JP のものがある）
- upstream の `*_test.ts` の入出力はできるだけそのまま表にして移す

## ライセンス
- 詳しくは `LICENSES/README.md`。upstream（skkeleton、skkeleton_indicator.nvim）はどちらも zlib
- upstream から移植したファイルの先頭には、移植元のファイル、著作権表示、改変したことを書く（書き方は `LICENSES/README.md`）
- SKK 辞書（GPL）と、upstream が使っている外部パッケージのコードはリポジトリに入れない。数値変換（漢数字、ローマ数字など）は自分で書く

## コミット
- `docs/PLAN.md` の方針どおり、1 コミット = 1 つの意味のある単位。`make test` が通る状態でだけコミットする
- メッセージは Conventional Commits 風（`feat:`、`fix:`、`test:`、`docs:`）。本文の最後に、書いたモデルの行を付ける（例: `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`）
- コメントは日本語で、コードの意図を短く書く
- ドキュメント（`docs/`、README、`doc/`）、issue、PR の日本語は、yomiyasu スキル（https://github.com/nanaism/yomiyasu）で推敲してからコミット・投稿する
