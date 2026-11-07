# SPIN のモデル（#193、親は #179）

`semantics/model/model.lua` の状態・イベント・遷移を Promela に写し、SPIN で性質 P1–P15 のうち表せるものを調べる。モデルのデータ源は `model.lua` だけで、`model.pml` は `gen_pml.lua` が作る。

この作業は今の振る舞いを書くだけで、望ましい振る舞いは決めない。見つけた振る舞いのうち、実装のバグは issue にして直さない。

## ファイル

- `model.pml`: Promela のモデル。手で直さない。
- `gen_pml.lua`: `model.lua` から `model.pml` を作る。状態 19・イベント 56・遷移 238 を確かめる。
- `check.lua`: SPIN を流し、Lua の `model_check.lua` と同じ違反になるかを見る。
- `counterexamples.md`: 反例と、`--replay` で実機に流した結果。

## 動かし方

SPIN（6.5.3 で確認）が要る。Fedora の dnf には spin のパッケージが無かったので、ソースからビルドして入れた。

```sh
git clone --depth 1 https://github.com/nimble-code/Spin.git /tmp/Spin
make -C /tmp/Spin
sudo install -m 755 /tmp/Spin/Src/spin /usr/local/bin/spin
```

モデルを作り直す。

```sh
nvim --headless -u NONE -i NONE -l semantics/spin/gen_pml.lua
```

検査する。SPIN の探索は重いので、ほかの検査と同時に流さず、`timeout` を付ける。

```sh
flock /tmp/heavy.lock timeout 1800 \
  nvim --headless -u NONE -i NONE -l semantics/spin/check.lua
```

SPIN を動かさず、Lua 側の違反と遷移列だけを見る。

```sh
SPIN_CHECK_DRY=1 nvim --headless -u NONE -i NONE -l semantics/spin/check.lua
```

## モデルの前提

- `config.keepState` は実行の初めに 0/1 を選び、その間は変えない。SPIN は両方を探索する。
- 辞書に候補があるか、バッファに文字があるか、補完のメニューが出ているかは状態クラスに持っていない。同じ (状態, イベント) で結果が分かれるところは、Promela の非決定選択として両方の遷移を並べる。分かれることの記録で、望ましさの判断ではない。
- autocmd（`winleave`、`bufleave`、`stale`、`completion_open` など）とキーの割り込み順は、次にどの遷移を選ぶかで表す。SPIN はそのすべての順番を探索する。
- バッファの中身・jumplist・辞書は持たない。状態は有限（状態クラスと `keepState` だけ）。Ganty の論文（SPIN 2024）が Neovim の状態を有限にするために設定とマッピングで挙動を止めたのと同じ考えで、ここでも辞書とバッファを状態から外している。
- c / terminal / 辞書登録の中 / 補完の中の細部は 07a–07d の担当。ここでは入口と出口だけを書く。

## 検査した性質

| 性質 | SPIN での表し方 | 結果 |
| --- | --- | --- |
| P1 読みが黙って消えない | `[] p1_ok`（遷移ごとのフラグ） | 36 件の違反。すべて `M.known` の P1 |
| P3 n / v / s / R で状態とマッピングが戻る | `[] p3_ok` | 違反 0 |
| P5 1 つのキーを二重に処理しない | `[] p5_ok` | 違反 0 |
| P10 同じ読みを 2 度確定しない | `[] p10_ok` | 違反 0 |
| P13 pending が片付く | `[] (transient -> <> !transient)` | 違反 0 |
| P8 enable のあと disable すると戻る | LTL では表さない（存在経路のため）。`check.lua` が Lua と同じ有向グラフの検査をする | 違反 0 |

P2 / P4 / P6 / P7 / P9 / P11 / P12 / P14 / P15 は、このモデルが持っていない層（表示、cmdline、terminal、辞書登録、かなモード、マッピングの数、片付けの繰り返し）が要るので検査しない。理由は `semantics/model/model.lua` の `M.properties` に書いてある。

P6（決定的に振る舞う）は、同じ (状態, イベント) で結果が分かれる組がモデルに 25 組あるため、SPIN では「非決定的」と出る。分かれている理由は辞書・バッファ・補完の有無で、状態クラスに持っていない。06 の比較で見る。

## Lua の検査器との関係

`check.lua` は P1/P3/P5/P10/P13 を `model_check.lua` と同じ規則で数え、P1 の違反遷移ごとに「その遷移に届くか」の LTL（`[] (last != N)`）を SPIN で調べる。SPIN が見つけた P1 の遷移は 36 件で、Lua の 36 件と一致した。知らない違反は無い。

P1 の反例の遷移列は `counterexamples.md` に書いた。実機で再生したところ、`M.known` のうち一部は今の `model.lua` の遷移（drop）と実機の振る舞い（読みを残す）が違った。モデルの誤りとして `counterexamples.md` に残す。`model.lua` はこのタスクでは直さない（04 の持ち物）。
