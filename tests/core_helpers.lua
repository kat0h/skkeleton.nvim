-- core のテストを子の nvim の中で動かすための補助（upstream の function/testutil.ts の dispatch に相当）
local M = {}

local util = require("skkeleton.util")

-- upstream のテストの registerHenkanResult と同じ動きの偽の Library。
-- 登録した候補が先に来る（ユーザー辞書と同じ）
local Fake = {}
Fake.__index = Fake

function Fake.new()
  return setmetatable({ data = {}, purged = {}, loaded = 0, saved = 0 }, Fake)
end

function Fake:get_henkan_result(type, word)
  return vim.deepcopy(self.data[type .. ":" .. word] or {})
end

function Fake:register_henkan_result(type, word, candidate)
  local key = type .. ":" .. word
  local list = vim.tbl_filter(function(c)
    return c ~= candidate
  end, self.data[key] or {})
  table.insert(list, 1, candidate)
  self.data[key] = list
end

function Fake:purge_candidate(type, word, candidate)
  local key = type .. ":" .. word
  self.data[key] = vim.tbl_filter(function(c)
    return c ~= candidate
  end, self.data[key] or {})
  table.insert(self.purged, { type, word, candidate })
end

function Fake:load()
  self.loaded = self.loaded + 1
end

function Fake:save()
  self.saved = self.saved + 1
end

M.FakeLibrary = Fake

-- 偽の Library を store に入れて返す
function M.setup_library()
  local lib = Fake.new()
  require("skkeleton.store").set_library(lib)
  return lib
end

-- keys を 1 文字ずつ ctx に流す
function M.dispatch(ctx, keys)
  local input = require("skkeleton.function.input")
  local common = require("skkeleton.function.common")
  local henkan = require("skkeleton.function.henkan")
  for _, key in ipairs(util.chars(keys)) do
    if ctx.state.type == "input" then
      if key == " " then
        henkan.henkan_first(ctx, key)
      elseif key == ";" then
        input.henkan_point(ctx)
      elseif key == "\n" then
        common.newline(ctx)
      else
        input.kana_input(ctx, key)
      end
    elseif ctx.state.type == "henkan" then
      if key == " " then
        henkan.henkan_forward(ctx)
      elseif key == "x" then
        henkan.henkan_backward(ctx)
      elseif key == "\n" then
        common.newline(ctx)
      end
    end
  end
end

-- 新しい Context に keys を流して、確定した文字列（preedit:output("")）を返す
function M.output(keys)
  local ctx = require("skkeleton.context").new()
  M.dispatch(ctx, keys)
  return ctx.preedit:output("")
end

-- 新しい Context に keys を流して、pre-edit の表示（to_string）を返す
function M.shown(keys)
  local ctx = require("skkeleton.context").new()
  M.dispatch(ctx, keys)
  return ctx:to_string()
end

-- host の関数を差し替えて、呼ばれた引数を M.calls に積む。返り値は ret[name] で決める
M.calls = {}
M.ret = {}
function M.spy_host()
  local host = require("skkeleton.host")
  M.calls = {}
  for _, name in ipairs({ "disable", "show_candidates", "input", "confirm", "keep_state_on_insert_enter" }) do
    host[name] = function(...)
      M.calls[#M.calls + 1] = { name, ... }
      local r = M.ret[name]
      if type(r) == "function" then
        return r(...)
      end
      return r
    end
  end
end

-- name の呼び出しだけを取り出す
function M.called(name)
  return vim.tbl_filter(function(c)
    return c[1] == name
  end, M.calls)
end

return M
