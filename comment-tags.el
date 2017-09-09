;;; comment-tags.el --- Highlight & navigate comment tags like 'TODO'. -*- lexical-binding: t -*-

;; Copyright © 2017 Vincent Dumas <vincekd@gmail.com>

;; Author: Vincent Dumas <vincekd@gmail.com>
;; URL: https://github.com/vincekd/comment-tags
;; Keywords: convenience, comments, tags
;; Version: 0.2
;; Package-Requires: ((emacs "24.5") (pkg-info "0.4"))

;; This file is NOT part of GNU Emacs.

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 3, or (at your option)
;; any later version.
;;
;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;;
;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs; see the file COPYING.  If not, write to the
;; Free Software Foundation, Inc., 51 Franklin Street, Fifth Floor,
;; Boston, MA 02110-1301, USA.

;;; Commentary:
;; A minor mode to highlight, track, and navigate comment tags like
;; TODO, FIXME, etc.  It scans the buffer to allow easily jumping
;; between comment tags, as well as viewing all tags in one view.

;;; TODO:
;; + find tags in all buffers with keyword search
;; + allow input of buffer name in `comment-tags-list-tags-buffer'
;; + jump to next, jump to previous (C-c t n, C-c t p)
;; + start only `comment-tags-comment-start-only' not implemented


;;; Changelog:
;; + allow differrent fonts for different `comment-tags-keywords'

;;; Code:


(require 'cl-lib)
(require 'subr-x)


;;; customize
(defgroup comment-tags nil
  "Highlight and navigate comment tags."
  :group 'tools
  :link '(url-link :tag "Github" "https://github.com/vincekd/comment-tags"))

(defcustom comment-tags-keywords
  '("TODO"
    "FIXME"
    "BUG"
    "HACK"
    "KLUDGE"
    "XXX"
    "INFO"
    "DONE")
  "Keywords to highlight and track."
  :group 'comment-tags
  :type '(repeat string))

(defcustom comment-tags-require-colon t
  "Require colon after tags."
  :group 'comment-tags
  :type 'boolean)

(defcustom comment-tags-case-sensitive t
  "Require tags to be case sensitive."
  :group 'comment-tags
  :type 'boolean)

(defcustom comment-tags-comment-start-only nil
  "Only highlight and track tags that are the beginning of a comment."
  :group 'comment-tags
  :type 'boolean)

(defcustom comment-tags-keymap-prefix (kbd "C-c t")
  "Prefix for keymap."
  :group 'comment-tags
  :type 'string)

(defcustom comment-tags-lighter nil
  "Mode-line text.")

(defcustom comment-tags-keyword-faces
  `(("TODO" . ,(list :inherit 'warning :weight 'bold))
    ("FIXME" . ,(list :inherit 'error :weight 'bold))
    ("BUG" . ,(list :inherit 'error :weight 'bold))
    ("HACK" . ,(list :inherit 'warning))
    ("KLUDGE" . ,(list :inherit 'warning))
    ("XXX" . ,(list :inherit 'underline :weight 'bold))
    ("INFO" . ,(list :inherit 'underline :weight 'bold))
    ("DONE" . ,(list :inherit 'success :weight 'bold)))
  "Faces for different keywords."
  :group 'comment-tags
  :type '(repeat (cons (string :tag "Keyword")
                       (string :tag "Face"))))

(defface comment-tags-default-face
  `((t :weight bold
       :underline nil
       :inherit default))
  "Defalut font face for highlighted tags."
  :group 'comment-tags)

(defconst comment-tags-temp-buffer-name "*comment-tags*"
  "Name for temp buffers to list tags.")

;;; funcs
(defun comment-tags--get-face ()
  "Find color for keyword."
  (let* ((str (replace-regexp-in-string (rx ":" eol) "" (match-string 1)))
         (face (cdr (assoc (upcase str) comment-tags-keyword-faces))))
    (or face 'comment-tags-default-face)))

(defun comment-tags--make-regexp ()
  "Create regexp from `comment-tags-keywords'."
  (rx-to-string
   `(seq
     bow
     (group
      (regexp ,(regexp-opt comment-tags-keywords))
      ,(if comment-tags-require-colon
           ":"
         `(opt ":"))))))

(defun comment-tags--in-comment (pos)
  "Checks if in comment at POS."
  (save-match-data (nth 4 (syntax-ppss pos))))
(defun comment-tags--comment-start (pos)
  "Returns start position of comment from POS."
  (save-match-data (nth 8 (syntax-ppss pos))))

(defun comment-tags--highlight-tags (limit)
  "Find areas marked with `comment-tags-highlight' and apply proper face within LIMIT."
  (let ((pos (point))
        (case-fold-search (not comment-tags-case-sensitive)))
    (with-silent-modifications
      (remove-text-properties pos (or limit (point-max)) '(comment-tags-highlight))
      (let ((chg (re-search-forward comment-tags-regexp limit t)))
        (when (and chg (> chg pos))
          (if (and (comment-tags--in-comment chg)
                   (or (not comment-tags-comment-start-only)
                       (string-match-p
                        (rx bos (* (not (any alphanumeric))) eos)
                        (buffer-substring-no-properties (comment-tags--comment-start chg) (match-beginning 0)))))
              (progn
                (put-text-property (match-beginning 0) (match-end 0) 'comment-tags-highlight (match-data))
                t)
            (comment-tags--highlight-tags limit)))))))

(defun comment-tags--scan ()
  "Scan current buffer from point with REGEXP."
  (when (comment-tags--highlight-tags nil)
    (comment-tags--scan)))

(defun comment-tags--scan-buffer ()
  "Scan current buffer at startup to populate file with `comment-tags-highlight'."
  (save-excursion
    (save-match-data
      (goto-char (point-min))
      (comment-tags--scan))))

(defun comment-tags--find-matched-tags (&optional noprops)
  "Find list of text marked with `comment-tags-highlight' from point.
If NOPROPS is non-nil, then return string without text properties."
  (let* ((pos (point))
        (chg (next-single-property-change pos 'comment-tags-highlight nil nil))
        (out (list)))
    (when (and chg (> chg pos))
      (goto-char chg)
      (let ((val (get-text-property chg 'comment-tags-highlight)))
        (when val
          (push (list
                 (count-lines 1 chg)
                 (string-trim
                  (if (not noprops)
                      (buffer-substring (line-beginning-position) (line-end-position))
                    (buffer-substring-no-properties (line-beginning-position) (line-end-position)))))
                out))
        (setq out (append out (comment-tags--find-matched-tags noprops)))))
    out))


(defun comment-tags--buffer-tags (buffer &optional noprops)
  "Find all comment tags in BUFFER.
If NOPROPS is non-nil, return strings without text properties."
  (with-current-buffer buffer
    (save-excursion
      (goto-char (point-min))
      (cl-remove-duplicates
       (comment-tags--find-matched-tags noprops)
       :test (lambda (x y)
               (or (null y) (equal (car x) (car y))))
       :from-end t))))


(defun comment-tags--format-tag-string (tag)
  "Format a TAG for insertion into the temp buffer."
  (format "%d:\t%s\n" (car tag) (nth 1 tag)))


(defun comment-tags--format-buffer-string (buf-name)
  "Format a buffer BUF-NAME for separation in temp buffer."
  (format "** COMMENT TAGS in '%s' **\n\n" buf-name))


(defun comment-tags--open-buffer-at-line (buf line)
  "Opens BUF at LINE."
  (pop-to-buffer buf)
  (goto-line line))


;;;###autoload
(defun comment-tags-list-tags-buffer ()
  "List all tags in the current buffer."
  (interactive)
  (let ((oldbuf (current-buffer))
        (oldbuf-name (buffer-name)))
    (with-temp-buffer-window
     comment-tags-temp-buffer-name nil nil
     (pop-to-buffer comment-tags-temp-buffer-name)
     (insert (comment-tags--format-buffer-string oldbuf-name))
     (dolist (element (comment-tags--buffer-tags oldbuf))
       (insert-text-button
        (comment-tags--format-tag-string element)
        'action (lambda (a)
                  (comment-tags--open-buffer-at-line oldbuf (car element))))))))


;;;###autoload
(defun comment-tags-find-tags-buffer ()
  "Complete tags in the current buffer and jump to line."
  (interactive)
  (let* ((tags (comment-tags--buffer-tags (current-buffer) t))
         (prompt "TAGS: ")
         (choice (completing-read
                  prompt
                  (mapcar (lambda (el)
                            (format "%d: %s" (car el) (nth 1 el)))
                            tags))))
    (when choice
      (string-match (rx bol (1+ digit)) choice)
      (let ((num (string-to-number (match-string 0 choice))))
        (comment-tags--open-buffer-at-line (current-buffer) num)))))


;;;###autoload
(defun comment-tags-list-tags-buffers ()
  "List tags for all open buffers."
  (interactive)
  (with-temp-buffer-window
   comment-tags-temp-buffer-name nil nil
   (pop-to-buffer comment-tags-temp-buffer-name)
   ;; list all buffers with comment-tags-mode enabled
   (dolist (buf (cl-remove-if-not
                 (lambda (b)
                   (with-current-buffer b
                     (and (boundp 'comment-tags-mode) comment-tags-mode)))
                 (buffer-list)))
     (let ((buf-name (with-current-buffer buf (buffer-name)))
           (tags (comment-tags--buffer-tags buf)))
       (when tags
         (insert (comment-tags--format-buffer-string buf-name))
         (dolist (element tags)
           (insert-text-button
            (comment-tags--format-tag-string element)
            'action (lambda (a)
                      (comment-tags--open-buffer-at-line buf (car element)))))
         (insert "\n"))))))


;; enable/disable functions
(defun comment-tags--enable ()
  "Enable 'comment-tags-mode'."
  (set (make-local-variable 'comment-tags-regexp) (comment-tags--make-regexp))
  (font-lock-add-keywords nil comment-tags-font-lock-keywords)
  (comment-tags--scan-buffer))

(defun comment-tags--disable ()
  "Disable 'comment-tags-mode'."
  (font-lock-remove-keywords nil comment-tags-font-lock-keywords))


;;; vars
(defvar comment-tags-font-lock-keywords
  `((comment-tags--highlight-tags 1 (comment-tags--get-face) t))
  "List of font-lock keywords to add to `default-keywords'.")

(defvar comment-tags-command-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "b") #'comment-tags-list-tags-buffer)
    (define-key map (kbd "a") #'comment-tags-list-tags-buffers)
    (define-key map (kbd "s") #'comment-tags-find-tags-buffer)
    map)
  "Command map.")
(fset 'comment-tags-command-map comment-tags-command-map)

(defvar comment-tags-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map comment-tags-keymap-prefix 'comment-tags-command-map)
    map)
  "Keymap for Comment-Tags mode.")

;;;###autoload
(define-minor-mode comment-tags-mode
  "Highlight and navigate comment tags."
  :lighter comment-tags-lighter
  :group 'comment-tags
  :require 'comment-tags
  :global nil
  :keymap comment-tags-mode-map
  (if comment-tags-mode
      (comment-tags--enable)
    (comment-tags--disable))
  (font-lock-flush))

(provide 'comment-tags)

;;; comment-tags.el ends here
