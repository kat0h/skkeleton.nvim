" ステータスラインなどから使われる互換の関数だけを置く。
" 本体は lua/skkeleton/ にある。

function! skkeleton#is_enabled() abort
  return get(g:, 'skkeleton#enabled', v:false)
endfunction

function! skkeleton#mode() abort
  if skkeleton#is_enabled()
    return get(g:, 'skkeleton#mode', '')
  else
    return ''
  endif
endfunction
