# 用語集（雛形）

Neovim のモードと skkeleton の入力状態を合わせた「今の」振る舞いを、タスクが同じ言葉で書けるようにする用語集です。親の issue は #179。ここに挙げた語の定義は、タスクが進むにつれて確定します。

## 3 層のモデル

状態は 3 つの層に分けて考えます。

1. **Vim のモード**：n / i / ni（`<C-o>`）/ R / v・s / c / cr / t / nt / ic / @（辞書登録のプロンプト）
2. **skkeleton の入力相**：off / direct / ▽ / ▼ / escape。かなのモード：hira / kata / hankata / zenkaku / abbrev
3. **表示**：pre-edit がどこにあるか（extmark / cmdline の文字 / terminal の文字）、popup、pending

## 状態クラス

人が読む状態クラスは約 20 個です。親の issue の一覧：

N_OFF、N_WAIT、N_LOST、V_PRE、I_DIRECT、I_POINT、I_SELECT、I_ESCAPE、I_PENDING、NI、IC、R_OFF、R_MID、C_DIRECT、C_POINT、C_REPLACE、P_PROMPT、T_DIRECT、T_POINT、T_NORMAL

全部の組み合わせは作りません。クラスを増やすのは、次のどちらかに当たるときだけです。

- Vim のモードが変わって、skkeleton の扱いが変わるとき
- モードは同じでも、読みが「確定する／消える／残る」で結果が分かれるとき

粒度は観測で決めます。同じクラスで同じイベントなのに結果が割れたら、クラスを分けます。いつも同じ結果になるクラスはまとめます。

## effects の語彙

遷移の結果（効果）を書くときの動詞です。各タスクは、同じ語で同じ効果を表します。

- `commit_reading`：読みを確定して流す
- `commit_candidate`：候補を確定して流す
- `cancel`：変換を取り消す
- `drop`：読みや候補を捨てる
- `keep`：読みや候補を残す
- `reset_state`：skkeleton の内部状態を元に戻す
- `restore_mapping`：退避したマッピングを元に戻す
- `clear_extmark`：pre-edit の extmark を消す
- `clean_cmdline`：cmdline の pre-edit を片付ける
- `render`：pre-edit を描き直す
- `feed_key`：キーを Neovim に流す
- `pass_key`：キーを skkeleton が奪わずに通す

## status

モデルと観測を突き合わせたときの一致の度合いです。

- `ok`：モデルどおり
- `gap`：モデルに書いていない遷移が観測で見つかった
- `unknown`：まだ観測できていない
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
