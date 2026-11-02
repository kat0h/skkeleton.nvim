-- tests/README.md の対応表に記載されたテストケースが
-- 実際に tests/ 配下に存在することを検証するテスト
local eq = MiniTest.expect.equality
local T = MiniTest.new_set()

T["all test cases referenced in tests/README.md exist"] = function()
  local f = io.open("tests/README.md", "r")
  if not f then
    error("tests/README.md not found")
  end
  local content = f:read("*a")
  f:close()

  -- ファイルごとの内容をキャッシュ
  local file_cache = {}
  local function get_file_content(path)
    if not file_cache[path] then
      local fp = io.open(path, "r")
      if not fp then
        return nil
      end
      file_cache[path] = fp:read("*a")
      fp:close()
    end
    return file_cache[path]
  end

  local checked_count = 0
  for line in content:gmatch("[^\r\n]+") do
    -- 例: `tests/test_function_common.lua` (`T["egg like newline"]`)
    for test_file, case_name in line:gmatch('`(tests/[%w_]+%.lua)`%s*%(%s*`T%["([^"]+)"%]`%s*%)') do
      local file_text = get_file_content(test_file)
      if not file_text then
        error(string.format("Referenced test file '%s' does not exist", test_file))
      end
      local pattern = string.format('T%%["%s"%%]', case_name:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1"))
      local found = file_text:find(pattern) ~= nil
      if not found then
        error(string.format("Test case '%s' not found in '%s'", case_name, test_file))
      end
      checked_count = checked_count + 1
    end
  end

  -- 最低限の件数がチェックされていることを担保
  eq(checked_count >= 40, true)
end

return T
