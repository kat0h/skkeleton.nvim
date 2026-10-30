-- upstream（denops 版）と意図して変えたところ。差分テストで違いが出ても、ここに当てはまれば除外する。
-- applies(scenario, step_index, a, b) は a = Lua 版、b = denops 版のその時点の状態を受けて、
-- 除外してよいなら true を返す。理由は docs/PLAN.md、docs/ARCHITECTURE.md、LICENSES/README.md を参照
return {}
