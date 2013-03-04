;;; cryptol-mode.el --- Cryptol major mode for Emacs

;; Copyright (c) 2013 Austin Seipp. All rights reserved.

;; Author:    Austin Seipp <aseipp [@at] pobox [dot] com>
;; URL:       http://github.com/thoughtpolice/cryptol-mode
;; Keywords:  cryptol cryptography
;; Version:   0.0.1
;; Released:  11 Feburary 2013

;; This file is not part of GNU Emacs.

;;; License:

;; Copyright (C) 2013 Austin Seipp
;; This program is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.
;;
;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;;
;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <http://www.gnu.org/licenses/>.
;;
;; [ GPLv3 license: http://www.gnu.org/licenses/gpl-3.0.txt ]

;;; Commentary:

;; This package provides a major mode for editing, compiling and
;; running Cryptol code.
;;
;; For more information about Cryptol, check out the homepage and
;; documentation: http://corp.galois.com/cryptol/
;;
;; For usage info, release notes and bugs, check the homepage.

;;; TODO:

;; * Indentation mode:
;;  - Maybe something like Haskell-mode?
;; * Better imenu support:
;;  - Should support function definitions
;;  - Modules? Parameterized modules?
;; * Better highlighting and syntax recognition:
;;  - Function names in particular.
;; * Compiler support:
;;  - Compile to C code based on the buffer name.
;;  - Ditto with VHDL, etc.
;;  - Isabelle compilation.
;;   - Would it be possible to drop from ':isabelle-i' into
;;     e.g. proof-general or something?
;; * Interactive features:
;;  - Mode switching.
;;  - Run 'check' or 'exhaust' on identifier (see REPL notes below.)
;;  - Prove function equivalence between top-level named identifiers.
;;  - Check satisfiability of constraints/propositions.
;; * Debugging:
;;  - It might be possible to have minimal debugger interaction with
;;    ':trace' and friends.
;; * REPL integration:
;;  - We'd like to be able to set optimization settings.
;;  - Run 'check' or 'exhaust' on given function/theorem.
;;  - Automatically run batch-mode files..
;; * Cross platformness:
;;  - Works OK on Linux, OS X
;;  - Windows? :|

;;; Known bugs:

;; * `imenu' support only identifies theorems.
;; * Literate file support is non-existant. Seriously.
;; * Indentation support is also non-existant.
;; * Highlighting is rather haphazard, but fairly complete.

(require 'comint)
(require 'shell)
(require 'easymenu)
(require 'font-lock)
(require 'generic-x)

;;; -- Customization variables -------------------------------------------------

(defconst cryptol-mode-version "0.0.1"
  "The version of `cryptol-mode'.")

(defgroup cryptol nil
  "A Cryptol major mode."
  :group 'languages)

(defcustom cryptol-tab-width tab-width
  "The tab width to use when indenting."
  :type  'integer
  :group 'cryptol)

(defcustom cryptol-command "cryptol"
  "The Cryptol command to use for evaluating code."
  :type  'string
  :group 'cryptol)

(defcustom cryptol-args-repl '("-n")
  "The arguments to pass to `cryptol-command' when starting a REPL."
  :type  'list
  :group 'cryptol)

(defcustom cryptol-args-compile '("-b")
  "The arguments to pass to `cryptol-command' to compile a file."
  :type  'list
  :group 'cryptol)

(defcustom cryptol-compiled-buffer-name "*cryptol-compiled*"
  "The name of the scratch buffer for compiled Cryptol."
  :type  'string
  :group 'cryptol)

(defcustom cryptol-mode-hook nil
  "Hook called by `cryptol-mode'."
  :type  'hook
  :group 'cryptol)

(defcustom cryptol-repl-hook nil
  "Hook called when `cryptol-repl' is invoked."
  :type 'hook
  :group 'cryptol)

(defvar cryptol-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "C-c C-l") 'cryptol-repl)
    map)
  "Keymap for `cryptol-mode'.")

;;; -- Language Syntax ---------------------------------------------------------

(defvar cryptol-string-regexp "\"\\.\\*\\?")

(defvar cryptol-symbols-regexp
  (regexp-opt '( "<|" "|>" "[" "]" "," "{" "}" "@" "#")))

(defvar cryptol-symbols2-regexp
  (regexp-opt '( "`" "|" "=>" "->" ":" ">>" ">>>" "<<" "<<<" )))

(defvar cryptol-consts-regexp
  (regexp-opt '( "True" "False" "inf" "fin" ) 'words))

(defvar cryptol-type-regexp
  (regexp-opt '( "Bit" ) 'words))

(defvar cryptol-keywords-regexp
  (regexp-opt '( "module" "theorem" "where" "include" "instantiate"
		 "let" "if" "else" "then" "type" ) 'words))

(defvar cryptol-theorem-regexp
  "^theorem \\(.*\\):")

;;; -- Utilities ---------------------------------------------------------------

(defvar *cryptol-backends* nil)

(defun get-cryptol-backends ()
  "Get the backends supported by the Cryptol compiler."
  (if (not (eq nil *cryptol-backends*))
      *cryptol-backends*
    (let ((cryptol-backends
	   (nthcdr 2 (split-string
		    (nth 3 (process-lines cryptol-command "-v"))))))
      (setq *cryptol-backends* cryptol-backends)
      *cryptol-backends*)))

;;;###autoload
(defun cryptol-backends ()
  "Show the backends supported by the `cryptol-command'."
  (interactive)
  (let ((cryptol-backend-out (mapconcat 'identity (get-cryptol-backends) " ")))
    (message (concat "Cryptol backends: " (concat cryptol-backend-out)))))

;;;###autoload
(defun cryptol-version ()
  "Show the `cryptol-mode' version in the echo area."
  (interactive)
  (let ((cryptol-ver-out (car (process-lines cryptol-command "-v"))))
    (message (concat "cryptol-mode v" cryptol-mode-version
		     ", using " cryptol-ver-out))))

;;; -- Menu --------------------------------------------------------------------

(easy-menu-define cryptol-mode-menu cryptol-mode-map
  "Menu for `cryptol-mode'."
  '("Cryptol"
    ["Start REPL" cryptol-repl]
    ["imenu"      imenu]
    "---"
    ["Customize Cryptol group" (customize-group 'cryptol)]
    "---"
    ["Version info" cryptol-version]
    ))

;;; -- REPL --------------------------------------------------------------------

(defvar cryptol-repl-process nil
  "The active Cryptol subprocess corresponding to the current buffer.")

(defvar cryptol-repl-process-buffer nil
  "*Buffer used for communication with Cryptol subprocess for current buffer.")

(defvar cryptol-repl-comint-prompt-regexp
  "^\\*?[[:upper:]][\\._[:alnum:]]*\\( \\*?[[:upper:]][\\._[:alnum:]]*\\)*> "
  "A regexp that matches the Cryptol prompt.")

(defun make-repl-command (file)
  (append (list cryptol-command) cryptol-args-repl (list file)))

(defun cryptol-repl ()
  "Launch a Cryptol REPL using `cryptol-command' as an inferior executable."
  (interactive)

  (message "Starting Cryptol REPL via `%s'." cryptol-command)
  (setq cryptol-repl-process-buffer
	(apply 'make-comint
	       "cryptol" cryptol-command nil
	       cryptol-args-repl))
  (setq cryptol-repl-process
	(get-buffer-process cryptol-repl-process-buffer))

  ;; Select REPL buffer and track `:cd' changes etc.
  (set-buffer cryptol-repl-process-buffer)
  (make-local-variable 'shell-cd-regexp)
  (make-local-variable 'shell-dirtrackp)

  (setq shell-cd-regexp ":cd")
  (setq shell-dirtrackp t)
  (add-hook 'comint-input-filter-functions 'shell-directory-tracker nil 'local)

  (setq comint-prompt-regexp cryptol-repl-comint-prompt-regexp)

  (setq comint-input-autoexpand nil)
  (setq comint-process-echoes nil)

  ;; Run hooks and clear message buffer
  (run-hooks 'cryptol-repl-hook)
  (pop-to-buffer "*cryptol*")
  (message ""))

;;; -- imenu -------------------------------------------------------------------

(defun cryptol-imenu-create-index ()
  "Creates an imenu index of all the methods/theorems in the buffer."
  (interactive)

  (goto-char (point-min))
  (let ((imenu-list '()) assign pos)
    (while (re-search-forward
	    (concat "\\("
		    cryptol-theorem-regexp
		    "\\)")
	    (point-max)
	    t)
      ;; Look for any theorems and add them to the list
      (when (match-string 2)
	(setq pos (match-beginning 2))
	(setq assign (match-string 2))
	(push (cons assign pos) imenu-list)))
    imenu-list))

;;; -- Syntax table and highlighting -------------------------------------------

(defvar cryptol-mode-syntax-table
  (let ((st (make-syntax-table)))
    (modify-syntax-entry ?/ ". 124" st)
    (modify-syntax-entry ?* ". 23bn" st)
    (modify-syntax-entry ?\n ">" st)
    st)
  "Syntax table for `cryptol-mode'.")

(defvar cryptol-font-lock-defaults
  `((,cryptol-string-regexp   . font-lock-string-face)
    (,cryptol-symbols-regexp  . font-lock-builtin-face)
    (,cryptol-symbols2-regexp . font-lock-variable-name-face)
    (,cryptol-keywords-regexp . font-lock-keyword-face)
    (,cryptol-consts-regexp   . font-lock-constant-face)
    (,cryptol-type-regexp     . font-lock-type-face)
    ))

;;; -- Mode entry --------------------------------------------------------------

;; Major mode for cryptol code
;;;###autoload
(define-derived-mode cryptol-mode prog-mode "Cryptol"
  "Major mode for editing Cryptol code."

  ;; Syntax highlighting
  (setq font-lock-defaults '((cryptol-font-lock-defaults)))

  ;; Indentation, no tabs
  (set (make-local-variable 'tab-width) cryptol-tab-width)
  (setq indent-tabs-mode nil)

  ;; imenu
  (make-local-variable 'imenu-create-index-function)
  (setq imenu-create-index-function 'cryptol-imenu-create-index))
(provide 'cryptol-mode)

;; Major mode for literate cryptol code
;;;###autoload
(define-derived-mode literate-cryptol-mode prog-mode "Literate Cryptol"
  "Major mode for editing Literate Cryptol code."

  ;; Syntax highlighting
  (setq font-lock-defaults '((lcryptol-font-lock-defaults)))

  ;; Indentation, no tabs
  (set (make-local-variable 'tab-width) cryptol-tab-width)
  (setq indent-tabs-mode nil))

;; Major mode used for .scr files (batch files)
;;;###autoload
(define-generic-mode 'cryptol-batch-mode
  '("#")                               ;; comments start with #
  '("autotrace" "bind_file" "browse"
    "cd" "check" "compile" "config"
    "definition" "deltr" "edit"
    "equals" "exhaust" "fm" "genTests"
    "getserial" "help" "info" 
    "install-runtime" "isabelle"
    "isabelle-b" "isabelle-i" "let"
    "load" "print" "prove" "quit"
    "reload" "runWith" "safe" "sat"
    "script" "sendserial" "set" "sfm"
    "showtr" "trace" "translate"
    "type" "version")
  '((":" . 'font-lock-builtin)         ;; ':' is a builtin
    ("@" . 'font-lock-operator))       ;; '@' is an operator
  nil nil                              ;; autoload is set below
  "A mode for Cryptol batch files")

;;; -- Autoloading -------------------------------------------------------------

;;;###autoload
(add-to-list 'auto-mode-alist '("\\.cry$\\|\\.cyl$"  . cryptol-mode))
;;;###autoload
(add-to-list 'auto-mode-alist '("\\.lcry$\\|\\.lcyl$" . literate-cryptol-mode))
;;;###autoload
(add-to-list 'auto-mode-alist '("\\.scr$"  . cryptol-batch-mode))

;;; cryptol-mode.el ends here
