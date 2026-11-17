#!/usr/bin/env python3
"""Run conformance cases against libskk through its GI binding."""

import argparse
import json
import re
import tempfile
from pathlib import Path

import gi

gi.require_version("Skk", "1.0")
from gi.repository import Skk


KEYS = {
    "Space": "SPC",
    "C-j": "C-j",
    "C-g": "C-g",
    "BS": "DEL",
    "CR": "RET",
    "C-q": "C-q",
}

MODE = {
    Skk.InputMode.HIRAGANA: "hira",
    Skk.InputMode.KATAKANA: "kata",
    Skk.InputMode.HANKAKU_KATAKANA: "hankata",
    Skk.InputMode.LATIN: "ascii",
    Skk.InputMode.WIDE_LATIN: "zenkaku",
}


def key_sequence(keys):
    parts = re.findall(r"<([^>]+)>|([^<>])", keys)
    result = []
    for special, char in parts:
        key = special or char
        if special:
            if key == "Esc":
                raise ValueError("<Esc> has no libskk input-context equivalent")
            if key not in KEYS:
                raise ValueError(f"unsupported key token: <{key}>")
            key = KEYS[key]
        result.append(key)
    return " ".join(result)


def dictionary_text(dictionary):
    # libskk の境界検索は、見出し行の直前に改行がある前提で進む。
    lines = [";; conformance test dictionary", ";; okuri-ari entries."]
    for key, candidates in sorted(dictionary["okuri_ari"], reverse=True):
        lines.append(f"{key} /{'/'.join(candidates)}/")
    lines.append(";; okuri-nasi entries.")
    for key, candidates in sorted(dictionary["okuri_nasi"]):
        lines.append(f"{key} /{'/'.join(candidates)}/")
    return "\n".join(lines) + "\n"


def observe(context, text, abbrev):
    preedit = context.get_preedit()
    observe = {"text": text}
    if "【" in preedit:
        # 登録欄は、libskk が付ける欄の印で見分ける。
        observe["stage"] = "register"
        payload = preedit.split("▼", 1)[-1].split("【", 1)[0]
        if "*" in payload:
            reading, okuri = payload.split("*", 1)
            observe["reading"] = reading
            observe["okuri"] = okuri
        else:
            observe["reading"] = payload
            observe["okuri"] = ""
    elif "▼" in preedit:
        observe["stage"] = "select"
        candidates = context.get_candidates()
        position = candidates.get_cursor_pos()
        if 0 <= position < candidates.get_size():
            candidate = candidates.get(position)
            candidate_text = candidate.get_text()
            observe["candidate"] = candidate_text
            midasi = candidate.get_midasi()
            if candidate.get_okuri():
                observe["reading"] = midasi[:-1]
                displayed = preedit.split("▼", 1)[1]
                if displayed.startswith(candidate_text):
                    observe["okuri"] = displayed[len(candidate_text) :]
            else:
                observe["reading"] = midasi
    elif "▽" in preedit:
        observe["stage"] = "reading"
        payload = preedit.split("▽", 1)[1]
        if "【" in payload:
            payload = payload.split("【", 1)[0]
        if "*" in payload:
            reading, okuri = payload.split("*", 1)
            observe["reading"] = reading
            observe["okuri"] = okuri
        else:
            observe["reading"] = payload
        if observe.get("okuri", "") == "":
            pending = re.search(r"[a-z]+$", payload)
            if pending:
                observe["pending"] = pending.group(0)
                observe["reading"] = payload[: pending.start()]
    elif preedit:
        # libskk は▽なしの打ちかけを preedit にそのまま返す。
        observe["stage"] = "none"
        pending = re.search(r"[a-z]+$", preedit)
        if pending:
            observe["pending"] = pending.group(0)
    else:
        observe["stage"] = "none"

    mode = None if abbrev else MODE.get(context.get_input_mode())
    if mode is not None:
        observe["mode"] = mode
    return observe


def run_case(case, dict_path, user_path):
    dictionary = Skk.FileDict.new(str(dict_path), "UTF-8")
    user_dictionary = Skk.UserDict.new(str(user_path), "UTF-8")
    context = Skk.Context.new([user_dictionary, dictionary])
    text = ""
    sequence = key_sequence(case["keys"])
    for key in sequence.split():
        context.process_key_events(key)
        text += context.poll_output()
    return {"observe": observe(context, text, "/" in sequence.split())}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--cases", type=Path, default=Path(".tests/conformance/cases.json"))
    parser.add_argument(
        "--output", type=Path, default=Path(".tests/conformance/results/libskk.json")
    )
    parser.add_argument("--version", default="1.1.1")
    args = parser.parse_args()
    cases_data = json.loads(args.cases.read_text(encoding="utf-8"))
    Skk.init()

    results = {}
    with tempfile.TemporaryDirectory(prefix="skkeleton-libskk-") as temporary:
        temporary = Path(temporary)
        dictionary_path = temporary / "dictionary"
        dictionary_path.write_text(
            dictionary_text(cases_data["dictionary"]), encoding="utf-8"
        )
        for case in cases_data["cases"]:
            user_path = temporary / f"user-{case['id']}"
            user_path.write_text(
                ";; conformance test user dictionary\n"
                ";; okuri-ari entries.\n"
                ";; okuri-nasi entries.\n",
                encoding="utf-8",
            )
            try:
                results[case["id"]] = run_case(case, dictionary_path, user_path)
            except Exception as error:
                results[case["id"]] = {"error": f"{type(error).__name__}: {error}"}

    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(
        json.dumps(
            {"impl": "libskk", "version": args.version, "results": results},
            ensure_ascii=False,
            indent=2,
        )
        + "\n",
        encoding="utf-8",
    )


if __name__ == "__main__":
    main()
