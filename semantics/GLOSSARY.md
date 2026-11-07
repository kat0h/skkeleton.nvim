# 用語集（雛形）

Neovim のモードと skkeleton の入力状態を合わせた「今の」振る舞いを、タスクが同じ言葉で書けるようにする用語集です。親の issue は #179。ここに挙げた語の定義は、タスクが進むにつれて確定します。

## 3 層のモデル

状態は 3 つの層に分けて考えます。

1. **Vim のモード**：n / i / ni（`<C-o>`）/ R / v・s / c / cr / t / nt / ic / @（辞書登録のプロンプト）
2. **skkeleton の入力相**：off / direct / ▽ / ▼ / escape。かなのモード：hira / kata / hankata / zenkaku / abbrev
3. **表示**：pre-edit がどこにあるか（extmark / cmdline の文字 / terminal の文字）、popup、pending

## 状態クラス

人が読む状態クラスは約 20 個です。親の issue の一覧：

N_OFF、N_WAIT、V_PRE、V_IDLE、I_OFF、I_DIRECT、I_POINT、I_SELECT、I_ESCAPE、I_ROMAJI、NI、IC、R_OFF、C_DIRECT、C_POINT、C_REPLACE、P_PROMPT、T_DIRECT、T_POINT、T_NORMAL

全部の組み合わせは作りません。クラスを増やすのは、次のどちらかに当たるときだけです。

- Vim のモードが変わって、skkeleton の扱いが変わるとき
- モードは同じでも、読みが「確定する／消える／残る」で結果が分かれるとき

粒度は観測で決めます。同じクラスで同じイベントなのに結果が割れたら、クラスを分けます。いつも同じ結果になるクラスはまとめます。

- `I_OFF` は insert で skkeleton が無効な状態、`V_IDLE` は visual / select で有効のまま pre-edit が無い状態です。どちらも、同じキーで有効な状態と結果が違うので分けています。
- `N_OFF` は normal などで無効な状態です。`keepState` の one-shot 待ちも `N_OFF` のままで、遷移の guard（`config.keepState`）で表します。クラスは分けません。
  - 07f（#192）で、one-shot 待ちとマクロの記録中を内部状態 `N_KEEP` / `N_REC` に分けました。どちらも人が読むクラスは `N_OFF` です。`.` が one-shot を使い切る（#152）ことを観測で確かめたためです。
- `N_LOST` はクラスにしません。読みが消えるのは遷移の結果なので、effects の `drop` と P1 の破れで表します。
- `R_MID` は観測のクラスではありません。`<Insert>` による insert と replace の移り変わりの途中の状態（transient）としてだけ残します。
- `NI` / `V_PRE` / `P_PROMPT` は人が読むクラスは 1 つです。抱えている相（direct / point / select）は属性で持つので、仕様書では `NI（point）` のように書きます。モデルの中で `NI_POINT` などに分けてもかまいません。
- `I_ROMAJI` はローマ字の打ちかけ（`state.feed`）がある状態です。`pending` は `render.is_pending()` の意味だけに使います。
- `IC` は補完のメニューが開いている状態です。組み込みの補完（Vim のモードは `ic`）と blink.cmp のメニュー（Vim のモードは `i` のまま）を、人の読むクラスでは 1 つにまとめます。モデルの中では、組み込みの `IC`、キー待ちの `IX_DIRECT` / `IX_ROMAJI` / `IX_POINT` / `IX_SELECT`、blink の `I_BLINK_POINT` に分けます。
- `I_OFF_MENU` は、insert で skkeleton が無効のまま blink.cmp の buffer 補完のメニューが開いている状態です。見分け方が `I_OFF` と同じで、有効化したときにメニューを閉じるかどうかだけが違うので、モデルの中だけで分けます。

`V_PRE` は、`<C-o>v` で visual / select に入ったあと、pre-edit が描かれたまま残り続ける状態です。マウスのドラッグで `ModeChanged` の確定より前に一瞬残るもの（events.md の O18）は、状態ではなく遷移の途中（transient）として扱います。

cmdline（07a / #187）の 3 つは、次の意味で使います。

- `C_DIRECT` は、cmdline に pre-edit が無い状態です。skk が有効でない（`:` で入っただけ、disable した）ときも、c のマッピングが無い（visual から入った）ときも、観測はこのクラスになります。モデルの中では `C_OFF` / `C_IDLE` に分けています。
- `C_POINT` は、cmdline に pre-edit を本物の文字として書いている状態です。ローマ字の打ちかけ（`k`）、▽、▼ を、人が読むクラスではまとめます。モデルの中では `C_ROMAJI` / `C_POINT` / `C_SELECT` に分けています。
- `C_REPLACE` は、cmdline の置換モード（`cr`）です。`<Insert>` で入り、`<C-j>` で確定しても `cr` のまま、`<CR>` でコマンドを実行して抜けます。モデルの中では `<Insert>` の前の相（direct / romaji / point / select / 無効）で分けています。

terminal（07b / #188）の 3 つは、次の意味で使います。

- `T_DIRECT` は、terminal に pre-edit が無い状態です。skk が無効のとき（`terminal` で入っただけ、disable、`<Esc>` のあと）も、観測はこのクラスになります。モデルの中では `T_OFF` / `T_ESCAPE` / `T_DIRECT` に分けています。
- `T_POINT` は、terminal の行に pre-edit を本物の文字として書いている状態です。ローマ字の打ちかけ、▽、▼ を、人が読むクラスではまとめます。モデルの中では `T_ROMAJI` / `T_POINT` / `T_SELECT` に分けています。
- `T_NORMAL` は terminal-normal（`nt`）です。`<C-\><C-n>` で移っても skk は有効のままで、読みと pre-edit（端末の行の文字）を抱えたままです。モデルの中では抱えている相と有効・無効で `T_NORMAL_*` に分けています。

辞書登録のプロンプト（07c / #189）は、人が読むクラスを `P_PROMPT` の 1 つにします（作者の判断 4）。

- 外側の読みの相は `aspect`（point / select）に持ちます。プロンプトを開く前の ▽ / ▼ がどちらだったかで、取り消したときの戻り先が変わります。
- プロンプトの入れ子の深さは `depth`（1 / 2）に持ちます。深さ 2 からは、取り消しか確定で深さ 1 に戻り、insert へは直接抜けません。深さ 3 以上は同じ入れ子の繰り返しなので、07c では対象外にしました。
- `reading` は、プロンプトの中の読み（none / point）です。外側の読みは `aspect` に持つので、`reading` とは別です。

## effects の語彙

遷移の結果（効果）を書くときの動詞です。各タスクは、同じ語で同じ効果を表します。

- `commit_reading`：読みを確定して流す
- `commit_candidate`：候補を確定して流す
- `cancel`：変換を取り消す
- `drop`：読みや候補を捨てる
- `keep`：読みや候補を残す
- `reset_state`：skkeleton の内部状態を元に戻す
- `restore_mapping`：退避したマッピングを元に戻す
- `install_mapping`：skkeleton のマッピングを張る
- `save_mapping`：元のマッピングを退避する
- `clear_extmark`：pre-edit の extmark を消す
- `show_completion`：補完のメニューを開く
- `hide_completion`：補完のメニューを閉じる
- `clean_cmdline`：cmdline の pre-edit を片付ける
- `render`：pre-edit を描き直す
- `feed_key`：キーを Neovim に流す
- `pass_key`：キーを skkeleton が奪わずに通す

## status

モデルと観測を突き合わせたときの一致の度合いです。

- `ok`：モデルが今の振る舞いに合っている（コード読解か観測で確かめた）
- `gap`：今の振る舞いが性質（P1 など）を破っている（モデルの `M.known` に issue を書く）
- `unknown`：まだ確かめていない
- `impossible`：起こり得ない遷移

## 性質

破れたら不具合とみなす決まりです。親の issue の P1–P15。

- P1 読みが黙って消えない
- P2 pre-edit は 1 つだけで、置き場所が正しく、中身が state と一致する
- P3 n / v / s / R では、状態とマッピングが元に戻っている
- P4 cmdline / terminal を抜けたら、何も残っていない
- P5 1 つのキーを二重に処理しない
- P6 決定的に振る舞う（タイミングに左右されるものには印を付ける）
- P7 片付けは何度やっても同じ結果になる
- P8 enable のあと disable すると元に戻る
- P9 辞書登録の入れ子から漏れずに戻れる
- P10 同じ読みを 2 度確定しない
- P11 `g:skkeleton#mode` が中の状態と一致する
- P12 マッピングの範囲が正しい
- P13 pending が片付く
- P14 terminal の Ctrl を正しく扱う
- P15 state が空でないなら、pre-edit が見えている
