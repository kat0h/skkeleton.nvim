# モデルと観測の差（`probe.lua` の結果）

- 観測: 614 件（一致 176 / 不一致 0 / 観測できず 36）
- モデルにだけある遷移: 70
- 観測にだけある遷移: 330（説明付き 330 / 説明なし 0）
- effects の食い違い: 0
- 非決定: 25 組

## 未確定（モデルが決めていない遷移）

| 観測 | 前 | キー | 観測の終わり | モデル |
|---|---|---|---|---|
| `p.t.I_POINT.key_gt` | `I_POINT` | `>` | `P_PROMPT` | `I_SELECT` |
| `p.t.I_SELECT.key_gt` | `I_SELECT` | `>` | `I_POINT` | `I_SELECT` |

## 観測にだけある遷移

| 観測 | 前 | キー | 後 | 説明 |
|---|---|---|---|---|
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
| `x.I_OFF._Left_` | `I_OFF` | `<Left>` | `I_OFF` | モデルに無い自己遷移（観測では何も変わらない） |
| `x.I_OFF._S_Tab_` | `I_OFF` | `<S-Tab>` | `I_OFF` | skk が無効な insert / replace。キーは Vim がそのまま処理する（モデルは無効な状態からのキー入力を書いていない） |
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
| `c.feed.I_ROMAJI_EMPTY._Space_` | `I_ROMAJI` | `<Space>` | `I_ROMAJI` | モデルに無い自己遷移（観測では何も変わらない） |
| `c.feed.I_ROMAJI._Space_` | `I_ROMAJI` | `<Space>` | `I_ROMAJI` | モデルに無い自己遷移（観測では何も変わらない） |

## モデルにだけある遷移

| 遷移 | 確かめなかった理由 |
|---|---|
| `t.N_OFF.enable` | 到達しない状態からの遷移 |
| `t.I_OFF.enable` | 到達しない状態からの遷移 |
| `t.N_OFF.toggle` | 到達しない状態からの遷移 |
| `t.I_OFF.toggle` | 到達しない状態からの遷移 |
| `t.I_ESCAPE.cleanup` | 遷移の途中（internal）。キーで観測できない |
| `t.N_OFF.insert_enter.keepstate` | autocmd。キーで観測できない（probe では stale / winleave を打っていない） |
| `t.N_OFF.insert_enter` | autocmd。キーで観測できない（probe では stale / winleave を打っていない） |
| `t.I_DIRECT.stopinsert` | 到達しない状態からの遷移 |
| `t.I_DIRECT.mouse_select` | 入力（マウス・貼り付け）。キーで観測できない（07e #191） |
| `t.I_DIRECT.winleave` | autocmd。キーで観測できない（probe では stale / winleave を打っていない） |
| `t.I_DIRECT.bufleave` | autocmd。キーで観測できない（probe では stale / winleave を打っていない） |
| `t.I_ROMAJI.stopinsert` | 到達しない状態からの遷移 |
| `t.I_ROMAJI.mouse_select` | 入力（マウス・貼り付け）。キーで観測できない（07e #191） |
| `t.I_ROMAJI.winleave` | autocmd。キーで観測できない（probe では stale / winleave を打っていない） |
| `t.I_ROMAJI.bufleave` | autocmd。キーで観測できない（probe では stale / winleave を打っていない） |
| `t.I_POINT.stopinsert` | 到達しない状態からの遷移 |
| `t.I_POINT.mouse_select` | 入力（マウス・貼り付け）。キーで観測できない（07e #191） |
| `t.I_POINT.winleave` | autocmd。キーで観測できない（probe では stale / winleave を打っていない） |
| `t.I_POINT.bufleave` | autocmd。キーで観測できない（probe では stale / winleave を打っていない） |
| `t.I_SELECT.stopinsert` | 到達しない状態からの遷移 |
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
| `t.I_SELECT.key_X.register` | 到達しない状態からの遷移 |
| `t.P_PROMPT_POINT.register_commit` | 到達しない状態からの遷移 |
| `t.P_PROMPT_SELECT.register_commit` | 到達しない状態からの遷移 |
| `t.P_PROMPT_POINT.winleave` | autocmd。キーで観測できない（probe では stale / winleave を打っていない） |
| `t.P_PROMPT_SELECT.winleave` | autocmd。キーで観測できない（probe では stale / winleave を打っていない） |
| `t.I_DIRECT.ctrl_a` | 到達しない状態からの遷移 |
| `t.I_ROMAJI.ctrl_a` | 到達しない状態からの遷移 |
| `t.I_POINT.ctrl_a` | 到達しない状態からの遷移 |
| `t.I_SELECT.ctrl_a` | 到達しない状態からの遷移 |
| `t.I_DIRECT.ctrl_at` | 到達しない状態からの遷移 |
| `t.I_ROMAJI.ctrl_at` | 到達しない状態からの遷移 |
| `t.I_POINT.ctrl_at` | 到達しない状態からの遷移 |
| `t.I_SELECT.ctrl_at` | 到達しない状態からの遷移 |
| `t.IC.stale` | autocmd。キーで観測できない（probe では stale / winleave を打っていない） |
| `t.IC.winleave` | autocmd。キーで観測できない（probe では stale / winleave を打っていない） |
| `t.I_DIRECT.mouse_click` | 入力（マウス・貼り付け）。キーで観測できない（07e #191） |
| `t.I_ROMAJI.mouse_click` | 入力（マウス・貼り付け）。キーで観測できない（07e #191） |
| `t.I_POINT.mouse_click` | 入力（マウス・貼り付け）。キーで観測できない（07e #191） |
| `t.I_SELECT.mouse_click` | 入力（マウス・貼り付け）。キーで観測できない（07e #191） |
| `t.I_DIRECT.wheel` | 入力（マウス・貼り付け）。キーで観測できない（07e #191） |
| `t.I_ROMAJI.wheel` | 入力（マウス・貼り付け）。キーで観測できない（07e #191） |
| `t.I_POINT.wheel` | 入力（マウス・貼り付け）。キーで観測できない（07e #191） |
| `t.I_SELECT.wheel` | 入力（マウス・貼り付け）。キーで観測できない（07e #191） |
| `t.I_DIRECT.paste` | 入力（マウス・貼り付け）。キーで観測できない（07e #191） |
| `t.I_ROMAJI.paste` | 入力（マウス・貼り付け）。キーで観測できない（07e #191） |
| `t.I_POINT.paste` | 入力（マウス・貼り付け）。キーで観測できない（07e #191） |
| `t.I_SELECT.paste` | 入力（マウス・貼り付け）。キーで観測できない（07e #191） |
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

## 非決定の組（同じ状態・イベントで分かれる）

| 前 | イベント | 遷移先 | 前提（状態クラスに持っていない条件） |
|---|---|---|---|
| `I_DIRECT` | `char` | `I_DIRECT / I_ROMAJI` | 打った文字（かなになるか、ローマ字が続くか） |
| `I_DIRECT` | `char_shift` | `I_ROMAJI / I_POINT` | 打った文字（1 打でかなになるか、▽ を始めるか） |
| `I_DIRECT` | `esc` | `I_ESCAPE / N_OFF` | config.keepState |
| `I_DIRECT` | `stale` | `I_DIRECT / I_DIRECT / I_DIRECT` | どの autocmd か（カーソルだけのずれか、バッファが変わったか、ずれが無いか） |
| `I_POINT` | `bs` | `I_POINT / I_ROMAJI` | 読みの長さ（1 文字か、2 文字以上か） |
| `I_POINT` | `ctrl_u` | `I_DIRECT / I_POINT` | バッファに消す文字があるか |
| `I_POINT` | `ctrl_w` | `I_DIRECT / I_POINT` | バッファに消す文字があるか |
| `I_POINT` | `esc` | `I_ESCAPE / N_OFF` | config.keepState |
| `I_POINT` | `space` | `I_SELECT / P_PROMPT_POINT` | 辞書に候補があるか／候補の位置 |
| `I_POINT` | `stale` | `I_DIRECT / I_DIRECT / I_POINT` | どの autocmd か（カーソルだけのずれか、バッファが変わったか、ずれが無いか） |
| `I_ROMAJI` | `bs` | `I_ROMAJI / I_DIRECT` | 読みの長さ（1 文字か、2 文字以上か） |
| `I_ROMAJI` | `char` | `I_ROMAJI / I_POINT` | 打った文字（かなになるか、ローマ字が続くか） |
| `I_ROMAJI` | `ctrl_u` | `I_DIRECT / I_ROMAJI` | バッファに消す文字があるか |
| `I_ROMAJI` | `ctrl_w` | `I_DIRECT / I_ROMAJI` | バッファに消す文字があるか |
| `I_ROMAJI` | `esc` | `I_ESCAPE / N_OFF` | config.keepState |
| `I_ROMAJI` | `stale` | `I_DIRECT / I_DIRECT / I_ROMAJI` | どの autocmd か（カーソルだけのずれか、バッファが変わったか、ずれが無いか） |
| `I_SELECT` | `char` | `I_DIRECT / I_ROMAJI` | 打った文字（かなになるか、ローマ字が続くか） |
| `I_SELECT` | `ctrl_u` | `I_DIRECT / I_SELECT` | バッファに消す文字があるか |
| `I_SELECT` | `ctrl_w` | `I_DIRECT / I_SELECT` | バッファに消す文字があるか |
| `I_SELECT` | `esc` | `I_ESCAPE / N_OFF` | config.keepState |
| `I_SELECT` | `key_X` | `I_SELECT / P_PROMPT_SELECT` | 候補の位置（最後の候補で登録に入るか） |
| `I_SELECT` | `key_x` | `I_SELECT / I_POINT` | 候補の位置（最初の候補か、2 つ目以降か） |
| `I_SELECT` | `space` | `I_SELECT / P_PROMPT_SELECT` | 辞書に候補があるか／候補の位置 |
| `I_SELECT` | `stale` | `I_DIRECT / I_DIRECT / I_SELECT` | どの autocmd か（カーソルだけのずれか、バッファが変わったか、ずれが無いか） |
| `N_OFF` | `insert_enter` | `I_DIRECT / I_OFF` | config.keepState |

## 人が読むクラスの中で、相によって終わりが割れるイベント

### `NI`

| イベント | 終わり |
|---|---|
| `ni_return_keep` | `I_DIRECT / I_POINT / I_SELECT` |
| `ni_v` | `V_IDLE / V_PRE` |

### `V_PRE`

| イベント | 終わり |
|---|---|
| `esc` | `I_POINT / I_SELECT` |

### `P_PROMPT`

| イベント | 終わり |
|---|---|
| `register_cancel` | `I_POINT / I_SELECT` |

