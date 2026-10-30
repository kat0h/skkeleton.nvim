# skkeleton.nvim の構成と設計規約

Phase 2 の実装を複数のモジュール担当に分けて進めるための設計規約。ここに記載したインターフェースはモジュール間で共有するため、変更する場合はこのドキュメントもあわせて更新する。

移植元は `skkeleton`（以下 upstream）および `skkeleton_indicator.nvim`。upstream の `denops/skkeleton/*.ts` と関数を 1 対 1 で対応させ、挙動に迷った場合は upstream の仕様に合わせる。

## 全体の方針
- Neovim 専用、純粋な Lua（LuaJIT）で実装し、FFI や外部コマンドには依存しない。
- denops 版にあった非同期処理（`await`）はすべて同期呼び出しにする。
- **入力エンジン（core）は Neovim の UI に直接触れない**。UI 操作が必要な処理（モード変更の通知、無効化、候補のポップアップ表示、`input()`、`confirm()`）はすべて `skkeleton.host` を経由して呼び出す。テスト時には `host` の関数をモックに差し替えられるようにする。
- 表示方式: pre-edit（`▽かん` など）は**バッファに直接書き込まず**、`virt_text_pos = "inline"` の extmark で表示する。確定した文字列は upstream と同様に `nvim_feedkeys(str, "nit")` で送出する（`\n` による autoindent、`\x07u` による undo point、`\b` による削除を効かせるため）。cmdline モードと terminal モードのみ、upstream と同じく `<BS>` で消去して書き直す方式をとる。
- 設定のキー名は upstream から移行しやすいよう、同じ camelCase（`markerHenkan` など）を維持する。
- `state` などの内部テーブルのフィールド名は snake_case とする。ただし、関数の登録名（キーマップやかなテーブルで文字列として指定するもの）は upstream と同じ camelCase（`henkanFirst` など）にする。

## モジュール構成と担当

| モジュール | 担当 | 内容 |
|---|---|---|
| `lua/skkeleton/util.lua` | 共通 | `lazy(name)`（循環 `require` を避ける遅延プロキシ）、UTF-8 の文字操作 |
| `lua/skkeleton/config.lua` | K | 既定値、バリデーション、正規化（`~` の展開など） |
| `lua/skkeleton/notation.lua` | K | キー表記の正規化（`<C-j>` → `<nl>` など） |
| `lua/skkeleton/kana/{init,rom_hira,rom_zen,hira_kata,hira_hankata}.lua` | K | かなテーブル（Trie）とかな変換 |
| `lua/skkeleton/{state,context,candidate,okuri,preedit,store,host}.lua` | K | 入力状態、Context、確定文字列のバッファ |
| `lua/skkeleton/keymap.lua` | K | 状態ごとのキーマップと `handle_key` |
| `lua/skkeleton/function/{init,common,input,henkan,mode,disable,dictionary}.lua` | K | upstream の `function/*.ts` に対応する各機能 |
| `lua/skkeleton/dictionary/{init,skk,db,user,numeral}.lua` | D | 辞書管理（Library、SKK 辞書、DB キャッシュ、ユーザー辞書、数値変換） |
| `lua/skkeleton/indicator/{init,modes}.lua` | I | `skkeleton_indicator.nvim` の移植 |
| `lua/skkeleton/{init,main,render,popup,map}.lua`、`plugin/skkeleton.lua`、`autoload/skkeleton.vim`、`host.lua` の UI 部分 | U | Neovim との結合。`main.lua` が enable/disable/toggle/handle と autocmd、`render.lua` が描画、`popup.lua` が候補ポップアップ、`map.lua` がマッピングとオプションの退避・復元を担当 |
| `tests/helpers.lua` のキー入力ドライバ、E2E テスト | U | 結合テスト・E2E テスト基盤 |

各担当は自身の担当ファイルのみを作成・変更する。他担当のモジュールを利用する際は以下のインターフェースのみを通し、単体テストではスタブに差し替える。

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
---@field candidate_index integer   -- 0 始まり（upstream と同じ。-1 は未選択）
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
store.context()        -- 現在の Context（未作成なら生成）
store.init_context()   -- 新規に生成して返す
store.library()        -- 現在の Library。未設定なら require("skkeleton.dictionary").load() で生成
store.set_library(lib) -- テスト用の差し替え
store.variables.last_mode
```

### PreEdit（K）
```lua
pe:do_kakutei(str)          -- 確定した文字列をバッファに追加する
pe:output(next) -> string   -- upstream と同じ。BS*(前回の文字数) .. 確定文字列 .. next を返す（cmdline/terminal およびテスト用）
pe:take_kakutei() -> string -- 蓄積した確定文字列を取り出して空にする（insert モードの描画用）
```

### host（K が既定実装を書き、U が UI 部分を実装する）
core から UI へアクセスする処理はすべてここを経由する。
```lua
host.mode_changed(mode)           -- g:skkeleton#mode を更新して User skkeleton-mode-changed を発火（K が実装）
host.disable()                    -- skkeleton を無効化する（U）
host.show_candidates(lines)       -- 候補一覧のポップアップ表示（U）。lines は "a: 候補" の配列
host.input(prompt) -> string?     -- 辞書登録のプロンプト入力（U）。キャンセル時は nil または ""
host.confirm(msg) -> boolean      -- purgeCandidate の確認ダイアログ（U）
host.keep_state_on_insert_enter() -- keepState 有効時の再有効化処理（U）
```

### KanaTable（K）
```lua
local kana = require("skkeleton.kana")
kana.get_table(name?) -> skkeleton.KanaTable  -- 省略時は現在のテーブル名
kana.current_name / kana.set_current(name)
kana.register(name, raw_table, create)        -- upstream の registerKanaTable
kana.load_file(name, path, encoding, create)
-- KanaTable の検索結果は { "あ", "" }（かなと次の feed）または関数（function/ の関数）
tbl:find(from) -> result?
tbl:node(prefix) -> { count = 前方一致する件数, result = 完全一致の結果? }?  -- Trie により O(len) で検索
tbl:filter(pred) -> KanaTable
```

### Library（D）
```lua
local dictionary = require("skkeleton.dictionary")
dictionary.load() -> Library      -- config（globalDictionaries、userDictionary、databasePath など）から生成
dictionary.Library.new(dicts, user_dict)
lib:get_henkan_result(type, word) -> string[]   -- 変換候補（ユーザー辞書優先、重複排除、数値変換を含む）
lib:register_henkan_result(type, word, candidate)
lib:purge_candidate(type, word, candidate)
lib:load(); lib:save()
-- 個々の辞書は :get_henkan_result(type, word) と :get_prefix(type, prefix, limit) を持つ
```
DB フォーマットは `docs/PLAN.md` の「DB の形式 v1」に従う（`bench/lib/cache.lua` がリファレンス実装）。

### indicator（I）
```lua
require("skkeleton.indicator").setup(opts)  -- opts は skkeleton_indicator と同じキー（camelCase）。false で無効化
```
モードは `vim.g["skkeleton#mode"]` と `vim.g["skkeleton#enabled"]` から読み取り、upstream と同じ User イベント（`skkeleton-mode-changed`、`skkeleton-enable-post`、`skkeleton-disable-post`）で表示を更新する。

### 公開インターフェース（U、upstream と互換）
- 変数: `g:skkeleton#enabled`、`g:skkeleton#mode`
- User イベント: `skkeleton-initialize-pre/post`、`skkeleton-enable-pre/post`、`skkeleton-disable-pre/post`、`skkeleton-mode-changed`、`skkeleton-handled`
- `<Plug>(skkeleton-enable)`、`<Plug>(skkeleton-disable)`、`<Plug>(skkeleton-toggle)`（`i` / `c` / `t` モード）
- Lua API: `require("skkeleton").setup(opts)`、`.enable()`、`.disable()`、`.toggle()`、`.mode()`、`.is_enabled()`、`.register_keymap(state, key, func)`、`.register_kanatable(name, tbl, create)`、`.register_kanatable_file(...)`、`.get_config()`、`.initialize()`、`.update_database(path, encoding, force)`
- pre-edit 用 extmark の namespace は `skkeleton-preedit`、ハイライトグループは `SkkeletonPreedit`（既定では属性未設定）
- `g:skkeleton#state`（`{ phase, henkanFeed }`）はキー処理（handle）のたびに更新する
- `autoload/skkeleton.vim` にはステータスライン連携用の `skkeleton#mode()` と `skkeleton#is_enabled()` のみを配置する

### 描画フロー（render）
- insert モード: 確定文字列がある場合は `nvim_feedkeys(…, "nit")` で送出し、続けて `<Cmd>lua require('skkeleton.render').finish()<CR>` を実行する。`finish()` 内で extmark の再配置、候補ポップアップの表示、`User skkeleton-handled` の発火を行う。確定文字列がない場合はその場で `finish()` を直接呼び出す。
- 送出する文字列に含まれる `0x80`（「、」などの UTF-8 バイト列に含まれる）は `0x80 0xfe 'X'` にエスケープし、末尾の `<Cmd>...<CR>` のみを `nvim_replace_termcodes` で変換して結合する。
- pre-edit が残っている状態で、カーソル位置または `changedtick` が前回描画時と異なる場合は、次の handle の冒頭で入力状態をリセットする（extmark は `right_gravity = false`）。
- cmdline モードと terminal モードでは `ctx.preedit:output(ctx:to_string())` を送出する。
- モードのみが変化し出力文字列がない場合も `finish()` を呼ぶため、upstream の `" \x08"` に相当する再描画ハックは不要。
- `virtualedit` は変更しない（pre-edit をバッファに書き込まないため）。`textwidth` のみ `0` に退避・設定する。

## テスト
- テストランナーは `mini.test`。`make test`（全件実行）、`make test FILE=tests/test_kana.lua`（単一ファイル実行）。
- テストファイルは `tests/test_<領域>.lua`。モジュールレベルの状態（config やかなテーブルなど）を変更するテストでは、`require("helpers").child_set()` で子プロセスの Neovim を使い、テストケースごとに環境を分離する。
- 辞書のテストデータは `tests/testdata/` に配置（upstream の testdata を複製したもの。EUC-JP エンコーディングのファイルを含む）。
- upstream の `*_test.ts` の入出力ケースは、可能な限りそのままテーブル駆動テストとして移植する。

## ライセンス
- 詳細は `LICENSES/README.md` を参照。移植元（skkeleton、skkeleton_indicator.nvim）はいずれも zlib ライセンス。
- upstream から移植したファイルの先頭には、移植元ファイル名、著作権表示、および改変した旨を明記する（書式は `LICENSES/README.md` を参照）。
- SKK 辞書（GPL）および upstream が依存している外部パッケージのコードはリポジトリに含めない。数値変換（漢数字、ローマ数字など）は独自に実装する。

## コミット規約
- `docs/PLAN.md` の方針に従い、1 コミット = 1 つの意味のある単位とし、`make test` が通る状態でコミットする。
- コミットメッセージは Conventional Commits 形式（`feat:`、`fix:`、`test:`、`docs:` など）とする。
- コード内のコメントは日本語で、処理の意図を簡潔に記述する。
