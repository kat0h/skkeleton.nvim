;;; DDskk driver for semantics/conformance/cases.lua observations.

(require 'json)
(defconst conformance-ddskk-library
  (expand-file-name ".tests/ddskk" (locate-dominating-file default-directory ".git")))
(add-to-list 'load-path conformance-ddskk-library)
(require 'skk)
(require 'skk-cus)
(require 'skk-version)
(require 'ccc)
(defconst conformance-ddskk-commit
  (with-temp-buffer
    (let ((default-directory conformance-ddskk-library))
      (call-process "git" nil t nil "rev-parse" "HEAD"))
    (string-trim (buffer-string))))
(defconst conformance-ddskk-cases
  '(("C01" "aiueo")
    ("C02" "Kanji<Space>")
    ("C03" "Kanji<Space><C-j>")
    ("C04" "Kanji<Space><Space>")
    ("C05" "KaKu")
    ("C06" "kt")
    ("C07" "k<C-j>")
    ("C08" "Kan<C-j>")
    ("C09" "Kak<Space>")
    ("C10" "Kak<Space><C-j>")
    ("C11" "KanSu")
    ("C12" "SasSi")
    ("C13" "TukaTta")
    ("C14" "Ka;<Space>")
    ("C15" "Kanji<Space><C-g>")
    ("C16" "Kanji<Space><BS>")
    ("C17" "Kanji<Space>x")
    ("C18" "Kanji<Space>a")
    ("C19" "qKa<C-j>")
    ("C20" "q/a<C-j>")))

(defun conformance-ddskk-tokens (keys)
  (let ((pos 0) tokens)
    (while (< pos (length keys))
      (if (eq (aref keys pos) ?<)
          (let ((end (string-match ">" keys pos)))
            (unless end (error "未完了のキー表記: %s" keys))
            (push (substring keys (1+ pos) end) tokens)
            (setq pos (1+ end)))
        (push (char-to-string (aref keys pos)) tokens)
        (setq pos (1+ pos))))
    (nreverse tokens)))

(defun conformance-ddskk-event (token)
  (cond ((equal token "Space") ?\s)
        ((equal token "C-j") ?\n)
        ((equal token "C-g") ?\C-g)
        ((equal token "BS") 127)
        ((equal token "CR") ?\r)
        ((equal token "Esc") ?\e)
        (t (string-to-char token))))

(defun conformance-ddskk-observe ()
  (let* ((contents (buffer-string))
         (marker (string-match "[▽▼]" contents))
         (text (if marker (substring contents 0 marker) contents))
         (selection (eq skk-henkan-mode 'active))
         (okuri (and selection skk-henkan-okurigana))
         (reading (and selection skk-henkan-key
                        (if (and okuri skk-okuri-char
                                 (string-suffix-p
                                  (if (stringp skk-okuri-char)
                                      skk-okuri-char
                                    (char-to-string skk-okuri-char))
                                  skk-henkan-key))
                            (substring skk-henkan-key 0 -1)
                          skk-henkan-key)))
         (candidate (and selection skk-henkan-list
                         (nth (or skk-henkan-count 0) skk-henkan-list)))
         (mode (cond (skk-latin-mode "ascii")
                     (skk-jisx0208-latin-mode "zenkaku")
                     (skk-abbrev-mode "abbrev")
                     (skk-jisx0201-mode "hankata")
                     (skk-katakana "kata")
                     (t "hira")))
         (stage (cond (selection "select")
                      (skk-henkan-mode "reading")
                      (t "none")))
         (result `((text . ,text) (stage . ,stage) (mode . ,mode))))
    (when reading (push (cons 'reading reading) result))
    (when candidate (push (cons 'candidate candidate) result))
    (when okuri (push (cons 'okuri okuri) result))
    result))

(defun conformance-ddskk-run-case (id keys dict-file user-dir)
  (if (equal id "C14")
      '((na . "batch では登録ミニバッファの表示を観測できない"))
    (condition-case err
        (with-temp-buffer
          (switch-to-buffer (current-buffer))
            (setq-local skk-jisyo (expand-file-name (concat id ".jisyo") user-dir)
                        skk-jisyo-code 'utf-8
                        skk-large-jisyo dict-file
                        skk-sticky-key ";"
                        skk-keep-record nil
                        skk-save-jisyo-instantly nil)
            (skk-mode 1)
            (let ((tokens (conformance-ddskk-tokens keys)))
              (dolist (token tokens)
                (execute-kbd-macro (vector (conformance-ddskk-event token))))
              `((observe . ,(conformance-ddskk-observe)))))
      (error `((error . ,(error-message-string err)))))))

(defun conformance-ddskk-main ()
  (let* ((root (locate-dominating-file default-directory ".git"))
         (tmp (make-temp-file "skkeleton-conformance-" t))
         (dict (expand-file-name "dictionary" tmp))
         (user-dir (expand-file-name "users" tmp))
         results)
    (make-directory user-dir)
    (setq skk-jisyo (expand-file-name "global.jisyo" user-dir)
          skk-jisyo-code 'utf-8
          skk-keep-record nil)
    (with-temp-file skk-jisyo (insert ""))
    (with-temp-file dict
      (insert ";; okuri-ari entries.\n"
              "つかt /使/\nさっs /察/\nかんs /関/\nかk /書/欠/\n"
              ";; okuri-nasi entries.\nか /蚊/\nかんじ /漢字/幹事/\n"))
    (dolist (case conformance-ddskk-cases)
      (push (cons (intern (car case))
                  (conformance-ddskk-run-case (car case) (cadr case) dict user-dir))
            results))
    (let ((output `((impl . "DDskk")
                    (version . ,(format "DDskk %s; Emacs %s" conformance-ddskk-commit emacs-version))
                    (settings . ((sticky . "有効にした")))
                    (results . ,(nreverse results)))))
      (with-temp-file (expand-file-name "semantics/conformance/results/DDskk.json" root)
        (insert (json-encode output) "\n")))
    (delete-directory tmp t)))

(conformance-ddskk-main)
