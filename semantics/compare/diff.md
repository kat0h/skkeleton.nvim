# モデルと観測の差（`probe.lua` の結果）

- 観測: 616 件（一致 178 / 不一致 0 / 観測できず 38）
- モデルにだけある遷移: 332
- 観測にだけある遷移: 328（説明付き 328 / 説明なし 0）
- effects の食い違い: 0
- 非決定: 36 組

## 未確定（モデルが決めていない遷移）

| 観測 | 前 | キー | 観測の終わり | モデル |
|---|---|---|---|---|
| `p.t.I_POINT.key_gt` | `I_POINT` | `>` | `P_PROMPT` | `I_SELECT` |
| `p.t.I_SELECT.key_gt` | `I_SELECT` | `>` | `I_POINT` | `I_SELECT` |

## 観測にだけある遷移

| 観測 | 前 | キー | 後 | 説明 |
|---|---|---|---|---|
| `c.feed.I_ROMAJI._Space_` | `I_ROMAJI` | `<Space>` | `I_ROMAJI` | モデルに無い自己遷移（観測では何も変わらない） |
| `c.feed.I_ROMAJI_EMPTY._Space_` | `I_ROMAJI` | `<Space>` | `I_ROMAJI` | モデルに無い自己遷移（観測では何も変わらない） |
| `c.idle.N_OFF._` | `N_OFF` | `:` | `C_DIRECT` | cmdline の中（07a #187） |
| `c.idle.N_OFF._C_g_` | `N_OFF` | `<C-g>` | `N_OFF` | モデルに無い自己遷移（観測では何も変わらない） |
| `c.idle.N_OFF._C_j_` | `N_OFF` | `<C-j>` | `N_OFF` | モデルに無い自己遷移（観測では何も変わらない） |
| `c.idle.N_OFF._C_o_` | `N_OFF` | `<C-o>` | `N_OFF` | モデルに無い自己遷移（観測では何も変わらない） |
| `c.idle.N_OFF.v` | `N_OFF` | `v` | `N_OFF` | モデルに無い自己遷移（観測では何も変わらない） |
| `c.idle.V_IDLE.R` | `V_IDLE` | `R` | `I_DIRECT` | visual / select の Vim のコマンド。モデルは <Esc> で insert に戻る道だけを書いている |
| `c.idle.V_IDLE._` | `V_IDLE` | `:` | `C_DIRECT` | cmdline の中（07a #187） |
| `c.idle.V_IDLE._C_g_` | `V_IDLE` | `<C-g>` | `V_IDLE` | モデルに無い自己遷移（観測では何も変わらない） |
| `c.idle.V_IDLE._C_j_` | `V_IDLE` | `<C-j>` | `V_IDLE` | モデルに無い自己遷移（観測では何も変わらない） |
| `c.idle.V_IDLE._C_o_` | `V_IDLE` | `<C-o>` | `V_IDLE` | モデルに無い自己遷移（観測では何も変わらない） |
| `c.idle.V_IDLE.v` | `V_IDLE` | `v` | `I_DIRECT` | visual / select の Vim のコマンド。モデルは <Esc> で insert に戻る道だけを書いている |
| `c.ioff.I_OFF.K` | `I_OFF` | `K` | `I_OFF` | skk が無効な insert / replace。キーは Vim がそのまま処理する（モデルは無効な状態からのキー入力を書いていない） |
| `c.ioff.I_OFF._C_o_` | `I_OFF` | `<C-o>` | `NI` | Vim のモード遷移（無効な insert / replace から <C-o> で niI・visual・replace へ）。モデルは無効な状態からのモード遷移を書いていない |
| `c.ioff.I_OFF._Space_` | `I_OFF` | `<Space>` | `I_OFF` | skk が無効な insert / replace。キーは Vim がそのまま処理する（モデルは無効な状態からのキー入力を書いていない） |
| `c.ioff.I_OFF.a` | `I_OFF` | `a` | `I_OFF` | skk が無効な insert / replace。キーは Vim がそのまま処理する（モデルは無効な状態からのキー入力を書いていない） |
| `c.ni.NI_DIRECT.X` | `NI` | `X` | `I_DIRECT` | niI の normal コマンド。モデルは効果で ni_return_keep / commit / drop にまとめていて、キーの一覧は代表だけ |
| `c.ni.NI_DIRECT._BS_` | `NI` | `<BS>` | `I_DIRECT` | niI の normal コマンド。モデルは効果で ni_return_keep / commit / drop にまとめていて、キーの一覧は代表だけ |
| `c.ni.NI_DIRECT._C_g_` | `NI` | `<C-g>` | `I_DIRECT` | niI の normal コマンド。モデルは効果で ni_return_keep / commit / drop にまとめていて、キーの一覧は代表だけ |
| `c.ni.NI_DIRECT._C_j_` | `NI` | `<C-j>` | `I_DIRECT` | niI の normal コマンド。モデルは効果で ni_return_keep / commit / drop にまとめていて、キーの一覧は代表だけ |
| `c.ni.NI_DIRECT._C_o_R` | `NI` | `<C-o>R` | `I_ROMAJI` | niI の normal コマンド。モデルは効果で ni_return_keep / commit / drop にまとめていて、キーの一覧は代表だけ |
| `c.ni.NI_DIRECT._C_o_v` | `NI` | `<C-o>v` | `I_ROMAJI` | niI の normal コマンド。モデルは効果で ni_return_keep / commit / drop にまとめていて、キーの一覧は代表だけ |
| `c.ni.NI_DIRECT._Esc_` | `NI` | `<Esc>` | `I_DIRECT` | niI の normal コマンド。モデルは効果で ni_return_keep / commit / drop にまとめていて、キーの一覧は代表だけ |
| `c.ni.NI_DIRECT._Space_` | `NI` | `<Space>` | `I_DIRECT` | niI の normal コマンド。モデルは効果で ni_return_keep / commit / drop にまとめていて、キーの一覧は代表だけ |
| `c.ni.NI_DIRECT.a` | `NI` | `a` | `I_DIRECT` | niI の normal コマンド。モデルは効果で ni_return_keep / commit / drop にまとめていて、キーの一覧は代表だけ |
| `c.ni.NI_POINT.X` | `NI` | `X` | `I_POINT` | niI の normal コマンド。モデルは効果で ni_return_keep / commit / drop にまとめていて、キーの一覧は代表だけ |
| `c.ni.NI_POINT._BS_` | `NI` | `<BS>` | `I_POINT` | niI の normal コマンド。モデルは効果で ni_return_keep / commit / drop にまとめていて、キーの一覧は代表だけ |
| `c.ni.NI_POINT._C_g_` | `NI` | `<C-g>` | `I_POINT` | niI の normal コマンド。モデルは効果で ni_return_keep / commit / drop にまとめていて、キーの一覧は代表だけ |
| `c.ni.NI_POINT._C_j_` | `NI` | `<C-j>` | `I_POINT` | niI の normal コマンド。モデルは効果で ni_return_keep / commit / drop にまとめていて、キーの一覧は代表だけ |
| `c.ni.NI_POINT._C_o_R` | `NI` | `<C-o>R` | `I_POINT` | niI の normal コマンド。モデルは効果で ni_return_keep / commit / drop にまとめていて、キーの一覧は代表だけ |
| `c.ni.NI_POINT._C_o_v` | `NI` | `<C-o>v` | `I_POINT` | niI の normal コマンド。モデルは効果で ni_return_keep / commit / drop にまとめていて、キーの一覧は代表だけ |
| `c.ni.NI_POINT._Esc_` | `NI` | `<Esc>` | `I_POINT` | niI の normal コマンド。モデルは効果で ni_return_keep / commit / drop にまとめていて、キーの一覧は代表だけ |
| `c.ni.NI_POINT._Space_` | `NI` | `<Space>` | `I_POINT` | niI の normal コマンド。モデルは効果で ni_return_keep / commit / drop にまとめていて、キーの一覧は代表だけ |
| `c.ni.NI_POINT.a` | `NI` | `a` | `I_POINT` | niI の normal コマンド。モデルは効果で ni_return_keep / commit / drop にまとめていて、キーの一覧は代表だけ |
| `c.ni.NI_SELECT.X` | `NI` | `X` | `I_SELECT` | niI の normal コマンド。モデルは効果で ni_return_keep / commit / drop にまとめていて、キーの一覧は代表だけ |
| `c.ni.NI_SELECT._BS_` | `NI` | `<BS>` | `I_SELECT` | niI の normal コマンド。モデルは効果で ni_return_keep / commit / drop にまとめていて、キーの一覧は代表だけ |
| `c.ni.NI_SELECT._C_g_` | `NI` | `<C-g>` | `I_SELECT` | niI の normal コマンド。モデルは効果で ni_return_keep / commit / drop にまとめていて、キーの一覧は代表だけ |
| `c.ni.NI_SELECT._C_j_` | `NI` | `<C-j>` | `I_SELECT` | niI の normal コマンド。モデルは効果で ni_return_keep / commit / drop にまとめていて、キーの一覧は代表だけ |
| `c.ni.NI_SELECT._C_o_R` | `NI` | `<C-o>R` | `I_ROMAJI` | niI の normal コマンド。モデルは効果で ni_return_keep / commit / drop にまとめていて、キーの一覧は代表だけ |
| `c.ni.NI_SELECT._C_o_v` | `NI` | `<C-o>v` | `I_ROMAJI` | niI の normal コマンド。モデルは効果で ni_return_keep / commit / drop にまとめていて、キーの一覧は代表だけ |
| `c.ni.NI_SELECT._Esc_` | `NI` | `<Esc>` | `I_SELECT` | niI の normal コマンド。モデルは効果で ni_return_keep / commit / drop にまとめていて、キーの一覧は代表だけ |
| `c.ni.NI_SELECT._Space_` | `NI` | `<Space>` | `I_SELECT` | niI の normal コマンド。モデルは効果で ni_return_keep / commit / drop にまとめていて、キーの一覧は代表だけ |
| `c.ni.NI_SELECT.a` | `NI` | `a` | `I_SELECT` | niI の normal コマンド。モデルは効果で ni_return_keep / commit / drop にまとめていて、キーの一覧は代表だけ |
| `d.disputed.ctrl-o-v-esc` | `I_POINT` | `<C-o>v,<Esc>` | `I_POINT` | モデルに無い自己遷移（観測では何も変わらない） |
| `d.disputed.ctrl-o-v-esc-select` | `I_SELECT` | `<C-o>v,<Esc>` | `I_SELECT` | モデルに無い自己遷移（観測では何も変わらない） |
| `d.register.commit` | `P_PROMPT` | `tesuto,<CR>` | `I_DIRECT` | 辞書登録のプロンプトの中（07c #189） |
| `x.IC.K` | `IC` | `K` | `I_ROMAJI` | 組み込みの補完の中（07d #190） |
| `x.IC.R` | `IC` | `R` | `I_ROMAJI` | 組み込みの補完の中（07d #190） |
| `x.IC._` | `IC` | `.` | `I_DIRECT` | 組み込みの補完の中（07d #190） |
| `x.IC._BS_` | `IC` | `<BS>` | `IC` | 組み込みの補完の中（07d #190） |
| `x.IC._C_g_` | `IC` | `<C-g>` | `IC` | 組み込みの補完の中（07d #190） |
| `x.IC._C_j_` | `IC` | `<C-j>` | `IC` | 組み込みの補完の中（07d #190） |
| `x.IC._C_k_a_` | `IC` | `<C-k>a:` | `I_DIRECT` | 組み込みの補完の中（07d #190） |
| `x.IC._C_o_` | `IC` | `<C-o>` | `NI` | 組み込みの補完の中（07d #190） |
| `x.IC._C_o_R` | `IC` | `<C-o>R` | `R_OFF` | 組み込みの補完の中（07d #190） |
| `x.IC._C_o___CR_` | `IC` | `<C-o>:<CR>` | `I_DIRECT` | cmdline の中（07a #187） |
| `x.IC._C_o___Esc_` | `IC` | `<C-o>:<Esc>` | `I_DIRECT` | cmdline の中（07a #187） |
| `x.IC._C_o_v` | `IC` | `<C-o>v` | `V_IDLE` | 組み込みの補完の中（07d #190） |
| `x.IC._C_r_a` | `IC` | `<C-r>a` | `I_DIRECT` | 組み込みの補完の中（07d #190） |
| `x.IC._C_u_` | `IC` | `<C-u>` | `I_DIRECT` | 組み込みの補完の中（07d #190） |
| `x.IC._C_v_065` | `IC` | `<C-v>065` | `I_DIRECT` | 組み込みの補完の中（07d #190） |
| `x.IC._C_w_` | `IC` | `<C-w>` | `I_DIRECT` | 組み込みの補完の中（07d #190） |
| `x.IC._Insert_` | `IC` | `<Insert>` | `R_OFF` | 組み込みの補完の中（07d #190） |
| `x.IC._Left_` | `IC` | `<Left>` | `I_DIRECT` | 組み込みの補完の中（07d #190） |
| `x.IC._S_Tab_` | `IC` | `<S-Tab>` | `I_DIRECT` | 組み込みの補完の中（07d #190） |
| `x.IC._Space_` | `IC` | `<Space>` | `I_DIRECT` | 組み込みの補完の中（07d #190） |
| `x.IC._Tab_` | `IC` | `<Tab>` | `I_DIRECT` | 組み込みの補完の中（07d #190） |
| `x.IC.a` | `IC` | `a` | `I_DIRECT` | 組み込みの補完の中（07d #190） |
| `x.IC.l` | `IC` | `l` | `IC` | 組み込みの補完の中（07d #190） |
| `x.IC.x` | `IC` | `x` | `IC` | 組み込みの補完の中（07d #190） |
| `x.I_OFF.K` | `I_OFF` | `K` | `I_OFF` | skk が無効な insert / replace。キーは Vim がそのまま処理する（モデルは無効な状態からのキー入力を書いていない） |
| `x.I_OFF.R` | `I_OFF` | `R` | `I_OFF` | skk が無効な insert / replace。キーは Vim がそのまま処理する（モデルは無効な状態からのキー入力を書いていない） |
| `x.I_OFF._` | `I_OFF` | `.` | `I_OFF` | マクロと `.` の繰り返し（07f #192） |
| `x.I_OFF._BS_` | `I_OFF` | `<BS>` | `I_OFF` | モデルに無い自己遷移（観測では何も変わらない） |
| `x.I_OFF._C_c_` | `I_OFF` | `<C-c>` | `N_OFF` | Vim の <C-c>（insert / replace を抜けて normal に戻る）。無効なのでモデルに無い |
| `x.I_OFF._C_j_` | `I_OFF` | `<C-j>` | `I_OFF` | skk が無効な insert / replace。キーは Vim がそのまま処理する（モデルは無効な状態からのキー入力を書いていない） |
| `x.I_OFF._C_k_a_` | `I_OFF` | `<C-k>a:` | `I_OFF` | skk が無効な insert / replace。キーは Vim がそのまま処理する（モデルは無効な状態からのキー入力を書いていない） |
| `x.I_OFF._C_n_` | `I_OFF` | `<C-n>` | `IC` | 組み込みの補完の中（07d #190） |
| `x.I_OFF._C_o_` | `I_OFF` | `<C-o>` | `NI` | Vim のモード遷移（無効な insert / replace から <C-o> で niI・visual・replace へ）。モデルは無効な状態からのモード遷移を書いていない |
| `x.I_OFF._C_o_R` | `I_OFF` | `<C-o>R` | `R_OFF` | Vim のモード遷移（無効な insert / replace から <C-o> で niI・visual・replace へ）。モデルは無効な状態からのモード遷移を書いていない |
| `x.I_OFF._C_o___CR_` | `I_OFF` | `<C-o>:<CR>` | `I_OFF` | cmdline の中（07a #187） |
| `x.I_OFF._C_o___Esc_` | `I_OFF` | `<C-o>:<Esc>` | `I_OFF` | cmdline の中（07a #187） |
| `x.I_OFF._C_o_v` | `I_OFF` | `<C-o>v` | `N_OFF` | Vim のモード遷移（無効な insert / replace から <C-o> で niI・visual・replace へ）。モデルは無効な状態からのモード遷移を書いていない |
| `x.I_OFF._C_r_a` | `I_OFF` | `<C-r>a` | `I_OFF` | skk が無効な insert / replace。キーは Vim がそのまま処理する（モデルは無効な状態からのキー入力を書いていない） |
| `x.I_OFF._C_u_` | `I_OFF` | `<C-u>` | `I_OFF` | モデルに無い自己遷移（観測では何も変わらない） |
| `x.I_OFF._C_v_065` | `I_OFF` | `<C-v>065` | `I_OFF` | skk が無効な insert / replace。キーは Vim がそのまま処理する（モデルは無効な状態からのキー入力を書いていない） |
| `x.I_OFF._C_w_` | `I_OFF` | `<C-w>` | `I_OFF` | モデルに無い自己遷移（観測では何も変わらない） |
| `x.I_OFF._C_y_` | `I_OFF` | `<C-y>` | `I_OFF` | モデルに無い自己遷移（観測では何も変わらない） |
| `x.I_OFF._Space_` | `I_OFF` | `<Space>` | `I_OFF` | skk が無効な insert / replace。キーは Vim がそのまま処理する（モデルは無効な状態からのキー入力を書いていない） |
| `x.I_OFF._Tab_` | `I_OFF` | `<Tab>` | `I_OFF` | skk が無効な insert / replace。キーは Vim がそのまま処理する（モデルは無効な状態からのキー入力を書いていない） |
| `x.I_OFF.a` | `I_OFF` | `a` | `I_OFF` | skk が無効な insert / replace。キーは Vim がそのまま処理する（モデルは無効な状態からのキー入力を書いていない） |
| `x.I_OFF.l` | `I_OFF` | `l` | `I_OFF` | skk が無効な insert / replace。キーは Vim がそのまま処理する（モデルは無効な状態からのキー入力を書いていない） |
| `x.I_OFF.x` | `I_OFF` | `x` | `I_OFF` | skk が無効な insert / replace。キーは Vim がそのまま処理する（モデルは無効な状態からのキー入力を書いていない） |
| `x.I_ROMAJI._Space_` | `I_ROMAJI` | `<Space>` | `I_ROMAJI` | モデルに無い自己遷移（観測では何も変わらない） |
| `x.I_ROMAJI_EMPTY._Space_` | `I_ROMAJI` | `<Space>` | `I_ROMAJI` | モデルに無い自己遷移（観測では何も変わらない） |
| `x.I_ROMAJI_KEEP._Space_` | `I_OFF` | `<Space>` | `I_OFF` | skk が無効な insert / replace。キーは Vim がそのまま処理する（モデルは無効な状態からのキー入力を書いていない） |
| `x.I_ROMAJI_TEXT._Space_` | `I_ROMAJI` | `<Space>` | `I_ROMAJI` | モデルに無い自己遷移（観測では何も変わらない） |
| `x.NI_DIRECT._` | `NI` | `.` | `I_DIRECT` | マクロと `.` の繰り返し（07f #192） |
| `x.NI_DIRECT._BS_` | `NI` | `<BS>` | `I_DIRECT` | niI の normal コマンド。モデルは効果で ni_return_keep / commit / drop にまとめていて、キーの一覧は代表だけ |
| `x.NI_DIRECT._C_c_` | `NI` | `<C-c>` | `N_OFF` | Vim の <C-c>（niI から normal に戻る） |
| `x.NI_DIRECT._C_g_` | `NI` | `<C-g>` | `I_DIRECT` | niI の normal コマンド。モデルは効果で ni_return_keep / commit / drop にまとめていて、キーの一覧は代表だけ |
| `x.NI_DIRECT._C_j_` | `NI` | `<C-j>` | `I_DIRECT` | niI の normal コマンド。モデルは効果で ni_return_keep / commit / drop にまとめていて、キーの一覧は代表だけ |
| `x.NI_DIRECT._C_k_a_` | `NI` | `<C-k>a:` | `I_DIRECT` | niI の normal コマンド。モデルは効果で ni_return_keep / commit / drop にまとめていて、キーの一覧は代表だけ |
| `x.NI_DIRECT._C_n_` | `NI` | `<C-n>` | `I_DIRECT` | niI の normal コマンド。モデルは効果で ni_return_keep / commit / drop にまとめていて、キーの一覧は代表だけ |
| `x.NI_DIRECT._C_o_` | `NI` | `<C-o>` | `I_DIRECT` | niI の normal コマンド。モデルは効果で ni_return_keep / commit / drop にまとめていて、キーの一覧は代表だけ |
| `x.NI_DIRECT._C_o_R` | `NI` | `<C-o>R` | `I_ROMAJI` | niI の normal コマンド。モデルは効果で ni_return_keep / commit / drop にまとめていて、キーの一覧は代表だけ |
| `x.NI_DIRECT._C_o___CR_` | `NI` | `<C-o>:<CR>` | `I_DIRECT` | cmdline の中（07a #187） |
| `x.NI_DIRECT._C_o___Esc_` | `NI` | `<C-o>:<Esc>` | `N_OFF` | cmdline の中（07a #187） |
| `x.NI_DIRECT._C_o_v` | `NI` | `<C-o>v` | `I_ROMAJI` | niI の normal コマンド。モデルは効果で ni_return_keep / commit / drop にまとめていて、キーの一覧は代表だけ |
| `x.NI_DIRECT._C_r_a` | `NI` | `<C-r>a` | `I_DIRECT` | niI の normal コマンド。モデルは効果で ni_return_keep / commit / drop にまとめていて、キーの一覧は代表だけ |
| `x.NI_DIRECT._C_u_` | `NI` | `<C-u>` | `I_DIRECT` | niI の normal コマンド。モデルは効果で ni_return_keep / commit / drop にまとめていて、キーの一覧は代表だけ |
| `x.NI_DIRECT._C_y_` | `NI` | `<C-y>` | `I_DIRECT` | niI の normal コマンド。モデルは効果で ni_return_keep / commit / drop にまとめていて、キーの一覧は代表だけ |
| `x.NI_DIRECT._Esc_` | `NI` | `<Esc>` | `I_DIRECT` | niI の normal コマンド。モデルは効果で ni_return_keep / commit / drop にまとめていて、キーの一覧は代表だけ |
| `x.NI_DIRECT._Insert_` | `NI` | `<Insert>` | `I_DIRECT` | niI の normal コマンド。モデルは効果で ni_return_keep / commit / drop にまとめていて、キーの一覧は代表だけ |
| `x.NI_DIRECT._S_Tab_` | `NI` | `<S-Tab>` | `I_DIRECT` | niI の normal コマンド。モデルは効果で ni_return_keep / commit / drop にまとめていて、キーの一覧は代表だけ |
| `x.NI_DIRECT._Space_` | `NI` | `<Space>` | `I_DIRECT` | niI の normal コマンド。モデルは効果で ni_return_keep / commit / drop にまとめていて、キーの一覧は代表だけ |
| `x.NI_DIRECT._Tab_` | `NI` | `<Tab>` | `I_DIRECT` | niI の normal コマンド。モデルは効果で ni_return_keep / commit / drop にまとめていて、キーの一覧は代表だけ |
| `x.NI_DIRECT.a` | `NI` | `a` | `I_DIRECT` | niI の normal コマンド。モデルは効果で ni_return_keep / commit / drop にまとめていて、キーの一覧は代表だけ |
| `x.NI_POINT._` | `NI` | `.` | `I_POINT` | マクロと `.` の繰り返し（07f #192） |
| `x.NI_POINT._BS_` | `NI` | `<BS>` | `I_POINT` | niI の normal コマンド。モデルは効果で ni_return_keep / commit / drop にまとめていて、キーの一覧は代表だけ |
| `x.NI_POINT._C_c_` | `NI` | `<C-c>` | `N_OFF` | Vim の <C-c>（niI から normal に戻る） |
| `x.NI_POINT._C_g_` | `NI` | `<C-g>` | `I_POINT` | niI の normal コマンド。モデルは効果で ni_return_keep / commit / drop にまとめていて、キーの一覧は代表だけ |
| `x.NI_POINT._C_j_` | `NI` | `<C-j>` | `I_POINT` | niI の normal コマンド。モデルは効果で ni_return_keep / commit / drop にまとめていて、キーの一覧は代表だけ |
| `x.NI_POINT._C_k_a_` | `NI` | `<C-k>a:` | `I_POINT` | niI の normal コマンド。モデルは効果で ni_return_keep / commit / drop にまとめていて、キーの一覧は代表だけ |
| `x.NI_POINT._C_n_` | `NI` | `<C-n>` | `I_POINT` | niI の normal コマンド。モデルは効果で ni_return_keep / commit / drop にまとめていて、キーの一覧は代表だけ |
| `x.NI_POINT._C_o_` | `NI` | `<C-o>` | `I_POINT` | niI の normal コマンド。モデルは効果で ni_return_keep / commit / drop にまとめていて、キーの一覧は代表だけ |
| `x.NI_POINT._C_o_R` | `NI` | `<C-o>R` | `I_POINT` | niI の normal コマンド。モデルは効果で ni_return_keep / commit / drop にまとめていて、キーの一覧は代表だけ |
| `x.NI_POINT._C_o___CR_` | `NI` | `<C-o>:<CR>` | `I_DIRECT` | cmdline の中（07a #187） |
| `x.NI_POINT._C_o___Esc_` | `NI` | `<C-o>:<Esc>` | `N_OFF` | cmdline の中（07a #187） |
| `x.NI_POINT._C_o_v` | `NI` | `<C-o>v` | `I_POINT` | niI の normal コマンド。モデルは効果で ni_return_keep / commit / drop にまとめていて、キーの一覧は代表だけ |
| `x.NI_POINT._C_r_a` | `NI` | `<C-r>a` | `I_POINT` | niI の normal コマンド。モデルは効果で ni_return_keep / commit / drop にまとめていて、キーの一覧は代表だけ |
| `x.NI_POINT._C_u_` | `NI` | `<C-u>` | `I_POINT` | niI の normal コマンド。モデルは効果で ni_return_keep / commit / drop にまとめていて、キーの一覧は代表だけ |
| `x.NI_POINT._C_y_` | `NI` | `<C-y>` | `I_POINT` | niI の normal コマンド。モデルは効果で ni_return_keep / commit / drop にまとめていて、キーの一覧は代表だけ |
| `x.NI_POINT._Esc_` | `NI` | `<Esc>` | `I_POINT` | niI の normal コマンド。モデルは効果で ni_return_keep / commit / drop にまとめていて、キーの一覧は代表だけ |
| `x.NI_POINT._Insert_` | `NI` | `<Insert>` | `I_POINT` | niI の normal コマンド。モデルは効果で ni_return_keep / commit / drop にまとめていて、キーの一覧は代表だけ |
| `x.NI_POINT._S_Tab_` | `NI` | `<S-Tab>` | `I_POINT` | niI の normal コマンド。モデルは効果で ni_return_keep / commit / drop にまとめていて、キーの一覧は代表だけ |
| `x.NI_POINT._Space_` | `NI` | `<Space>` | `I_POINT` | niI の normal コマンド。モデルは効果で ni_return_keep / commit / drop にまとめていて、キーの一覧は代表だけ |
| `x.NI_POINT._Tab_` | `NI` | `<Tab>` | `I_POINT` | niI の normal コマンド。モデルは効果で ni_return_keep / commit / drop にまとめていて、キーの一覧は代表だけ |
| `x.NI_POINT.a` | `NI` | `a` | `I_POINT` | niI の normal コマンド。モデルは効果で ni_return_keep / commit / drop にまとめていて、キーの一覧は代表だけ |
| `x.NI_SELECT._` | `NI` | `.` | `I_SELECT` | マクロと `.` の繰り返し（07f #192） |
| `x.NI_SELECT._BS_` | `NI` | `<BS>` | `I_SELECT` | niI の normal コマンド。モデルは効果で ni_return_keep / commit / drop にまとめていて、キーの一覧は代表だけ |
| `x.NI_SELECT._C_c_` | `NI` | `<C-c>` | `N_OFF` | Vim の <C-c>（niI から normal に戻る） |
| `x.NI_SELECT._C_g_` | `NI` | `<C-g>` | `I_SELECT` | niI の normal コマンド。モデルは効果で ni_return_keep / commit / drop にまとめていて、キーの一覧は代表だけ |
| `x.NI_SELECT._C_j_` | `NI` | `<C-j>` | `I_SELECT` | niI の normal コマンド。モデルは効果で ni_return_keep / commit / drop にまとめていて、キーの一覧は代表だけ |
| `x.NI_SELECT._C_k_a_` | `NI` | `<C-k>a:` | `I_DIRECT` | niI の normal コマンド。モデルは効果で ni_return_keep / commit / drop にまとめていて、キーの一覧は代表だけ |
| `x.NI_SELECT._C_n_` | `NI` | `<C-n>` | `I_SELECT` | niI の normal コマンド。モデルは効果で ni_return_keep / commit / drop にまとめていて、キーの一覧は代表だけ |
| `x.NI_SELECT._C_o_` | `NI` | `<C-o>` | `I_SELECT` | niI の normal コマンド。モデルは効果で ni_return_keep / commit / drop にまとめていて、キーの一覧は代表だけ |
| `x.NI_SELECT._C_o_R` | `NI` | `<C-o>R` | `I_ROMAJI` | niI の normal コマンド。モデルは効果で ni_return_keep / commit / drop にまとめていて、キーの一覧は代表だけ |
| `x.NI_SELECT._C_o___CR_` | `NI` | `<C-o>:<CR>` | `I_DIRECT` | cmdline の中（07a #187） |
| `x.NI_SELECT._C_o___Esc_` | `NI` | `<C-o>:<Esc>` | `N_OFF` | cmdline の中（07a #187） |
| `x.NI_SELECT._C_o_v` | `NI` | `<C-o>v` | `I_ROMAJI` | niI の normal コマンド。モデルは効果で ni_return_keep / commit / drop にまとめていて、キーの一覧は代表だけ |
| `x.NI_SELECT._C_r_a` | `NI` | `<C-r>a` | `I_DIRECT` | niI の normal コマンド。モデルは効果で ni_return_keep / commit / drop にまとめていて、キーの一覧は代表だけ |
| `x.NI_SELECT._C_u_` | `NI` | `<C-u>` | `I_SELECT` | niI の normal コマンド。モデルは効果で ni_return_keep / commit / drop にまとめていて、キーの一覧は代表だけ |
| `x.NI_SELECT._C_y_` | `NI` | `<C-y>` | `I_SELECT` | niI の normal コマンド。モデルは効果で ni_return_keep / commit / drop にまとめていて、キーの一覧は代表だけ |
| `x.NI_SELECT._Esc_` | `NI` | `<Esc>` | `I_SELECT` | niI の normal コマンド。モデルは効果で ni_return_keep / commit / drop にまとめていて、キーの一覧は代表だけ |
| `x.NI_SELECT._Insert_` | `NI` | `<Insert>` | `I_SELECT` | niI の normal コマンド。モデルは効果で ni_return_keep / commit / drop にまとめていて、キーの一覧は代表だけ |
| `x.NI_SELECT._S_Tab_` | `NI` | `<S-Tab>` | `I_SELECT` | niI の normal コマンド。モデルは効果で ni_return_keep / commit / drop にまとめていて、キーの一覧は代表だけ |
| `x.NI_SELECT._Space_` | `NI` | `<Space>` | `I_SELECT` | niI の normal コマンド。モデルは効果で ni_return_keep / commit / drop にまとめていて、キーの一覧は代表だけ |
| `x.NI_SELECT._Tab_` | `NI` | `<Tab>` | `I_SELECT` | niI の normal コマンド。モデルは効果で ni_return_keep / commit / drop にまとめていて、キーの一覧は代表だけ |
| `x.NI_SELECT.a` | `NI` | `a` | `I_SELECT` | niI の normal コマンド。モデルは効果で ni_return_keep / commit / drop にまとめていて、キーの一覧は代表だけ |
| `x.N_OFF._` | `N_OFF` | `.` | `N_OFF` | マクロと `.` の繰り返し（07f #192） |
| `x.N_OFF._BS_` | `N_OFF` | `<BS>` | `N_OFF` | モデルに無い自己遷移（観測では何も変わらない） |
| `x.N_OFF._C_c_` | `N_OFF` | `<C-c>` | `N_OFF` | モデルに無い自己遷移（観測では何も変わらない） |
| `x.N_OFF._C_g_` | `N_OFF` | `<C-g>` | `N_OFF` | モデルに無い自己遷移（観測では何も変わらない） |
| `x.N_OFF._C_j_` | `N_OFF` | `<C-j>` | `N_OFF` | モデルに無い自己遷移（観測では何も変わらない） |
| `x.N_OFF._C_k_a_` | `N_OFF` | `<C-k>a:` | `I_OFF` | normal の Vim のコマンド。モデルは insert に入る道と <Insert>・R だけを書いている |
| `x.N_OFF._C_n_` | `N_OFF` | `<C-n>` | `N_OFF` | モデルに無い自己遷移（観測では何も変わらない） |
| `x.N_OFF._C_o_` | `N_OFF` | `<C-o>` | `N_OFF` | モデルに無い自己遷移（観測では何も変わらない） |
| `x.N_OFF._C_o_R` | `N_OFF` | `<C-o>R` | `R_OFF` | normal の Vim のコマンド。モデルは insert に入る道と <Insert>・R だけを書いている |
| `x.N_OFF._C_o___CR_` | `N_OFF` | `<C-o>:<CR>` | `N_OFF` | cmdline の中（07a #187） |
| `x.N_OFF._C_o___Esc_` | `N_OFF` | `<C-o>:<Esc>` | `N_OFF` | cmdline の中（07a #187） |
| `x.N_OFF._C_o_v` | `N_OFF` | `<C-o>v` | `N_OFF` | モデルに無い自己遷移（観測では何も変わらない） |
| `x.N_OFF._C_r_a` | `N_OFF` | `<C-r>a` | `I_OFF` | normal の Vim のコマンド。モデルは insert に入る道と <Insert>・R だけを書いている |
| `x.N_OFF._C_u_` | `N_OFF` | `<C-u>` | `N_OFF` | モデルに無い自己遷移（観測では何も変わらない） |
| `x.N_OFF._C_y_` | `N_OFF` | `<C-y>` | `N_OFF` | モデルに無い自己遷移（観測では何も変わらない） |
| `x.N_OFF._Left_` | `N_OFF` | `<Left>` | `N_OFF` | モデルに無い自己遷移（観測では何も変わらない） |
| `x.N_OFF._S_Tab_` | `N_OFF` | `<S-Tab>` | `N_OFF` | モデルに無い自己遷移（観測では何も変わらない） |
| `x.N_OFF._Space_` | `N_OFF` | `<Space>` | `N_OFF` | モデルに無い自己遷移（観測では何も変わらない） |
| `x.N_OFF._Tab_` | `N_OFF` | `<Tab>` | `N_OFF` | モデルに無い自己遷移（観測では何も変わらない） |
| `x.N_OFF.l` | `N_OFF` | `l` | `N_OFF` | モデルに無い自己遷移（観測では何も変わらない） |
| `x.N_OFF.x` | `N_OFF` | `x` | `N_OFF` | モデルに無い自己遷移（観測では何も変わらない） |
| `x.P_PROMPT_POINT.K` | `P_PROMPT` | `K` | `P_PROMPT` | 辞書登録のプロンプトの中（07c #189） |
| `x.P_PROMPT_POINT.R` | `P_PROMPT` | `R` | `P_PROMPT` | 辞書登録のプロンプトの中（07c #189） |
| `x.P_PROMPT_POINT._` | `P_PROMPT` | `.` | `P_PROMPT` | 辞書登録のプロンプトの中（07c #189） |
| `x.P_PROMPT_POINT._BS_` | `P_PROMPT` | `<BS>` | `P_PROMPT` | 辞書登録のプロンプトの中（07c #189） |
| `x.P_PROMPT_POINT._C_c_` | `P_PROMPT` | `<C-c>` | `I_POINT` | 辞書登録のプロンプトの中（07c #189） |
| `x.P_PROMPT_POINT._C_j_` | `P_PROMPT` | `<C-j>` | `P_PROMPT` | 辞書登録のプロンプトの中（07c #189） |
| `x.P_PROMPT_POINT._C_k_a_` | `P_PROMPT` | `<C-k>a:` | `P_PROMPT` | 辞書登録のプロンプトの中（07c #189） |
| `x.P_PROMPT_POINT._C_n_` | `P_PROMPT` | `<C-n>` | `P_PROMPT` | 辞書登録のプロンプトの中（07c #189） |
| `x.P_PROMPT_POINT._C_o_` | `P_PROMPT` | `<C-o>` | `P_PROMPT` | 辞書登録のプロンプトの中（07c #189） |
| `x.P_PROMPT_POINT._C_o_R` | `P_PROMPT` | `<C-o>R` | `P_PROMPT` | 辞書登録のプロンプトの中（07c #189） |
| `x.P_PROMPT_POINT._C_o___CR_` | `P_PROMPT` | `<C-o>:<CR>` | `I_DIRECT` | cmdline の中（07a #187） |
| `x.P_PROMPT_POINT._C_o___Esc_` | `P_PROMPT` | `<C-o>:<Esc>` | `I_POINT` | cmdline の中（07a #187） |
| `x.P_PROMPT_POINT._C_o_v` | `P_PROMPT` | `<C-o>v` | `P_PROMPT` | 辞書登録のプロンプトの中（07c #189） |
| `x.P_PROMPT_POINT._C_r_a` | `P_PROMPT` | `<C-r>a` | `P_PROMPT` | 辞書登録のプロンプトの中（07c #189） |
| `x.P_PROMPT_POINT._C_u_` | `P_PROMPT` | `<C-u>` | `P_PROMPT` | 辞書登録のプロンプトの中（07c #189） |
| `x.P_PROMPT_POINT._C_v_065` | `P_PROMPT` | `<C-v>065` | `P_PROMPT` | 辞書登録のプロンプトの中（07c #189） |
| `x.P_PROMPT_POINT._C_w_` | `P_PROMPT` | `<C-w>` | `P_PROMPT` | 辞書登録のプロンプトの中（07c #189） |
| `x.P_PROMPT_POINT._C_y_` | `P_PROMPT` | `<C-y>` | `P_PROMPT` | 辞書登録のプロンプトの中（07c #189） |
| `x.P_PROMPT_POINT._Insert_` | `P_PROMPT` | `<Insert>` | `P_PROMPT` | 辞書登録のプロンプトの中（07c #189） |
| `x.P_PROMPT_POINT._Left_` | `P_PROMPT` | `<Left>` | `P_PROMPT` | 辞書登録のプロンプトの中（07c #189） |
| `x.P_PROMPT_POINT._S_Tab_` | `P_PROMPT` | `<S-Tab>` | `P_PROMPT` | 辞書登録のプロンプトの中（07c #189） |
| `x.P_PROMPT_POINT._Space_` | `P_PROMPT` | `<Space>` | `P_PROMPT` | 辞書登録のプロンプトの中（07c #189） |
| `x.P_PROMPT_POINT._Tab_` | `P_PROMPT` | `<Tab>` | `P_PROMPT` | 辞書登録のプロンプトの中（07c #189） |
| `x.P_PROMPT_POINT.a` | `P_PROMPT` | `a` | `P_PROMPT` | 辞書登録のプロンプトの中（07c #189） |
| `x.P_PROMPT_POINT.l` | `P_PROMPT` | `l` | `P_PROMPT` | 辞書登録のプロンプトの中（07c #189） |
| `x.P_PROMPT_POINT.x` | `P_PROMPT` | `x` | `P_PROMPT` | 辞書登録のプロンプトの中（07c #189） |
| `x.P_PROMPT_SELECT.K` | `P_PROMPT` | `K` | `P_PROMPT` | 辞書登録のプロンプトの中（07c #189） |
| `x.P_PROMPT_SELECT.R` | `P_PROMPT` | `R` | `P_PROMPT` | 辞書登録のプロンプトの中（07c #189） |
| `x.P_PROMPT_SELECT._` | `P_PROMPT` | `.` | `P_PROMPT` | 辞書登録のプロンプトの中（07c #189） |
| `x.P_PROMPT_SELECT._BS_` | `P_PROMPT` | `<BS>` | `P_PROMPT` | 辞書登録のプロンプトの中（07c #189） |
| `x.P_PROMPT_SELECT._C_c_` | `P_PROMPT` | `<C-c>` | `I_SELECT` | 辞書登録のプロンプトの中（07c #189） |
| `x.P_PROMPT_SELECT._C_j_` | `P_PROMPT` | `<C-j>` | `P_PROMPT` | 辞書登録のプロンプトの中（07c #189） |
| `x.P_PROMPT_SELECT._C_k_a_` | `P_PROMPT` | `<C-k>a:` | `P_PROMPT` | 辞書登録のプロンプトの中（07c #189） |
| `x.P_PROMPT_SELECT._C_n_` | `P_PROMPT` | `<C-n>` | `P_PROMPT` | 辞書登録のプロンプトの中（07c #189） |
| `x.P_PROMPT_SELECT._C_o_` | `P_PROMPT` | `<C-o>` | `P_PROMPT` | 辞書登録のプロンプトの中（07c #189） |
| `x.P_PROMPT_SELECT._C_o_R` | `P_PROMPT` | `<C-o>R` | `P_PROMPT` | 辞書登録のプロンプトの中（07c #189） |
| `x.P_PROMPT_SELECT._C_o___CR_` | `P_PROMPT` | `<C-o>:<CR>` | `I_DIRECT` | cmdline の中（07a #187） |
| `x.P_PROMPT_SELECT._C_o___Esc_` | `P_PROMPT` | `<C-o>:<Esc>` | `I_SELECT` | cmdline の中（07a #187） |
| `x.P_PROMPT_SELECT._C_o_v` | `P_PROMPT` | `<C-o>v` | `P_PROMPT` | 辞書登録のプロンプトの中（07c #189） |
| `x.P_PROMPT_SELECT._C_r_a` | `P_PROMPT` | `<C-r>a` | `P_PROMPT` | 辞書登録のプロンプトの中（07c #189） |
| `x.P_PROMPT_SELECT._C_u_` | `P_PROMPT` | `<C-u>` | `P_PROMPT` | 辞書登録のプロンプトの中（07c #189） |
| `x.P_PROMPT_SELECT._C_v_065` | `P_PROMPT` | `<C-v>065` | `P_PROMPT` | 辞書登録のプロンプトの中（07c #189） |
| `x.P_PROMPT_SELECT._C_w_` | `P_PROMPT` | `<C-w>` | `P_PROMPT` | 辞書登録のプロンプトの中（07c #189） |
| `x.P_PROMPT_SELECT._C_y_` | `P_PROMPT` | `<C-y>` | `P_PROMPT` | 辞書登録のプロンプトの中（07c #189） |
| `x.P_PROMPT_SELECT._Insert_` | `P_PROMPT` | `<Insert>` | `P_PROMPT` | 辞書登録のプロンプトの中（07c #189） |
| `x.P_PROMPT_SELECT._Left_` | `P_PROMPT` | `<Left>` | `P_PROMPT` | 辞書登録のプロンプトの中（07c #189） |
| `x.P_PROMPT_SELECT._S_Tab_` | `P_PROMPT` | `<S-Tab>` | `P_PROMPT` | 辞書登録のプロンプトの中（07c #189） |
| `x.P_PROMPT_SELECT._Space_` | `P_PROMPT` | `<Space>` | `P_PROMPT` | 辞書登録のプロンプトの中（07c #189） |
| `x.P_PROMPT_SELECT._Tab_` | `P_PROMPT` | `<Tab>` | `P_PROMPT` | 辞書登録のプロンプトの中（07c #189） |
| `x.P_PROMPT_SELECT.a` | `P_PROMPT` | `a` | `P_PROMPT` | 辞書登録のプロンプトの中（07c #189） |
| `x.P_PROMPT_SELECT.l` | `P_PROMPT` | `l` | `P_PROMPT` | 辞書登録のプロンプトの中（07c #189） |
| `x.P_PROMPT_SELECT.x` | `P_PROMPT` | `x` | `P_PROMPT` | 辞書登録のプロンプトの中（07c #189） |
| `x.R_OFF.K` | `R_OFF` | `K` | `R_OFF` | skk が無効な insert / replace。キーは Vim がそのまま処理する（モデルは無効な状態からのキー入力を書いていない） |
| `x.R_OFF.R` | `R_OFF` | `R` | `R_OFF` | skk が無効な insert / replace。キーは Vim がそのまま処理する（モデルは無効な状態からのキー入力を書いていない） |
| `x.R_OFF._` | `R_OFF` | `.` | `R_OFF` | マクロと `.` の繰り返し（07f #192） |
| `x.R_OFF._BS_` | `R_OFF` | `<BS>` | `R_OFF` | モデルに無い自己遷移（観測では何も変わらない） |
| `x.R_OFF._C_c_` | `R_OFF` | `<C-c>` | `N_OFF` | Vim の <C-c>（insert / replace を抜けて normal に戻る）。無効なのでモデルに無い |
| `x.R_OFF._C_j_` | `R_OFF` | `<C-j>` | `R_OFF` | skk が無効な insert / replace。キーは Vim がそのまま処理する（モデルは無効な状態からのキー入力を書いていない） |
| `x.R_OFF._C_k_a_` | `R_OFF` | `<C-k>a:` | `R_OFF` | skk が無効な insert / replace。キーは Vim がそのまま処理する（モデルは無効な状態からのキー入力を書いていない） |
| `x.R_OFF._C_n_` | `R_OFF` | `<C-n>` | `R_OFF` | モデルに無い自己遷移（観測では何も変わらない） |
| `x.R_OFF._C_o_` | `R_OFF` | `<C-o>` | `NI` | Vim のモード遷移（無効な insert / replace から <C-o> で niI・visual・replace へ）。モデルは無効な状態からのモード遷移を書いていない |
| `x.R_OFF._C_o_R` | `R_OFF` | `<C-o>R` | `R_OFF` | モデルに無い自己遷移（観測では何も変わらない） |
| `x.R_OFF._C_o___CR_` | `R_OFF` | `<C-o>:<CR>` | `R_OFF` | cmdline の中（07a #187） |
| `x.R_OFF._C_o___Esc_` | `R_OFF` | `<C-o>:<Esc>` | `R_OFF` | cmdline の中（07a #187） |
| `x.R_OFF._C_o_v` | `R_OFF` | `<C-o>v` | `N_OFF` | Vim のモード遷移（無効な insert / replace から <C-o> で niI・visual・replace へ）。モデルは無効な状態からのモード遷移を書いていない |
| `x.R_OFF._C_r_a` | `R_OFF` | `<C-r>a` | `R_OFF` | skk が無効な insert / replace。キーは Vim がそのまま処理する（モデルは無効な状態からのキー入力を書いていない） |
| `x.R_OFF._C_u_` | `R_OFF` | `<C-u>` | `R_OFF` | モデルに無い自己遷移（観測では何も変わらない） |
| `x.R_OFF._C_v_065` | `R_OFF` | `<C-v>065` | `R_OFF` | skk が無効な insert / replace。キーは Vim がそのまま処理する（モデルは無効な状態からのキー入力を書いていない） |
| `x.R_OFF._C_w_` | `R_OFF` | `<C-w>` | `R_OFF` | モデルに無い自己遷移（観測では何も変わらない） |
| `x.R_OFF._C_y_` | `R_OFF` | `<C-y>` | `R_OFF` | モデルに無い自己遷移（観測では何も変わらない） |
| `x.R_OFF._Left_` | `R_OFF` | `<Left>` | `R_OFF` | モデルに無い自己遷移（観測では何も変わらない） |
| `x.R_OFF._S_Tab_` | `R_OFF` | `<S-Tab>` | `R_OFF` | skk が無効な insert / replace。キーは Vim がそのまま処理する（モデルは無効な状態からのキー入力を書いていない） |
| `x.R_OFF._Space_` | `R_OFF` | `<Space>` | `R_OFF` | skk が無効な insert / replace。キーは Vim がそのまま処理する（モデルは無効な状態からのキー入力を書いていない） |
| `x.R_OFF._Tab_` | `R_OFF` | `<Tab>` | `R_OFF` | skk が無効な insert / replace。キーは Vim がそのまま処理する（モデルは無効な状態からのキー入力を書いていない） |
| `x.R_OFF.a` | `R_OFF` | `a` | `R_OFF` | skk が無効な insert / replace。キーは Vim がそのまま処理する（モデルは無効な状態からのキー入力を書いていない） |
| `x.R_OFF.l` | `R_OFF` | `l` | `R_OFF` | skk が無効な insert / replace。キーは Vim がそのまま処理する（モデルは無効な状態からのキー入力を書いていない） |
| `x.R_OFF.x` | `R_OFF` | `x` | `R_OFF` | skk が無効な insert / replace。キーは Vim がそのまま処理する（モデルは無効な状態からのキー入力を書いていない） |
| `x.V_IDLE.K` | `V_IDLE` | `K` | `I_DIRECT` | visual / select の Vim のコマンド。モデルは <Esc> で insert に戻る道だけを書いている |
| `x.V_IDLE.R` | `V_IDLE` | `R` | `I_DIRECT` | visual / select の Vim のコマンド。モデルは <Esc> で insert に戻る道だけを書いている |
| `x.V_IDLE._` | `V_IDLE` | `.` | `V_IDLE` | マクロと `.` の繰り返し（07f #192） |
| `x.V_IDLE._BS_` | `V_IDLE` | `<BS>` | `V_IDLE` | モデルに無い自己遷移（観測では何も変わらない） |
| `x.V_IDLE._C_c_` | `V_IDLE` | `<C-c>` | `N_OFF` | Vim の <C-c>（visual から normal に戻る） |
| `x.V_IDLE._C_g_` | `V_IDLE` | `<C-g>` | `V_IDLE` | モデルに無い自己遷移（観測では何も変わらない） |
| `x.V_IDLE._C_j_` | `V_IDLE` | `<C-j>` | `V_IDLE` | モデルに無い自己遷移（観測では何も変わらない） |
| `x.V_IDLE._C_k_a_` | `V_IDLE` | `<C-k>a:` | `V_IDLE` | モデルに無い自己遷移（観測では何も変わらない） |
| `x.V_IDLE._C_n_` | `V_IDLE` | `<C-n>` | `V_IDLE` | モデルに無い自己遷移（観測では何も変わらない） |
| `x.V_IDLE._C_o_` | `V_IDLE` | `<C-o>` | `V_IDLE` | モデルに無い自己遷移（観測では何も変わらない） |
| `x.V_IDLE._C_o_R` | `V_IDLE` | `<C-o>R` | `I_DIRECT` | visual / select の Vim のコマンド。モデルは <Esc> で insert に戻る道だけを書いている |
| `x.V_IDLE._C_o___CR_` | `V_IDLE` | `<C-o>:<CR>` | `I_DIRECT` | cmdline の中（07a #187） |
| `x.V_IDLE._C_o___Esc_` | `V_IDLE` | `<C-o>:<Esc>` | `I_DIRECT` | cmdline の中（07a #187） |
| `x.V_IDLE._C_o_v` | `V_IDLE` | `<C-o>v` | `I_DIRECT` | visual / select の Vim のコマンド。モデルは <Esc> で insert に戻る道だけを書いている |
| `x.V_IDLE._C_u_` | `V_IDLE` | `<C-u>` | `V_IDLE` | モデルに無い自己遷移（観測では何も変わらない） |
| `x.V_IDLE._C_y_` | `V_IDLE` | `<C-y>` | `V_IDLE` | モデルに無い自己遷移（観測では何も変わらない） |
| `x.V_IDLE._Insert_` | `V_IDLE` | `<Insert>` | `V_IDLE` | モデルに無い自己遷移（観測では何も変わらない） |
| `x.V_IDLE._Left_` | `V_IDLE` | `<Left>` | `V_IDLE` | モデルに無い自己遷移（観測では何も変わらない） |
| `x.V_IDLE._S_Tab_` | `V_IDLE` | `<S-Tab>` | `V_IDLE` | モデルに無い自己遷移（観測では何も変わらない） |
| `x.V_IDLE._Space_` | `V_IDLE` | `<Space>` | `V_IDLE` | モデルに無い自己遷移（観測では何も変わらない） |
| `x.V_IDLE._Tab_` | `V_IDLE` | `<Tab>` | `V_IDLE` | モデルに無い自己遷移（観測では何も変わらない） |
| `x.V_IDLE.l` | `V_IDLE` | `l` | `V_IDLE` | モデルに無い自己遷移（観測では何も変わらない） |
| `x.V_IDLE.x` | `V_IDLE` | `x` | `I_DIRECT` | visual / select の Vim のコマンド。モデルは <Esc> で insert に戻る道だけを書いている |
| `x.V_PRE_POINT.K` | `V_PRE` | `K` | `I_POINT` | visual / select の Vim のコマンド。モデルは <Esc> で insert に戻る道だけを書いている |
| `x.V_PRE_POINT.R` | `V_PRE` | `R` | `I_POINT` | visual / select の Vim のコマンド。モデルは <Esc> で insert に戻る道だけを書いている |
| `x.V_PRE_POINT._` | `V_PRE` | `.` | `V_PRE` | マクロと `.` の繰り返し（07f #192） |
| `x.V_PRE_POINT._BS_` | `V_PRE` | `<BS>` | `V_PRE` | モデルに無い自己遷移（観測では何も変わらない） |
| `x.V_PRE_POINT._C_c_` | `V_PRE` | `<C-c>` | `N_OFF` | Vim の <C-c>（visual から normal に戻る） |
| `x.V_PRE_POINT._C_g_` | `V_PRE` | `<C-g>` | `V_PRE` | モデルに無い自己遷移（観測では何も変わらない） |
| `x.V_PRE_POINT._C_j_` | `V_PRE` | `<C-j>` | `V_PRE` | モデルに無い自己遷移（観測では何も変わらない） |
| `x.V_PRE_POINT._C_k_a_` | `V_PRE` | `<C-k>a:` | `V_PRE` | モデルに無い自己遷移（観測では何も変わらない） |
| `x.V_PRE_POINT._C_n_` | `V_PRE` | `<C-n>` | `V_PRE` | モデルに無い自己遷移（観測では何も変わらない） |
| `x.V_PRE_POINT._C_o_` | `V_PRE` | `<C-o>` | `V_PRE` | モデルに無い自己遷移（観測では何も変わらない） |
| `x.V_PRE_POINT._C_o_R` | `V_PRE` | `<C-o>R` | `I_POINT` | visual / select の Vim のコマンド。モデルは <Esc> で insert に戻る道だけを書いている |
| `x.V_PRE_POINT._C_o___CR_` | `V_PRE` | `<C-o>:<CR>` | `I_DIRECT` | cmdline の中（07a #187） |
| `x.V_PRE_POINT._C_o___Esc_` | `V_PRE` | `<C-o>:<Esc>` | `I_DIRECT` | cmdline の中（07a #187） |
| `x.V_PRE_POINT._C_o_v` | `V_PRE` | `<C-o>v` | `I_POINT` | visual / select の Vim のコマンド。モデルは <Esc> で insert に戻る道だけを書いている |
| `x.V_PRE_POINT._C_u_` | `V_PRE` | `<C-u>` | `V_PRE` | モデルに無い自己遷移（観測では何も変わらない） |
| `x.V_PRE_POINT._C_y_` | `V_PRE` | `<C-y>` | `V_PRE` | モデルに無い自己遷移（観測では何も変わらない） |
| `x.V_PRE_POINT._Insert_` | `V_PRE` | `<Insert>` | `V_PRE` | モデルに無い自己遷移（観測では何も変わらない） |
| `x.V_PRE_POINT._Left_` | `V_PRE` | `<Left>` | `V_PRE` | モデルに無い自己遷移（観測では何も変わらない） |
| `x.V_PRE_POINT._S_Tab_` | `V_PRE` | `<S-Tab>` | `V_PRE` | モデルに無い自己遷移（観測では何も変わらない） |
| `x.V_PRE_POINT._Space_` | `V_PRE` | `<Space>` | `V_PRE` | モデルに無い自己遷移（観測では何も変わらない） |
| `x.V_PRE_POINT._Tab_` | `V_PRE` | `<Tab>` | `V_PRE` | モデルに無い自己遷移（観測では何も変わらない） |
| `x.V_PRE_POINT.l` | `V_PRE` | `l` | `V_PRE` | モデルに無い自己遷移（観測では何も変わらない） |
| `x.V_PRE_POINT.x` | `V_PRE` | `x` | `I_POINT` | visual / select の Vim のコマンド。モデルは <Esc> で insert に戻る道だけを書いている |
| `x.V_PRE_SELECT.K` | `V_PRE` | `K` | `I_SELECT` | visual / select の Vim のコマンド。モデルは <Esc> で insert に戻る道だけを書いている |
| `x.V_PRE_SELECT.R` | `V_PRE` | `R` | `I_SELECT` | visual / select の Vim のコマンド。モデルは <Esc> で insert に戻る道だけを書いている |
| `x.V_PRE_SELECT._` | `V_PRE` | `.` | `V_PRE` | マクロと `.` の繰り返し（07f #192） |
| `x.V_PRE_SELECT._BS_` | `V_PRE` | `<BS>` | `V_PRE` | モデルに無い自己遷移（観測では何も変わらない） |
| `x.V_PRE_SELECT._C_c_` | `V_PRE` | `<C-c>` | `N_OFF` | Vim の <C-c>（visual から normal に戻る） |
| `x.V_PRE_SELECT._C_g_` | `V_PRE` | `<C-g>` | `V_PRE` | モデルに無い自己遷移（観測では何も変わらない） |
| `x.V_PRE_SELECT._C_j_` | `V_PRE` | `<C-j>` | `V_PRE` | モデルに無い自己遷移（観測では何も変わらない） |
| `x.V_PRE_SELECT._C_k_a_` | `V_PRE` | `<C-k>a:` | `V_PRE` | モデルに無い自己遷移（観測では何も変わらない） |
| `x.V_PRE_SELECT._C_n_` | `V_PRE` | `<C-n>` | `V_PRE` | モデルに無い自己遷移（観測では何も変わらない） |
| `x.V_PRE_SELECT._C_o_` | `V_PRE` | `<C-o>` | `V_PRE` | モデルに無い自己遷移（観測では何も変わらない） |
| `x.V_PRE_SELECT._C_o_R` | `V_PRE` | `<C-o>R` | `I_SELECT` | visual / select の Vim のコマンド。モデルは <Esc> で insert に戻る道だけを書いている |
| `x.V_PRE_SELECT._C_o___CR_` | `V_PRE` | `<C-o>:<CR>` | `I_DIRECT` | cmdline の中（07a #187） |
| `x.V_PRE_SELECT._C_o___Esc_` | `V_PRE` | `<C-o>:<Esc>` | `I_DIRECT` | cmdline の中（07a #187） |
| `x.V_PRE_SELECT._C_o_v` | `V_PRE` | `<C-o>v` | `I_SELECT` | visual / select の Vim のコマンド。モデルは <Esc> で insert に戻る道だけを書いている |
| `x.V_PRE_SELECT._C_u_` | `V_PRE` | `<C-u>` | `V_PRE` | モデルに無い自己遷移（観測では何も変わらない） |
| `x.V_PRE_SELECT._C_y_` | `V_PRE` | `<C-y>` | `V_PRE` | モデルに無い自己遷移（観測では何も変わらない） |
| `x.V_PRE_SELECT._Insert_` | `V_PRE` | `<Insert>` | `V_PRE` | モデルに無い自己遷移（観測では何も変わらない） |
| `x.V_PRE_SELECT._Left_` | `V_PRE` | `<Left>` | `V_PRE` | モデルに無い自己遷移（観測では何も変わらない） |
| `x.V_PRE_SELECT._S_Tab_` | `V_PRE` | `<S-Tab>` | `V_PRE` | モデルに無い自己遷移（観測では何も変わらない） |
| `x.V_PRE_SELECT._Space_` | `V_PRE` | `<Space>` | `V_PRE` | モデルに無い自己遷移（観測では何も変わらない） |
| `x.V_PRE_SELECT._Tab_` | `V_PRE` | `<Tab>` | `V_PRE` | モデルに無い自己遷移（観測では何も変わらない） |
| `x.V_PRE_SELECT.l` | `V_PRE` | `l` | `V_PRE` | モデルに無い自己遷移（観測では何も変わらない） |
| `x.V_PRE_SELECT.x` | `V_PRE` | `x` | `I_SELECT` | visual / select の Vim のコマンド。モデルは <Esc> で insert に戻る道だけを書いている |

## モデルにだけある遷移

| 遷移 | 確かめなかった理由 |
|---|---|
| `t.N_OFF.enable` | 観測していない |
| `t.I_OFF.enable` | 観測していない |
| `t.N_OFF.toggle` | 観測していない |
| `t.I_OFF.toggle` | 観測していない |
| `t.I_ESCAPE.cleanup` | 遷移の途中（internal）。キーで観測できない |
| `t.N_OFF.insert_enter.keepstate` | autocmd。キーで観測できない（probe では stale / winleave を打っていない） |
| `t.N_OFF.insert_enter` | autocmd。キーで観測できない（probe では stale / winleave を打っていない） |
| `t.I_DIRECT.stopinsert` | 観測していない |
| `t.I_DIRECT.mouse_select` | 入力（マウス・貼り付け）。キーで観測できない（07e #191） |
| `t.I_DIRECT.winleave` | autocmd。キーで観測できない（probe では stale / winleave を打っていない） |
| `t.I_DIRECT.bufleave` | autocmd。キーで観測できない（probe では stale / winleave を打っていない） |
| `t.I_ROMAJI.stopinsert` | 観測していない |
| `t.I_ROMAJI.mouse_select` | 入力（マウス・貼り付け）。キーで観測できない（07e #191） |
| `t.I_ROMAJI.winleave` | autocmd。キーで観測できない（probe では stale / winleave を打っていない） |
| `t.I_ROMAJI.bufleave` | autocmd。キーで観測できない（probe では stale / winleave を打っていない） |
| `t.I_POINT.stopinsert` | 観測していない |
| `t.I_POINT.mouse_select` | 入力（マウス・貼り付け）。キーで観測できない（07e #191） |
| `t.I_POINT.winleave` | autocmd。キーで観測できない（probe では stale / winleave を打っていない） |
| `t.I_POINT.bufleave` | autocmd。キーで観測できない（probe では stale / winleave を打っていない） |
| `t.I_SELECT.stopinsert` | 観測していない |
| `t.I_SELECT.mouse_select` | 入力（マウス・貼り付け）。キーで観測できない（07e #191） |
| `t.I_SELECT.winleave` | autocmd。キーで観測できない（probe では stale / winleave を打っていない） |
| `t.I_SELECT.bufleave` | autocmd。キーで観測できない（probe では stale / winleave を打っていない） |
| `t.N_WAIT.safestate` | 遷移の途中（internal）。キーで観測できない |
| `t.R_MID.modechanged` | 遷移の途中（internal）。キーで観測できない |
| `t.NI_POINT.winleave` | autocmd。キーで観測できない（probe では stale / winleave を打っていない） |
| `t.NI_SELECT.winleave` | autocmd。キーで観測できない（probe では stale / winleave を打っていない） |
| `t.NI_DIRECT.winleave` | autocmd。キーで観測できない（probe では stale / winleave を打っていない） |
| `t.V_PRE_POINT.winleave` | autocmd。キーで観測できない（probe では stale / winleave を打っていない） |
| `t.V_PRE_SELECT.winleave` | autocmd。キーで観測できない（probe では stale / winleave を打っていない） |
| `t.V_IDLE.winleave` | autocmd。キーで観測できない（probe では stale / winleave を打っていない） |
| `t.V_IDLE.bufleave` | autocmd。キーで観測できない（probe では stale / winleave を打っていない） |
| `t.V_PRE_POINT.bufleave` | autocmd。キーで観測できない（probe では stale / winleave を打っていない） |
| `t.V_PRE_SELECT.bufleave` | autocmd。キーで観測できない（probe では stale / winleave を打っていない） |
| `t.NI_DIRECT.bufleave` | autocmd。キーで観測できない（probe では stale / winleave を打っていない） |
| `t.NI_POINT.bufleave` | autocmd。キーで観測できない（probe では stale / winleave を打っていない） |
| `t.NI_SELECT.bufleave` | autocmd。キーで観測できない（probe では stale / winleave を打っていない） |
| `t.I_OFF.winleave` | autocmd。キーで観測できない（probe では stale / winleave を打っていない） |
| `t.I_OFF.bufleave` | autocmd。キーで観測できない（probe では stale / winleave を打っていない） |
| `t.IC.bufleave` | autocmd。キーで観測できない（probe では stale / winleave を打っていない） |
| `t.I_SELECT.key_X.register` | 観測していない |
| `t.P_PROMPT_POINT.register_commit` | 観測していない |
| `t.P_PROMPT_SELECT.register_commit` | 観測していない |
| `t.P_PROMPT_POINT.winleave` | autocmd。キーで観測できない（probe では stale / winleave を打っていない） |
| `t.P_PROMPT_SELECT.winleave` | autocmd。キーで観測できない（probe では stale / winleave を打っていない） |
| `t.I_DIRECT.ctrl_a` | 観測できず（BLOCKED）。probe では観測できなかった |
| `t.I_ROMAJI.ctrl_a` | 観測できず（BLOCKED）。probe では観測できなかった |
| `t.I_POINT.ctrl_a` | 観測できず（BLOCKED）。probe では観測できなかった |
| `t.I_SELECT.ctrl_a` | 観測できず（BLOCKED）。probe では観測できなかった |
| `t.I_ROMAJI.ctrl_a.e29` | 観測できず（BLOCKED）。probe では観測できなかった |
| `t.I_POINT.ctrl_a.e29` | 観測できず（BLOCKED）。probe では観測できなかった |
| `t.I_DIRECT.ctrl_at` | 観測できず（BLOCKED）。probe では観測できなかった |
| `t.I_ROMAJI.ctrl_at` | 観測できず（BLOCKED）。probe では観測できなかった |
| `t.I_POINT.ctrl_at` | 観測できず（BLOCKED）。probe では観測できなかった |
| `t.I_SELECT.ctrl_at` | 観測できず（BLOCKED）。probe では観測できなかった |
| `t.IC.stale` | autocmd。キーで観測できない（probe では stale / winleave を打っていない） |
| `t.IC.winleave` | autocmd。キーで観測できない（probe では stale / winleave を打っていない） |
| `t.I_DIRECT.mouse_click` | 入力（マウス・貼り付け）。キーで観測できない（07e #191） |
| `t.I_OFF.mouse_click` | 入力（マウス・貼り付け）。キーで観測できない（07e #191） |
| `t.N_OFF.mouse_click` | 入力（マウス・貼り付け）。キーで観測できない（07e #191） |
| `t.I_ROMAJI.mouse_click` | 入力（マウス・貼り付け）。キーで観測できない（07e #191） |
| `t.I_ROMAJI.mouse_click.keep` | 入力（マウス・貼り付け）。キーで観測できない（07e #191） |
| `t.I_POINT.mouse_click` | 入力（マウス・貼り付け）。キーで観測できない（07e #191） |
| `t.I_POINT.mouse_click.keep` | 入力（マウス・貼り付け）。キーで観測できない（07e #191） |
| `t.I_SELECT.mouse_click` | 入力（マウス・貼り付け）。キーで観測できない（07e #191） |
| `t.I_SELECT.mouse_click.keep` | 入力（マウス・貼り付け）。キーで観測できない（07e #191） |
| `t.I_ROMAJI.mouse_click_other` | 入力（マウス・貼り付け）。キーで観測できない（07e #191） |
| `t.I_POINT.mouse_click_other` | 入力（マウス・貼り付け）。キーで観測できない（07e #191） |
| `t.I_SELECT.mouse_click_other` | 入力（マウス・貼り付け）。キーで観測できない（07e #191） |
| `t.I_DIRECT.mouse_click_other` | 入力（マウス・貼り付け）。キーで観測できない（07e #191） |
| `t.I_OFF.mouse_click_other` | 入力（マウス・貼り付け）。キーで観測できない（07e #191） |
| `t.V_PRE_POINT.mouse_click_other` | 入力（マウス・貼り付け）。キーで観測できない（07e #191） |
| `t.V_PRE_SELECT.mouse_click_other` | 入力（マウス・貼り付け）。キーで観測できない（07e #191） |
| `t.I_OFF.mouse_select` | 入力（マウス・貼り付け）。キーで観測できない（07e #191） |
| `t.I_DIRECT.wheel` | 入力（マウス・貼り付け）。キーで観測できない（07e #191） |
| `t.I_ROMAJI.wheel` | 入力（マウス・貼り付け）。キーで観測できない（07e #191） |
| `t.I_POINT.wheel` | 入力（マウス・貼り付け）。キーで観測できない（07e #191） |
| `t.I_SELECT.wheel` | 入力（マウス・貼り付け）。キーで観測できない（07e #191） |
| `t.I_OFF.wheel` | 入力（マウス・貼り付け）。キーで観測できない（07e #191） |
| `t.I_DIRECT.paste` | 入力（マウス・貼り付け）。キーで観測できない（07e #191） |
| `t.I_ROMAJI.paste` | 入力（マウス・貼り付け）。キーで観測できない（07e #191） |
| `t.I_POINT.paste` | 入力（マウス・貼り付け）。キーで観測できない（07e #191） |
| `t.I_SELECT.paste` | 入力（マウス・貼り付け）。キーで観測できない（07e #191） |
| `t.I_OFF.paste` | 入力（マウス・貼り付け）。キーで観測できない（07e #191） |
| `t.I_DIRECT.stale.cursor` | autocmd。キーで観測できない（probe では stale / winleave を打っていない） |
| `t.I_DIRECT.stale.buffer` | autocmd。キーで観測できない（probe では stale / winleave を打っていない） |
| `t.I_DIRECT.stale.none` | autocmd。キーで観測できない（probe では stale / winleave を打っていない） |
| `t.I_ROMAJI.stale.cursor` | autocmd。キーで観測できない（probe では stale / winleave を打っていない） |
| `t.I_ROMAJI.stale.buffer` | autocmd。キーで観測できない（probe では stale / winleave を打っていない） |
| `t.I_ROMAJI.stale.none` | autocmd。キーで観測できない（probe では stale / winleave を打っていない） |
| `t.I_POINT.stale.cursor` | autocmd。キーで観測できない（probe では stale / winleave を打っていない） |
| `t.I_POINT.stale.buffer` | autocmd。キーで観測できない（probe では stale / winleave を打っていない） |
| `t.I_POINT.stale.none` | autocmd。キーで観測できない（probe では stale / winleave を打っていない） |
| `t.I_SELECT.stale.cursor` | autocmd。キーで観測できない（probe では stale / winleave を打っていない） |
| `t.I_SELECT.stale.buffer` | autocmd。キーで観測できない（probe では stale / winleave を打っていない） |
| `t.I_SELECT.stale.none` | autocmd。キーで観測できない（probe では stale / winleave を打っていない） |
| `t.N_OFF.term_open` | 観測していない |
| `t.T_OFF.enable` | 観測していない |
| `t.T_OFF.toggle` | 観測していない |
| `t.T_ESCAPE.enable` | 観測していない |
| `t.T_DIRECT.disable` | 観測していない |
| `t.T_DIRECT.toggle` | 観測していない |
| `t.T_DIRECT.esc` | 観測していない |
| `t.T_ROMAJI.disable` | 観測していない |
| `t.T_ROMAJI.toggle` | 観測していない |
| `t.T_ROMAJI.esc` | 観測していない |
| `t.T_POINT.disable` | 観測していない |
| `t.T_POINT.toggle` | 観測していない |
| `t.T_POINT.esc` | 観測していない |
| `t.T_SELECT.disable` | 観測していない |
| `t.T_SELECT.toggle` | 観測していない |
| `t.T_SELECT.esc` | 観測していない |
| `t.T_DIRECT.t_normal` | 観測していない |
| `t.T_ROMAJI.t_normal` | 観測していない |
| `t.T_POINT.t_normal` | 観測していない |
| `t.T_SELECT.t_normal` | 観測していない |
| `t.T_OFF.t_normal` | 観測していない |
| `t.T_ESCAPE.t_normal` | 観測していない |
| `t.T_NORMAL_DIRECT.nt_insert` | 観測していない |
| `t.T_NORMAL_ROMAJI.nt_insert` | 観測していない |
| `t.T_NORMAL_POINT.nt_insert` | 観測していない |
| `t.T_NORMAL_SELECT.nt_insert` | 観測していない |
| `t.T_NORMAL_OFF.nt_insert` | 観測していない |
| `t.T_NORMAL_DIRECT.nt_edit` | 観測していない |
| `t.T_NORMAL_DIRECT.t_normal_again` | 観測していない |
| `t.T_NORMAL_DIRECT.esc` | 観測していない |
| `t.T_NORMAL_DIRECT.ctrl_c` | 観測していない |
| `t.T_NORMAL_ROMAJI.nt_edit` | 観測していない |
| `t.T_NORMAL_ROMAJI.t_normal_again` | 観測していない |
| `t.T_NORMAL_ROMAJI.esc` | 観測していない |
| `t.T_NORMAL_ROMAJI.ctrl_c` | 観測していない |
| `t.T_NORMAL_POINT.nt_edit` | 観測していない |
| `t.T_NORMAL_POINT.t_normal_again` | 観測していない |
| `t.T_NORMAL_POINT.esc` | 観測していない |
| `t.T_NORMAL_POINT.ctrl_c` | 観測していない |
| `t.T_NORMAL_SELECT.nt_edit` | 観測していない |
| `t.T_NORMAL_SELECT.t_normal_again` | 観測していない |
| `t.T_NORMAL_SELECT.esc` | 観測していない |
| `t.T_NORMAL_SELECT.ctrl_c` | 観測していない |
| `t.T_NORMAL_OFF.nt_edit` | 観測していない |
| `t.T_NORMAL_OFF.t_normal_again` | 観測していない |
| `t.T_NORMAL_OFF.esc` | 観測していない |
| `t.T_NORMAL_OFF.ctrl_c` | 観測していない |
| `t.T_OFF.char` | 観測していない |
| `t.T_OFF.char_shift` | 観測していない |
| `t.T_OFF.key_x` | 観測していない |
| `t.T_OFF.key_X` | 観測していない |
| `t.T_OFF.key_L` | 観測していない |
| `t.T_OFF.key_l` | 観測していない |
| `t.T_OFF.key_q` | 観測していない |
| `t.T_OFF.key_semicolon` | 観測していない |
| `t.T_OFF.key_slash` | 観測していない |
| `t.T_OFF.key_gt` | 観測していない |
| `t.T_OFF.key_cq` | 観測していない |
| `t.T_OFF.bs` | 観測していない |
| `t.T_OFF.cr` | 観測していない |
| `t.T_OFF.space` | 観測していない |
| `t.T_OFF.nl` | 観測していない |
| `t.T_OFF.cg` | 観測していない |
| `t.T_OFF.esc` | 観測していない |
| `t.T_OFF.insert_key` | 観測していない |
| `t.T_OFF.ctrl_o` | 観測していない |
| `t.T_OFF.ctrl_r` | 観測していない |
| `t.T_OFF.ctrl_v` | 観測していない |
| `t.T_OFF.ctrl_k` | 観測していない |
| `t.T_OFF.ctrl_t` | 観測していない |
| `t.T_OFF.tab` | 観測していない |
| `t.T_OFF.ctrl_w` | 観測していない |
| `t.T_OFF.ctrl_u` | 観測していない |
| `t.T_OFF.ctrl_a` | 観測していない |
| `t.T_OFF.ctrl_at` | 観測していない |
| `t.T_OFF.completion_open` | 観測していない |
| `t.T_OFF.completion_accept` | 観測していない |
| `t.T_OFF.guard_special` | 観測していない |
| `t.T_ESCAPE.char` | 観測していない |
| `t.T_ESCAPE.char_shift` | 観測していない |
| `t.T_ESCAPE.key_x` | 観測していない |
| `t.T_ESCAPE.key_X` | 観測していない |
| `t.T_ESCAPE.key_L` | 観測していない |
| `t.T_ESCAPE.key_l` | 観測していない |
| `t.T_ESCAPE.key_q` | 観測していない |
| `t.T_ESCAPE.key_semicolon` | 観測していない |
| `t.T_ESCAPE.key_slash` | 観測していない |
| `t.T_ESCAPE.key_gt` | 観測していない |
| `t.T_ESCAPE.key_cq` | 観測していない |
| `t.T_ESCAPE.bs` | 観測していない |
| `t.T_ESCAPE.cr` | 観測していない |
| `t.T_ESCAPE.space` | 観測していない |
| `t.T_ESCAPE.nl` | 観測していない |
| `t.T_ESCAPE.cg` | 観測していない |
| `t.T_ESCAPE.esc` | 観測していない |
| `t.T_ESCAPE.insert_key` | 観測していない |
| `t.T_ESCAPE.ctrl_o` | 観測していない |
| `t.T_ESCAPE.ctrl_r` | 観測していない |
| `t.T_ESCAPE.ctrl_v` | 観測していない |
| `t.T_ESCAPE.ctrl_k` | 観測していない |
| `t.T_ESCAPE.ctrl_t` | 観測していない |
| `t.T_ESCAPE.tab` | 観測していない |
| `t.T_ESCAPE.ctrl_w` | 観測していない |
| `t.T_ESCAPE.ctrl_u` | 観測していない |
| `t.T_ESCAPE.ctrl_a` | 観測していない |
| `t.T_ESCAPE.ctrl_at` | 観測していない |
| `t.T_ESCAPE.completion_open` | 観測していない |
| `t.T_ESCAPE.completion_accept` | 観測していない |
| `t.T_ESCAPE.guard_special` | 観測していない |
| `t.T_DIRECT.char.keep` | 観測していない |
| `t.T_DIRECT.char.romaji` | 観測していない |
| `t.T_DIRECT.char_shift` | 観測していない |
| `t.T_DIRECT.char_shift.point` | 観測していない |
| `t.T_DIRECT.key_X` | 観測していない |
| `t.T_DIRECT.key_l` | 観測していない |
| `t.T_DIRECT.key_q` | 観測していない |
| `t.T_DIRECT.key_semicolon` | 観測していない |
| `t.T_DIRECT.key_slash` | 観測していない |
| `t.T_DIRECT.key_L` | 観測していない |
| `t.T_DIRECT.key_cq` | 観測していない |
| `t.T_DIRECT.key_gt` | 観測していない |
| `t.T_DIRECT.space` | 観測していない |
| `t.T_DIRECT.bs` | 観測していない |
| `t.T_DIRECT.cr` | 観測していない |
| `t.T_DIRECT.nl` | 観測していない |
| `t.T_DIRECT.cg` | 観測していない |
| `t.T_DIRECT.insert_key` | 観測していない |
| `t.T_DIRECT.ctrl_c` | 観測していない |
| `t.T_DIRECT.ctrl_o` | 観測していない |
| `t.T_DIRECT.ctrl_r` | 観測していない |
| `t.T_DIRECT.ctrl_a` | 観測していない |
| `t.T_DIRECT.ctrl_v` | 観測していない |
| `t.T_DIRECT.ctrl_k` | 観測していない |
| `t.T_DIRECT.ctrl_t` | 観測していない |
| `t.T_DIRECT.tab` | 観測していない |
| `t.T_DIRECT.ctrl_w` | 観測していない |
| `t.T_DIRECT.ctrl_u` | 観測していない |
| `t.T_DIRECT.ctrl_at` | 観測していない |
| `t.T_DIRECT.completion_open` | 観測していない |
| `t.T_DIRECT.completion_accept` | 観測していない |
| `t.T_DIRECT.guard_special` | 観測していない |
| `t.T_ROMAJI.char.keep` | 観測していない |
| `t.T_ROMAJI.char.commit` | 観測していない |
| `t.T_ROMAJI.char_shift` | 観測していない |
| `t.T_ROMAJI.key_X` | 観測していない |
| `t.T_ROMAJI.key_l` | 観測していない |
| `t.T_ROMAJI.key_q` | 観測していない |
| `t.T_ROMAJI.key_semicolon` | 観測していない |
| `t.T_ROMAJI.key_slash` | 観測していない |
| `t.T_ROMAJI.key_L` | 観測していない |
| `t.T_ROMAJI.key_cq` | 観測していない |
| `t.T_ROMAJI.key_gt` | 観測していない |
| `t.T_ROMAJI.space` | 観測していない |
| `t.T_ROMAJI.bs` | 観測していない |
| `t.T_ROMAJI.cr` | 観測していない |
| `t.T_ROMAJI.nl` | 観測していない |
| `t.T_ROMAJI.cg` | 観測していない |
| `t.T_ROMAJI.insert_key` | 観測していない |
| `t.T_ROMAJI.tab` | 観測していない |
| `t.T_ROMAJI.ctrl_c` | 観測していない |
| `t.T_ROMAJI.ctrl_o` | 観測していない |
| `t.T_ROMAJI.ctrl_a` | 観測していない |
| `t.T_ROMAJI.ctrl_r` | 観測していない |
| `t.T_ROMAJI.ctrl_v` | 観測していない |
| `t.T_ROMAJI.ctrl_k` | 観測していない |
| `t.T_ROMAJI.ctrl_t` | 観測していない |
| `t.T_ROMAJI.ctrl_w` | 観測していない |
| `t.T_ROMAJI.ctrl_u` | 観測していない |
| `t.T_ROMAJI.ctrl_at` | 観測していない |
| `t.T_ROMAJI.completion_open` | 観測していない |
| `t.T_ROMAJI.completion_accept` | 観測していない |
| `t.T_ROMAJI.guard_special` | 観測していない |
| `t.T_POINT.char` | 観測していない |
| `t.T_POINT.char_shift` | 観測していない |
| `t.T_POINT.key_X` | 観測していない |
| `t.T_POINT.key_l` | 観測していない |
| `t.T_POINT.key_q` | 観測していない |
| `t.T_POINT.key_semicolon` | 観測していない |
| `t.T_POINT.key_slash` | 観測していない |
| `t.T_POINT.key_L` | 観測していない |
| `t.T_POINT.key_gt` | 観測していない |
| `t.T_POINT.key_cq` | 観測していない |
| `t.T_POINT.space.select` | 観測していない |
| `t.T_POINT.bs` | 観測していない |
| `t.T_POINT.bs.empty` | 観測していない |
| `t.T_POINT.cr` | 観測していない |
| `t.T_POINT.nl` | 観測していない |
| `t.T_POINT.cg` | 観測していない |
| `t.T_POINT.insert_key` | 観測していない |
| `t.T_POINT.tab` | 観測していない |
| `t.T_POINT.ctrl_c` | 観測していない |
| `t.T_POINT.ctrl_o` | 観測していない |
| `t.T_POINT.ctrl_r` | 観測していない |
| `t.T_POINT.ctrl_v` | 観測していない |
| `t.T_POINT.ctrl_k` | 観測していない |
| `t.T_POINT.ctrl_t` | 観測していない |
| `t.T_POINT.ctrl_w` | 観測していない |
| `t.T_POINT.ctrl_u` | 観測していない |
| `t.T_POINT.ctrl_a` | 観測していない |
| `t.T_POINT.ctrl_at` | 観測していない |
| `t.T_POINT.completion_open` | 観測していない |
| `t.T_POINT.completion_accept` | 観測していない |
| `t.T_POINT.guard_special` | 観測していない |
| `t.T_SELECT.char.commit` | 観測していない |
| `t.T_SELECT.char.commit_romaji` | 観測していない |
| `t.T_SELECT.char_shift` | 観測していない |
| `t.T_SELECT.key_x.back` | 観測していない |
| `t.T_SELECT.key_x.prev` | 観測していない |
| `t.T_SELECT.key_X` | 観測していない |
| `t.T_SELECT.key_l` | 観測していない |
| `t.T_SELECT.key_q` | 観測していない |
| `t.T_SELECT.key_semicolon` | 観測していない |
| `t.T_SELECT.key_slash` | 観測していない |
| `t.T_SELECT.key_L` | 観測していない |
| `t.T_SELECT.key_gt` | 観測していない |
| `t.T_SELECT.key_cq` | 観測していない |
| `t.T_SELECT.space.next` | 観測していない |
| `t.T_SELECT.bs` | 観測していない |
| `t.T_SELECT.cr` | 観測していない |
| `t.T_SELECT.nl` | 観測していない |
| `t.T_SELECT.cg` | 観測していない |
| `t.T_SELECT.insert_key` | 観測していない |
| `t.T_SELECT.tab` | 観測していない |
| `t.T_SELECT.ctrl_c` | 観測していない |
| `t.T_SELECT.ctrl_a` | 観測していない |
| `t.T_SELECT.ctrl_r` | 観測していない |
| `t.T_SELECT.ctrl_v` | 観測していない |
| `t.T_SELECT.ctrl_k` | 観測していない |
| `t.T_SELECT.ctrl_t` | 観測していない |
| `t.T_SELECT.ctrl_w` | 観測していない |
| `t.T_SELECT.ctrl_u` | 観測していない |
| `t.T_SELECT.ctrl_at` | 観測していない |
| `t.T_SELECT.ctrl_o` | 観測していない |
| `t.T_SELECT.completion_open` | 観測していない |
| `t.T_SELECT.completion_accept` | 観測していない |
| `t.T_SELECT.guard_special` | 観測していない |

## 非決定の組（同じ状態・イベントで分かれる）

| 前 | イベント | 遷移先 | 前提（状態クラスに持っていない条件） |
|---|---|---|---|
| `I_DIRECT` | `char` | `I_DIRECT / I_ROMAJI` | 打った文字（かなになるか、ローマ字が続くか） |
| `I_DIRECT` | `char_shift` | `I_ROMAJI / I_POINT` | 打った文字（1 打でかなになるか、▽ を始めるか） |
| `I_DIRECT` | `esc` | `I_ESCAPE / N_OFF` | config.keepState |
| `I_DIRECT` | `stale` | `I_DIRECT / I_DIRECT / I_DIRECT` | どの autocmd か（カーソルだけのずれか、バッファが変わったか、ずれが無いか） |
| `I_POINT` | `bs` | `I_POINT / I_ROMAJI` | 読みの長さ（1 文字か、2 文字以上か） |
| `I_POINT` | `ctrl_a` | `I_DIRECT / I_POINT` | 前に挿入した文字があるか（バッファの中身） |
| `I_POINT` | `ctrl_u` | `I_DIRECT / I_POINT` | バッファに消す文字があるか |
| `I_POINT` | `ctrl_w` | `I_DIRECT / I_POINT` | バッファに消す文字があるか |
| `I_POINT` | `esc` | `I_ESCAPE / N_OFF` | config.keepState |
| `I_POINT` | `mouse_click` | `I_DIRECT / I_POINT` | クリックでカーソルが動くか（クリックした位置） |
| `I_POINT` | `space` | `I_SELECT / P_PROMPT_POINT` | 辞書に候補があるか／候補の位置 |
| `I_POINT` | `stale` | `I_DIRECT / I_DIRECT / I_POINT` | どの autocmd か（カーソルだけのずれか、バッファが変わったか、ずれが無いか） |
| `I_ROMAJI` | `bs` | `I_ROMAJI / I_DIRECT` | 読みの長さ（1 文字か、2 文字以上か） |
| `I_ROMAJI` | `char` | `I_ROMAJI / I_POINT` | 打った文字（かなになるか、ローマ字が続くか） |
| `I_ROMAJI` | `ctrl_a` | `I_DIRECT / I_ROMAJI` | 前に挿入した文字があるか（バッファの中身） |
| `I_ROMAJI` | `ctrl_u` | `I_DIRECT / I_ROMAJI` | バッファに消す文字があるか |
| `I_ROMAJI` | `ctrl_w` | `I_DIRECT / I_ROMAJI` | バッファに消す文字があるか |
| `I_ROMAJI` | `esc` | `I_ESCAPE / N_OFF` | config.keepState |
| `I_ROMAJI` | `mouse_click` | `I_DIRECT / I_ROMAJI` | クリックでカーソルが動くか（クリックした位置） |
| `I_ROMAJI` | `stale` | `I_DIRECT / I_DIRECT / I_ROMAJI` | どの autocmd か（カーソルだけのずれか、バッファが変わったか、ずれが無いか） |
| `I_SELECT` | `char` | `I_DIRECT / I_ROMAJI` | 打った文字（かなになるか、ローマ字が続くか） |
| `I_SELECT` | `ctrl_u` | `I_DIRECT / I_SELECT` | バッファに消す文字があるか |
| `I_SELECT` | `ctrl_w` | `I_DIRECT / I_SELECT` | バッファに消す文字があるか |
| `I_SELECT` | `esc` | `I_ESCAPE / N_OFF` | config.keepState |
| `I_SELECT` | `key_X` | `I_SELECT / P_PROMPT_SELECT` | 候補の位置（最後の候補で登録に入るか） |
| `I_SELECT` | `key_x` | `I_SELECT / I_POINT` | 候補の位置（最初の候補か、2 つ目以降か） |
| `I_SELECT` | `mouse_click` | `I_DIRECT / I_SELECT` | クリックでカーソルが動くか（クリックした位置） |
| `I_SELECT` | `space` | `I_SELECT / P_PROMPT_SELECT` | 辞書に候補があるか／候補の位置 |
| `I_SELECT` | `stale` | `I_DIRECT / I_DIRECT / I_SELECT` | どの autocmd か（カーソルだけのずれか、バッファが変わったか、ずれが無いか） |
| `N_OFF` | `insert_enter` | `I_DIRECT / I_OFF` | config.keepState |
| `T_DIRECT` | `char` | `T_DIRECT / T_ROMAJI` | 打った文字（かなになるか、ローマ字が続くか） |
| `T_DIRECT` | `char_shift` | `T_ROMAJI / T_POINT` | 打った文字（1 打でかなになるか、▽ を始めるか） |
| `T_POINT` | `bs` | `T_POINT / T_DIRECT` | 読みの長さ（1 文字か、2 文字以上か） |
| `T_ROMAJI` | `char` | `T_ROMAJI / T_DIRECT` | 打った文字（かなになるか、ローマ字が続くか） |
| `T_SELECT` | `char` | `T_DIRECT / T_ROMAJI` | 打った文字（かなになるか、ローマ字が続くか） |
| `T_SELECT` | `key_x` | `T_POINT / T_SELECT` | 候補の位置（最初の候補か、2 つ目以降か） |

## 人が読むクラスの中で、相によって終わりが割れるイベント

### `NI`

| イベント | 終わり |
|---|---|
| `ni_return_keep` | `I_DIRECT / I_POINT / I_SELECT` |
| `ni_v` | `V_IDLE / V_PRE` |

### `T_DIRECT`

| イベント | 終わり |
|---|---|
| `char` | `T_DIRECT / T_POINT` |
| `char_shift` | `T_DIRECT / T_POINT` |
| `key_X` | `T_DIRECT / T_POINT` |
| `key_semicolon` | `T_DIRECT / T_POINT` |

### `V_PRE`

| イベント | 終わり |
|---|---|
| `esc` | `I_POINT / I_SELECT` |

### `T_NORMAL`

| イベント | 終わり |
|---|---|
| `nt_insert` | `T_DIRECT / T_POINT` |

### `P_PROMPT`

| イベント | 終わり |
|---|---|
| `register_cancel` | `I_POINT / I_SELECT` |

### `T_POINT`

| イベント | 終わり |
|---|---|
| `bs` | `T_DIRECT / T_POINT` |
| `char` | `T_DIRECT / T_POINT` |
| `char_shift` | `T_DIRECT / T_POINT` |

