# skkeleton.nvim の構成と設計

skkeleton.nvim のモジュールの構成と、モジュールのあいだのインターフェース。インターフェースを変えるときは、このドキュメントもあわせて更新する。

移植元は `skkeleton`（以下 upstream）および `skkeleton_indicator.nvim`。upstream の `denops/skkeleton/*.ts` と関数を 1 対 1 で対応させ、挙動に迷った場合は upstream の仕様に合わせる。

## 全体の方針
- Neovim 専用、純粋な Lua（LuaJIT）で実装し、FFI や外部コマンドには依存しない。
- denops 版にあった非同期処理（`await`）はすべて同期呼び出しにする。
- **入力エンジン（core）は Neovim の UI に直接触れない**。UI 操作が必要な処理（モード変更の通知、無効化、候補のポップアップ表示、`input()`、`confirm()`）はすべて `skkeleton.host` を経由して呼び出す。テスト時には `host` の関数をモックに差し替えられるようにする。
- 表示方式: pre-edit（`▽かん` など）は**バッファに直接書き込まず**、`virt_text_pos = "inline"` の extmark で表示する。確定した文字列は upstream と同様に `nvim_feedkeys(str, "nit")` で送出する（`\n` による autoindent、`\x07u` による undo point、`\b` による削除を効かせるため）。cmdline モードと terminal モードのみ、upstream と同じく `<BS>` で消去して書き直す方式をとる。
- 設定のキー名は upstream から移行しやすいよう、同じ camelCase（`markerHenkan` など）を維持する。
- `state` などの内部テーブルのフィールド名は snake_case とする。ただし、関数の登録名（キーマップやかなテーブルで文字列として指定するもの）は upstream と同じ camelCase（`henkanFirst` など）にする。

## モジュール構成

| モジュール | 区分 | 内容 |
|---|---|---|
| `lua/skkeleton/util.lua` | 共通 | `lazy(name)`（循環 `require` を避ける遅延プロキシ）、UTF-8 の文字操作 |
| `lua/skkeleton/config.lua` | コア | 既定値、バリデーション、正規化（`~` の展開など） |
| `lua/skkeleton/notation.lua` | コア | キー表記の正規化（`<C-j>` → `<nl>` など） |
| `lua/skkeleton/kana/{init,rom_hira,rom_zen,hira_kata,hira_hankata}.lua` | コア | かなテーブル（Trie）とかな変換 |
| `lua/skkeleton/{state,context,candidate,okuri,preedit,store,host}.lua` | コア | 入力状態、Context、確定文字列のバッファ |
| `lua/skkeleton/keymap.lua` | コア | 状態ごとのキーマップと `handle_key` |
| `lua/skkeleton/function/{init,common,input,henkan,mode,disable,dictionary}.lua` | コア | upstream の `function/*.ts` に対応する各機能 |
| `lua/skkeleton/dictionary/{init,skk,db,user,numeral}.lua` | 辞書 | 辞書管理（Library、SKK 辞書、DB キャッシュ、ユーザー辞書、数値変換） |
| `lua/skkeleton/indicator/{init,indicator,config,modes,strings}.lua` | インジケータ | `skkeleton_indicator.nvim` の移植。本体の中を見ない（下の indicator） |
| `lua/skkeleton/completion/{init,blink,sort}.lua` | 補完 | blink.cmp の source と、候補作り・判定・確定の共通の処理（`can_complete()`、`items()`、`confirm()`）。補完は blink.cmp だけ（#69） |
| `lua/skkeleton/{init,main,render,popup,map}.lua`、`plugin/skkeleton.lua`、`autoload/skkeleton.vim`、`host.lua` の UI 部分 | UI | Neovim との結合。`main.lua` が enable/disable/toggle/handle と autocmd、`render.lua` が描画、`popup.lua` が候補ポップアップ、`map.lua` がマッピングとオプションの退避・復元を担当 |
| `tests/helpers.lua` のキー入力ドライバ、E2E テスト | UI | 結合テスト・E2E テスト基盤 |

ほかの区分のモジュールを使うときは、以下のインターフェースだけを通す。単体テストでは、ほかの区分のモジュールをスタブに差し替える。

## インターフェース

### state（コア）
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

### Context と store（コア）
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

### PreEdit（コア）
```lua
pe:do_kakutei(str)          -- 確定した文字列をバッファに追加する
pe:output(next) -> string   -- upstream と同じ。BS*(前回の文字数) .. 確定文字列 .. next を返す（cmdline/terminal およびテスト用）
pe:take_kakutei() -> string -- 蓄積した確定文字列を取り出して空にする（insert モードの描画用）
```

### host（既定の実装はコア、UI の部分は UI）
core から UI へアクセスする処理はすべてここを経由する。
```lua
host.mode_changed(mode)           -- g:skkeleton#mode を更新して User skkeleton-mode-changed を発火（コア）
host.disable()                    -- skkeleton を無効化する（UI）
host.show_candidates(lines)       -- 候補一覧のポップアップ表示（UI）。lines は "a: 候補" の配列
host.input(prompt) -> string?     -- 辞書登録のプロンプト入力（UI）。キャンセル時は nil または ""
host.confirm(msg) -> boolean      -- purgeCandidate の確認ダイアログ（UI）
host.keep_state_on_insert_enter() -- keepState 有効時の再有効化処理（UI）
```

### KanaTable（コア）
```lua
local kana = require("skkeleton.kana")
kana.get_table(name?) -> skkeleton.KanaTable  -- 省略時は現在のテーブル名
kana.current_name / kana.set_current(name)
kana.register(name, raw_table, create)        -- upstream の registerKanaTable
kana.load_file(name, path, encoding, create)
-- KanaTable の検索結果は { "あ", "" }（かなと次の feed）だけ。関数はかなテーブルに置かず、キーマップ（keymap.lua）に置く（#67）
tbl:find(from) -> result?
tbl:node(prefix) -> { count = 前方一致する件数, result = 完全一致の結果? }?  -- Trie により O(len) で検索
```
1 打ごとの処理（`keymap.handle_key`）は、打ちかけ＋キーがかなテーブルにあればかなテーブル、なければキーマップの関数、それもなければ `kana_input` の順に見る。`l`、`q`、`;`、`/`、`L` のように既定のローマ字のテーブルでだけ関数として効くキーは、`function/input.lua` の `kana_function` で包んでいる。

### Library（辞書）
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
DB の形式 v1（`lua/skkeleton/dictionary/db.lua`）:
- 置き場所: `stdpath("cache")/skkeleton/<元の辞書の正規化した絶対パスの sha256 の先頭 16 文字>.db`（設定の `databasePath` があればそのディレクトリ）
- `[0,128)` のヘッダは ASCII で `SKKDB <ver> <nari> <nnasi> <src_size> <src_mtime_sec> <src_mtime_nsec>\n` を空白で埋めたもの。ヘッダのサイズと mtime が元の辞書と合わなければ作り直す
- `[128,…)` の索引: u32 LE の行頭オフセット。okuri-ari が nari 個＋終端、okuri-nasi が nnasi 個＋終端。行の長さはオフセットの差でわかる
- データ部: UTF-8 の `読み 候補\n` を、種類ごとにバイト順（LuaJIT の文字列比較と同じ）でソートしたもの
- 書き込みは `.tmp` に書いてから rename する。同じ読みが 2 回あれば先のものを使う（#48）

### indicator（インジケータ）
```lua
require("skkeleton.indicator").setup(opts)  -- opts は skkeleton_indicator と同じキー（camelCase）。false で無効化
```
インジケータは本体から切り離す。本体が公開する状態（`g:skkeleton#mode`、`g:skkeleton#enabled`、`g:skkeleton#state`）と User イベント（`skkeleton-mode-changed`、`skkeleton-enable-post`、`skkeleton-disable-post`、`skkeleton-handled`）だけを読み、`skkeleton.render` などを `require` しない。本体からインジケータを呼ぶのは `init.lua` の `setup` だけにする。今は本体から `move()` を呼んでいるところと、インジケータが `skkeleton.render` を読んでいるところが残っていて、#63 で消す。

### 公開インターフェース（UI、upstream と互換）
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
- pre-edit とバッファのずれは、`main.lua` の `reset_if_stale()` の 1 か所で見つけて片付ける（#61）。判定は `render.is_stale()`。pre-edit を出している間は `nvim_buf_attach` の `on_bytes` でバッファの書き換えを受け、ずれた合図にする（#66）。extmark は `right_gravity = false`。
- Vim のモードが移ったときの片付けは、`main.lua` の `ModeChanged` 1 か所で受け、`MODE_TRANSITIONS` の表で片付け方を決める（#62）。insert から normal へ移るときは、pre-edit を `<Esc>` と同じく確定してから片付ける（#70）。
- cmdline モードと terminal モードでは `ctx.preedit:output(ctx:to_string())` を送出する。
- モードのみが変化し出力文字列がない場合も `finish()` を呼ぶため、upstream の `" \x08"` に相当する再描画ハックは不要。
- `virtualedit` は変更しない（pre-edit をバッファに書き込まないため）。`textwidth` のみ `0` に退避・設定する。

テスト、ライセンス、コミットの決まりは [AGENTS.md](../AGENTS.md) にある。
