// D（参考）: skkeleton の deno_kv.ts を denops を介さずに直接動かし、KV そのものの速さを測る
// 使い方: deno run -A --unstable-kv --config <skkeleton>/denops/skkeleton/deno.json \
//           bench/deno_kv_direct.ts <skkeleton>/denops/skkeleton <dict> <db> <queries.tsv>
const [skk, dict, db, queriesPath] = Deno.args;
const { Dictionary } = await import(`${skk}/sources/deno_kv.ts`);

const t0 = performance.now();
const d = await Dictionary.create(dict, "", db);
await d.load();
const t1 = performance.now();

const queries = (await Deno.readTextFile(queriesPath)).trim().split("\n")
  .map((l) => l.split("\t"));
const xs: Record<string, number[]> = { hit: [], miss: [], prefix: [] };
let found = 0;
for (const [what, kind, key] of queries) {
  const s = performance.now();
  if (what === "prefix") {
    await d.getCompletionResult(key, "");
  } else {
    const c = await d.getHenkanResult(kind, key);
    if (what === "hit" && c.length > 0) found++;
  }
  xs[what].push(performance.now() - s);
}
const stats = (a: number[]) => {
  a.sort((x, y) => x - y);
  const p = (r: number) => a[Math.max(0, Math.ceil(a.length * r) - 1)];
  return { n: a.length, p50: p(0.5), p99: p(0.99), max: a[a.length - 1] };
};
console.log(JSON.stringify({
  kind: "deno_kv_direct",
  open_and_load_ms: t1 - t0,
  hit_found: found,
  lookup: stats(xs.hit),
  miss: stats(xs.miss),
  prefix: stats(xs.prefix),
}));
d.cleanup();
