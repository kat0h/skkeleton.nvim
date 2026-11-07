/*
 * skkeleton.nvim の状態機械（#193、親は #179）
 *
 * これは semantics/model/model.lua を Promela に写したもの。手で直さない。
 * 作り直すとき: nvim --headless -u NONE -i NONE -l semantics/spin/gen_pml.lua
 *
 * 状態 19・イベント 56・遷移 238。model.lua と同じ数を gen_pml.lua が確かめる。
 *
 * 前提:
 * - config.keepState は最初に 0/1 を選び、その実行の間は変えない。SPIN は両方を探索する。
 * - 辞書に候補があるか、バッファに文字があるか、補完のメニューが出ているかは状態クラスに
 *   持っていない。同じ (状態, イベント) で結果が分かれるところは、Promela の
 *   非決定選択として両方の遷移を並べる。これは「分かれる」ことの記録で、望ましさの判断ではない。
 * - autocmd（winleave / bufleave / stale / completion_open など）とキーの割り込み順は、
 *   次にどの遷移を選ぶかで表す。SPIN はそのすべての順番を探索する。
 * - バッファの中身・jumplist・辞書は持たない。状態は有限（状態クラスと keepState だけ）。
 * - c / terminal / 辞書登録の中 / 補完の中の細部は 07a–07d の担当。ここでは入口と出口だけ。
 *
 * 性質は末尾の ltl。P1/P3/P5/P10 は遷移ごとの assert 相当（フラグ）、P13 は liveness。
 * P2/P4/P6/P7/P9/P11/P12/P14/P15 は、このモデルが持っていない層が要るので検査しない。
 */

mtype = { IC, I_DIRECT, I_ESCAPE, I_OFF, I_POINT, I_ROMAJI, I_SELECT, NI_DIRECT, NI_POINT, NI_SELECT, N_OFF, N_WAIT, P_PROMPT_POINT, P_PROMPT_SELECT, R_MID, R_OFF, V_IDLE, V_PRE_POINT, V_PRE_SELECT };

mtype state = N_OFF;
bool keep_state = false;
byte last = 0;

/* 直前の遷移の、from の事実と to の reading */
byte old_reading = 0;
bool old_enabled = false;
byte to_reading = 0;
bool duplicate_effect = false;

/* 効果のフラグ（遷移ごとに reset_effects で戻す） */
bool eff_commit_reading = false;
bool eff_commit_candidate = false;
bool eff_cancel = false;
bool eff_drop = false;
bool eff_keep = false;
bool eff_reset_state = false;
bool eff_restore_mapping = false;
bool eff_install_mapping = false;
bool eff_save_mapping = false;
bool eff_clear_extmark = false;
bool eff_clean_cmdline = false;
bool eff_render = false;
bool eff_feed_key = false;
bool eff_pass_key = false;

/* 性質のフラグ。false になったら、その性質は破れている */
bool p1_ok = true;
bool p3_ok = true;
bool p5_ok = true;
bool p10_ok = true;

inline reset_effects() {
  eff_commit_reading = false;
  eff_commit_candidate = false;
  eff_cancel = false;
  eff_drop = false;
  eff_keep = false;
  eff_reset_state = false;
  eff_restore_mapping = false;
  eff_install_mapping = false;
  eff_save_mapping = false;
  eff_clear_extmark = false;
  eff_clean_cmdline = false;
  eff_render = false;
  eff_feed_key = false;
  eff_pass_key = false;
}

inline check_properties() {
  /* P1: 読みが黙って消えない。確定・取消・keep の効果なしに reading が none へ移らない */
  if
  :: (old_reading != 0) && (to_reading == 0) &&
     !(eff_commit_reading || eff_commit_candidate || eff_cancel || eff_keep) ->
     p1_ok = false
  :: else -> skip
  fi;
  /* P3: n / v / s / R へ戻るときは reset_state と restore_mapping が揃っている */
  if
  :: old_enabled && (state == N_OFF || state == I_OFF || state == R_OFF) &&
     !(eff_reset_state && eff_restore_mapping) ->
     p3_ok = false
  :: else -> skip
  fi;
  /* P5 / P10: 同じ効果を 2 度、または読みと候補を同じ遷移で確定しない */
  if
  :: duplicate_effect ->
     p5_ok = false; p10_ok = false
  :: else -> skip
  fi;
  if
  :: eff_commit_reading && eff_commit_candidate ->
     p5_ok = false; p10_ok = false
  :: else -> skip
  fi
}

active proctype skk() {
  /* 設定は実行の初めに 1 つ選ぶ。SPIN は両方の実行を調べる */
  atomic {
    if
    :: keep_state = false
    :: keep_state = true
    fi
  }
  do

  /* TRANS t.N_OFF.enable event=enable from=N_OFF to=I_DIRECT */
  :: (state == N_OFF) ->
      atomic {
        last = 1;
        old_reading = 0;
        old_enabled = false;
        to_reading = 0;
        duplicate_effect = false;
        reset_effects();
        eff_reset_state = true;
        eff_install_mapping = true;
        eff_save_mapping = true;
        state = I_DIRECT;
        check_properties();
        printf("TRANS %d\n", last);
      }

  /* TRANS t.I_OFF.enable event=enable from=I_OFF to=I_DIRECT */
  :: (state == I_OFF) ->
      atomic {
        last = 2;
        old_reading = 0;
        old_enabled = false;
        to_reading = 0;
        duplicate_effect = false;
        reset_effects();
        eff_reset_state = true;
        eff_install_mapping = true;
        eff_save_mapping = true;
        state = I_DIRECT;
        check_properties();
        printf("TRANS %d\n", last);
      }

  /* TRANS t.N_OFF.toggle event=toggle from=N_OFF to=I_DIRECT */
  :: (state == N_OFF) ->
      atomic {
        last = 3;
        old_reading = 0;
        old_enabled = false;
        to_reading = 0;
        duplicate_effect = false;
        reset_effects();
        eff_reset_state = true;
        eff_install_mapping = true;
        eff_save_mapping = true;
        state = I_DIRECT;
        check_properties();
        printf("TRANS %d\n", last);
      }

  /* TRANS t.I_OFF.toggle event=toggle from=I_OFF to=I_DIRECT */
  :: (state == I_OFF) ->
      atomic {
        last = 4;
        old_reading = 0;
        old_enabled = false;
        to_reading = 0;
        duplicate_effect = false;
        reset_effects();
        eff_reset_state = true;
        eff_install_mapping = true;
        eff_save_mapping = true;
        state = I_DIRECT;
        check_properties();
        printf("TRANS %d\n", last);
      }

  /* TRANS t.I_DIRECT.toggle event=toggle from=I_DIRECT to=I_OFF */
  :: (state == I_DIRECT) ->
      atomic {
        last = 5;
        old_reading = 0;
        old_enabled = true;
        to_reading = 0;
        duplicate_effect = false;
        reset_effects();
        eff_reset_state = true;
        eff_restore_mapping = true;
        eff_clear_extmark = true;
        state = I_OFF;
        check_properties();
        printf("TRANS %d\n", last);
      }

  /* TRANS t.I_ROMAJI.toggle event=toggle from=I_ROMAJI to=I_OFF */
  :: (state == I_ROMAJI) ->
      atomic {
        last = 6;
        old_reading = 1;
        old_enabled = true;
        to_reading = 0;
        duplicate_effect = false;
        reset_effects();
        eff_commit_reading = true;
        eff_reset_state = true;
        eff_restore_mapping = true;
        eff_clear_extmark = true;
        state = I_OFF;
        check_properties();
        printf("TRANS %d\n", last);
      }

  /* TRANS t.I_POINT.toggle event=toggle from=I_POINT to=I_OFF */
  :: (state == I_POINT) ->
      atomic {
        last = 7;
        old_reading = 2;
        old_enabled = true;
        to_reading = 0;
        duplicate_effect = false;
        reset_effects();
        eff_commit_reading = true;
        eff_reset_state = true;
        eff_restore_mapping = true;
        eff_clear_extmark = true;
        state = I_OFF;
        check_properties();
        printf("TRANS %d\n", last);
      }

  /* TRANS t.I_SELECT.toggle event=toggle from=I_SELECT to=I_OFF */
  :: (state == I_SELECT) ->
      atomic {
        last = 8;
        old_reading = 3;
        old_enabled = true;
        to_reading = 0;
        duplicate_effect = false;
        reset_effects();
        eff_commit_candidate = true;
        eff_reset_state = true;
        eff_restore_mapping = true;
        eff_clear_extmark = true;
        state = I_OFF;
        check_properties();
        printf("TRANS %d\n", last);
      }

  /* TRANS t.I_DIRECT.disable event=disable from=I_DIRECT to=I_OFF */
  :: (state == I_DIRECT) ->
      atomic {
        last = 9;
        old_reading = 0;
        old_enabled = true;
        to_reading = 0;
        duplicate_effect = false;
        reset_effects();
        eff_reset_state = true;
        eff_restore_mapping = true;
        eff_clear_extmark = true;
        state = I_OFF;
        check_properties();
        printf("TRANS %d\n", last);
      }

  /* TRANS t.I_ROMAJI.disable event=disable from=I_ROMAJI to=I_OFF */
  :: (state == I_ROMAJI) ->
      atomic {
        last = 10;
        old_reading = 1;
        old_enabled = true;
        to_reading = 0;
        duplicate_effect = false;
        reset_effects();
        eff_commit_reading = true;
        eff_reset_state = true;
        eff_restore_mapping = true;
        eff_clear_extmark = true;
        state = I_OFF;
        check_properties();
        printf("TRANS %d\n", last);
      }

  /* TRANS t.I_POINT.disable event=disable from=I_POINT to=I_OFF */
  :: (state == I_POINT) ->
      atomic {
        last = 11;
        old_reading = 2;
        old_enabled = true;
        to_reading = 0;
        duplicate_effect = false;
        reset_effects();
        eff_commit_reading = true;
        eff_reset_state = true;
        eff_restore_mapping = true;
        eff_clear_extmark = true;
        state = I_OFF;
        check_properties();
        printf("TRANS %d\n", last);
      }

  /* TRANS t.I_SELECT.disable event=disable from=I_SELECT to=I_OFF */
  :: (state == I_SELECT) ->
      atomic {
        last = 12;
        old_reading = 3;
        old_enabled = true;
        to_reading = 0;
        duplicate_effect = false;
        reset_effects();
        eff_commit_candidate = true;
        eff_reset_state = true;
        eff_restore_mapping = true;
        eff_clear_extmark = true;
        state = I_OFF;
        check_properties();
        printf("TRANS %d\n", last);
      }

  /* TRANS t.NI_POINT.disable event=disable from=NI_POINT to=I_OFF */
  :: (state == NI_POINT) ->
      atomic {
        last = 13;
        old_reading = 2;
        old_enabled = true;
        to_reading = 0;
        duplicate_effect = false;
        reset_effects();
        eff_commit_reading = true;
        eff_reset_state = true;
        eff_restore_mapping = true;
        eff_clear_extmark = true;
        state = I_OFF;
        check_properties();
        printf("TRANS %d\n", last);
      }

  /* TRANS t.I_DIRECT.esc event=esc from=I_DIRECT to=I_ESCAPE */
  :: (state == I_DIRECT && !keep_state) ->
      atomic {
        last = 14;
        old_reading = 0;
        old_enabled = true;
        to_reading = 0;
        duplicate_effect = false;
        reset_effects();
        eff_reset_state = true;
        eff_restore_mapping = true;
        eff_clear_extmark = true;
        state = I_ESCAPE;
        check_properties();
        printf("TRANS %d\n", last);
      }

  /* TRANS t.I_ROMAJI.esc event=esc from=I_ROMAJI to=I_ESCAPE */
  :: (state == I_ROMAJI && !keep_state) ->
      atomic {
        last = 15;
        old_reading = 1;
        old_enabled = true;
        to_reading = 0;
        duplicate_effect = false;
        reset_effects();
        eff_commit_reading = true;
        eff_reset_state = true;
        eff_restore_mapping = true;
        eff_clear_extmark = true;
        state = I_ESCAPE;
        check_properties();
        printf("TRANS %d\n", last);
      }

  /* TRANS t.I_POINT.esc event=esc from=I_POINT to=I_ESCAPE */
  :: (state == I_POINT && !keep_state) ->
      atomic {
        last = 16;
        old_reading = 2;
        old_enabled = true;
        to_reading = 0;
        duplicate_effect = false;
        reset_effects();
        eff_commit_reading = true;
        eff_reset_state = true;
        eff_restore_mapping = true;
        eff_clear_extmark = true;
        state = I_ESCAPE;
        check_properties();
        printf("TRANS %d\n", last);
      }

  /* TRANS t.I_SELECT.esc event=esc from=I_SELECT to=I_ESCAPE */
  :: (state == I_SELECT && !keep_state) ->
      atomic {
        last = 17;
        old_reading = 3;
        old_enabled = true;
        to_reading = 0;
        duplicate_effect = false;
        reset_effects();
        eff_commit_candidate = true;
        eff_reset_state = true;
        eff_restore_mapping = true;
        eff_clear_extmark = true;
        state = I_ESCAPE;
        check_properties();
        printf("TRANS %d\n", last);
      }

  /* TRANS t.I_DIRECT.esc.keepstate event=esc from=I_DIRECT to=N_OFF */
  :: (state == I_DIRECT && keep_state) ->
      atomic {
        last = 18;
        old_reading = 0;
        old_enabled = true;
        to_reading = 0;
        duplicate_effect = false;
        reset_effects();
        eff_reset_state = true;
        eff_restore_mapping = true;
        eff_clear_extmark = true;
        state = N_OFF;
        check_properties();
        printf("TRANS %d\n", last);
      }

  /* TRANS t.I_ROMAJI.esc.keepstate event=esc from=I_ROMAJI to=N_OFF */
  :: (state == I_ROMAJI && keep_state) ->
      atomic {
        last = 19;
        old_reading = 1;
        old_enabled = true;
        to_reading = 0;
        duplicate_effect = false;
        reset_effects();
        eff_commit_reading = true;
        eff_reset_state = true;
        eff_restore_mapping = true;
        eff_clear_extmark = true;
        state = N_OFF;
        check_properties();
        printf("TRANS %d\n", last);
      }

  /* TRANS t.I_POINT.esc.keepstate event=esc from=I_POINT to=N_OFF */
  :: (state == I_POINT && keep_state) ->
      atomic {
        last = 20;
        old_reading = 2;
        old_enabled = true;
        to_reading = 0;
        duplicate_effect = false;
        reset_effects();
        eff_commit_reading = true;
        eff_reset_state = true;
        eff_restore_mapping = true;
        eff_clear_extmark = true;
        state = N_OFF;
        check_properties();
        printf("TRANS %d\n", last);
      }

  /* TRANS t.I_SELECT.esc.keepstate event=esc from=I_SELECT to=N_OFF */
  :: (state == I_SELECT && keep_state) ->
      atomic {
        last = 21;
        old_reading = 3;
        old_enabled = true;
        to_reading = 0;
        duplicate_effect = false;
        reset_effects();
        eff_commit_candidate = true;
        eff_reset_state = true;
        eff_restore_mapping = true;
        eff_clear_extmark = true;
        state = N_OFF;
        check_properties();
        printf("TRANS %d\n", last);
      }

  /* TRANS t.I_ESCAPE.cleanup event=cleanup_escape from=I_ESCAPE to=N_OFF */
  :: (state == I_ESCAPE) ->
      atomic {
        last = 22;
        old_reading = 0;
        old_enabled = false;
        to_reading = 0;
        duplicate_effect = false;
        reset_effects();
        eff_reset_state = true;
        state = N_OFF;
        check_properties();
        printf("TRANS %d\n", last);
      }

  /* TRANS t.N_OFF.insert_enter.keepstate event=insert_enter from=N_OFF to=I_DIRECT */
  :: (state == N_OFF && keep_state) ->
      atomic {
        last = 23;
        old_reading = 0;
        old_enabled = false;
        to_reading = 0;
        duplicate_effect = false;
        reset_effects();
        eff_reset_state = true;
        eff_install_mapping = true;
        eff_save_mapping = true;
        state = I_DIRECT;
        check_properties();
        printf("TRANS %d\n", last);
      }

  /* TRANS t.N_OFF.insert_enter event=insert_enter from=N_OFF to=I_OFF */
  :: (state == N_OFF && !keep_state) ->
      atomic {
        last = 24;
        old_reading = 0;
        old_enabled = false;
        to_reading = 0;
        duplicate_effect = false;
        reset_effects();
        eff_pass_key = true;
        state = I_OFF;
        check_properties();
        printf("TRANS %d\n", last);
      }

  /* TRANS t.I_OFF.esc event=esc from=I_OFF to=N_OFF */
  :: (state == I_OFF) ->
      atomic {
        last = 25;
        old_reading = 0;
        old_enabled = false;
        to_reading = 0;
        duplicate_effect = false;
        reset_effects();
        eff_pass_key = true;
        state = N_OFF;
        check_properties();
        printf("TRANS %d\n", last);
      }

  /* TRANS t.R_OFF.esc event=esc from=R_OFF to=N_OFF */
  :: (state == R_OFF) ->
      atomic {
        last = 26;
        old_reading = 0;
        old_enabled = false;
        to_reading = 0;
        duplicate_effect = false;
        reset_effects();
        eff_pass_key = true;
        state = N_OFF;
        check_properties();
        printf("TRANS %d\n", last);
      }

  /* TRANS t.N_OFF.esc event=esc from=N_OFF to=N_OFF */
  :: (state == N_OFF) ->
      atomic {
        last = 27;
        old_reading = 0;
        old_enabled = false;
        to_reading = 0;
        duplicate_effect = false;
        reset_effects();
        eff_pass_key = true;
        state = N_OFF;
        check_properties();
        printf("TRANS %d\n", last);
      }

  /* TRANS t.N_OFF.insert_key event=insert_key from=N_OFF to=R_OFF */
  :: (state == N_OFF) ->
      atomic {
        last = 28;
        old_reading = 0;
        old_enabled = false;
        to_reading = 0;
        duplicate_effect = false;
        reset_effects();
        eff_pass_key = true;
        state = R_OFF;
        check_properties();
        printf("TRANS %d\n", last);
      }

  /* TRANS t.I_OFF.insert_key event=insert_key from=I_OFF to=R_OFF */
  :: (state == I_OFF) ->
      atomic {
        last = 29;
        old_reading = 0;
        old_enabled = false;
        to_reading = 0;
        duplicate_effect = false;
        reset_effects();
        eff_pass_key = true;
        state = R_OFF;
        check_properties();
        printf("TRANS %d\n", last);
      }

  /* TRANS t.R_OFF.insert_key event=insert_key from=R_OFF to=I_OFF */
  :: (state == R_OFF) ->
      atomic {
        last = 30;
        old_reading = 0;
        old_enabled = false;
        to_reading = 0;
        duplicate_effect = false;
        reset_effects();
        eff_pass_key = true;
        state = I_OFF;
        check_properties();
        printf("TRANS %d\n", last);
      }

  /* TRANS t.I_DIRECT.ctrl_c event=ctrl_c from=I_DIRECT to=N_WAIT */
  :: (state == I_DIRECT) ->
      atomic {
        last = 31;
        old_reading = 0;
        old_enabled = true;
        to_reading = 4;
        duplicate_effect = false;
        reset_effects();
        state = N_WAIT;
        check_properties();
        printf("TRANS %d\n", last);
      }

  /* TRANS t.I_DIRECT.stopinsert event=stopinsert from=I_DIRECT to=N_OFF */
  :: (state == I_DIRECT) ->
      atomic {
        last = 32;
        old_reading = 0;
        old_enabled = true;
        to_reading = 0;
        duplicate_effect = false;
        reset_effects();
        eff_reset_state = true;
        eff_restore_mapping = true;
        eff_clear_extmark = true;
        state = N_OFF;
        check_properties();
        printf("TRANS %d\n", last);
      }

  /* TRANS t.I_DIRECT.mouse_select event=mouse_select from=I_DIRECT to=N_OFF */
  :: (state == I_DIRECT) ->
      atomic {
        last = 33;
        old_reading = 0;
        old_enabled = true;
        to_reading = 0;
        duplicate_effect = false;
        reset_effects();
        eff_reset_state = true;
        eff_restore_mapping = true;
        eff_clear_extmark = true;
        state = N_OFF;
        check_properties();
        printf("TRANS %d\n", last);
      }

  /* TRANS t.I_DIRECT.winleave event=winleave from=I_DIRECT to=N_OFF */
  :: (state == I_DIRECT) ->
      atomic {
        last = 34;
        old_reading = 0;
        old_enabled = true;
        to_reading = 0;
        duplicate_effect = false;
        reset_effects();
        eff_drop = true;
        eff_reset_state = true;
        eff_restore_mapping = true;
        eff_clear_extmark = true;
        state = N_OFF;
        check_properties();
        printf("TRANS %d\n", last);
      }

  /* TRANS t.I_DIRECT.bufleave event=bufleave from=I_DIRECT to=N_OFF */
  :: (state == I_DIRECT) ->
      atomic {
        last = 35;
        old_reading = 0;
        old_enabled = true;
        to_reading = 0;
        duplicate_effect = false;
        reset_effects();
        eff_drop = true;
        eff_reset_state = true;
        eff_restore_mapping = true;
        eff_clear_extmark = true;
        state = N_OFF;
        check_properties();
        printf("TRANS %d\n", last);
      }

  /* TRANS t.I_ROMAJI.ctrl_c event=ctrl_c from=I_ROMAJI to=N_WAIT */
  :: (state == I_ROMAJI) ->
      atomic {
        last = 36;
        old_reading = 1;
        old_enabled = true;
        to_reading = 4;
        duplicate_effect = false;
        reset_effects();
        state = N_WAIT;
        check_properties();
        printf("TRANS %d\n", last);
      }

  /* TRANS t.I_ROMAJI.stopinsert event=stopinsert from=I_ROMAJI to=N_OFF */
  :: (state == I_ROMAJI) ->
      atomic {
        last = 37;
        old_reading = 1;
        old_enabled = true;
        to_reading = 0;
        duplicate_effect = false;
        reset_effects();
        eff_commit_reading = true;
        eff_reset_state = true;
        eff_restore_mapping = true;
        eff_clear_extmark = true;
        state = N_OFF;
        check_properties();
        printf("TRANS %d\n", last);
      }

  /* TRANS t.I_ROMAJI.mouse_select event=mouse_select from=I_ROMAJI to=N_OFF */
  :: (state == I_ROMAJI) ->
      atomic {
        last = 38;
        old_reading = 1;
        old_enabled = true;
        to_reading = 0;
        duplicate_effect = false;
        reset_effects();
        eff_commit_reading = true;
        eff_reset_state = true;
        eff_restore_mapping = true;
        eff_clear_extmark = true;
        state = N_OFF;
        check_properties();
        printf("TRANS %d\n", last);
      }

  /* TRANS t.I_ROMAJI.winleave event=winleave from=I_ROMAJI to=N_OFF */
  :: (state == I_ROMAJI) ->
      atomic {
        last = 39;
        old_reading = 1;
        old_enabled = true;
        to_reading = 0;
        duplicate_effect = false;
        reset_effects();
        eff_drop = true;
        eff_reset_state = true;
        eff_restore_mapping = true;
        eff_clear_extmark = true;
        state = N_OFF;
        check_properties();
        printf("TRANS %d\n", last);
      }

  /* TRANS t.I_ROMAJI.bufleave event=bufleave from=I_ROMAJI to=N_OFF */
  :: (state == I_ROMAJI) ->
      atomic {
        last = 40;
        old_reading = 1;
        old_enabled = true;
        to_reading = 0;
        duplicate_effect = false;
        reset_effects();
        eff_drop = true;
        eff_reset_state = true;
        eff_restore_mapping = true;
        eff_clear_extmark = true;
        state = N_OFF;
        check_properties();
        printf("TRANS %d\n", last);
      }

  /* TRANS t.I_POINT.ctrl_c event=ctrl_c from=I_POINT to=N_WAIT */
  :: (state == I_POINT) ->
      atomic {
        last = 41;
        old_reading = 2;
        old_enabled = true;
        to_reading = 4;
        duplicate_effect = false;
        reset_effects();
        state = N_WAIT;
        check_properties();
        printf("TRANS %d\n", last);
      }

  /* TRANS t.I_POINT.stopinsert event=stopinsert from=I_POINT to=N_OFF */
  :: (state == I_POINT) ->
      atomic {
        last = 42;
        old_reading = 2;
        old_enabled = true;
        to_reading = 0;
        duplicate_effect = false;
        reset_effects();
        eff_commit_reading = true;
        eff_reset_state = true;
        eff_restore_mapping = true;
        eff_clear_extmark = true;
        state = N_OFF;
        check_properties();
        printf("TRANS %d\n", last);
      }

  /* TRANS t.I_POINT.mouse_select event=mouse_select from=I_POINT to=N_OFF */
  :: (state == I_POINT) ->
      atomic {
        last = 43;
        old_reading = 2;
        old_enabled = true;
        to_reading = 0;
        duplicate_effect = false;
        reset_effects();
        eff_commit_reading = true;
        eff_reset_state = true;
        eff_restore_mapping = true;
        eff_clear_extmark = true;
        state = N_OFF;
        check_properties();
        printf("TRANS %d\n", last);
      }

  /* TRANS t.I_POINT.winleave event=winleave from=I_POINT to=N_OFF */
  :: (state == I_POINT) ->
      atomic {
        last = 44;
        old_reading = 2;
        old_enabled = true;
        to_reading = 0;
        duplicate_effect = false;
        reset_effects();
        eff_drop = true;
        eff_reset_state = true;
        eff_restore_mapping = true;
        eff_clear_extmark = true;
        state = N_OFF;
        check_properties();
        printf("TRANS %d\n", last);
      }

  /* TRANS t.I_POINT.bufleave event=bufleave from=I_POINT to=N_OFF */
  :: (state == I_POINT) ->
      atomic {
        last = 45;
        old_reading = 2;
        old_enabled = true;
        to_reading = 0;
        duplicate_effect = false;
        reset_effects();
        eff_drop = true;
        eff_reset_state = true;
        eff_restore_mapping = true;
        eff_clear_extmark = true;
        state = N_OFF;
        check_properties();
        printf("TRANS %d\n", last);
      }

  /* TRANS t.I_SELECT.ctrl_c event=ctrl_c from=I_SELECT to=N_WAIT */
  :: (state == I_SELECT) ->
      atomic {
        last = 46;
        old_reading = 3;
        old_enabled = true;
        to_reading = 4;
        duplicate_effect = false;
        reset_effects();
        state = N_WAIT;
        check_properties();
        printf("TRANS %d\n", last);
      }

  /* TRANS t.I_SELECT.stopinsert event=stopinsert from=I_SELECT to=N_OFF */
  :: (state == I_SELECT) ->
      atomic {
        last = 47;
        old_reading = 3;
        old_enabled = true;
        to_reading = 0;
        duplicate_effect = false;
        reset_effects();
        eff_commit_reading = true;
        eff_reset_state = true;
        eff_restore_mapping = true;
        eff_clear_extmark = true;
        state = N_OFF;
        check_properties();
        printf("TRANS %d\n", last);
      }

  /* TRANS t.I_SELECT.mouse_select event=mouse_select from=I_SELECT to=N_OFF */
  :: (state == I_SELECT) ->
      atomic {
        last = 48;
        old_reading = 3;
        old_enabled = true;
        to_reading = 0;
        duplicate_effect = false;
        reset_effects();
        eff_commit_reading = true;
        eff_reset_state = true;
        eff_restore_mapping = true;
        eff_clear_extmark = true;
        state = N_OFF;
        check_properties();
        printf("TRANS %d\n", last);
      }

  /* TRANS t.I_SELECT.winleave event=winleave from=I_SELECT to=N_OFF */
  :: (state == I_SELECT) ->
      atomic {
        last = 49;
        old_reading = 3;
        old_enabled = true;
        to_reading = 0;
        duplicate_effect = false;
        reset_effects();
        eff_drop = true;
        eff_reset_state = true;
        eff_restore_mapping = true;
        eff_clear_extmark = true;
        state = N_OFF;
        check_properties();
        printf("TRANS %d\n", last);
      }

  /* TRANS t.I_SELECT.bufleave event=bufleave from=I_SELECT to=N_OFF */
  :: (state == I_SELECT) ->
      atomic {
        last = 50;
        old_reading = 3;
        old_enabled = true;
        to_reading = 0;
        duplicate_effect = false;
        reset_effects();
        eff_drop = true;
        eff_reset_state = true;
        eff_restore_mapping = true;
        eff_clear_extmark = true;
        state = N_OFF;
        check_properties();
        printf("TRANS %d\n", last);
      }

  /* TRANS t.N_WAIT.safestate event=safestate from=N_WAIT to=N_OFF */
  :: (state == N_WAIT) ->
      atomic {
        last = 51;
        old_reading = 4;
        old_enabled = true;
        to_reading = 0;
        duplicate_effect = false;
        reset_effects();
        eff_commit_reading = true;
        eff_reset_state = true;
        eff_restore_mapping = true;
        eff_clear_extmark = true;
        state = N_OFF;
        check_properties();
        printf("TRANS %d\n", last);
      }

  /* TRANS t.I_DIRECT.insert_key event=insert_key from=I_DIRECT to=R_MID */
  :: (state == I_DIRECT) ->
      atomic {
        last = 52;
        old_reading = 0;
        old_enabled = true;
        to_reading = 0;
        duplicate_effect = false;
        reset_effects();
        eff_clear_extmark = true;
        state = R_MID;
        check_properties();
        printf("TRANS %d\n", last);
      }

  /* TRANS t.I_ROMAJI.insert_key event=insert_key from=I_ROMAJI to=R_MID */
  :: (state == I_ROMAJI) ->
      atomic {
        last = 53;
        old_reading = 1;
        old_enabled = true;
        to_reading = 0;
        duplicate_effect = false;
        reset_effects();
        eff_commit_reading = true;
        eff_clear_extmark = true;
        state = R_MID;
        check_properties();
        printf("TRANS %d\n", last);
      }

  /* TRANS t.I_POINT.insert_key event=insert_key from=I_POINT to=R_MID */
  :: (state == I_POINT) ->
      atomic {
        last = 54;
        old_reading = 2;
        old_enabled = true;
        to_reading = 0;
        duplicate_effect = false;
        reset_effects();
        eff_commit_reading = true;
        eff_clear_extmark = true;
        state = R_MID;
        check_properties();
        printf("TRANS %d\n", last);
      }

  /* TRANS t.I_SELECT.insert_key event=insert_key from=I_SELECT to=R_MID */
  :: (state == I_SELECT) ->
      atomic {
        last = 55;
        old_reading = 3;
        old_enabled = true;
        to_reading = 0;
        duplicate_effect = false;
        reset_effects();
        eff_commit_candidate = true;
        eff_clear_extmark = true;
        state = R_MID;
        check_properties();
        printf("TRANS %d\n", last);
      }

  /* TRANS t.R_MID.modechanged event=modechanged_i_to_R from=R_MID to=R_OFF */
  :: (state == R_MID) ->
      atomic {
        last = 56;
        old_reading = 0;
        old_enabled = true;
        to_reading = 0;
        duplicate_effect = false;
        reset_effects();
        eff_reset_state = true;
        eff_restore_mapping = true;
        state = R_OFF;
        check_properties();
        printf("TRANS %d\n", last);
      }

  /* TRANS t.I_DIRECT.ctrl_o event=ctrl_o from=I_DIRECT to=NI_DIRECT */
  :: (state == I_DIRECT) ->
      atomic {
        last = 57;
        old_reading = 0;
        old_enabled = true;
        to_reading = 0;
        duplicate_effect = false;
        reset_effects();
        eff_keep = true;
        state = NI_DIRECT;
        check_properties();
        printf("TRANS %d\n", last);
      }

  /* TRANS t.I_ROMAJI.ctrl_o event=ctrl_o from=I_ROMAJI to=NI_DIRECT */
  :: (state == I_ROMAJI) ->
      atomic {
        last = 58;
        old_reading = 1;
        old_enabled = true;
        to_reading = 0;
        duplicate_effect = false;
        reset_effects();
        eff_keep = true;
        state = NI_DIRECT;
        check_properties();
        printf("TRANS %d\n", last);
      }

  /* TRANS t.I_POINT.ctrl_o event=ctrl_o from=I_POINT to=NI_POINT */
  :: (state == I_POINT) ->
      atomic {
        last = 59;
        old_reading = 2;
        old_enabled = true;
        to_reading = 2;
        duplicate_effect = false;
        reset_effects();
        eff_keep = true;
        state = NI_POINT;
        check_properties();
        printf("TRANS %d\n", last);
      }

  /* TRANS t.I_SELECT.ctrl_o event=ctrl_o from=I_SELECT to=NI_SELECT */
  :: (state == I_SELECT) ->
      atomic {
        last = 60;
        old_reading = 3;
        old_enabled = true;
        to_reading = 3;
        duplicate_effect = false;
        reset_effects();
        eff_keep = true;
        state = NI_SELECT;
        check_properties();
        printf("TRANS %d\n", last);
      }

  /* TRANS t.NI_DIRECT.return_commit event=ni_return_commit from=NI_DIRECT to=I_DIRECT */
  :: (state == NI_DIRECT) ->
      atomic {
        last = 61;
        old_reading = 0;
        old_enabled = true;
        to_reading = 0;
        duplicate_effect = false;
        reset_effects();
        eff_reset_state = true;
        eff_render = true;
        state = I_DIRECT;
        check_properties();
        printf("TRANS %d\n", last);
      }

  /* TRANS t.NI_DIRECT.return_drop event=ni_return_drop from=NI_DIRECT to=I_DIRECT */
  :: (state == NI_DIRECT) ->
      atomic {
        last = 62;
        old_reading = 0;
        old_enabled = true;
        to_reading = 0;
        duplicate_effect = false;
        reset_effects();
        eff_drop = true;
        eff_reset_state = true;
        eff_clear_extmark = true;
        eff_render = true;
        state = I_DIRECT;
        check_properties();
        printf("TRANS %d\n", last);
      }

  /* TRANS t.NI_POINT.return_commit event=ni_return_commit from=NI_POINT to=I_DIRECT */
  :: (state == NI_POINT) ->
      atomic {
        last = 63;
        old_reading = 2;
        old_enabled = true;
        to_reading = 0;
        duplicate_effect = false;
        reset_effects();
        eff_commit_reading = true;
        eff_reset_state = true;
        eff_render = true;
        state = I_DIRECT;
        check_properties();
        printf("TRANS %d\n", last);
      }

  /* TRANS t.NI_POINT.return_drop event=ni_return_drop from=NI_POINT to=I_DIRECT */
  :: (state == NI_POINT) ->
      atomic {
        last = 64;
        old_reading = 2;
        old_enabled = true;
        to_reading = 0;
        duplicate_effect = false;
        reset_effects();
        eff_drop = true;
        eff_reset_state = true;
        eff_clear_extmark = true;
        eff_render = true;
        state = I_DIRECT;
        check_properties();
        printf("TRANS %d\n", last);
      }

  /* TRANS t.NI_SELECT.return_commit event=ni_return_commit from=NI_SELECT to=I_DIRECT */
  :: (state == NI_SELECT) ->
      atomic {
        last = 65;
        old_reading = 3;
        old_enabled = true;
        to_reading = 0;
        duplicate_effect = false;
        reset_effects();
        eff_commit_candidate = true;
        eff_reset_state = true;
        eff_render = true;
        state = I_DIRECT;
        check_properties();
        printf("TRANS %d\n", last);
      }

  /* TRANS t.NI_SELECT.return_drop event=ni_return_drop from=NI_SELECT to=I_DIRECT */
  :: (state == NI_SELECT) ->
      atomic {
        last = 66;
        old_reading = 3;
        old_enabled = true;
        to_reading = 0;
        duplicate_effect = false;
        reset_effects();
        eff_drop = true;
        eff_reset_state = true;
        eff_clear_extmark = true;
        eff_render = true;
        state = I_DIRECT;
        check_properties();
        printf("TRANS %d\n", last);
      }

  /* TRANS t.NI_DIRECT.return_keep event=ni_return_keep from=NI_DIRECT to=I_DIRECT */
  :: (state == NI_DIRECT) ->
      atomic {
        last = 67;
        old_reading = 0;
        old_enabled = true;
        to_reading = 0;
        duplicate_effect = false;
        reset_effects();
        eff_keep = true;
        state = I_DIRECT;
        check_properties();
        printf("TRANS %d\n", last);
      }

  /* TRANS t.NI_POINT.return_keep event=ni_return_keep from=NI_POINT to=I_POINT */
  :: (state == NI_POINT) ->
      atomic {
        last = 68;
        old_reading = 2;
        old_enabled = true;
        to_reading = 2;
        duplicate_effect = false;
        reset_effects();
        eff_keep = true;
        state = I_POINT;
        check_properties();
        printf("TRANS %d\n", last);
      }

  /* TRANS t.NI_SELECT.return_keep event=ni_return_keep from=NI_SELECT to=I_SELECT */
  :: (state == NI_SELECT) ->
      atomic {
        last = 69;
        old_reading = 3;
        old_enabled = true;
        to_reading = 3;
        duplicate_effect = false;
        reset_effects();
        eff_keep = true;
        state = I_SELECT;
        check_properties();
        printf("TRANS %d\n", last);
      }

  /* TRANS t.NI_DIRECT.visual event=ctrl_o_v from=NI_DIRECT to=V_IDLE */
  :: (state == NI_DIRECT) ->
      atomic {
        last = 70;
        old_reading = 0;
        old_enabled = true;
        to_reading = 0;
        duplicate_effect = false;
        reset_effects();
        eff_keep = true;
        state = V_IDLE;
        check_properties();
        printf("TRANS %d\n", last);
      }

  /* TRANS t.NI_POINT.visual event=ctrl_o_v from=NI_POINT to=V_PRE_POINT */
  :: (state == NI_POINT) ->
      atomic {
        last = 71;
        old_reading = 2;
        old_enabled = true;
        to_reading = 2;
        duplicate_effect = false;
        reset_effects();
        eff_keep = true;
        eff_render = true;
        state = V_PRE_POINT;
        check_properties();
        printf("TRANS %d\n", last);
      }

  /* TRANS t.NI_SELECT.visual event=ctrl_o_v from=NI_SELECT to=V_PRE_SELECT */
  :: (state == NI_SELECT) ->
      atomic {
        last = 72;
        old_reading = 3;
        old_enabled = true;
        to_reading = 3;
        duplicate_effect = false;
        reset_effects();
        eff_keep = true;
        eff_render = true;
        state = V_PRE_SELECT;
        check_properties();
        printf("TRANS %d\n", last);
      }

  /* TRANS t.I_DIRECT.ctrl_o_v event=ctrl_o_v from=I_DIRECT to=V_IDLE */
  :: (state == I_DIRECT) ->
      atomic {
        last = 73;
        old_reading = 0;
        old_enabled = true;
        to_reading = 0;
        duplicate_effect = false;
        reset_effects();
        eff_keep = true;
        state = V_IDLE;
        check_properties();
        printf("TRANS %d\n", last);
      }

  /* TRANS t.I_POINT.ctrl_o_v event=ctrl_o_v from=I_POINT to=V_PRE_POINT */
  :: (state == I_POINT) ->
      atomic {
        last = 74;
        old_reading = 2;
        old_enabled = true;
        to_reading = 2;
        duplicate_effect = false;
        reset_effects();
        eff_keep = true;
        eff_render = true;
        state = V_PRE_POINT;
        check_properties();
        printf("TRANS %d\n", last);
      }

  /* TRANS t.I_SELECT.ctrl_o_v event=ctrl_o_v from=I_SELECT to=V_PRE_SELECT */
  :: (state == I_SELECT) ->
      atomic {
        last = 75;
        old_reading = 3;
        old_enabled = true;
        to_reading = 3;
        duplicate_effect = false;
        reset_effects();
        eff_keep = true;
        eff_render = true;
        state = V_PRE_SELECT;
        check_properties();
        printf("TRANS %d\n", last);
      }

  /* TRANS t.NI_DIRECT.replace event=ctrl_o_R from=NI_DIRECT to=R_OFF */
  :: (state == NI_DIRECT) ->
      atomic {
        last = 76;
        old_reading = 0;
        old_enabled = true;
        to_reading = 0;
        duplicate_effect = false;
        reset_effects();
        eff_reset_state = true;
        eff_restore_mapping = true;
        eff_clear_extmark = true;
        state = R_OFF;
        check_properties();
        printf("TRANS %d\n", last);
      }

  /* TRANS t.NI_POINT.replace event=ctrl_o_R from=NI_POINT to=R_OFF */
  :: (state == NI_POINT) ->
      atomic {
        last = 77;
        old_reading = 2;
        old_enabled = true;
        to_reading = 0;
        duplicate_effect = false;
        reset_effects();
        eff_commit_reading = true;
        eff_reset_state = true;
        eff_restore_mapping = true;
        eff_clear_extmark = true;
        state = R_OFF;
        check_properties();
        printf("TRANS %d\n", last);
      }

  /* TRANS t.NI_SELECT.replace event=ctrl_o_R from=NI_SELECT to=R_OFF */
  :: (state == NI_SELECT) ->
      atomic {
        last = 78;
        old_reading = 3;
        old_enabled = true;
        to_reading = 0;
        duplicate_effect = false;
        reset_effects();
        eff_commit_candidate = true;
        eff_reset_state = true;
        eff_restore_mapping = true;
        eff_clear_extmark = true;
        state = R_OFF;
        check_properties();
        printf("TRANS %d\n", last);
      }

  /* TRANS t.I_DIRECT.ctrl_o_R event=ctrl_o_R from=I_DIRECT to=R_OFF */
  :: (state == I_DIRECT) ->
      atomic {
        last = 79;
        old_reading = 0;
        old_enabled = true;
        to_reading = 0;
        duplicate_effect = false;
        reset_effects();
        eff_reset_state = true;
        eff_restore_mapping = true;
        eff_clear_extmark = true;
        state = R_OFF;
        check_properties();
        printf("TRANS %d\n", last);
      }

  /* TRANS t.I_POINT.ctrl_o_R event=ctrl_o_R from=I_POINT to=R_OFF */
  :: (state == I_POINT) ->
      atomic {
        last = 80;
        old_reading = 2;
        old_enabled = true;
        to_reading = 0;
        duplicate_effect = false;
        reset_effects();
        eff_commit_reading = true;
        eff_reset_state = true;
        eff_restore_mapping = true;
        eff_clear_extmark = true;
        state = R_OFF;
        check_properties();
        printf("TRANS %d\n", last);
      }

  /* TRANS t.I_SELECT.ctrl_o_R event=ctrl_o_R from=I_SELECT to=R_OFF */
  :: (state == I_SELECT) ->
      atomic {
        last = 81;
        old_reading = 3;
        old_enabled = true;
        to_reading = 0;
        duplicate_effect = false;
        reset_effects();
        eff_commit_candidate = true;
        eff_reset_state = true;
        eff_restore_mapping = true;
        eff_clear_extmark = true;
        state = R_OFF;
        check_properties();
        printf("TRANS %d\n", last);
      }

  /* TRANS t.NI_POINT.winleave event=winleave from=NI_POINT to=N_OFF */
  :: (state == NI_POINT) ->
      atomic {
        last = 82;
        old_reading = 2;
        old_enabled = true;
        to_reading = 0;
        duplicate_effect = false;
        reset_effects();
        eff_drop = true;
        eff_reset_state = true;
        eff_restore_mapping = true;
        eff_clear_extmark = true;
        state = N_OFF;
        check_properties();
        printf("TRANS %d\n", last);
      }

  /* TRANS t.NI_SELECT.winleave event=winleave from=NI_SELECT to=N_OFF */
  :: (state == NI_SELECT) ->
      atomic {
        last = 83;
        old_reading = 3;
        old_enabled = true;
        to_reading = 0;
        duplicate_effect = false;
        reset_effects();
        eff_drop = true;
        eff_reset_state = true;
        eff_restore_mapping = true;
        eff_clear_extmark = true;
        state = N_OFF;
        check_properties();
        printf("TRANS %d\n", last);
      }

  /* TRANS t.NI_DIRECT.winleave event=winleave from=NI_DIRECT to=N_OFF */
  :: (state == NI_DIRECT) ->
      atomic {
        last = 84;
        old_reading = 0;
        old_enabled = true;
        to_reading = 0;
        duplicate_effect = false;
        reset_effects();
        eff_reset_state = true;
        eff_restore_mapping = true;
        eff_clear_extmark = true;
        state = N_OFF;
        check_properties();
        printf("TRANS %d\n", last);
      }

  /* TRANS t.V_IDLE.esc event=esc from=V_IDLE to=I_DIRECT */
  :: (state == V_IDLE) ->
      atomic {
        last = 85;
        old_reading = 0;
        old_enabled = true;
        to_reading = 0;
        duplicate_effect = false;
        reset_effects();
        eff_keep = true;
        state = I_DIRECT;
        check_properties();
        printf("TRANS %d\n", last);
      }

  /* TRANS t.V_PRE_POINT.esc event=esc from=V_PRE_POINT to=I_POINT */
  :: (state == V_PRE_POINT) ->
      atomic {
        last = 86;
        old_reading = 2;
        old_enabled = true;
        to_reading = 2;
        duplicate_effect = false;
        reset_effects();
        eff_keep = true;
        eff_render = true;
        state = I_POINT;
        check_properties();
        printf("TRANS %d\n", last);
      }

  /* TRANS t.V_PRE_SELECT.esc event=esc from=V_PRE_SELECT to=I_SELECT */
  :: (state == V_PRE_SELECT) ->
      atomic {
        last = 87;
        old_reading = 3;
        old_enabled = true;
        to_reading = 3;
        duplicate_effect = false;
        reset_effects();
        eff_keep = true;
        eff_render = true;
        state = I_SELECT;
        check_properties();
        printf("TRANS %d\n", last);
      }

  /* TRANS t.V_PRE_POINT.winleave event=winleave from=V_PRE_POINT to=N_OFF */
  :: (state == V_PRE_POINT) ->
      atomic {
        last = 88;
        old_reading = 2;
        old_enabled = true;
        to_reading = 0;
        duplicate_effect = false;
        reset_effects();
        eff_drop = true;
        eff_reset_state = true;
        eff_restore_mapping = true;
        eff_clear_extmark = true;
        state = N_OFF;
        check_properties();
        printf("TRANS %d\n", last);
      }

  /* TRANS t.V_PRE_SELECT.winleave event=winleave from=V_PRE_SELECT to=N_OFF */
  :: (state == V_PRE_SELECT) ->
      atomic {
        last = 89;
        old_reading = 3;
        old_enabled = true;
        to_reading = 0;
        duplicate_effect = false;
        reset_effects();
        eff_drop = true;
        eff_reset_state = true;
        eff_restore_mapping = true;
        eff_clear_extmark = true;
        state = N_OFF;
        check_properties();
        printf("TRANS %d\n", last);
      }

  /* TRANS t.V_IDLE.winleave event=winleave from=V_IDLE to=N_OFF */
  :: (state == V_IDLE) ->
      atomic {
        last = 90;
        old_reading = 0;
        old_enabled = true;
        to_reading = 0;
        duplicate_effect = false;
        reset_effects();
        eff_reset_state = true;
        eff_restore_mapping = true;
        eff_clear_extmark = true;
        state = N_OFF;
        check_properties();
        printf("TRANS %d\n", last);
      }

  /* TRANS t.I_DIRECT.ctrl_o_colon event=ctrl_o_colon from=I_DIRECT to=I_DIRECT */
  :: (state == I_DIRECT) ->
      atomic {
        last = 91;
        old_reading = 0;
        old_enabled = true;
        to_reading = 0;
        duplicate_effect = false;
        reset_effects();
        eff_keep = true;
        eff_clean_cmdline = true;
        state = I_DIRECT;
        check_properties();
        printf("TRANS %d\n", last);
      }

  /* TRANS t.I_ROMAJI.ctrl_o_colon event=ctrl_o_colon from=I_ROMAJI to=I_ROMAJI */
  :: (state == I_ROMAJI) ->
      atomic {
        last = 92;
        old_reading = 1;
        old_enabled = true;
        to_reading = 1;
        duplicate_effect = false;
        reset_effects();
        eff_keep = true;
        eff_clean_cmdline = true;
        state = I_ROMAJI;
        check_properties();
        printf("TRANS %d\n", last);
      }

  /* TRANS t.I_POINT.ctrl_o_colon event=ctrl_o_colon from=I_POINT to=I_POINT */
  :: (state == I_POINT) ->
      atomic {
        last = 93;
        old_reading = 2;
        old_enabled = true;
        to_reading = 2;
        duplicate_effect = false;
        reset_effects();
        eff_keep = true;
        eff_clean_cmdline = true;
        state = I_POINT;
        check_properties();
        printf("TRANS %d\n", last);
      }

  /* TRANS t.I_SELECT.ctrl_o_colon event=ctrl_o_colon from=I_SELECT to=I_SELECT */
  :: (state == I_SELECT) ->
      atomic {
        last = 94;
        old_reading = 3;
        old_enabled = true;
        to_reading = 3;
        duplicate_effect = false;
        reset_effects();
        eff_keep = true;
        eff_clean_cmdline = true;
        state = I_SELECT;
        check_properties();
        printf("TRANS %d\n", last);
      }

  /* TRANS t.I_DIRECT.char.keep event=char from=I_DIRECT to=I_DIRECT */
  :: (state == I_DIRECT) ->
      atomic {
        last = 95;
        old_reading = 0;
        old_enabled = true;
        to_reading = 0;
        duplicate_effect = false;
        reset_effects();
        eff_feed_key = true;
        state = I_DIRECT;
        check_properties();
        printf("TRANS %d\n", last);
      }

  /* TRANS t.I_DIRECT.char.romaji event=char from=I_DIRECT to=I_ROMAJI */
  :: (state == I_DIRECT) ->
      atomic {
        last = 96;
        old_reading = 0;
        old_enabled = true;
        to_reading = 1;
        duplicate_effect = false;
        reset_effects();
        eff_render = true;
        eff_feed_key = true;
        state = I_ROMAJI;
        check_properties();
        printf("TRANS %d\n", last);
      }

  /* TRANS t.I_ROMAJI.char.keep event=char from=I_ROMAJI to=I_ROMAJI */
  :: (state == I_ROMAJI) ->
      atomic {
        last = 97;
        old_reading = 1;
        old_enabled = true;
        to_reading = 1;
        duplicate_effect = false;
        reset_effects();
        eff_render = true;
        eff_feed_key = true;
        state = I_ROMAJI;
        check_properties();
        printf("TRANS %d\n", last);
      }

  /* TRANS t.I_ROMAJI.char.commit event=char from=I_ROMAJI to=I_DIRECT */
  :: (state == I_ROMAJI) ->
      atomic {
        last = 98;
        old_reading = 1;
        old_enabled = true;
        to_reading = 0;
        duplicate_effect = false;
        reset_effects();
        eff_feed_key = true;
        state = I_DIRECT;
        check_properties();
        printf("TRANS %d\n", last);
      }

  /* TRANS t.I_POINT.char event=char from=I_POINT to=I_POINT */
  :: (state == I_POINT) ->
      atomic {
        last = 99;
        old_reading = 2;
        old_enabled = true;
        to_reading = 2;
        duplicate_effect = false;
        reset_effects();
        eff_keep = true;
        eff_render = true;
        state = I_POINT;
        check_properties();
        printf("TRANS %d\n", last);
      }

  /* TRANS t.I_SELECT.char.commit event=char from=I_SELECT to=I_DIRECT */
  :: (state == I_SELECT) ->
      atomic {
        last = 100;
        old_reading = 3;
        old_enabled = true;
        to_reading = 0;
        duplicate_effect = false;
        reset_effects();
        eff_commit_candidate = true;
        eff_reset_state = true;
        eff_feed_key = true;
        state = I_DIRECT;
        check_properties();
        printf("TRANS %d\n", last);
      }

  /* TRANS t.I_SELECT.char.commit_romaji event=char from=I_SELECT to=I_ROMAJI */
  :: (state == I_SELECT) ->
      atomic {
        last = 101;
        old_reading = 3;
        old_enabled = true;
        to_reading = 1;
        duplicate_effect = false;
        reset_effects();
        eff_commit_candidate = true;
        eff_render = true;
        eff_feed_key = true;
        state = I_ROMAJI;
        check_properties();
        printf("TRANS %d\n", last);
      }

  /* TRANS t.I_DIRECT.char_shift event=char_shift from=I_DIRECT to=I_ROMAJI */
  :: (state == I_DIRECT) ->
      atomic {
        last = 102;
        old_reading = 0;
        old_enabled = true;
        to_reading = 1;
        duplicate_effect = false;
        reset_effects();
        eff_render = true;
        state = I_ROMAJI;
        check_properties();
        printf("TRANS %d\n", last);
      }

  /* TRANS t.I_DIRECT.char_shift.point event=char_shift from=I_DIRECT to=I_POINT */
  :: (state == I_DIRECT) ->
      atomic {
        last = 103;
        old_reading = 0;
        old_enabled = true;
        to_reading = 2;
        duplicate_effect = false;
        reset_effects();
        eff_render = true;
        state = I_POINT;
        check_properties();
        printf("TRANS %d\n", last);
      }

  /* TRANS t.I_ROMAJI.char_shift event=char_shift from=I_ROMAJI to=I_POINT */
  :: (state == I_ROMAJI) ->
      atomic {
        last = 104;
        old_reading = 1;
        old_enabled = true;
        to_reading = 2;
        duplicate_effect = false;
        reset_effects();
        eff_keep = true;
        eff_render = true;
        state = I_POINT;
        check_properties();
        printf("TRANS %d\n", last);
      }

  /* TRANS t.I_POINT.char_shift event=char_shift from=I_POINT to=I_POINT */
  :: (state == I_POINT) ->
      atomic {
        last = 105;
        old_reading = 2;
        old_enabled = true;
        to_reading = 2;
        duplicate_effect = false;
        reset_effects();
        eff_keep = true;
        eff_render = true;
        state = I_POINT;
        check_properties();
        printf("TRANS %d\n", last);
      }

  /* TRANS t.I_SELECT.char_shift event=char_shift from=I_SELECT to=I_DIRECT */
  :: (state == I_SELECT) ->
      atomic {
        last = 106;
        old_reading = 3;
        old_enabled = true;
        to_reading = 0;
        duplicate_effect = false;
        reset_effects();
        eff_commit_candidate = true;
        eff_reset_state = true;
        eff_feed_key = true;
        state = I_DIRECT;
        check_properties();
        printf("TRANS %d\n", last);
      }

  /* TRANS t.I_DIRECT.key_X event=key_X from=I_DIRECT to=I_ROMAJI */
  :: (state == I_DIRECT) ->
      atomic {
        last = 107;
        old_reading = 0;
        old_enabled = true;
        to_reading = 1;
        duplicate_effect = false;
        reset_effects();
        eff_render = true;
        state = I_ROMAJI;
        check_properties();
        printf("TRANS %d\n", last);
      }

  /* TRANS t.I_POINT.key_X event=key_X from=I_POINT to=I_POINT */
  :: (state == I_POINT) ->
      atomic {
        last = 108;
        old_reading = 2;
        old_enabled = true;
        to_reading = 2;
        duplicate_effect = false;
        reset_effects();
        eff_keep = true;
        eff_render = true;
        state = I_POINT;
        check_properties();
        printf("TRANS %d\n", last);
      }

  /* TRANS t.I_DIRECT.key_l event=key_l from=I_DIRECT to=I_OFF */
  :: (state == I_DIRECT) ->
      atomic {
        last = 109;
        old_reading = 0;
        old_enabled = true;
        to_reading = 0;
        duplicate_effect = false;
        reset_effects();
        eff_reset_state = true;
        eff_restore_mapping = true;
        eff_clear_extmark = true;
        state = I_OFF;
        check_properties();
        printf("TRANS %d\n", last);
      }

  /* TRANS t.I_POINT.key_l event=key_l from=I_POINT to=I_OFF */
  :: (state == I_POINT) ->
      atomic {
        last = 110;
        old_reading = 2;
        old_enabled = true;
        to_reading = 0;
        duplicate_effect = false;
        reset_effects();
        eff_commit_reading = true;
        eff_reset_state = true;
        eff_restore_mapping = true;
        eff_clear_extmark = true;
        state = I_OFF;
        check_properties();
        printf("TRANS %d\n", last);
      }

  /* TRANS t.I_DIRECT.key_q event=key_q from=I_DIRECT to=I_DIRECT */
  :: (state == I_DIRECT) ->
      atomic {
        last = 111;
        old_reading = 0;
        old_enabled = true;
        to_reading = 0;
        duplicate_effect = false;
        reset_effects();
        eff_render = true;
        state = I_DIRECT;
        check_properties();
        printf("TRANS %d\n", last);
      }

  /* TRANS t.I_POINT.key_q event=key_q from=I_POINT to=I_POINT */
  :: (state == I_POINT) ->
      atomic {
        last = 112;
        old_reading = 2;
        old_enabled = true;
        to_reading = 2;
        duplicate_effect = false;
        reset_effects();
        eff_keep = true;
        eff_render = true;
        state = I_POINT;
        check_properties();
        printf("TRANS %d\n", last);
      }

  /* TRANS t.I_DIRECT.key_semicolon event=key_semicolon from=I_DIRECT to=I_POINT */
  :: (state == I_DIRECT) ->
      atomic {
        last = 113;
        old_reading = 0;
        old_enabled = true;
        to_reading = 2;
        duplicate_effect = false;
        reset_effects();
        eff_render = true;
        state = I_POINT;
        check_properties();
        printf("TRANS %d\n", last);
      }

  /* TRANS t.I_POINT.key_semicolon event=key_semicolon from=I_POINT to=I_POINT */
  :: (state == I_POINT) ->
      atomic {
        last = 114;
        old_reading = 2;
        old_enabled = true;
        to_reading = 2;
        duplicate_effect = false;
        reset_effects();
        eff_keep = true;
        eff_render = true;
        state = I_POINT;
        check_properties();
        printf("TRANS %d\n", last);
      }

  /* TRANS t.I_DIRECT.key_slash event=key_slash from=I_DIRECT to=I_DIRECT */
  :: (state == I_DIRECT) ->
      atomic {
        last = 115;
        old_reading = 0;
        old_enabled = true;
        to_reading = 0;
        duplicate_effect = false;
        reset_effects();
        eff_render = true;
        state = I_DIRECT;
        check_properties();
        printf("TRANS %d\n", last);
      }

  /* TRANS t.I_DIRECT.key_L event=key_L from=I_DIRECT to=I_DIRECT */
  :: (state == I_DIRECT) ->
      atomic {
        last = 116;
        old_reading = 0;
        old_enabled = true;
        to_reading = 0;
        duplicate_effect = false;
        reset_effects();
        eff_render = true;
        state = I_DIRECT;
        check_properties();
        printf("TRANS %d\n", last);
      }

  /* TRANS t.I_POINT.key_L event=key_L from=I_POINT to=I_POINT */
  :: (state == I_POINT) ->
      atomic {
        last = 117;
        old_reading = 2;
        old_enabled = true;
        to_reading = 2;
        duplicate_effect = false;
        reset_effects();
        eff_keep = true;
        eff_render = true;
        state = I_POINT;
        check_properties();
        printf("TRANS %d\n", last);
      }

  /* TRANS t.I_DIRECT.key_cq event=key_cq from=I_DIRECT to=I_DIRECT */
  :: (state == I_DIRECT) ->
      atomic {
        last = 118;
        old_reading = 0;
        old_enabled = true;
        to_reading = 0;
        duplicate_effect = false;
        reset_effects();
        eff_render = true;
        state = I_DIRECT;
        check_properties();
        printf("TRANS %d\n", last);
      }

  /* TRANS t.I_POINT.key_cq event=key_cq from=I_POINT to=I_POINT */
  :: (state == I_POINT) ->
      atomic {
        last = 119;
        old_reading = 2;
        old_enabled = true;
        to_reading = 2;
        duplicate_effect = false;
        reset_effects();
        eff_keep = true;
        eff_render = true;
        state = I_POINT;
        check_properties();
        printf("TRANS %d\n", last);
      }

  /* TRANS t.I_DIRECT.key_gt event=key_gt from=I_DIRECT to=I_DIRECT */
  :: (state == I_DIRECT) ->
      atomic {
        last = 120;
        old_reading = 0;
        old_enabled = true;
        to_reading = 0;
        duplicate_effect = false;
        reset_effects();
        eff_feed_key = true;
        state = I_DIRECT;
        check_properties();
        printf("TRANS %d\n", last);
      }

  /* TRANS t.I_POINT.key_gt event=key_gt from=I_POINT to=I_SELECT */
  :: (state == I_POINT) ->
      atomic {
        last = 121;
        old_reading = 2;
        old_enabled = true;
        to_reading = 3;
        duplicate_effect = false;
        reset_effects();
        eff_keep = true;
        eff_render = true;
        state = I_SELECT;
        check_properties();
        printf("TRANS %d\n", last);
      }

  /* TRANS t.I_SELECT.key_gt event=key_gt from=I_SELECT to=I_SELECT */
  :: (state == I_SELECT) ->
      atomic {
        last = 122;
        old_reading = 3;
        old_enabled = true;
        to_reading = 3;
        duplicate_effect = false;
        reset_effects();
        eff_keep = true;
        state = I_SELECT;
        check_properties();
        printf("TRANS %d\n", last);
      }

  /* TRANS t.I_POINT.space.select event=space from=I_POINT to=I_SELECT */
  :: (state == I_POINT) ->
      atomic {
        last = 123;
        old_reading = 2;
        old_enabled = true;
        to_reading = 3;
        duplicate_effect = false;
        reset_effects();
        eff_keep = true;
        eff_render = true;
        state = I_SELECT;
        check_properties();
        printf("TRANS %d\n", last);
      }

  /* TRANS t.I_POINT.space.register event=space from=I_POINT to=P_PROMPT_POINT */
  :: (state == I_POINT) ->
      atomic {
        last = 124;
        old_reading = 2;
        old_enabled = true;
        to_reading = 2;
        duplicate_effect = false;
        reset_effects();
        eff_keep = true;
        eff_render = true;
        state = P_PROMPT_POINT;
        check_properties();
        printf("TRANS %d\n", last);
      }

  /* TRANS t.I_SELECT.space.next event=space from=I_SELECT to=I_SELECT */
  :: (state == I_SELECT) ->
      atomic {
        last = 125;
        old_reading = 3;
        old_enabled = true;
        to_reading = 3;
        duplicate_effect = false;
        reset_effects();
        eff_keep = true;
        eff_render = true;
        state = I_SELECT;
        check_properties();
        printf("TRANS %d\n", last);
      }

  /* TRANS t.I_SELECT.space.register event=space from=I_SELECT to=P_PROMPT_SELECT */
  :: (state == I_SELECT) ->
      atomic {
        last = 126;
        old_reading = 3;
        old_enabled = true;
        to_reading = 3;
        duplicate_effect = false;
        reset_effects();
        eff_keep = true;
        eff_render = true;
        state = P_PROMPT_SELECT;
        check_properties();
        printf("TRANS %d\n", last);
      }

  /* TRANS t.I_SELECT.x.prev event=key_x from=I_SELECT to=I_SELECT */
  :: (state == I_SELECT) ->
      atomic {
        last = 127;
        old_reading = 3;
        old_enabled = true;
        to_reading = 3;
        duplicate_effect = false;
        reset_effects();
        eff_keep = true;
        eff_render = true;
        state = I_SELECT;
        check_properties();
        printf("TRANS %d\n", last);
      }

  /* TRANS t.I_SELECT.x.back event=key_x from=I_SELECT to=I_POINT */
  :: (state == I_SELECT) ->
      atomic {
        last = 128;
        old_reading = 3;
        old_enabled = true;
        to_reading = 2;
        duplicate_effect = false;
        reset_effects();
        eff_keep = true;
        eff_render = true;
        state = I_POINT;
        check_properties();
        printf("TRANS %d\n", last);
      }

  /* TRANS t.I_SELECT.key_X.purge event=key_X from=I_SELECT to=I_SELECT */
  :: (state == I_SELECT) ->
      atomic {
        last = 129;
        old_reading = 3;
        old_enabled = true;
        to_reading = 3;
        duplicate_effect = false;
        reset_effects();
        eff_keep = true;
        eff_render = true;
        state = I_SELECT;
        check_properties();
        printf("TRANS %d\n", last);
      }

  /* TRANS t.I_SELECT.key_X.register event=key_X from=I_SELECT to=P_PROMPT_SELECT */
  :: (state == I_SELECT) ->
      atomic {
        last = 130;
        old_reading = 3;
        old_enabled = true;
        to_reading = 3;
        duplicate_effect = false;
        reset_effects();
        eff_keep = true;
        eff_render = true;
        state = P_PROMPT_SELECT;
        check_properties();
        printf("TRANS %d\n", last);
      }

  /* TRANS t.P_PROMPT_POINT.register_commit event=register_commit from=P_PROMPT_POINT to=I_DIRECT */
  :: (state == P_PROMPT_POINT) ->
      atomic {
        last = 131;
        old_reading = 2;
        old_enabled = true;
        to_reading = 0;
        duplicate_effect = false;
        reset_effects();
        eff_commit_reading = true;
        eff_reset_state = true;
        eff_render = true;
        state = I_DIRECT;
        check_properties();
        printf("TRANS %d\n", last);
      }

  /* TRANS t.P_PROMPT_SELECT.register_commit event=register_commit from=P_PROMPT_SELECT to=I_DIRECT */
  :: (state == P_PROMPT_SELECT) ->
      atomic {
        last = 132;
        old_reading = 3;
        old_enabled = true;
        to_reading = 0;
        duplicate_effect = false;
        reset_effects();
        eff_commit_candidate = true;
        eff_reset_state = true;
        eff_render = true;
        state = I_DIRECT;
        check_properties();
        printf("TRANS %d\n", last);
      }

  /* TRANS t.P_PROMPT_POINT.register_cancel event=register_cancel from=P_PROMPT_POINT to=I_POINT */
  :: (state == P_PROMPT_POINT) ->
      atomic {
        last = 133;
        old_reading = 2;
        old_enabled = true;
        to_reading = 2;
        duplicate_effect = false;
        reset_effects();
        eff_keep = true;
        eff_render = true;
        state = I_POINT;
        check_properties();
        printf("TRANS %d\n", last);
      }

  /* TRANS t.P_PROMPT_SELECT.register_cancel event=register_cancel from=P_PROMPT_SELECT to=I_SELECT */
  :: (state == P_PROMPT_SELECT) ->
      atomic {
        last = 134;
        old_reading = 3;
        old_enabled = true;
        to_reading = 3;
        duplicate_effect = false;
        reset_effects();
        eff_keep = true;
        eff_render = true;
        state = I_SELECT;
        check_properties();
        printf("TRANS %d\n", last);
      }

  /* TRANS t.P_PROMPT_POINT.winleave event=winleave from=P_PROMPT_POINT to=P_PROMPT_POINT */
  :: (state == P_PROMPT_POINT) ->
      atomic {
        last = 135;
        old_reading = 2;
        old_enabled = true;
        to_reading = 2;
        duplicate_effect = false;
        reset_effects();
        eff_keep = true;
        eff_render = true;
        state = P_PROMPT_POINT;
        check_properties();
        printf("TRANS %d\n", last);
      }

  /* TRANS t.P_PROMPT_SELECT.winleave event=winleave from=P_PROMPT_SELECT to=P_PROMPT_SELECT */
  :: (state == P_PROMPT_SELECT) ->
      atomic {
        last = 136;
        old_reading = 3;
        old_enabled = true;
        to_reading = 3;
        duplicate_effect = false;
        reset_effects();
        eff_keep = true;
        eff_render = true;
        state = P_PROMPT_SELECT;
        check_properties();
        printf("TRANS %d\n", last);
      }

  /* TRANS t.I_DIRECT.nl event=nl from=I_DIRECT to=I_DIRECT */
  :: (state == I_DIRECT) ->
      atomic {
        last = 137;
        old_reading = 0;
        old_enabled = true;
        to_reading = 0;
        duplicate_effect = false;
        reset_effects();
        eff_feed_key = true;
        state = I_DIRECT;
        check_properties();
        printf("TRANS %d\n", last);
      }

  /* TRANS t.I_ROMAJI.nl event=nl from=I_ROMAJI to=I_DIRECT */
  :: (state == I_ROMAJI) ->
      atomic {
        last = 138;
        old_reading = 1;
        old_enabled = true;
        to_reading = 0;
        duplicate_effect = false;
        reset_effects();
        eff_commit_reading = true;
        eff_feed_key = true;
        state = I_DIRECT;
        check_properties();
        printf("TRANS %d\n", last);
      }

  /* TRANS t.I_POINT.nl event=nl from=I_POINT to=I_DIRECT */
  :: (state == I_POINT) ->
      atomic {
        last = 139;
        old_reading = 2;
        old_enabled = true;
        to_reading = 0;
        duplicate_effect = false;
        reset_effects();
        eff_commit_reading = true;
        eff_feed_key = true;
        state = I_DIRECT;
        check_properties();
        printf("TRANS %d\n", last);
      }

  /* TRANS t.I_SELECT.nl event=nl from=I_SELECT to=I_DIRECT */
  :: (state == I_SELECT) ->
      atomic {
        last = 140;
        old_reading = 3;
        old_enabled = true;
        to_reading = 0;
        duplicate_effect = false;
        reset_effects();
        eff_commit_candidate = true;
        eff_feed_key = true;
        state = I_DIRECT;
        check_properties();
        printf("TRANS %d\n", last);
      }

  /* TRANS t.I_DIRECT.cr event=cr from=I_DIRECT to=I_DIRECT */
  :: (state == I_DIRECT) ->
      atomic {
        last = 141;
        old_reading = 0;
        old_enabled = true;
        to_reading = 0;
        duplicate_effect = false;
        reset_effects();
        eff_feed_key = true;
        state = I_DIRECT;
        check_properties();
        printf("TRANS %d\n", last);
      }

  /* TRANS t.I_ROMAJI.cr event=cr from=I_ROMAJI to=I_DIRECT */
  :: (state == I_ROMAJI) ->
      atomic {
        last = 142;
        old_reading = 1;
        old_enabled = true;
        to_reading = 0;
        duplicate_effect = false;
        reset_effects();
        eff_commit_reading = true;
        eff_feed_key = true;
        state = I_DIRECT;
        check_properties();
        printf("TRANS %d\n", last);
      }

  /* TRANS t.I_POINT.cr event=cr from=I_POINT to=I_DIRECT */
  :: (state == I_POINT) ->
      atomic {
        last = 143;
        old_reading = 2;
        old_enabled = true;
        to_reading = 0;
        duplicate_effect = false;
        reset_effects();
        eff_commit_reading = true;
        eff_feed_key = true;
        state = I_DIRECT;
        check_properties();
        printf("TRANS %d\n", last);
      }

  /* TRANS t.I_SELECT.cr event=cr from=I_SELECT to=I_DIRECT */
  :: (state == I_SELECT) ->
      atomic {
        last = 144;
        old_reading = 3;
        old_enabled = true;
        to_reading = 0;
        duplicate_effect = false;
        reset_effects();
        eff_commit_candidate = true;
        eff_feed_key = true;
        state = I_DIRECT;
        check_properties();
        printf("TRANS %d\n", last);
      }

  /* TRANS t.I_DIRECT.cg event=cg from=I_DIRECT to=I_DIRECT */
  :: (state == I_DIRECT) ->
      atomic {
        last = 145;
        old_reading = 0;
        old_enabled = true;
        to_reading = 0;
        duplicate_effect = false;
        reset_effects();
        eff_pass_key = true;
        state = I_DIRECT;
        check_properties();
        printf("TRANS %d\n", last);
      }

  /* TRANS t.I_ROMAJI.cg event=cg from=I_ROMAJI to=I_DIRECT */
  :: (state == I_ROMAJI) ->
      atomic {
        last = 146;
        old_reading = 1;
        old_enabled = true;
        to_reading = 0;
        duplicate_effect = false;
        reset_effects();
        eff_cancel = true;
        eff_reset_state = true;
        state = I_DIRECT;
        check_properties();
        printf("TRANS %d\n", last);
      }

  /* TRANS t.I_POINT.cg event=cg from=I_POINT to=I_DIRECT */
  :: (state == I_POINT) ->
      atomic {
        last = 147;
        old_reading = 2;
        old_enabled = true;
        to_reading = 0;
        duplicate_effect = false;
        reset_effects();
        eff_cancel = true;
        eff_reset_state = true;
        state = I_DIRECT;
        check_properties();
        printf("TRANS %d\n", last);
      }

  /* TRANS t.I_SELECT.cg event=cg from=I_SELECT to=I_DIRECT */
  :: (state == I_SELECT) ->
      atomic {
        last = 148;
        old_reading = 3;
        old_enabled = true;
        to_reading = 0;
        duplicate_effect = false;
        reset_effects();
        eff_cancel = true;
        eff_reset_state = true;
        state = I_DIRECT;
        check_properties();
        printf("TRANS %d\n", last);
      }

  /* TRANS t.I_POINT.bs event=bs from=I_POINT to=I_POINT */
  :: (state == I_POINT) ->
      atomic {
        last = 149;
        old_reading = 2;
        old_enabled = true;
        to_reading = 2;
        duplicate_effect = false;
        reset_effects();
        eff_keep = true;
        eff_render = true;
        state = I_POINT;
        check_properties();
        printf("TRANS %d\n", last);
      }

  /* TRANS t.I_POINT.bs.empty event=bs from=I_POINT to=I_DIRECT */
  :: (state == I_POINT) ->
      atomic {
        last = 150;
        old_reading = 2;
        old_enabled = true;
        to_reading = 0;
        duplicate_effect = false;
        reset_effects();
        eff_cancel = true;
        eff_reset_state = true;
        eff_clear_extmark = true;
        state = I_DIRECT;
        check_properties();
        printf("TRANS %d\n", last);
      }

  /* TRANS t.I_ROMAJI.bs event=bs from=I_ROMAJI to=I_ROMAJI */
  :: (state == I_ROMAJI) ->
      atomic {
        last = 151;
        old_reading = 1;
        old_enabled = true;
        to_reading = 1;
        duplicate_effect = false;
        reset_effects();
        eff_keep = true;
        eff_render = true;
        state = I_ROMAJI;
        check_properties();
        printf("TRANS %d\n", last);
      }

  /* TRANS t.I_ROMAJI.bs.empty event=bs from=I_ROMAJI to=I_DIRECT */
  :: (state == I_ROMAJI) ->
      atomic {
        last = 152;
        old_reading = 1;
        old_enabled = true;
        to_reading = 0;
        duplicate_effect = false;
        reset_effects();
        eff_cancel = true;
        eff_reset_state = true;
        state = I_DIRECT;
        check_properties();
        printf("TRANS %d\n", last);
      }

  /* TRANS t.I_DIRECT.bs event=bs from=I_DIRECT to=I_DIRECT */
  :: (state == I_DIRECT) ->
      atomic {
        last = 153;
        old_reading = 0;
        old_enabled = true;
        to_reading = 0;
        duplicate_effect = false;
        reset_effects();
        eff_feed_key = true;
        state = I_DIRECT;
        check_properties();
        printf("TRANS %d\n", last);
      }

  /* TRANS t.I_SELECT.bs event=bs from=I_SELECT to=I_DIRECT */
  :: (state == I_SELECT) ->
      atomic {
        last = 154;
        old_reading = 3;
        old_enabled = true;
        to_reading = 0;
        duplicate_effect = false;
        reset_effects();
        eff_commit_candidate = true;
        eff_reset_state = true;
        eff_feed_key = true;
        state = I_DIRECT;
        check_properties();
        printf("TRANS %d\n", last);
      }

  /* TRANS t.I_DIRECT.ctrl_r event=ctrl_r from=I_DIRECT to=I_DIRECT */
  :: (state == I_DIRECT) ->
      atomic {
        last = 155;
        old_reading = 0;
        old_enabled = true;
        to_reading = 0;
        duplicate_effect = false;
        reset_effects();
        eff_feed_key = true;
        state = I_DIRECT;
        check_properties();
        printf("TRANS %d\n", last);
      }

  /* TRANS t.I_ROMAJI.ctrl_r event=ctrl_r from=I_ROMAJI to=I_DIRECT */
  :: (state == I_ROMAJI) ->
      atomic {
        last = 156;
        old_reading = 1;
        old_enabled = true;
        to_reading = 0;
        duplicate_effect = false;
        reset_effects();
        eff_drop = true;
        eff_reset_state = true;
        eff_clear_extmark = true;
        eff_render = true;
        state = I_DIRECT;
        check_properties();
        printf("TRANS %d\n", last);
      }

  /* TRANS t.I_POINT.ctrl_r event=ctrl_r from=I_POINT to=I_DIRECT */
  :: (state == I_POINT) ->
      atomic {
        last = 157;
        old_reading = 2;
        old_enabled = true;
        to_reading = 0;
        duplicate_effect = false;
        reset_effects();
        eff_drop = true;
        eff_reset_state = true;
        eff_clear_extmark = true;
        eff_render = true;
        state = I_DIRECT;
        check_properties();
        printf("TRANS %d\n", last);
      }

  /* TRANS t.I_SELECT.ctrl_r event=ctrl_r from=I_SELECT to=I_DIRECT */
  :: (state == I_SELECT) ->
      atomic {
        last = 158;
        old_reading = 3;
        old_enabled = true;
        to_reading = 0;
        duplicate_effect = false;
        reset_effects();
        eff_commit_candidate = true;
        eff_reset_state = true;
        eff_clear_extmark = true;
        eff_feed_key = true;
        state = I_DIRECT;
        check_properties();
        printf("TRANS %d\n", last);
      }

  /* TRANS t.I_DIRECT.ctrl_v event=ctrl_v from=I_DIRECT to=I_DIRECT */
  :: (state == I_DIRECT) ->
      atomic {
        last = 159;
        old_reading = 0;
        old_enabled = true;
        to_reading = 0;
        duplicate_effect = false;
        reset_effects();
        eff_feed_key = true;
        state = I_DIRECT;
        check_properties();
        printf("TRANS %d\n", last);
      }

  /* TRANS t.I_ROMAJI.ctrl_v event=ctrl_v from=I_ROMAJI to=I_DIRECT */
  :: (state == I_ROMAJI) ->
      atomic {
        last = 160;
        old_reading = 1;
        old_enabled = true;
        to_reading = 0;
        duplicate_effect = false;
        reset_effects();
        eff_drop = true;
        eff_reset_state = true;
        eff_clear_extmark = true;
        eff_render = true;
        state = I_DIRECT;
        check_properties();
        printf("TRANS %d\n", last);
      }

  /* TRANS t.I_POINT.ctrl_v event=ctrl_v from=I_POINT to=I_DIRECT */
  :: (state == I_POINT) ->
      atomic {
        last = 161;
        old_reading = 2;
        old_enabled = true;
        to_reading = 0;
        duplicate_effect = false;
        reset_effects();
        eff_drop = true;
        eff_reset_state = true;
        eff_clear_extmark = true;
        eff_render = true;
        state = I_DIRECT;
        check_properties();
        printf("TRANS %d\n", last);
      }

  /* TRANS t.I_SELECT.ctrl_v event=ctrl_v from=I_SELECT to=I_DIRECT */
  :: (state == I_SELECT) ->
      atomic {
        last = 162;
        old_reading = 3;
        old_enabled = true;
        to_reading = 0;
        duplicate_effect = false;
        reset_effects();
        eff_commit_candidate = true;
        eff_reset_state = true;
        eff_clear_extmark = true;
        eff_feed_key = true;
        state = I_DIRECT;
        check_properties();
        printf("TRANS %d\n", last);
      }

  /* TRANS t.I_DIRECT.ctrl_k event=ctrl_k from=I_DIRECT to=I_DIRECT */
  :: (state == I_DIRECT) ->
      atomic {
        last = 163;
        old_reading = 0;
        old_enabled = true;
        to_reading = 0;
        duplicate_effect = false;
        reset_effects();
        eff_feed_key = true;
        state = I_DIRECT;
        check_properties();
        printf("TRANS %d\n", last);
      }

  /* TRANS t.I_ROMAJI.ctrl_k event=ctrl_k from=I_ROMAJI to=I_DIRECT */
  :: (state == I_ROMAJI) ->
      atomic {
        last = 164;
        old_reading = 1;
        old_enabled = true;
        to_reading = 0;
        duplicate_effect = false;
        reset_effects();
        eff_drop = true;
        eff_reset_state = true;
        eff_clear_extmark = true;
        eff_render = true;
        state = I_DIRECT;
        check_properties();
        printf("TRANS %d\n", last);
      }

  /* TRANS t.I_POINT.ctrl_k event=ctrl_k from=I_POINT to=I_DIRECT */
  :: (state == I_POINT) ->
      atomic {
        last = 165;
        old_reading = 2;
        old_enabled = true;
        to_reading = 0;
        duplicate_effect = false;
        reset_effects();
        eff_drop = true;
        eff_reset_state = true;
        eff_clear_extmark = true;
        eff_render = true;
        state = I_DIRECT;
        check_properties();
        printf("TRANS %d\n", last);
      }

  /* TRANS t.I_SELECT.ctrl_k event=ctrl_k from=I_SELECT to=I_DIRECT */
  :: (state == I_SELECT) ->
      atomic {
        last = 166;
        old_reading = 3;
        old_enabled = true;
        to_reading = 0;
        duplicate_effect = false;
        reset_effects();
        eff_commit_candidate = true;
        eff_reset_state = true;
        eff_clear_extmark = true;
        eff_feed_key = true;
        state = I_DIRECT;
        check_properties();
        printf("TRANS %d\n", last);
      }

  /* TRANS t.I_DIRECT.ctrl_t event=ctrl_t from=I_DIRECT to=I_DIRECT */
  :: (state == I_DIRECT) ->
      atomic {
        last = 167;
        old_reading = 0;
        old_enabled = true;
        to_reading = 0;
        duplicate_effect = false;
        reset_effects();
        eff_feed_key = true;
        state = I_DIRECT;
        check_properties();
        printf("TRANS %d\n", last);
      }

  /* TRANS t.I_ROMAJI.ctrl_t event=ctrl_t from=I_ROMAJI to=I_DIRECT */
  :: (state == I_ROMAJI) ->
      atomic {
        last = 168;
        old_reading = 1;
        old_enabled = true;
        to_reading = 0;
        duplicate_effect = false;
        reset_effects();
        eff_drop = true;
        eff_reset_state = true;
        eff_clear_extmark = true;
        eff_render = true;
        state = I_DIRECT;
        check_properties();
        printf("TRANS %d\n", last);
      }

  /* TRANS t.I_POINT.ctrl_t event=ctrl_t from=I_POINT to=I_DIRECT */
  :: (state == I_POINT) ->
      atomic {
        last = 169;
        old_reading = 2;
        old_enabled = true;
        to_reading = 0;
        duplicate_effect = false;
        reset_effects();
        eff_drop = true;
        eff_reset_state = true;
        eff_clear_extmark = true;
        eff_render = true;
        state = I_DIRECT;
        check_properties();
        printf("TRANS %d\n", last);
      }

  /* TRANS t.I_SELECT.ctrl_t event=ctrl_t from=I_SELECT to=I_DIRECT */
  :: (state == I_SELECT) ->
      atomic {
        last = 170;
        old_reading = 3;
        old_enabled = true;
        to_reading = 0;
        duplicate_effect = false;
        reset_effects();
        eff_commit_candidate = true;
        eff_reset_state = true;
        eff_clear_extmark = true;
        eff_feed_key = true;
        state = I_DIRECT;
        check_properties();
        printf("TRANS %d\n", last);
      }

  /* TRANS t.I_DIRECT.tab event=tab from=I_DIRECT to=I_DIRECT */
  :: (state == I_DIRECT) ->
      atomic {
        last = 171;
        old_reading = 0;
        old_enabled = true;
        to_reading = 0;
        duplicate_effect = false;
        reset_effects();
        eff_feed_key = true;
        state = I_DIRECT;
        check_properties();
        printf("TRANS %d\n", last);
      }

  /* TRANS t.I_ROMAJI.tab event=tab from=I_ROMAJI to=I_DIRECT */
  :: (state == I_ROMAJI) ->
      atomic {
        last = 172;
        old_reading = 1;
        old_enabled = true;
        to_reading = 0;
        duplicate_effect = false;
        reset_effects();
        eff_drop = true;
        eff_reset_state = true;
        eff_clear_extmark = true;
        eff_render = true;
        state = I_DIRECT;
        check_properties();
        printf("TRANS %d\n", last);
      }

  /* TRANS t.I_POINT.tab event=tab from=I_POINT to=I_DIRECT */
  :: (state == I_POINT) ->
      atomic {
        last = 173;
        old_reading = 2;
        old_enabled = true;
        to_reading = 0;
        duplicate_effect = false;
        reset_effects();
        eff_drop = true;
        eff_reset_state = true;
        eff_clear_extmark = true;
        eff_render = true;
        state = I_DIRECT;
        check_properties();
        printf("TRANS %d\n", last);
      }

  /* TRANS t.I_SELECT.tab event=tab from=I_SELECT to=I_DIRECT */
  :: (state == I_SELECT) ->
      atomic {
        last = 174;
        old_reading = 3;
        old_enabled = true;
        to_reading = 0;
        duplicate_effect = false;
        reset_effects();
        eff_commit_candidate = true;
        eff_reset_state = true;
        eff_clear_extmark = true;
        eff_feed_key = true;
        state = I_DIRECT;
        check_properties();
        printf("TRANS %d\n", last);
      }

  /* TRANS t.I_DIRECT.ctrl_w event=ctrl_w from=I_DIRECT to=I_DIRECT */
  :: (state == I_DIRECT) ->
      atomic {
        last = 175;
        old_reading = 0;
        old_enabled = true;
        to_reading = 0;
        duplicate_effect = false;
        reset_effects();
        eff_feed_key = true;
        state = I_DIRECT;
        check_properties();
        printf("TRANS %d\n", last);
      }

  /* TRANS t.I_ROMAJI.ctrl_w event=ctrl_w from=I_ROMAJI to=I_DIRECT */
  :: (state == I_ROMAJI) ->
      atomic {
        last = 176;
        old_reading = 1;
        old_enabled = true;
        to_reading = 0;
        duplicate_effect = false;
        reset_effects();
        eff_drop = true;
        eff_reset_state = true;
        eff_clear_extmark = true;
        eff_render = true;
        state = I_DIRECT;
        check_properties();
        printf("TRANS %d\n", last);
      }

  /* TRANS t.I_POINT.ctrl_w event=ctrl_w from=I_POINT to=I_DIRECT */
  :: (state == I_POINT) ->
      atomic {
        last = 177;
        old_reading = 2;
        old_enabled = true;
        to_reading = 0;
        duplicate_effect = false;
        reset_effects();
        eff_drop = true;
        eff_reset_state = true;
        eff_clear_extmark = true;
        eff_render = true;
        state = I_DIRECT;
        check_properties();
        printf("TRANS %d\n", last);
      }

  /* TRANS t.I_SELECT.ctrl_w event=ctrl_w from=I_SELECT to=I_DIRECT */
  :: (state == I_SELECT) ->
      atomic {
        last = 178;
        old_reading = 3;
        old_enabled = true;
        to_reading = 0;
        duplicate_effect = false;
        reset_effects();
        eff_commit_candidate = true;
        eff_reset_state = true;
        eff_clear_extmark = true;
        eff_feed_key = true;
        state = I_DIRECT;
        check_properties();
        printf("TRANS %d\n", last);
      }

  /* TRANS t.I_DIRECT.ctrl_u event=ctrl_u from=I_DIRECT to=I_DIRECT */
  :: (state == I_DIRECT) ->
      atomic {
        last = 179;
        old_reading = 0;
        old_enabled = true;
        to_reading = 0;
        duplicate_effect = false;
        reset_effects();
        eff_feed_key = true;
        state = I_DIRECT;
        check_properties();
        printf("TRANS %d\n", last);
      }

  /* TRANS t.I_ROMAJI.ctrl_u event=ctrl_u from=I_ROMAJI to=I_DIRECT */
  :: (state == I_ROMAJI) ->
      atomic {
        last = 180;
        old_reading = 1;
        old_enabled = true;
        to_reading = 0;
        duplicate_effect = false;
        reset_effects();
        eff_drop = true;
        eff_reset_state = true;
        eff_clear_extmark = true;
        eff_render = true;
        state = I_DIRECT;
        check_properties();
        printf("TRANS %d\n", last);
      }

  /* TRANS t.I_POINT.ctrl_u event=ctrl_u from=I_POINT to=I_DIRECT */
  :: (state == I_POINT) ->
      atomic {
        last = 181;
        old_reading = 2;
        old_enabled = true;
        to_reading = 0;
        duplicate_effect = false;
        reset_effects();
        eff_drop = true;
        eff_reset_state = true;
        eff_clear_extmark = true;
        eff_render = true;
        state = I_DIRECT;
        check_properties();
        printf("TRANS %d\n", last);
      }

  /* TRANS t.I_SELECT.ctrl_u event=ctrl_u from=I_SELECT to=I_DIRECT */
  :: (state == I_SELECT) ->
      atomic {
        last = 182;
        old_reading = 3;
        old_enabled = true;
        to_reading = 0;
        duplicate_effect = false;
        reset_effects();
        eff_commit_candidate = true;
        eff_reset_state = true;
        eff_clear_extmark = true;
        eff_feed_key = true;
        state = I_DIRECT;
        check_properties();
        printf("TRANS %d\n", last);
      }

  /* TRANS t.I_DIRECT.ctrl_a event=ctrl_a from=I_DIRECT to=I_DIRECT */
  :: (state == I_DIRECT) ->
      atomic {
        last = 183;
        old_reading = 0;
        old_enabled = true;
        to_reading = 0;
        duplicate_effect = false;
        reset_effects();
        eff_feed_key = true;
        state = I_DIRECT;
        check_properties();
        printf("TRANS %d\n", last);
      }

  /* TRANS t.I_ROMAJI.ctrl_a event=ctrl_a from=I_ROMAJI to=I_DIRECT */
  :: (state == I_ROMAJI) ->
      atomic {
        last = 184;
        old_reading = 1;
        old_enabled = true;
        to_reading = 0;
        duplicate_effect = false;
        reset_effects();
        eff_drop = true;
        eff_reset_state = true;
        eff_clear_extmark = true;
        eff_render = true;
        state = I_DIRECT;
        check_properties();
        printf("TRANS %d\n", last);
      }

  /* TRANS t.I_POINT.ctrl_a event=ctrl_a from=I_POINT to=I_DIRECT */
  :: (state == I_POINT) ->
      atomic {
        last = 185;
        old_reading = 2;
        old_enabled = true;
        to_reading = 0;
        duplicate_effect = false;
        reset_effects();
        eff_drop = true;
        eff_reset_state = true;
        eff_clear_extmark = true;
        eff_render = true;
        state = I_DIRECT;
        check_properties();
        printf("TRANS %d\n", last);
      }

  /* TRANS t.I_SELECT.ctrl_a event=ctrl_a from=I_SELECT to=I_DIRECT */
  :: (state == I_SELECT) ->
      atomic {
        last = 186;
        old_reading = 3;
        old_enabled = true;
        to_reading = 0;
        duplicate_effect = false;
        reset_effects();
        eff_commit_candidate = true;
        eff_reset_state = true;
        eff_clear_extmark = true;
        eff_feed_key = true;
        state = I_DIRECT;
        check_properties();
        printf("TRANS %d\n", last);
      }

  /* TRANS t.I_DIRECT.ctrl_at event=ctrl_at from=I_DIRECT to=I_DIRECT */
  :: (state == I_DIRECT) ->
      atomic {
        last = 187;
        old_reading = 0;
        old_enabled = true;
        to_reading = 0;
        duplicate_effect = false;
        reset_effects();
        eff_feed_key = true;
        state = I_DIRECT;
        check_properties();
        printf("TRANS %d\n", last);
      }

  /* TRANS t.I_ROMAJI.ctrl_at event=ctrl_at from=I_ROMAJI to=I_DIRECT */
  :: (state == I_ROMAJI) ->
      atomic {
        last = 188;
        old_reading = 1;
        old_enabled = true;
        to_reading = 0;
        duplicate_effect = false;
        reset_effects();
        eff_drop = true;
        eff_reset_state = true;
        eff_clear_extmark = true;
        eff_render = true;
        state = I_DIRECT;
        check_properties();
        printf("TRANS %d\n", last);
      }

  /* TRANS t.I_POINT.ctrl_at event=ctrl_at from=I_POINT to=I_DIRECT */
  :: (state == I_POINT) ->
      atomic {
        last = 189;
        old_reading = 2;
        old_enabled = true;
        to_reading = 0;
        duplicate_effect = false;
        reset_effects();
        eff_drop = true;
        eff_reset_state = true;
        eff_clear_extmark = true;
        eff_render = true;
        state = I_DIRECT;
        check_properties();
        printf("TRANS %d\n", last);
      }

  /* TRANS t.I_SELECT.ctrl_at event=ctrl_at from=I_SELECT to=I_DIRECT */
  :: (state == I_SELECT) ->
      atomic {
        last = 190;
        old_reading = 3;
        old_enabled = true;
        to_reading = 0;
        duplicate_effect = false;
        reset_effects();
        eff_commit_candidate = true;
        eff_reset_state = true;
        eff_clear_extmark = true;
        eff_feed_key = true;
        state = I_DIRECT;
        check_properties();
        printf("TRANS %d\n", last);
      }

  /* TRANS t.I_ROMAJI.ctrl_w.keep event=ctrl_w from=I_ROMAJI to=I_ROMAJI */
  :: (state == I_ROMAJI) ->
      atomic {
        last = 191;
        old_reading = 1;
        old_enabled = true;
        to_reading = 1;
        duplicate_effect = false;
        reset_effects();
        eff_pass_key = true;
        state = I_ROMAJI;
        check_properties();
        printf("TRANS %d\n", last);
      }

  /* TRANS t.I_ROMAJI.ctrl_u.keep event=ctrl_u from=I_ROMAJI to=I_ROMAJI */
  :: (state == I_ROMAJI) ->
      atomic {
        last = 192;
        old_reading = 1;
        old_enabled = true;
        to_reading = 1;
        duplicate_effect = false;
        reset_effects();
        eff_pass_key = true;
        state = I_ROMAJI;
        check_properties();
        printf("TRANS %d\n", last);
      }

  /* TRANS t.I_POINT.ctrl_w.keep event=ctrl_w from=I_POINT to=I_POINT */
  :: (state == I_POINT) ->
      atomic {
        last = 193;
        old_reading = 2;
        old_enabled = true;
        to_reading = 2;
        duplicate_effect = false;
        reset_effects();
        eff_pass_key = true;
        state = I_POINT;
        check_properties();
        printf("TRANS %d\n", last);
      }

  /* TRANS t.I_POINT.ctrl_u.keep event=ctrl_u from=I_POINT to=I_POINT */
  :: (state == I_POINT) ->
      atomic {
        last = 194;
        old_reading = 2;
        old_enabled = true;
        to_reading = 2;
        duplicate_effect = false;
        reset_effects();
        eff_pass_key = true;
        state = I_POINT;
        check_properties();
        printf("TRANS %d\n", last);
      }

  /* TRANS t.I_SELECT.ctrl_w.keep event=ctrl_w from=I_SELECT to=I_SELECT */
  :: (state == I_SELECT) ->
      atomic {
        last = 195;
        old_reading = 3;
        old_enabled = true;
        to_reading = 3;
        duplicate_effect = false;
        reset_effects();
        eff_pass_key = true;
        state = I_SELECT;
        check_properties();
        printf("TRANS %d\n", last);
      }

  /* TRANS t.I_SELECT.ctrl_u.keep event=ctrl_u from=I_SELECT to=I_SELECT */
  :: (state == I_SELECT) ->
      atomic {
        last = 196;
        old_reading = 3;
        old_enabled = true;
        to_reading = 3;
        duplicate_effect = false;
        reset_effects();
        eff_pass_key = true;
        state = I_SELECT;
        check_properties();
        printf("TRANS %d\n", last);
      }

  /* TRANS t.I_DIRECT.completion_accept event=completion_accept from=I_DIRECT to=I_DIRECT */
  :: (state == I_DIRECT) ->
      atomic {
        last = 197;
        old_reading = 0;
        old_enabled = true;
        to_reading = 0;
        duplicate_effect = false;
        reset_effects();
        eff_pass_key = true;
        state = I_DIRECT;
        check_properties();
        printf("TRANS %d\n", last);
      }

  /* TRANS t.I_ROMAJI.completion_accept event=completion_accept from=I_ROMAJI to=I_ROMAJI */
  :: (state == I_ROMAJI) ->
      atomic {
        last = 198;
        old_reading = 1;
        old_enabled = true;
        to_reading = 1;
        duplicate_effect = false;
        reset_effects();
        eff_pass_key = true;
        state = I_ROMAJI;
        check_properties();
        printf("TRANS %d\n", last);
      }

  /* TRANS t.I_POINT.completion_accept event=completion_accept from=I_POINT to=I_POINT */
  :: (state == I_POINT) ->
      atomic {
        last = 199;
        old_reading = 2;
        old_enabled = true;
        to_reading = 2;
        duplicate_effect = false;
        reset_effects();
        eff_pass_key = true;
        state = I_POINT;
        check_properties();
        printf("TRANS %d\n", last);
      }

  /* TRANS t.I_SELECT.completion_accept event=completion_accept from=I_SELECT to=I_SELECT */
  :: (state == I_SELECT) ->
      atomic {
        last = 200;
        old_reading = 3;
        old_enabled = true;
        to_reading = 3;
        duplicate_effect = false;
        reset_effects();
        eff_pass_key = true;
        state = I_SELECT;
        check_properties();
        printf("TRANS %d\n", last);
      }

  /* TRANS t.I_DIRECT.completion_open event=completion_open from=I_DIRECT to=IC */
  :: (state == I_DIRECT) ->
      atomic {
        last = 201;
        old_reading = 0;
        old_enabled = true;
        to_reading = 0;
        duplicate_effect = false;
        reset_effects();
        eff_pass_key = true;
        state = IC;
        check_properties();
        printf("TRANS %d\n", last);
      }

  /* TRANS t.I_ROMAJI.completion_open event=completion_open from=I_ROMAJI to=IC */
  :: (state == I_ROMAJI) ->
      atomic {
        last = 202;
        old_reading = 1;
        old_enabled = true;
        to_reading = 0;
        duplicate_effect = false;
        reset_effects();
        eff_drop = true;
        eff_clear_extmark = true;
        state = IC;
        check_properties();
        printf("TRANS %d\n", last);
      }

  /* TRANS t.I_POINT.completion_open event=completion_open from=I_POINT to=IC */
  :: (state == I_POINT) ->
      atomic {
        last = 203;
        old_reading = 2;
        old_enabled = true;
        to_reading = 0;
        duplicate_effect = false;
        reset_effects();
        eff_drop = true;
        eff_clear_extmark = true;
        state = IC;
        check_properties();
        printf("TRANS %d\n", last);
      }

  /* TRANS t.I_SELECT.completion_open event=completion_open from=I_SELECT to=IC */
  :: (state == I_SELECT) ->
      atomic {
        last = 204;
        old_reading = 3;
        old_enabled = true;
        to_reading = 0;
        duplicate_effect = false;
        reset_effects();
        eff_drop = true;
        eff_clear_extmark = true;
        state = IC;
        check_properties();
        printf("TRANS %d\n", last);
      }

  /* TRANS t.IC.completion_next event=completion_next from=IC to=IC */
  :: (state == IC) ->
      atomic {
        last = 205;
        old_reading = 0;
        old_enabled = true;
        to_reading = 0;
        duplicate_effect = false;
        reset_effects();
        eff_pass_key = true;
        state = IC;
        check_properties();
        printf("TRANS %d\n", last);
      }

  /* TRANS t.IC.completion_accept.C-y event=completion_accept from=IC to=I_DIRECT */
  :: (state == IC) ->
      atomic {
        last = 206;
        old_reading = 0;
        old_enabled = true;
        to_reading = 0;
        duplicate_effect = false;
        reset_effects();
        eff_reset_state = true;
        state = I_DIRECT;
        check_properties();
        printf("TRANS %d\n", last);
      }

  /* TRANS t.IC.esc event=esc from=IC to=N_OFF */
  :: (state == IC) ->
      atomic {
        last = 207;
        old_reading = 0;
        old_enabled = true;
        to_reading = 0;
        duplicate_effect = false;
        reset_effects();
        eff_reset_state = true;
        eff_restore_mapping = true;
        eff_clear_extmark = true;
        state = N_OFF;
        check_properties();
        printf("TRANS %d\n", last);
      }

  /* TRANS t.IC.ctrl_c event=ctrl_c from=IC to=N_WAIT */
  :: (state == IC) ->
      atomic {
        last = 208;
        old_reading = 0;
        old_enabled = true;
        to_reading = 4;
        duplicate_effect = false;
        reset_effects();
        state = N_WAIT;
        check_properties();
        printf("TRANS %d\n", last);
      }

  /* TRANS t.IC.stale event=stale from=IC to=I_DIRECT */
  :: (state == IC) ->
      atomic {
        last = 209;
        old_reading = 0;
        old_enabled = true;
        to_reading = 0;
        duplicate_effect = false;
        reset_effects();
        eff_reset_state = true;
        state = I_DIRECT;
        check_properties();
        printf("TRANS %d\n", last);
      }

  /* TRANS t.IC.winleave event=winleave from=IC to=N_OFF */
  :: (state == IC) ->
      atomic {
        last = 210;
        old_reading = 0;
        old_enabled = true;
        to_reading = 0;
        duplicate_effect = false;
        reset_effects();
        eff_drop = true;
        eff_reset_state = true;
        eff_restore_mapping = true;
        eff_clear_extmark = true;
        state = N_OFF;
        check_properties();
        printf("TRANS %d\n", last);
      }

  /* TRANS t.I_DIRECT.guard_special event=guard_special from=I_DIRECT to=I_DIRECT */
  :: (state == I_DIRECT) ->
      atomic {
        last = 211;
        old_reading = 0;
        old_enabled = true;
        to_reading = 0;
        duplicate_effect = false;
        reset_effects();
        eff_feed_key = true;
        state = I_DIRECT;
        check_properties();
        printf("TRANS %d\n", last);
      }

  /* TRANS t.I_ROMAJI.guard_special event=guard_special from=I_ROMAJI to=I_DIRECT */
  :: (state == I_ROMAJI) ->
      atomic {
        last = 212;
        old_reading = 1;
        old_enabled = true;
        to_reading = 0;
        duplicate_effect = false;
        reset_effects();
        eff_commit_reading = true;
        eff_reset_state = true;
        eff_clear_extmark = true;
        eff_feed_key = true;
        state = I_DIRECT;
        check_properties();
        printf("TRANS %d\n", last);
      }

  /* TRANS t.I_POINT.guard_special event=guard_special from=I_POINT to=I_DIRECT */
  :: (state == I_POINT) ->
      atomic {
        last = 213;
        old_reading = 2;
        old_enabled = true;
        to_reading = 0;
        duplicate_effect = false;
        reset_effects();
        eff_commit_reading = true;
        eff_reset_state = true;
        eff_clear_extmark = true;
        eff_feed_key = true;
        state = I_DIRECT;
        check_properties();
        printf("TRANS %d\n", last);
      }

  /* TRANS t.I_SELECT.guard_special event=guard_special from=I_SELECT to=I_DIRECT */
  :: (state == I_SELECT) ->
      atomic {
        last = 214;
        old_reading = 3;
        old_enabled = true;
        to_reading = 0;
        duplicate_effect = false;
        reset_effects();
        eff_commit_candidate = true;
        eff_reset_state = true;
        eff_clear_extmark = true;
        eff_feed_key = true;
        state = I_DIRECT;
        check_properties();
        printf("TRANS %d\n", last);
      }

  /* TRANS t.I_DIRECT.mouse_click event=mouse_click from=I_DIRECT to=I_DIRECT */
  :: (state == I_DIRECT) ->
      atomic {
        last = 215;
        old_reading = 0;
        old_enabled = true;
        to_reading = 0;
        duplicate_effect = false;
        reset_effects();
        eff_feed_key = true;
        state = I_DIRECT;
        check_properties();
        printf("TRANS %d\n", last);
      }

  /* TRANS t.I_ROMAJI.mouse_click event=mouse_click from=I_ROMAJI to=I_DIRECT */
  :: (state == I_ROMAJI) ->
      atomic {
        last = 216;
        old_reading = 1;
        old_enabled = true;
        to_reading = 0;
        duplicate_effect = false;
        reset_effects();
        eff_commit_reading = true;
        eff_reset_state = true;
        eff_clear_extmark = true;
        eff_feed_key = true;
        state = I_DIRECT;
        check_properties();
        printf("TRANS %d\n", last);
      }

  /* TRANS t.I_POINT.mouse_click event=mouse_click from=I_POINT to=I_DIRECT */
  :: (state == I_POINT) ->
      atomic {
        last = 217;
        old_reading = 2;
        old_enabled = true;
        to_reading = 0;
        duplicate_effect = false;
        reset_effects();
        eff_commit_reading = true;
        eff_reset_state = true;
        eff_clear_extmark = true;
        eff_feed_key = true;
        state = I_DIRECT;
        check_properties();
        printf("TRANS %d\n", last);
      }

  /* TRANS t.I_SELECT.mouse_click event=mouse_click from=I_SELECT to=I_DIRECT */
  :: (state == I_SELECT) ->
      atomic {
        last = 218;
        old_reading = 3;
        old_enabled = true;
        to_reading = 0;
        duplicate_effect = false;
        reset_effects();
        eff_commit_candidate = true;
        eff_reset_state = true;
        eff_clear_extmark = true;
        eff_feed_key = true;
        state = I_DIRECT;
        check_properties();
        printf("TRANS %d\n", last);
      }

  /* TRANS t.I_DIRECT.wheel event=wheel from=I_DIRECT to=I_DIRECT */
  :: (state == I_DIRECT) ->
      atomic {
        last = 219;
        old_reading = 0;
        old_enabled = true;
        to_reading = 0;
        duplicate_effect = false;
        reset_effects();
        eff_pass_key = true;
        state = I_DIRECT;
        check_properties();
        printf("TRANS %d\n", last);
      }

  /* TRANS t.I_ROMAJI.wheel event=wheel from=I_ROMAJI to=I_ROMAJI */
  :: (state == I_ROMAJI) ->
      atomic {
        last = 220;
        old_reading = 1;
        old_enabled = true;
        to_reading = 1;
        duplicate_effect = false;
        reset_effects();
        eff_pass_key = true;
        state = I_ROMAJI;
        check_properties();
        printf("TRANS %d\n", last);
      }

  /* TRANS t.I_POINT.wheel event=wheel from=I_POINT to=I_POINT */
  :: (state == I_POINT) ->
      atomic {
        last = 221;
        old_reading = 2;
        old_enabled = true;
        to_reading = 2;
        duplicate_effect = false;
        reset_effects();
        eff_pass_key = true;
        state = I_POINT;
        check_properties();
        printf("TRANS %d\n", last);
      }

  /* TRANS t.I_SELECT.wheel event=wheel from=I_SELECT to=I_SELECT */
  :: (state == I_SELECT) ->
      atomic {
        last = 222;
        old_reading = 3;
        old_enabled = true;
        to_reading = 3;
        duplicate_effect = false;
        reset_effects();
        eff_pass_key = true;
        state = I_SELECT;
        check_properties();
        printf("TRANS %d\n", last);
      }

  /* TRANS t.I_DIRECT.paste event=paste from=I_DIRECT to=I_DIRECT */
  :: (state == I_DIRECT) ->
      atomic {
        last = 223;
        old_reading = 0;
        old_enabled = true;
        to_reading = 0;
        duplicate_effect = false;
        reset_effects();
        eff_feed_key = true;
        state = I_DIRECT;
        check_properties();
        printf("TRANS %d\n", last);
      }

  /* TRANS t.I_ROMAJI.paste event=paste from=I_ROMAJI to=I_DIRECT */
  :: (state == I_ROMAJI) ->
      atomic {
        last = 224;
        old_reading = 1;
        old_enabled = true;
        to_reading = 0;
        duplicate_effect = false;
        reset_effects();
        eff_commit_reading = true;
        eff_reset_state = true;
        eff_clear_extmark = true;
        state = I_DIRECT;
        check_properties();
        printf("TRANS %d\n", last);
      }

  /* TRANS t.I_POINT.paste event=paste from=I_POINT to=I_DIRECT */
  :: (state == I_POINT) ->
      atomic {
        last = 225;
        old_reading = 2;
        old_enabled = true;
        to_reading = 0;
        duplicate_effect = false;
        reset_effects();
        eff_commit_reading = true;
        eff_reset_state = true;
        eff_clear_extmark = true;
        state = I_DIRECT;
        check_properties();
        printf("TRANS %d\n", last);
      }

  /* TRANS t.I_SELECT.paste event=paste from=I_SELECT to=I_DIRECT */
  :: (state == I_SELECT) ->
      atomic {
        last = 226;
        old_reading = 3;
        old_enabled = true;
        to_reading = 0;
        duplicate_effect = false;
        reset_effects();
        eff_commit_candidate = true;
        eff_reset_state = true;
        eff_clear_extmark = true;
        state = I_DIRECT;
        check_properties();
        printf("TRANS %d\n", last);
      }

  /* TRANS t.I_DIRECT.stale.cursor event=stale from=I_DIRECT to=I_DIRECT */
  :: (state == I_DIRECT && 0) ->
      atomic {
        last = 227;
        old_reading = 0;
        old_enabled = true;
        to_reading = 0;
        duplicate_effect = false;
        reset_effects();
        eff_render = true;
        state = I_DIRECT;
        check_properties();
        printf("TRANS %d\n", last);
      }

  /* TRANS t.I_DIRECT.stale.buffer event=stale from=I_DIRECT to=I_DIRECT */
  :: (state == I_DIRECT && 0) ->
      atomic {
        last = 228;
        old_reading = 0;
        old_enabled = true;
        to_reading = 0;
        duplicate_effect = false;
        reset_effects();
        eff_drop = true;
        eff_reset_state = true;
        eff_clear_extmark = true;
        eff_render = true;
        state = I_DIRECT;
        check_properties();
        printf("TRANS %d\n", last);
      }

  /* TRANS t.I_DIRECT.stale.none event=stale from=I_DIRECT to=I_DIRECT */
  :: (state == I_DIRECT) ->
      atomic {
        last = 229;
        old_reading = 0;
        old_enabled = true;
        to_reading = 0;
        duplicate_effect = false;
        reset_effects();
        eff_pass_key = true;
        state = I_DIRECT;
        check_properties();
        printf("TRANS %d\n", last);
      }

  /* TRANS t.I_ROMAJI.stale.cursor event=stale from=I_ROMAJI to=I_DIRECT */
  :: (state == I_ROMAJI) ->
      atomic {
        last = 230;
        old_reading = 1;
        old_enabled = true;
        to_reading = 0;
        duplicate_effect = false;
        reset_effects();
        eff_commit_reading = true;
        eff_reset_state = true;
        eff_render = true;
        state = I_DIRECT;
        check_properties();
        printf("TRANS %d\n", last);
      }

  /* TRANS t.I_ROMAJI.stale.buffer event=stale from=I_ROMAJI to=I_DIRECT */
  :: (state == I_ROMAJI) ->
      atomic {
        last = 231;
        old_reading = 1;
        old_enabled = true;
        to_reading = 0;
        duplicate_effect = false;
        reset_effects();
        eff_drop = true;
        eff_reset_state = true;
        eff_clear_extmark = true;
        eff_render = true;
        state = I_DIRECT;
        check_properties();
        printf("TRANS %d\n", last);
      }

  /* TRANS t.I_ROMAJI.stale.none event=stale from=I_ROMAJI to=I_ROMAJI */
  :: (state == I_ROMAJI) ->
      atomic {
        last = 232;
        old_reading = 1;
        old_enabled = true;
        to_reading = 1;
        duplicate_effect = false;
        reset_effects();
        eff_pass_key = true;
        state = I_ROMAJI;
        check_properties();
        printf("TRANS %d\n", last);
      }

  /* TRANS t.I_POINT.stale.cursor event=stale from=I_POINT to=I_DIRECT */
  :: (state == I_POINT) ->
      atomic {
        last = 233;
        old_reading = 2;
        old_enabled = true;
        to_reading = 0;
        duplicate_effect = false;
        reset_effects();
        eff_commit_reading = true;
        eff_reset_state = true;
        eff_render = true;
        state = I_DIRECT;
        check_properties();
        printf("TRANS %d\n", last);
      }

  /* TRANS t.I_POINT.stale.buffer event=stale from=I_POINT to=I_DIRECT */
  :: (state == I_POINT) ->
      atomic {
        last = 234;
        old_reading = 2;
        old_enabled = true;
        to_reading = 0;
        duplicate_effect = false;
        reset_effects();
        eff_drop = true;
        eff_reset_state = true;
        eff_clear_extmark = true;
        eff_render = true;
        state = I_DIRECT;
        check_properties();
        printf("TRANS %d\n", last);
      }

  /* TRANS t.I_POINT.stale.none event=stale from=I_POINT to=I_POINT */
  :: (state == I_POINT) ->
      atomic {
        last = 235;
        old_reading = 2;
        old_enabled = true;
        to_reading = 2;
        duplicate_effect = false;
        reset_effects();
        eff_pass_key = true;
        state = I_POINT;
        check_properties();
        printf("TRANS %d\n", last);
      }

  /* TRANS t.I_SELECT.stale.cursor event=stale from=I_SELECT to=I_DIRECT */
  :: (state == I_SELECT) ->
      atomic {
        last = 236;
        old_reading = 3;
        old_enabled = true;
        to_reading = 0;
        duplicate_effect = false;
        reset_effects();
        eff_commit_candidate = true;
        eff_reset_state = true;
        eff_render = true;
        state = I_DIRECT;
        check_properties();
        printf("TRANS %d\n", last);
      }

  /* TRANS t.I_SELECT.stale.buffer event=stale from=I_SELECT to=I_DIRECT */
  :: (state == I_SELECT) ->
      atomic {
        last = 237;
        old_reading = 3;
        old_enabled = true;
        to_reading = 0;
        duplicate_effect = false;
        reset_effects();
        eff_drop = true;
        eff_reset_state = true;
        eff_clear_extmark = true;
        eff_render = true;
        state = I_DIRECT;
        check_properties();
        printf("TRANS %d\n", last);
      }

  /* TRANS t.I_SELECT.stale.none event=stale from=I_SELECT to=I_SELECT */
  :: (state == I_SELECT) ->
      atomic {
        last = 238;
        old_reading = 3;
        old_enabled = true;
        to_reading = 3;
        duplicate_effect = false;
        reset_effects();
        eff_pass_key = true;
        state = I_SELECT;
        check_properties();
        printf("TRANS %d\n", last);
      }
  od
}

/* P13: 途中の状態（transient）から必ず出られる */
#define TRANSIENT(s) (((s) == I_ESCAPE) || ((s) == N_WAIT) || ((s) == R_MID))

ltl p1 { [] (p1_ok) }
ltl p3 { [] (p3_ok) }
ltl p5 { [] (p5_ok) }
ltl p10 { [] (p10_ok) }
ltl p13 { [] (TRANSIENT(state) -> <> (!TRANSIENT(state))) }
