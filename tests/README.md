# テスト構成と upstream 対応表

skkeleton.nvim のテストスイート（`tests/`）は、upstream である [vim-skk/skkeleton](https://github.com/vim-skk/skkeleton)（コミット `770b265d`）のテストケースを移植したものと、skkeleton.nvim 独自の E2E・結合テストで構成されています。

## upstream（denops/skkeleton）49 ケースとの対応表

区分は以下の 3 つです：
- **移植済み**: `tests/` 内の単体テストまたは結合テストとして移植済み
- **E2E で扱う**: 画面表示や Neovim 内部のキー入力処理（UI）が関わるため、E2E テスト（`tests/test_e2e_*.lua`）側で検証
- **対象外**: Deno/ddc 固有の処理など、skkeleton.nvim に該当機能が存在しないため対象外

| Upstream ファイル | Upstream ケース名 | 区分 | skkeleton.nvim での対応 |
|---|---|---|---|
| `denops/@ddc-sources/skkeleton_okuri/okurisplits_test.ts` | `split` | 対象外 | ddc source（skkeleton_okuri）用の送り仮名分割。skkeleton.nvim には該当機能がないため |
| `denops/skkeleton/config_test.ts` | `egg like newline` | 移植済み | `tests/test_function_common.lua` (`T["egg like newline"]`) |
| `denops/skkeleton/config_test.ts` | `acceptIllegalResult` | 移植済み | `tests/test_function_common.lua` (`T["acceptIllegalResult"]`) |
| `denops/skkeleton/config_test.ts` | `immediatelyOkuriConvert` | 移植済み | `tests/test_function_common.lua` (`T["immediatelyOkuriConvert"]`) |
| `denops/skkeleton/config_test.ts` | `keepMode` | 移植済み | `tests/test_e2e_mode.lua` (`T["keepMode"]`) |
| `denops/skkeleton/dictionary_test.ts` | `load new JisyoJson` | 移植済み | `tests/test_dictionary.lua` (`T["load new JisyoJson"]`) |
| `denops/skkeleton/dictionary_test.ts` | `load new JisyoYaml` | 移植済み | `tests/test_dictionary.lua` (`T["load new JisyoYaml is not supported"]`) |
| `denops/skkeleton/dictionary_test.ts` | `get candidates` | 移植済み | `tests/test_dictionary.lua` (`T["get candidates"]`) |
| `denops/skkeleton/dictionary_test.ts` | `get num candidates` | 移植済み | `tests/test_dictionary.lua` (`T["get num candidates"]`) |
| `denops/skkeleton/dictionary_test.ts` | `get num candidates (Kifu)` | 移植済み | `tests/test_dictionary.lua` (`T["get num candidates (Kifu)"]`) |
| `denops/skkeleton/dictionary_test.ts` | `get candidates from words that include numbers` | 移植済み | `tests/test_dictionary.lua` (`T["get candidates from words that include numbers"]`) |
| `denops/skkeleton/dictionary_test.ts` | `register candidate` | 移植済み | `tests/test_dictionary.lua` (`T["register candidate"]`) |
| `denops/skkeleton/dictionary_test.ts` | `global/local jisyo interop` | 移植済み | `tests/test_dictionary.lua` (`T["global/local jisyo interop"]`) |
| `denops/skkeleton/dictionary_test.ts` | `read/write skk jisyo` | 移植済み | `tests/test_dictionary_user.lua` (`T["reads and writes an SKK dictionary"]`) |
| `denops/skkeleton/dictionary_test.ts` | `don't register empty candidate` | 移植済み | `tests/test_dictionary_user.lua` (`T["does not register an empty candidate"]`) |
| `denops/skkeleton/dictionary_test.ts` | `getRanks` | 移植済み | `tests/test_dictionary_user.lua` (`T["load_ranks and save_ranks"]`) |
| `denops/skkeleton/function/common_test.ts` | `input cancel` | 移植済み | `tests/test_function_common.lua` (`T["input cancel"]`) |
| `denops/skkeleton/function/common_test.ts` | `annotation` | 移植済み | `tests/test_function_common.lua` (`T["annotation"]`) |
| `denops/skkeleton/function/common_test.ts` | `turn off mode when kakutei with empty input` | 移植済み | `tests/test_function_common.lua` (`T["turn off mode when kakutei with empty input"]`) |
| `denops/skkeleton/function/dictionary_test.ts` | `Don't put string when register dictionary was cancelled` | 移植済み | `tests/test_function_disable.lua` (`T["Don't put string when register dictionary was cancelled"]`) |
| `denops/skkeleton/function/dictionary_test.ts` | `Unregistered internal mapping` | 移植済み | `tests/test_function_disable.lua` (`T["Unregistered internal mapping"]`) |
| `denops/skkeleton/function/disable_test.ts` | `kakutei at disable` | 移植済み | `tests/test_function_disable.lua` (`T["kakutei at disable"]`), `tests/test_e2e_mode.lua` (`T["kakutei at disable"]`) |
| `denops/skkeleton/function/disable_test.ts` | `disable just after completion` | 移植済み | `tests/test_function_disable.lua` (`T["disable just after completion"]`), `tests/test_e2e_mode.lua` (`T["disable just after completion"]`) |
| `denops/skkeleton/function/henkan_test.ts` | `okurinasi henkan` | 移植済み | `tests/test_function_henkan.lua` (`T["okurinasi henkan"]`) |
| `denops/skkeleton/function/henkan_test.ts` | `okuriari henkan` | 移植済み | `tests/test_function_henkan.lua` (`T["okuriari henkan"]`) |
| `denops/skkeleton/function/henkan_test.ts` | `henkan cancel` | 移植済み | `tests/test_function_henkan.lua` (`T["henkan cancel"]`) |
| `denops/skkeleton/function/henkan_test.ts` | `fallback to kanaInput in henkanFirst` | 移植済み | `tests/test_function_henkan.lua` (`T["fallback to kana_input in henkan_first"]`) |
| `denops/skkeleton/function/input_test.ts` | `kana input` | 移植済み | `tests/test_function_input.lua` (`T["kana input"]`) |
| `denops/skkeleton/function/input_test.ts` | `kana input with illegal key` | 移植済み | `tests/test_function_input.lua` (`T["kana input with illegal key"]`) |
| `denops/skkeleton/function/input_test.ts` | `henkan point` | 移植済み | `tests/test_function_input.lua` (`T["henkan point"]`) |
| `denops/skkeleton/function/input_test.ts` | `upper case input` | 移植済み | `tests/test_function_input.lua` (`T["upper case input"]`) |
| `denops/skkeleton/function/input_test.ts` | `upper case input with lowercaseMap` | 移植済み | `tests/test_function_input.lua` (`T["upper case input with lowercaseMap"]`) |
| `denops/skkeleton/function/input_test.ts` | `delete char` | 移植済み | `tests/test_function_input.lua` (`T["delete char"]`) |
| `denops/skkeleton/function/input_test.ts` | `undo point` | 移植済み | `tests/test_function_input.lua` (`T["undo point"]`) |
| `denops/skkeleton/function/input_test.ts` | `new line` | E2E で扱う | `tests/test_e2e_input.lua` (`T["indent is kept by a newline"]`) |
| `denops/skkeleton/function/input_test.ts` | `katakana input` | 移植済み | `tests/test_function_input.lua` (`T["katakana input"]`) |
| `denops/skkeleton/function/input_test.ts` | `hankatakana input` | 移植済み | `tests/test_function_input.lua` (`T["hankatakana input"]`) |
| `denops/skkeleton/function/mode_test.ts` | `Can get skkeleton mode` | 移植済み | `tests/test_function_mode.lua` (`T["Can get skkeleton mode"]`), `tests/test_e2e_mode.lua` (`T["Can get skkeleton mode"]`) |
| `denops/skkeleton/function/mode_test.ts` | `Fire autocmd for mode changed` | 移植済み | `tests/test_function_mode.lua` (`T["Fire autocmd for mode changed"]`), `tests/test_e2e_mode.lua` (`T["Fire autocmd for mode changed"]`) |
| `denops/skkeleton/function/mode_test.ts` | `abbrev` | 移植済み | `tests/test_function_mode.lua` (`T["abbrev"]`) |
| `denops/skkeleton/function/mode_test.ts` | `can convert okuri string properly when mode changed` | 移植済み | `tests/test_function_mode.lua` (`T["can convert okuri string properly when mode changed"]`) |
| `denops/skkeleton/function/mode_test.ts` | `mode change  at enable` | E2E で扱う | `tests/test_e2e_mode.lua` (`T["mode change at enable"]`) |
| `denops/skkeleton/kana_test.ts` | `customize kanatable` | 移植済み | `tests/test_kana.lua` (`T["customize kanatable"]`) |
| `denops/skkeleton/kana_test.ts` | `create kanatable` | 移植済み | `tests/test_kana.lua` (`T["create kanatable"]`) |
| `denops/skkeleton/keymap_test.ts` | `registerKeyMap` | 移植済み | `tests/test_keymap.lua` (`T["registerKeyMap"]`) |
| `denops/skkeleton/keymap_test.ts` | `send multiple keys into handleKey` | 移植済み | `tests/test_keymap.lua` (`T["send multiple keys into handle_key"]`), `tests/test_e2e_mode.lua` (`T["send multiple keys into handleKey"]`) |
| `denops/skkeleton/preedit_test.ts` | `preedit test` | 移植済み | `tests/test_preedit.lua` (`T["preedit test"]`) |
| `denops/skkeleton/preedit_test.ts` | `preedit with grapheme` | 移植済み | `tests/test_preedit.lua` (`T["preedit with grapheme"]`) |
| `denops/skkeleton/util_test.ts` | `LazyCell` | 対象外 | Deno / TypeScript 固有の遅延初期化ヘルパー。skkeleton.nvim では不要なため |
