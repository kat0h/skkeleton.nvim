# キーの棚卸し（#181）

skkeleton.nvim が受けるキーと受けないキーを、キー 1 つごとに「どこで処理されるか」で並べた表です。親の issue は #179 です。用語は [GLOSSARY.md](../GLOSSARY.md) に合わせます。ここには今の振る舞いだけを書き、望ましい振る舞いは決めません。

- 基準コミット: `ac567ab22e418401d1a3e6240263091fa7dde8dd`（`formal-semantics`、PR #195 のマージ）
- 対象: `lua/skkeleton/map.lua`、`keymap.lua`、`guard.lua`、`notation.lua`、`plugin/skkeleton.lua`、`main.lua`、`cleanup.lua`、`host.lua`、`function/`、`doc/skkeleton.txt`
- 黒箱の観測は Neovim 0.12.0 と 0.11.6 で、`tests/helpers.lua` の `e2e_set`（一時ディレクトリの辞書）を使って行いました。打ったあとの `g:skkeleton#state.preedit`、バッファ、モードを読みました。主な結果は両方の版で同じです。§6 の cmdline の行だけは 0.11.6 で観測しました。

## 表の読み方

- **キー**: `<>` 表記です。`notation.normalize`（`lua/skkeleton/notation.lua:125-137`）を通したあとの表記で書きます。`<C-j>` は `<nl>`、`<BS>` と `<C-h>` は `<bs>`、`\` は `<bslash>`、`|` は `<bar>` になります。
- **Vim のモード**: skkeleton のマッピングが効く Vim のモードです。`i` は insert、`c` は cmdline、`t` は terminal です。insert-normal（`ni`）では `map.lua` が `n` を `i` に読み替えます（`lua/skkeleton/map.lua:114-117`）。
- **処理する場所**: `map` は `lua/skkeleton/map.lua` が置くマッピング、`keymap` は `lua/skkeleton/keymap.lua` の状態ごとの処理、`guard` は `lua/skkeleton/guard.lua` の `vim.on_key`、`Neovim` は skkeleton が関与しない素通しです。順に処理される場合は `map → keymap` のように書きます。
- **根拠**: ファイル:行です。
- **未確認**: 「なし（実測）」は、この表を作るときにマッピングの有無か振る舞いを実際に確かめたものです。「コード読解のみ」は実装を読んで判断したもので、打って確かめていません。「未確認（…）」は、確かめていない理由を書いています。

## 前提

- skkeleton がキーを奪うのは、有効化したときの Vim モードのバッファローカルマッピングだけです（`lua/skkeleton/map.lua:113-139`、`lua/skkeleton/main.lua:117-119`）。insert で有効化すれば `i` に、cmdline で有効化すれば `c` に、terminal で有効化すれば `t` に置きます。複数のモードに一度に置くことはありません。
- 置換モード `R` では有効化を拒否します（`lua/skkeleton/main.lua:103-106`）。normal / visual / select ではマッピングを置きません。
- 辞書登録のプロンプト（`P_PROMPT`）では、`host.input` が cmdline に入った時点で `c` のマッピングを置き直します（`lua/skkeleton/host.lua:175-204`）。このとき `<Esc>`、`<C-g>`、`<C-c>` は登録の取り消しに差し替えます（`lua/skkeleton/host.lua:197-204`）。
- insert で有効な間、`:` も skkeleton が奪うキーです（§1 の記号）。insert から cmdline に入るには `<C-o>:` などを使います。

## 1. `map.lua` が奪うキー

`default_keys` は 102 個のキーを返します（`lua/skkeleton/map.lua:13-23`、実測）。内訳は次のとおりです。どのキーも、有効化したときの Vim モード（`i` / `c` / `t`）にバッファローカルで置かれ、押すと `main.handle("handleKey")` を通って `keymap` に渡ります（`lua/skkeleton/map.lua:123-137`）。

| キー | Vim のモード | 処理する場所 | 根拠 | 未確認 |
|---|---|---|---|---|
| `a` `b` `c` `d` `e` `f` `g` `h` `i` `j` `k` `l` `m` `n` `o` `p` `q` `r` `s` `t` `u` `v` `w` `x` `y` `z` | i / c / t | map → keymap（状態で分岐。§3） | `lua/skkeleton/map.lua:14,21,123-137`、`lua/skkeleton/keymap.lua:23-59` | なし（実測: 102 個のマッピング） |
| `A` `B` `C` `D` `E` `F` `G` `H` `I` `J` `K` `L` `M` `N` `O` `P` `Q` `R` `S` `T` `U` `V` `W` `X` `Y` `Z` | i / c / t | map → keymap（`L` は zenkaku、`X` は henkan で purgeCandidate、ほかは kana_input） | `lua/skkeleton/map.lua:15,123-137`、`lua/skkeleton/notation.lua:114-117,130-131`、`lua/skkeleton/keymap.lua:41,52` | なし（実測） |
| `1` `2` `3` `4` `5` `6` `7` `8` `9` `0` | i / c / t | map → keymap | `lua/skkeleton/map.lua:16,123-137` | なし（実測） |
| `!` `"` `#` `$` `%` `&` `'` `(` `)` `,` `.` `/` `;` `:` `]` `@` `[` `-` `^` `\` `>` `?` `_` `+` `*` `}` `` ` `` `{` `=` `~` | i / c / t | map → keymap（`/` は abbrev、`;` は henkanPoint、`>` は prefix / suffix） | `lua/skkeleton/map.lua:17-19,123-137`、`lua/skkeleton/keymap.lua:34,39-40,53` | なし（実測） |
| `<lt>`（`<`） | i / c / t | map → keymap | `lua/skkeleton/map.lua:21,123-137` | なし（実測） |
| `<Bar>`（`\|`） | i / c / t | map → keymap | `lua/skkeleton/map.lua:21,123-137` | なし（実測） |
| `<BS>` | i / c / t | map → keymap（input で deleteChar） | `lua/skkeleton/map.lua:21,123-137`、`lua/skkeleton/keymap.lua:27` | なし（実測） |
| `<C-h>` | i / c / t | map → keymap（`<bs>` に正規化されて deleteChar） | `lua/skkeleton/map.lua:21`、`lua/skkeleton/notation.lua:130-136`、`lua/skkeleton/keymap.lua:29` | なし（実測: 正規化すると `<bs>` になり、`keymap.lua:29` の `<c-h>` の行は引かれない） |
| `<CR>` | i / c / t | map → keymap（input / henkan で newline） | `lua/skkeleton/map.lua:21,123-137`、`lua/skkeleton/keymap.lua:30,48` | なし（実測） |
| `<Space>` | i / c / t | map → keymap（input で henkanFirst、henkan で henkanForward） | `lua/skkeleton/map.lua:21,123-137`、`lua/skkeleton/keymap.lua:35,50` | なし（実測） |
| `<C-q>` | i / c / t | map → keymap（input で hankatakana） | `lua/skkeleton/map.lua:21,123-137`、`lua/skkeleton/keymap.lua:33` | なし（実測） |
| `<C-j>`（`<nl>`） | i / c / t | map → keymap（input / henkan で kakutei） | `lua/skkeleton/map.lua:21`、`lua/skkeleton/notation.lua:130-136`、`lua/skkeleton/keymap.lua:32,49` | なし（実測） |
| `<C-g>` | i / c / t | map → keymap（input / henkan で cancel） | `lua/skkeleton/map.lua:21,123-137`、`lua/skkeleton/keymap.lua:28,47` | なし（実測） |
| `<Esc>` | i / c / t | map → keymap（input で escape。henkan では default 経由） | `lua/skkeleton/map.lua:21,123-137`、`lua/skkeleton/keymap.lua:31,86` | なし（実測） |

補足です。

- 表記の正規化で、いくつかのキーが同じ表記になります。`<BS>` と `<C-h>` はどちらも `<bs>`、`<Bar>` は `<bar>`、`\` は `<bslash>` です（実測）。マッピングは `<BS>` と `<C-H>` を別の lhs として 102 個置きますが、callback に渡るキーはどちらも `<bs>` です（`lua/skkeleton/map.lua:123-137`）。
- 大文字は `A` のまま渡ります（`lua/skkeleton/notation.lua:130-131`）。`l`、`q`、`;`、`/`、`L` は、既定のかなテーブルを使っているときだけ関数として扱い、利用者がかなテーブルに同じキーの規則を書いていれば規則を優先します（`lua/skkeleton/function/input.lua:122-145`、`doc/skkeleton.txt:549-552`）。
- 102 個のキーのうち `<C-h>` は `<bs>` と同じ扱いになるため、`keymap.lua` の `<c-h>` の行（`lua/skkeleton/keymap.lua:29`）は引かれません。振る舞いは `<BS>` と同じ deleteChar です。

## 2. `g:skkeleton#mapped_keys`（利用者が足すキー）

既定値は未設定（`nil`）です（実測）。設定すると、既定の 102 個に足して、有効化したときの Vim モードに置きます（`lua/skkeleton/map.lua:27-30,123-137`）。機能を割り当てるには `register_keymap` を使います（`lua/skkeleton/keymap.lua:94-112`、`doc/skkeleton.txt:235-252`）。

| キー | Vim のモード | 処理する場所 | 根拠 | 未確認 |
|---|---|---|---|---|
| 利用者が `g:skkeleton#mapped_keys` に足したキー（例 `<C-l>`） | i / c / t（有効化したモード） | map → keymap（`register_keymap` で割り当てた関数） | `lua/skkeleton/map.lua:27-30,123-137`、`lua/skkeleton/keymap.lua:94-112` | なし（実測: `<C-l>` を足すとマッピングが 103 個になり、`zenkaku` が動いた） |
| 利用者が `<Plug>(skkeleton-xxx)` に割り当てたキー | i / c / t | map（`<Plug>` の rhs から関数名を引き継ぐ）→ main（`enable` / `disable` / `toggle`。状態によっては keymap を通る） | `lua/skkeleton/map.lua:125-133`、`lua/skkeleton/main.lua:89-96,107-110,132-136,163-175`、`plugin/skkeleton.lua:20-24` | コード読解のみ |

## 3. `keymap.lua` の状態ごとの処理

`keymap.handle_key` は `ctx.state.type`（`input` / `henkan`）で表を選び、正規化したキーで関数を引きます。引けなければ default を使います（`lua/skkeleton/keymap.lua:64-88`）。`input` では、打ちかけの feed とキーがかなテーブルにあれば、キーマップよりかなテーブルを先に使います（`lua/skkeleton/keymap.lua:79-85`）。この表のキーは、§1 のマッピングが置かれている Vim モード（`i` / `c` / `t`）で効きます。

### input 状態（`type = "input"`）

| キー | Vim のモード | 処理する場所 | 根拠 | 未確認 |
|---|---|---|---|---|
| `<bs>`（`<BS>` / `<C-h>`） | i / c / t | keymap: deleteChar | `lua/skkeleton/keymap.lua:27` | なし（実測） |
| `<c-g>` | i / c / t | keymap: cancel | `lua/skkeleton/keymap.lua:28` | なし（実測） |
| `<cr>` | i / c / t | keymap: newline | `lua/skkeleton/keymap.lua:30` | なし（実測） |
| `<esc>` | i / c / t | keymap: escape（disable） | `lua/skkeleton/keymap.lua:31`、`lua/skkeleton/function/disable.lua:21-27` | なし（実測） |
| `<nl>`（`<C-j>`） | i / c / t | keymap: kakutei | `lua/skkeleton/keymap.lua:32` | なし（実測） |
| `<c-q>` | i / c / t | keymap: hankatakana | `lua/skkeleton/keymap.lua:33` | なし（実測） |
| `>` | i / c / t | keymap: prefix | `lua/skkeleton/keymap.lua:34` | コード読解のみ |
| `<space>` | i / c / t | keymap: henkanFirst | `lua/skkeleton/keymap.lua:35` | なし（実測） |
| `l` | i / c / t | keymap: disable（既定のかなテーブルのときだけ） | `lua/skkeleton/keymap.lua:37`、`lua/skkeleton/function/input.lua:122-145` | コード読解のみ |
| `q` | i / c / t | keymap: katakana（同上） | `lua/skkeleton/keymap.lua:38`、`lua/skkeleton/function/input.lua:122-145` | コード読解のみ |
| `;` | i / c / t | keymap: henkanPoint（同上） | `lua/skkeleton/keymap.lua:39`、`lua/skkeleton/function/input.lua:122-145` | コード読解のみ |
| `/` | i / c / t | keymap: abbrev（同上） | `lua/skkeleton/keymap.lua:40`、`lua/skkeleton/function/input.lua:122-145` | コード読解のみ |
| `L` | i / c / t | keymap: zenkaku（同上） | `lua/skkeleton/keymap.lua:41`、`lua/skkeleton/function/input.lua:122-145` | コード読解のみ |
| 上のどれでもない、§1・§2 で奪ったキー | i / c / t | keymap: default（kana_input） | `lua/skkeleton/keymap.lua:25,86`、`lua/skkeleton/function/input.lua:85-120` | なし（実測: `z` で `▽かんz`） |

### henkan 状態（`type = "henkan"`、▼）

henkan 状態の表にないキーは default の `henkanInput` に渡り、選択中の候補を確定してから、同じキーを input 状態として処理し直します（`lua/skkeleton/function/henkan.lua:160-161`）。そのため `<Esc>` や `<BS>` なども input の処理に落ちます。

| キー | Vim のモード | 処理する場所 | 根拠 | 未確認 |
|---|---|---|---|---|
| `<c-g>` | i / c / t | keymap: cancel | `lua/skkeleton/keymap.lua:47` | コード読解のみ |
| `<cr>` | i / c / t | keymap: newline | `lua/skkeleton/keymap.lua:48` | コード読解のみ |
| `<nl>`（`<C-j>`） | i / c / t | keymap: kakutei | `lua/skkeleton/keymap.lua:49` | コード読解のみ |
| `<space>` | i / c / t | keymap: henkanForward | `lua/skkeleton/keymap.lua:50` | なし（実測: 候補が進む） |
| `x` | i / c / t | keymap: henkanBackward | `lua/skkeleton/keymap.lua:51` | コード読解のみ |
| `X` | i / c / t | keymap: purgeCandidate | `lua/skkeleton/keymap.lua:52` | コード読解のみ |
| `>` | i / c / t | keymap: suffix | `lua/skkeleton/keymap.lua:53` | コード読解のみ |
| `a` `s` `d` `f` `j` `k` `l` | i / c / t | keymap に無い → default（henkanInput）で候補を選ぶ。候補の popup が出ているときだけ（`candidate_index >= showCandidatesCount`） | `lua/skkeleton/keymap.lua:44-55,86`、`lua/skkeleton/function/henkan.lua:137-158`、`lua/skkeleton/config.lua:29,32` | コード読解のみ |
| ほかの §1・§2 のキー（`<Esc>`、`<BS>`、文字など） | i / c / t | default（henkanInput）: 候補を確定してから input で処理し直す | `lua/skkeleton/keymap.lua:86`、`lua/skkeleton/function/henkan.lua:160-161` | なし（実測: `<Esc>` で確定して抜ける） |

## 4. `guard.lua` が見る K_SPECIAL

guard は `vim.on_key` で、マッピングに消費されずに素通りしてきたキーを見ます（`lua/skkeleton/guard.lua:139-189`、`lua/skkeleton/cleanup.lua:295`）。次の条件をすべて満たすときだけ、pre-edit を `<Esc>` と同じ形で確定してからキーを流し直します（`lua/skkeleton/guard.lua:174-188`）。

- `typed ~= ""`（打鍵。feedkeys で流したキーではない）`lua/skkeleton/guard.lua:146-149`
- いまの Vim モードが `i` / `c` / `t` `lua/skkeleton/guard.lua:150-153`
- `g:skkeleton#enabled` が真 `lua/skkeleton/guard.lua:174-177`
- `g:skkeleton#state.preedit` が空でない `lua/skkeleton/guard.lua:178-182`

| K_SPECIAL（バイト） | Vim のモード | 処理する場所 | 根拠 | 未確認 |
|---|---|---|---|---|
| `0x80 0xfd 0x67`（KS_EXTRA の KE_LUA。skkeleton が置いた Lua callback マッピング） | i / c / t | guard は何もしない（マッピングが処理する） | `lua/skkeleton/guard.lua:43-45,140-142` | なし（実測: `<C-g>` などで pre-edit が残る） |
| `<Insert>`（`0x80 0x6b 0x49`） | i | guard は何もしない。Neovim が置換モードに入り、後片付けが pre-edit を確定して無効にする | `lua/skkeleton/guard.lua:15-16,143-145`、`lua/skkeleton/cleanup.lua:182-183,207-214` | なし（実測: `tests/test_e2e_guard.lua:82-89`） |
| `0x80 0xfe`（KS_SPECIAL。本文中の 0x80 のエスケープ） | i / c / t | guard は何もしない（キーではない） | `lua/skkeleton/guard.lua:55-58` | なし（実測: `tests/test_guard.lua:36-41`） |
| `0x80 0xfd` で、`<S-Up>` `<S-Down>` `<S-Left>` `<S-Right>` `<C-Left>` `<C-Right>` `<S-F1>`〜`<S-F12>` | i / c / t | guard が確定してからキーを流し直す | `lua/skkeleton/guard.lua:22-37,59-61,165-188` | なし（実測: `<C-Left>` は `tests/test_e2e_guard.lua:42-48`） |
| `0x80 0xfd` のその他（`<ScrollWheelUp>` `0x80 0xfd 0x4b`、`<ScrollWheelDown>` `0x80 0xfd 0x4c`、マウスの押下 `0x80 0xfd 0x2c`、離す `0x80 0xfd 0x2e` など） | i / c / t | guard は確定しない | `lua/skkeleton/guard.lua:59-61` | なし（実測: wheel で pre-edit が残り、クリックではカーソル移動の後片付けが確定する。§5） |
| `0x80 0xfc`（KS_MODIFIER）で、Ctrl + 英数字（`<C-r>` `<C-v>` `<C-k>` `<C-t>` `<C-w>` `<C-u>` `<C-a>` `<C-n>` `<C-p>` `<C-x>` `<C-y>` `<C-e>` など）と Ctrl + 記号 `[` `\` `]` `^` `_` `@` `?` | i / c（`t` は下の KS_MODIFIER の行） | guard は確定しない（Neovim に渡す） | `lua/skkeleton/guard.lua:66-84` | コード読解のみ（単バイトで届く `<C-r>` などは実測で false） |
| `0x80 0xfc` で、上の条件に合わないもの（Ctrl + 記号の `<C-.>`、Ctrl + `<Space>`、Alt / Meta / Cmd 付き、base が文字でないもの、`<S-CR>`） | i / c / t | guard が確定してからキーを流し直す | `lua/skkeleton/guard.lua:66-84` | `<C-.>` は実測（`tests/test_e2e_guard.lua:26-32`）。`<S-CR>` はコード読解のみ（判定は `tests/test_guard.lua:13-17` の単体テストで確認、E2E は未確認） |
| `0x80` のあとが `0xfc` `0xfd` `0xfe` 以外（termcap 系。`<Left>`、`<Right>`、`<Up>`、`<Down>`、`<Home>`、`<End>`、`<PageUp>`、`<PageDown>`、`<F5>`、`<S-Tab>` など） | i / c / t | guard が確定してからキーを流し直す | `lua/skkeleton/guard.lua:62-65` | なし（実測: `<Left>` `<F5>`） |
| `0x80 0xff 0x58`（NUL のエスケープ。`<C-@>`） | i / c / t | guard が確定してからキーを流し直す（termcap 扱いの fallback に入る） | `lua/skkeleton/guard.lua:62-65` | なし（実測: `guard._is_physical_special` は true。UI から打つと確定のあと Neovim の `i_CTRL-@` が E29 で insert を抜ける） |
| terminal の単バイト制御（`0x00`〜`0x1f`、`0x7f`）で、`0x07` `0x08` `0x09` `0x0a` `0x0d` `0x1b` 以外 | t | guard が確定してからキーを流し直す | `lua/skkeleton/guard.lua:89-96,103-112` | なし（実測: `<C-a>` は `tests/test_e2e_guard.lua:102-121`） |
| terminal の単バイト `0x07`（`<C-g>`）`0x08`（`<BS>`）`0x09`（`<Tab>`）`0x0a`（`<NL>`）`0x0d`（`<CR>`）`0x1b`（`<Esc>`） | t | guard は確定しない（skkeleton 自身の書き直しと区別できないため） | `lua/skkeleton/guard.lua:89-96,107-110` | なし（コード読解。`<Tab>` は `tests/test_guard.lua:31-33`） |
| terminal の `0x80 0xfc`（KS_MODIFIER。Ctrl + 文字） | t | guard が確定してからキーを流し直す | `lua/skkeleton/guard.lua:99-112,168-170` | コード読解のみ（実端末の Ctrl が KS_MODIFIER で届くかは端末しだい） |
| terminal の `<C-\>`（`0x1c` か `0x80 0xfc ... 0x5c`）に続く `<C-n>`（`0x0e` か `0x80 0xfc ... 0x4e`/`0x6e`） | t | guard は確定しない（terminal-normal に抜ける） | `lua/skkeleton/guard.lua:114-124,154-163` | なし（実測: `tests/test_e2e_cmdline.lua:147-172`） |

補足です。

- `map.lua` が置いたキーは Lua callback マッピングなので、`on_key` には `0x80 0xfd 0x67` で届きます（実測）。`<BS>` や `<Left>` の termcode が物理キーの K_SPECIAL でも、マッピングがあるキーはこの形になるため guard は確定しません。
- `<Mouse>` の表記の termcode は `0x80 0xfb 0x58` ですが、UI から届く実際のマウス押下は `0x80 0xfd 0x2c` でした（実測）。guard は実際のバイトで判定するので、マウスでは確定しません。確定はカーソル移動の後片付け（`lua/skkeleton/cleanup.lua:120-160` の `reset_if_stale`、`lua/skkeleton/cleanup.lua:129-131`）で起きます。
- `<BS>` の termcode も termcap 系（`0x80 0x6b 0x62`）ですが、§1 で奪うキーなので、実際は KE_LUA（`0x80 0xfd 0x67`）で届きます。
- `<C-@>` は NUL のエスケープ `0x80 0xff 0x58` で届き、guard の「`0xfc` 以外は termcap 系」という fallback に当たって物理キー扱いになります（実測）。`<C-a>` と `<C-@>` の E29 は #179 の「ここでは決めないこと」に含まれるので、ここでは今の振る舞いだけを書きました。

## 5. skkeleton が奪わず、Neovim が処理するキー

§1・§2 に無いキーは、モードごとに Neovim（cmdline・terminal ではその機能）が処理します。guard が確定するものとしないものは §4 のとおりです。

| キー | Vim のモード | 処理する場所 | 根拠 | 未確認 |
|---|---|---|---|---|
| `<C-r>` | i / c（t は §4） | Neovim（`i_CTRL-R`）。guard は確定しない | `lua/skkeleton/guard.lua:78-80`、`lua/skkeleton/map.lua:13-23` | なし（実測） |
| `<C-v>` | i | Neovim（`i_CTRL-V`）。guard は確定しない | 同上 | なし（実測） |
| `<C-k>` | i | Neovim（`i_CTRL-K` の digraph）。guard は確定しない | 同上 | なし（実測） |
| `<C-t>` | i | Neovim（`i_CTRL-T` のインデント）。guard は確定しない | 同上 | なし（実測） |
| `<Tab>` | i / c | Neovim。terminal では guard の対象外（§4） | `lua/skkeleton/guard.lua:89-96`、`lua/skkeleton/map.lua:13-23` | なし（実測） |
| `<C-w>` | i | Neovim（`i_CTRL-W`）。guard は確定しない | `lua/skkeleton/guard.lua:78-80` | なし（実測） |
| `<C-u>` | i | Neovim（`i_CTRL-U`）。guard は確定しない | 同上 | なし（実測） |
| `<C-a>` | i | Neovim（`i_CTRL-A`）。guard は確定しない | 同上 | なし（実測） |
| `<C-@>` | i | guard が確定してから Neovim（`i_CTRL-@`） | §4 の `0x80 0xff 0x58` の行 | なし（実測: 読みを確定してから E29 で insert を抜ける） |
| `<C-c>` | i / c | Neovim（insert / cmdline を抜ける）。insert を抜けたあとに後片付けが確定する | `lua/skkeleton/cleanup.lua:179-222,225-250`、`lua/skkeleton/cleanup.lua:63-67` | なし（実測: `tests/test_e2e_mode.lua:303-310`） |
| `<C-o>` | i | Neovim（insert-normal）。戻ったときにずれていれば確定する | `lua/skkeleton/cleanup.lua:179-187,120-131`、`tests/test_e2e_input.lua:399-411` | なし（実測: `<C-o>l` で確定） |
| `<C-n>` `<C-p>` `<C-x>` | i | Neovim の補完（`ic`）。blink.cmp が入っていれば blink のキー | `lua/skkeleton/map.lua:13-23`、`lua/skkeleton/cleanup.lua:283-286` | なし（実測: `<C-n>` `<C-p>` `<C-x><C-n>` で `ic` に入り pre-edit が消える。`<C-x>` だけなら `ix` で pre-edit が残る）。blink の既定キーは #190 で実測 |
| `<C-y>` `<C-e>` | i | Neovim（補完のメニューが無いとき）。メニューがあれば補完の確定・取消 | `lua/skkeleton/map.lua:13-23` | なし（実測: メニューが無ければ pre-edit が残る。メニューがあれば `ic` から `i` に戻る） |
| `<CR>`（blink のメニューで項目を選んでいるとき） | i | skkeleton が blink に回す（`eggLikeNewline` が真のとき） | `lua/skkeleton/main.lua:84-87`、`lua/skkeleton/completion/init.lua:278-310`、`doc/skkeleton.txt:516-518` | 未確認（blink.cmp が要る） |
| マウスの押下・離す・ドラッグ（`<LeftMouse>` など。実イベントは `0x80 0xfd 0x2c` / `0x2e`） | i | Neovim。guard は確定しない。カーソルが動けば後片付けが確定し、visual に入れば確定して無効化する | `lua/skkeleton/guard.lua:59-61`、`lua/skkeleton/cleanup.lua:120-160,179-222` | なし（実測: 1 回クリックで確定、ダブルクリックは `tests/test_e2e_mode.lua:319-338`） |
| `<ScrollWheelUp>` `<ScrollWheelDown>`（`0x80 0xfd 0x4b` / `0x4c`） | i | Neovim（スクロール）。guard は確定しない | `lua/skkeleton/guard.lua:59-61` | なし（実測: pre-edit が残る） |
| `<Plug>(skkeleton-enable)` `<Plug>(skkeleton-disable)` `<Plug>(skkeleton-toggle)` | i / c / t | plugin が置く入口。利用者が好きなキーに割り当てる | `plugin/skkeleton.lua:21-25`、`doc/skkeleton.txt:192-206` | なし（実測: `e2e_set` の子で enable に使える） |
| `q` | n | Neovim（マクロの記録の開始・停止）。skk は normal にマッピングを置かない | `lua/skkeleton/map.lua:123-137`、`semantics/explore/repeat.lua` | なし（実測: `qa` のあと `reg_recording()` が `a` になる） |
| `@` | n | Neovim（マクロの実行）。skk は normal にマッピングを置かない | 同上 | なし（実測: `@a` で再生） |
| `.` | n | Neovim（直前の変更の繰り返し）。skk は normal にマッピングを置かない | 同上 | なし（実測） |

補足です。

- 補完のキー自体は skkeleton のどこにもマッピングがありません（実測: 102 個の一覧に入っていない）。skkeleton が関わるのは `<CR>` の 1 か所だけで、blink のメニューが開いていて項目を選んでいるときに限ります（`lua/skkeleton/main.lua:84-87`）。blink.cmp のキー割り当ては skkeleton の外です。
- `<C-h>` は §1 で奪うキーです。`<C-r>` などの単バイト制御は、insert と cmdline では奪いません（terminal は §4 の guard が確定します）。
- `q` `@` `.` は、insert / cmdline / terminal では §1 の skk のキーです。normal の `q` `@` `.` は §5 のとおり Neovim が処理し、skk の状態は変えません（#192）。

## 6. 観測した振る舞い

一時辞書の子 nvim で、`abc` の行末に `▽かn` を出してからキーを 1 つ打ち、そのあとの pre-edit、バッファ、モードを読みました（insert の行は Neovim 0.12.0、cmdline の行は 0.11.6）。

確かめ方は、既存の E2E テスト（`tests/test_e2e_guard.lua`、`tests/test_e2e_cmdline.lua`、`tests/test_e2e_mode.lua`）と同じです。MiniTest の子 nvim に一時ディレクトリの辞書を渡し、キーを打ってから状態を読みました。既存の期待値は `make test FILE=tests/test_e2e_guard.lua` などで流せます。`<C-r>` はレジスタ `a` に `XYZ` を入れてから打っています。pre-edit が消えた場合は、読みが確定したのか捨てられたのかをバッファで分けました。

| キー | Vim のモード | 打つ前 | 打ったあと | 未確認 |
|---|---|---|---|---|
| `<C-r>a` | i | `▽かn` | バッファ `abcXYZ`、pre-edit が消える（読みは捨てられる） | なし（実測） |
| `<C-v>065` | i | `▽かn` | バッファ `abcA`、読みは捨てられる | なし（実測） |
| `<C-k>a:` | i | `▽かn` | バッファ `abcä`、読みは捨てられる | なし（実測） |
| `<C-t>` | i | `▽かn` | バッファ `\tabc`、読みは捨てられる | なし（実測） |
| `<Tab>` | i | `▽かn` | バッファ `abc\t`、読みは捨てられる | なし（実測） |
| `<C-w>` | i | `▽かn` | バッファが空、読みは捨てられる | なし（実測） |
| `<C-u>` | i | `▽かn` | バッファが空、読みは捨てられる | なし（実測） |
| `<C-a>` | i | `▽かn` | バッファ `abcPQ`（直前に入れた文字列）、読みは捨てられる | なし（実測） |
| `<C-@>` | i | `▽かn` | バッファ `abcかん`（読みを確定）→ E29。insert を抜けて無効になる | なし（実測） |
| `<C-n>` `<C-p>` `<C-x><C-n>` | i | `▽かn` | pre-edit が消える（`ic` に入る。読みは確定しない） | なし（実測: #190） |
| `<C-x>` | i | `▽かn` | pre-edit が残る（`ix` のキー待ち） | なし（実測: #190） |
| `<C-e>` `<C-y>` | i | `▽かn` | 補完のメニューが無ければ pre-edit が残る | なし（実測） |
| `<C-o>l` | i | `▽かn` | バッファ `abcかん`、pre-edit が消える（カーソル移動で確定） | なし（実測） |
| マウスの左クリック（1 回） | i | `▽かn` | バッファ `hello worldかん`、pre-edit が消える（カーソル移動で確定）。insert のまま | なし（実測） |
| ホイール上 | i | `▽かn` | pre-edit が残る | なし（実測） |
| `<C-r>a` | c | `▽かn` | cmdline が `XYZ` になり、pre-edit が消える | なし（実測） |
| `<C-v>065` | c | `▽かn` | cmdline が `A`、pre-edit が消える | なし（実測） |
| `<C-k>a:` | c | `▽かn` | cmdline が `ä`、pre-edit が消える | なし（実測） |
| `<C-t>` | c | `▽かn` | cmdline が `^T`、pre-edit が消える | なし（実測） |
| `<Tab>` | c | `▽かn` | cmdline が `▽かn` のまま、pre-edit が残る | なし（実測） |
| `<C-w>` `<C-u>` | c | `▽かn` | cmdline が空、pre-edit が消える | なし（実測） |
| `<C-a>` `<C-e>` `<C-n>` | c | `▽かn` | cmdline が `▽かn` のまま、pre-edit が残る | なし（実測） |
| `<C-y>` | c | `▽かn` | cmdline が制御文字 `0x19` になり、pre-edit が消える | なし（実測） |
| `<C-p>` | c | `▽かn` | 一致する cmdline の履歴（`かん`）があるときだけ cmdline が `かん` になり、pre-edit が消える。履歴が無いときは何も変わらない | なし（実測） |
| `<C-@>` | c | `▽かn` | cmdline が `かん` と改行になり、pre-edit が消える | なし（実測） |
| `<C-c>` | c | `▽かn` | cmdline を抜けて無効になる | なし（実測） |

補足です。

- insert と cmdline では、バッファや cmdline の文字が変わると、`TextChangedI` / `TextChangedP` / `CmdlineChanged` の後片付け（`lua/skkeleton/cleanup.lua:120-160,283-286`）が pre-edit のずれを直します。このとき読みは確定ではなく捨てられます（`reset_if_stale` の `mode_mod.initialize_state_with_abbrev`）。
- 文字が変わらないキー（`<C-w>` や `<C-u>` で消す文字が無いとき、`<Tab>` が cmdline で効かないとき）は pre-edit が残ります。

## 7. 未確認のこと

- Neovim 0.11.6 と 0.12.0 の違い。insert の制御キー、マウス、ホイール、`<C-@>` は両方の版で同じ結果でしたが、cmdline の細かい結果は 0.11.6 でだけ観測しました。
- 実端末が Ctrl + 文字を KS_MODIFIER（`0x80 0xfc`）で送るか、単バイトで送るか。guard は両方を見ますが、観測したのは単バイトだけです（`tests/test_guard.lua:25-34` は termcode で確かめています）。
- blink.cmp のキー割り当て。skkeleton は `<CR>` 以外の補完キーに関与しません。
- `<C-@>` と `<C-Space>` を確定の対象にするか。§4 の fallback の結果で、#179 の「ここでは決めないこと」に含まれます。
- `<Plug>(skkeleton-xxx)` にキーを割り当てたときの関数の引き継ぎ（`lua/skkeleton/map.lua:125-133`）は、打って確かめていません。

## 完了の条件との対応

- `map.lua` に出てくるキー: §1 に 102 個をすべて並べました（文字の範囲は列挙しています）。`<lt>`、`<Bar>`、`<BS>`、`<C-h>`、`<CR>`、`<Space>`、`<C-q>`、`<C-j>`、`<C-g>`、`<Esc>` も個別の行があります。
- `guard.lua` に出てくるキー: §4 に `<Insert>`、`<S-Up>`〜`<S-Right>`、`<C-Left>`、`<C-Right>`、`<S-F1>`〜`<S-F12>`、`<C-\>`、`<C-n>` と、K_SPECIAL の各クラスを並べました。
- 表を作った基準のコミット: 冒頭に `ac567ab22e418401d1a3e6240263091fa7dde8dd` と書きました。
