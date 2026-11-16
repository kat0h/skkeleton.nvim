------------------------------ MODULE Skkeleton ------------------------------
(***************************************************************************)
(* skkeleton の handler の抽象（#264 の第 1 段）。Nvim.tla の上に載せる。  *)
(*                                                                         *)
(* 書いてあるのは、マッピングの handler（main.handle）、guard（vim.on_key）*)
(* 、render の feed と finish、ModeChanged の反応だけ。core は 1 つの操作  *)
(* として扱い、結果を非決定に選ぶ。                                        *)
(*                                                                         *)
(* 根拠にしたコード（origin/main）：                                       *)
(*   lua/skkeleton/main.lua   handle_inner、commit_preedit                 *)
(*   lua/skkeleton/guard.lua  _on_key                                      *)
(*   lua/skkeleton/render.lua feed、update、finish                         *)
(***************************************************************************)
EXTENDS Nvim

\* どの時点のコードか。
\*   "before36"  : #36 を直す前。確定文字列をいつも "nit" で流す
\*   "before214" : #36 のあと、#214 の前。insert は "ni"、cmdline は "nit"
\*   "main"      : いまの main。cmdline でも、記録中は "t" を外す
CONSTANT Variant

ASSUME Variant \in {"before36", "before214", "main"}

VARIABLES
  pre,      \* 読み（pre-edit）を抱えているか
  pend,     \* render の pending。流した確定文字列のあとの finish を待っているか
  stale,    \* pre-edit の置き場所が、Neovim の変化でずれたか（METHOD の P）
  handled   \* 打ったキーごとの、skkeleton の handler が走った回数

skkVars == <<pre, pend, stale, handled>>
vars == <<inq, ta, mode, wait, recording, rec, nextId, pre, pend, stale, handled>>

\* 経路（METHOD.md §2.4）。キーごとに決まる。
\*   "map"    : マッピングが奪う
\*   "commit" : 奪わないが、guard が確定してから流し直す
\*   "pass"   : 奪わず、guard も何もしない
Route(k) ==
  CASE k \in {"a", "CR", "Esc"} -> "map"
    [] k = "Left"               -> "commit"
    [] k \in {"C-v", "C-c"}     -> "pass"

\* render.lua の feed が "t" を付けるか（m は流すときのモード）
FeedTyped(m) ==
  CASE Variant = "before36"  -> TRUE
    [] Variant = "before214" -> m # "i"
    [] OTHER                 -> (m # "i" /\ ~recording)

\* skkeleton が render.lua の feed で流す項目。"n" なのでマッピングを通らない
Fed(kind, k, i) ==
  [kind |-> kind, key |-> k, id |-> i, src |-> "skk",
   typed |-> FeedTyped(mode), remap |-> FALSE]

\* guard が nvim_feedkeys(key, "n") で流し直すキー。"t" は付かない
Refeed(k, i) ==
  [kind |-> "key", key |-> k, id |-> i, src |-> "skk", typed |-> FALSE, remap |-> FALSE]

Bump(i) == [handled EXCEPT ![i] = @ + 1]

-----------------------------------------------------------------------------

Init ==
  /\ NvimInit
  /\ pre = FALSE
  /\ pend = FALSE
  /\ stale = FALSE
  /\ handled = [i \in Ids |-> 0]

\* マッピングが奪うか。続きを待っている間のキーは、マッピングを通らない（仮定 N8）
IsMapped(h) ==
  /\ h.kind = "key"
  /\ h.remap
  /\ ~wait
  /\ mode \in {"i", "c"}
  /\ Route(h.key) = "map"

\* guard が確定するか。guard は続きの待ちを知らないので、wait は見ない
GuardCommits(h) ==
  /\ h.kind = "key"
  /\ h.typed
  /\ mode \in {"i", "c"}
  /\ Route(h.key) = "commit"
  /\ pre

\* <Cmd>lua ...finish()<CR> を読む。続きを待っているときは、引数として食われて
\* 実行されない（仮定 N11）
ConsumeFinish ==
  /\ ta # <<>>
  /\ Head(ta).kind = "finish"
  /\ ta' = Tail(ta)
  /\ rec' = RecAfter(Head(ta))
  /\ IF wait
       THEN wait' = FALSE /\ pend' = pend
       ELSE wait' = wait /\ pend' = FALSE
  /\ UNCHANGED <<inq, mode, recording, nextId, pre, stale, handled>>

\* 流した確定文字列を読む。マッピングは通らず、guard も何もしない
ConsumeText ==
  /\ ta # <<>>
  /\ Head(ta).kind = "text"
  /\ ta' = Tail(ta)
  /\ rec' = RecAfter(Head(ta))
  /\ wait' = FALSE
  /\ UNCHANGED <<inq, mode, recording, nextId, pre, pend, stale, handled>>

\* マッピングが奪ったキーを main.handle が処理する。
\* reset_if_stale のあと core を 1 回動かし、render.update が確定文字列を
\* typebuf の先頭に流す（feedkeys の "i"。仮定 N2）
ConsumeMapped ==
  /\ ta # <<>>
  /\ IsMapped(Head(ta))
  /\ LET h    == Head(ta)
         had  == pre /\ ~stale      \* ずれていたら、読みは捨てられている
         T    == Fed("text", "-", h.id)
         F    == Fed("finish", "-", h.id)
         K    == Fed("key", h.key, h.id)
         txt  == IF had THEN <<T>> ELSE <<>>
         outs ==
           CASE h.key = "a" ->
                  \* 読みを持つ（何も流さない）か、確定して流す
                  { [pre |-> TRUE,  pend |-> FALSE, fed |-> <<>>],
                    [pre |-> FALSE, pend |-> TRUE,  fed |-> <<T, F>>] }
             [] h.key = "CR" ->
                  \* 確定して改行を流す。cmdline を抜けるときは finish をその場で走らせる
                  IF mode = "i"
                    THEN { [pre |-> FALSE, pend |-> TRUE,  fed |-> txt \o <<K, F>>] }
                    ELSE { [pre |-> FALSE, pend |-> FALSE, fed |-> txt \o <<K>>] }
             [] h.key = "Esc" ->
                  \* 確定して <Esc> を流す。finish はその場で走らせる
                  { [pre |-> FALSE, pend |-> FALSE, fed |-> txt \o <<K>>] }
     IN /\ \E o \in outs :
             /\ pre' = o.pre
             /\ pend' = o.pend
             /\ ta' = o.fed \o Tail(ta)
        /\ rec' = RecAfter(h)
        /\ handled' = Bump(h.id)
  /\ stale' = FALSE
  /\ UNCHANGED <<inq, mode, wait, recording, nextId>>

\* guard が、奪われなかった打鍵を見て確定する。
\* commit_preedit が確定文字列と finish を先頭に流し、そのあと guard がキーを
\* "n" で末尾に流し直して、いまのキーは捨てる（仮定 N2、N7）
ConsumeGuard ==
  /\ ta # <<>>
  /\ ~IsMapped(Head(ta))
  /\ GuardCommits(Head(ta))
  /\ LET h == Head(ta)
     IN /\ ta' = <<Fed("text", "-", h.id), Fed("finish", "-", h.id)>>
                   \o Tail(ta) \o <<Refeed(h.key, h.id)>>
        /\ rec' = RecAfter(h)
        /\ handled' = Bump(h.id)
  /\ pre' = FALSE
  /\ pend' = TRUE
  /\ stale' = FALSE
  /\ UNCHANGED <<inq, mode, wait, recording, nextId>>

\* skkeleton が何もしないキーを、Neovim が類のとおりに処理する。
\* モードが変わると ModeChanged が同期して出て（仮定 N9）、skkeleton は状態を
\* 捨てる。SafeState を待つ道は第 2 段で書く（README の S4）
ConsumePlain ==
  /\ ta # <<>>
  /\ Head(ta).kind = "key"
  /\ ~IsMapped(Head(ta))
  /\ ~GuardCommits(Head(ta))
  /\ LET h == Head(ta)
         c == ClassOf(h.key, Ctx)
     IN /\ ta' = Tail(ta)
        /\ rec' = RecAfter(h)
        /\ ApplyClass(c)
        /\ IF ModeChanges(c)
             THEN pre' = FALSE /\ stale' = FALSE
             ELSE /\ pre' = pre
                  /\ stale' = (stale \/ (pre /\ c.P # "none" /\ h.src = "user"))
  /\ UNCHANGED <<inq, recording, nextId, pend, handled>>

Next ==
  \/ (UserType /\ UNCHANGED skkVars)
  \/ (Pull /\ UNCHANGED skkVars)
  \/ ConsumeFinish
  \/ ConsumeText
  \/ ConsumeMapped
  \/ ConsumeGuard
  \/ ConsumePlain

Spec == Init /\ [][Next]_vars

-----------------------------------------------------------------------------

TypeOK ==
  /\ NvimTypeOK
  /\ pre \in BOOLEAN
  /\ pend \in BOOLEAN
  /\ stale \in BOOLEAN
  /\ handled \in [Ids -> Nat]

\* P5：1 つのキーを二重に処理しない。
\* 打ったキー i について、handler が走るのは 1 回までで、i から skkeleton が
\* 流したキーは記録に入らない（入ると、再生のときに i の結果がもう一度入る）
P5 ==
  \A i \in Ids :
    /\ handled[i] <= 1
    /\ \A j \in DOMAIN rec : ~(rec[j].id = i /\ rec[j].src = "skk")

=============================================================================
