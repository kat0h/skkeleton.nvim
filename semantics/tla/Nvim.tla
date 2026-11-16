-------------------------------- MODULE Nvim --------------------------------
(***************************************************************************)
(* Neovim のキーの読み方の抽象（#264 の第 1 段）。                         *)
(*                                                                         *)
(* 書いてあるのは、入力の待ち行列、typebuf（先行入力）、feedkeys の旗、    *)
(* モード、続きのキーの待ち、マクロの記録に入るキーだけ。                  *)
(* Neovim のソースは読んでいない。動きはすべて README.md の仮定の表        *)
(* （N1 から N12）による。                                                 *)
(*                                                                         *)
(* キーの効き方は semantics/nvim/METHOD.md の類で書く。類は、軸 M（モード）*)
(* 、P（置き場所）、W（待ち）の値の組。                                    *)
(***************************************************************************)
EXTENDS Naturals, Sequences

CONSTANT NKeys      \* 利用者が打つキーの数の上限

ASSUME NKeys \in Nat \ {0}

VARIABLES
  inq,        \* 入力の待ち行列。打ったが、まだ typebuf に取り込まれていないキー
  ta,         \* typebuf。次に読まれるキーが先頭
  mode,       \* Vim のモード。"i" / "c" / "n"
  wait,       \* 続きのキーを待っているか（METHOD の W が「続きを待つ」のあと）
  recording,  \* マクロを記録しているか
  rec,        \* 記録に入ったキーの列
  nextId      \* 次に打つキーの番号

nvimVars == <<inq, ta, mode, wait, recording, rec, nextId>>

Ids == 1..NKeys

\* 利用者が打つキー。類 × 経路の升の代表（経路は Skkeleton.tla の Route）
Keys == {"a", "CR", "Left", "C-v", "Esc", "C-c"}

-----------------------------------------------------------------------------
(* typebuf と入力の待ち行列に入る項目 *)

\* kind  : "key"（キー）、"text"（skkeleton が流した確定文字列）、
\*         "finish"（skkeleton が流した <Cmd>lua ...finish()<CR>）
\* key   : kind が "key" のときのキーの名前。ほかは "-"
\* id    : もとになった、利用者の打ったキーの番号
\* src   : "user"（利用者が打った）、"skk"（skkeleton が feedkeys で流した）
\* typed : Neovim が打鍵として扱うか（feedkeys の "t"）
\* remap : マッピングを通るか（feedkeys の "n" なら FALSE）
Item == [kind : {"key", "text", "finish"}, key : Keys \cup {"-"}, id : Ids,
         src : {"user", "skk"}, typed : BOOLEAN, remap : BOOLEAN]

UserItem(k, i) ==
  [kind |-> "key", key |-> k, id |-> i, src |-> "user", typed |-> TRUE, remap |-> TRUE]

-----------------------------------------------------------------------------
(* 類。METHOD.md §6 の番号を添える。cmdline の類は METHOD に表が無いので、 *)
(* insert の類と同じ軸の値を借りた（README の仮定 K2）。                   *)

\* 文脈の組。"i+" と "c+" は続きのキーを待っている文脈
Contexts == {"i", "i+", "c", "c+", "n"}

Cls(from, to, il, p, w) ==
  [M |-> [from |-> from, to |-> to, il |-> il], P |-> p, W |-> w]

I_ADD  == Cls("i",  "i",  FALSE, "add",     "none")  \* 1  文字を足す
I_NL   == Cls("i",  "i",  FALSE, "newline", "none")  \* 2  改行する
I_WAIT == Cls("i",  "i+", FALSE, "none",    "wait")  \* 6  続きのキーを待つ
I_MOVE == Cls("i",  "i",  FALSE, "cursor",  "none")  \* 7  カーソルを動かす
I_ESC  == Cls("i",  "n",  TRUE,  "cursor",  "none")  \* 13 normal に抜ける（InsertLeave あり）
I_CC   == Cls("i",  "n",  FALSE, "cursor",  "none")  \* 14 normal に抜ける（InsertLeave なし）
I_ARG  == Cls("i+", "i",  FALSE, "add",     "none")  \* 21 引数を受けて足す
C_ADD  == Cls("c",  "c",  FALSE, "add",     "none")  \* cmdline の「文字を足す」
C_WAIT == Cls("c",  "c+", FALSE, "none",    "wait")  \* cmdline の「続きのキーを待つ」
C_MOVE == Cls("c",  "c",  FALSE, "cursor",  "none")  \* cmdline の「カーソルを動かす」
C_RUN  == Cls("c",  "n",  FALSE, "none",    "none")  \* cmdline の「実行して抜ける」
C_ESC  == Cls("c",  "n",  FALSE, "none",    "none")  \* cmdline の「捨てて抜ける」
C_ARG  == Cls("c+", "c",  FALSE, "add",     "none")  \* cmdline の「引数を受けて足す」
N_ANY  == Cls("n",  "n",  FALSE, "none",    "none")  \* normal（第 2 の環。ここでは何もしない）

\* いまの文脈
Ctx == IF wait THEN (IF mode = "i" THEN "i+" ELSE "c+") ELSE mode

\* 文脈 c でキー k を素通しにしたときの類。
\* 続きを待つ文脈では、どのキーも「引数を受けて足す」として扱う（仮定 K3）
ClassOf(k, c) ==
  CASE c = "n"  -> N_ANY
    [] c = "i+" -> I_ARG
    [] c = "c+" -> C_ARG
    [] c = "i"  -> (CASE k = "a"    -> I_ADD
                      [] k = "CR"   -> I_NL
                      [] k = "Left" -> I_MOVE
                      [] k = "C-v"  -> I_WAIT
                      [] k = "Esc"  -> I_ESC
                      [] k = "C-c"  -> I_CC)
    [] c = "c"  -> (CASE k = "a"    -> C_ADD
                      [] k = "CR"   -> C_RUN
                      [] k = "Left" -> C_MOVE
                      [] k = "C-v"  -> C_WAIT
                      [] k = "Esc"  -> C_ESC
                      [] k = "C-c"  -> C_ESC)

\* 文脈の組から Vim のモードへ
ModeOf(c) == CASE c = "i+" -> "i" [] c = "c+" -> "c" [] OTHER -> c

-----------------------------------------------------------------------------
(* Neovim だけで決まる動き *)

NvimInit ==
  /\ inq = <<>>
  /\ ta = <<>>
  /\ mode \in {"i", "c"}        \* skkeleton を有効にしたモードから始める
  /\ wait = FALSE
  /\ recording \in BOOLEAN      \* 記録中かどうかは、始めに決めて変えない
  /\ rec = <<>>
  /\ nextId = 1

\* 利用者がキーを打つ。入力の待ち行列の末尾に入る
UserType ==
  /\ nextId <= NKeys
  /\ \E k \in Keys : inq' = Append(inq, UserItem(k, nextId))
  /\ nextId' = nextId + 1
  /\ UNCHANGED <<ta, mode, wait, recording, rec>>

\* typebuf が空のとき、入力の待ち行列から 1 個以上をまとめて取り込む（仮定 N1）
Pull ==
  /\ ta = <<>>
  /\ inq # <<>>
  /\ \E n \in 1..Len(inq) :
       /\ ta' = SubSeq(inq, 1, n)
       /\ inq' = SubSeq(inq, n + 1, Len(inq))
  /\ UNCHANGED <<mode, wait, recording, rec, nextId>>

\* キー h を読んだあとの記録。打鍵として扱うキーだけが入る（仮定 N4、N10）
RecAfter(h) == IF recording /\ h.typed THEN Append(rec, h) ELSE rec

\* 類 c の M と W を当てる。P は skkeleton の側（置き場所）で使う
ApplyClass(c) ==
  /\ mode' = ModeOf(c.M.to)
  /\ wait' = (c.W = "wait")

\* 類 c で ModeChanged が出るか
ModeChanges(c) == ModeOf(c.M.to) # ModeOf(c.M.from)

NvimTypeOK ==
  /\ inq \in Seq(Item)
  /\ ta \in Seq(Item)
  /\ mode \in {"i", "c", "n"}
  /\ wait \in BOOLEAN
  /\ wait => mode \in {"i", "c"}
  /\ recording \in BOOLEAN
  /\ rec \in Seq(Item)
  /\ nextId \in 1..(NKeys + 1)

=============================================================================
