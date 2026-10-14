// Bundled TypeScript type stripper and ES module transformer for JavaScriptCore (ADR-D6, #435).
// Preserves line numbers and maps columns back to the original .part.ts or .part.js source.

(function (global) {
  'use strict';

  var KEYWORDS_ALLOWING_REGEX = {
    'return': true, 'throw': true, 'case': true, 'delete': true,
    'void': true, 'typeof': true, 'instanceof': true, 'in': true,
    'of': true, 'new': true, 'yield': true, 'await': true, 'else': true,
    'do': true, 'export': true
  };

  var PUNCT_ALLOWING_REGEX = {
    '(': true, '{': true, '[': true, ',': true, ';': true, ':': true,
    '?': true, '=': true, '+=': true, '-=': true, '*=': true, '/=': true,
    '%=': true, '&=': true, '|=': true, '^=': true, '<<=': true, '>>=': true,
    '>>>=': true, '&&=': true, '||=': true, '??=': true, '=>': true,
    '!': true, '~': true, '+': true, '-': true, '*': true, '%': true,
    '**': true, '&&': true, '||': true, '??': true, '==': true, '===': true,
    '!=': true, '!==': true, '<': true, '>': true, '<=': true, '>=': true,
    '&': true, '|': true, '^': true, '<<': true, '>>': true, '>>>': true
  };

  var TYPE_CONTINUATION_AFTER = {
    '|': true, '&': true, '=>': true, 'extends': true, 'keyof': true,
    'typeof': true, 'infer': true, 'readonly': true, 'is': true, 'asserts': true,
    '.': true, ',': true, '<': true, '[': true, '(': true, '{': true, '?': true, ':': true
  };

  var TYPE_CONTINUATION_BEFORE = {
    '|': true, '&': true, '=>': true, 'extends': true, 'is': true,
    '.': true, '<': true, '[': true, '?': true
  };

  function isIdentStart(ch) {
    var code = ch.charCodeAt(0);
    return (code >= 65 && code <= 90) || (code >= 97 && code <= 122) || code === 95 || code === 36 || code > 127;
  }

  function isIdentPart(ch) {
    var code = ch.charCodeAt(0);
    return isIdentStart(ch) || (code >= 48 && code <= 57);
  }

  function isDigit(ch) {
    var code = ch.charCodeAt(0);
    return code >= 48 && code <= 57;
  }

  function tokenize(source) {
    var tokens = [];
    var len = source.length;
    var i = 0;
    var line = 1;
    var col = 1;
    var hadNewlineSinceLast = false;

    function advance(n) {
      for (var k = 0; k < n && i < len; k++) {
        if (source[i] === '\n') {
          line++;
          col = 1;
          hadNewlineSinceLast = true;
        } else {
          col++;
        }
        i++;
      }
    }

    function canStartRegex() {
      if (tokens.length === 0) return true;
      var prev = tokens[tokens.length - 1];
      if (prev.type === 'ident') {
        return !!KEYWORDS_ALLOWING_REGEX[prev.value];
      }
      if (prev.type === 'punct') {
        return !!PUNCT_ALLOWING_REGEX[prev.value];
      }
      return false;
    }

    while (i < len) {
      var ch = source[i];

      // Whitespace
      if (ch === ' ' || ch === '\t' || ch === '\r' || ch === '\n') {
        advance(1);
        continue;
      }

      // Single-line comment
      if (ch === '/' && source[i + 1] === '/') {
        while (i < len && source[i] !== '\n') {
          advance(1);
        }
        continue;
      }

      // Multi-line comment
      if (ch === '/' && source[i + 1] === '*') {
        var commentLine = line;
        var commentCol = col;
        advance(2);
        while (i < len && !(source[i] === '*' && source[i + 1] === '/')) {
          advance(1);
        }
        if (i >= len) {
          var err = new SyntaxError('Unterminated block comment');
          err.line = commentLine;
          err.column = commentCol;
          throw err;
        }
        advance(2);
        continue;
      }

      var start = i;
      var startLine = line;
      var startCol = col;
      var newlineBefore = hadNewlineSinceLast;
      hadNewlineSinceLast = false;

      // String literal
      if (ch === '\'' || ch === '"') {
        var quote = ch;
        advance(1);
        while (i < len && source[i] !== quote) {
          if (source[i] === '\n') {
            var sErr = new SyntaxError('Unterminated string literal');
            sErr.line = startLine;
            sErr.column = startCol;
            throw sErr;
          }
          if (source[i] === '\\') {
            advance(2);
          } else {
            advance(1);
          }
        }
        if (i >= len) {
          var uErr = new SyntaxError('Unterminated string literal');
          uErr.line = startLine;
          uErr.column = startCol;
          throw uErr;
        }
        advance(1);
        tokens.push({
          type: 'string',
          value: source.slice(start, i),
          start: start,
          end: i,
          line: startLine,
          col: startCol,
          newlineBefore: newlineBefore
        });
        continue;
      }

      // Template literal (kept intact as a single token or balanced with nested braces)
      if (ch === '`') {
        advance(1);
        var braceDepth = 0;
        while (i < len) {
          var tc = source[i];
          if (tc === '\\') {
            advance(2);
          } else if (tc === '`' && braceDepth === 0) {
            advance(1);
            break;
          } else if (tc === '$' && source[i + 1] === '{') {
            braceDepth++;
            advance(2);
          } else if (tc === '}' && braceDepth > 0) {
            braceDepth--;
            advance(1);
          } else {
            advance(1);
          }
        }
        tokens.push({
          type: 'template',
          value: source.slice(start, i),
          start: start,
          end: i,
          line: startLine,
          col: startCol,
          newlineBefore: newlineBefore
        });
        continue;
      }

      // RegExp literal
      if (ch === '/' && source[i + 1] !== '/' && source[i + 1] !== '*' && canStartRegex()) {
        advance(1);
        var inCharClass = false;
        while (i < len) {
          var rc = source[i];
          if (rc === '\n') {
            var rErr = new SyntaxError('Unterminated regular expression literal');
            rErr.line = startLine;
            rErr.column = startCol;
            throw rErr;
          }
          if (rc === '\\') {
            advance(2);
          } else if (rc === '[') {
            inCharClass = true;
            advance(1);
          } else if (rc === ']') {
            inCharClass = false;
            advance(1);
          } else if (rc === '/' && !inCharClass) {
            advance(1);
            while (i < len && isIdentPart(source[i])) {
              advance(1);
            }
            break;
          } else {
            advance(1);
          }
        }
        tokens.push({
          type: 'regex',
          value: source.slice(start, i),
          start: start,
          end: i,
          line: startLine,
          col: startCol,
          newlineBefore: newlineBefore
        });
        continue;
      }

      // Numbers
      if (isDigit(ch) || (ch === '.' && i + 1 < len && isDigit(source[i + 1]))) {
        if (ch === '0' && (source[i + 1] === 'x' || source[i + 1] === 'X' || source[i + 1] === 'b' || source[i + 1] === 'B' || source[i + 1] === 'o' || source[i + 1] === 'O')) {
          advance(2);
          while (i < len && (isIdentPart(source[i]) || source[i] === '_')) {
            advance(1);
          }
        } else {
          while (i < len && (isDigit(source[i]) || source[i] === '_')) {
            advance(1);
          }
          if (i < len && source[i] === '.' && source[i + 1] !== '.') {
            advance(1);
            while (i < len && (isDigit(source[i]) || source[i] === '_')) {
              advance(1);
            }
          }
          if (i < len && (source[i] === 'e' || source[i] === 'E')) {
            advance(1);
            if (i < len && (source[i] === '+' || source[i] === '-')) {
              advance(1);
            }
            while (i < len && (isDigit(source[i]) || source[i] === '_')) {
              advance(1);
            }
          }
        }
        tokens.push({
          type: 'number',
          value: source.slice(start, i),
          start: start,
          end: i,
          line: startLine,
          col: startCol,
          newlineBefore: newlineBefore
        });
        continue;
      }

      // Identifiers and keywords
      if (isIdentStart(ch)) {
        advance(1);
        while (i < len && isIdentPart(source[i])) {
          advance(1);
        }
        tokens.push({
          type: 'ident',
          value: source.slice(start, i),
          start: start,
          end: i,
          line: startLine,
          col: startCol,
          newlineBefore: newlineBefore
        });
        continue;
      }

      // Multi-char punctuation
      var three = source.slice(i, i + 3);
      var two = source.slice(i, i + 2);
      if (three === '...' || three === '===' || three === '!==' || three === '>>>' ||
          three === '<<=' || three === '>>=' || three === '&&=' || three === '||=' || three === '??=') {
        advance(3);
        tokens.push({
          type: 'punct',
          value: three,
          start: start,
          end: i,
          line: startLine,
          col: startCol,
          newlineBefore: newlineBefore
        });
        continue;
      }
      if (two === '=>' || two === '==' || two === '!=' || two === '<=' || two === '>=' ||
          two === '&&' || two === '||' || two === '??' || two === '?.' || two === '++' ||
          two === '--' || two === '**' || two === '<<' || two === '>>' || two === '+=' ||
          two === '-=' || two === '*=' || two === '/=' || two === '%=' || two === '&=' ||
          two === '|=' || two === '^=') {
        advance(2);
        tokens.push({
          type: 'punct',
          value: two,
          start: start,
          end: i,
          line: startLine,
          col: startCol,
          newlineBefore: newlineBefore
        });
        continue;
      }

      advance(1);
      tokens.push({
        type: 'punct',
        value: ch,
        start: start,
        end: i,
        line: startLine,
        col: startCol,
        newlineBefore: newlineBefore
      });
    }

    return tokens;
  }

  function makeCharArray(source) {
    return source.split('');
  }

  function blankRange(chars, start, end) {
    for (var idx = start; idx < end; idx++) {
      if (chars[idx] !== '\n' && chars[idx] !== '\r') {
        chars[idx] = ' ';
      }
    }
  }

  function findMatchingClose(tokens, openIdx, openVal, closeVal) {
    var depth = 0;
    for (var i = openIdx; i < tokens.length; i++) {
      var v = tokens[i].value;
      if (v === openVal) depth++;
      else if (v === closeVal) {
        depth--;
        if (depth === 0) return i;
      }
    }
    return -1;
  }

  // Finds the matching '>' for a type parameter or type argument list starting at openIdx ('<').
  function findMatchingAngle(tokens, openIdx) {
    var angleDepth = 0;
    var parenDepth = 0;
    var braceDepth = 0;
    var bracketDepth = 0;
    for (var i = openIdx; i < tokens.length; i++) {
      var tok = tokens[i];
      var v = tok.value;
      if (parenDepth === 0 && braceDepth === 0 && bracketDepth === 0) {
        if (v === '<') {
          angleDepth++;
          continue;
        }
        if (v === '>') {
          angleDepth--;
          if (angleDepth === 0) return i;
          continue;
        }
        if (v === '>>') {
          angleDepth -= 2;
          if (angleDepth <= 0) return i;
          continue;
        }
        if (v === '>>>') {
          angleDepth -= 3;
          if (angleDepth <= 0) return i;
          continue;
        }
        if (v === ';') return -1;
      }
      if (v === '(') parenDepth++;
      else if (v === ')') { if (parenDepth > 0) parenDepth--; else return -1; }
      else if (v === '{') braceDepth++;
      else if (v === '}') { if (braceDepth > 0) braceDepth--; else return -1; }
      else if (v === '[') bracketDepth++;
      else if (v === ']') { if (bracketDepth > 0) bracketDepth--; else return -1; }
    }
    return -1;
  }

  // Scans a TypeScript type expression starting at startIdx and returns the index of the last token belonging to the type.
  // stopOptions: { allowArrow: boolean, stopAtComma: boolean, stopAtEquals: boolean, stopAtOpenBrace: boolean, stopAtCloseParen: boolean }
  function scanTypeExpression(tokens, startIdx, stopOptions) {
    var opts = stopOptions || {};
    var i = startIdx;
    var parenDepth = 0;
    var braceDepth = 0;
    var bracketDepth = 0;
    var angleDepth = 0;
    var lastIdx = startIdx - 1;

    while (i < tokens.length) {
      var tok = tokens[i];
      var v = tok.value;
      var atTop = (parenDepth === 0 && braceDepth === 0 && bracketDepth === 0 && angleDepth === 0);

      if (atTop) {
        if (v === ';') break;
        if (v === ')' || v === ']' || v === '}') break;
        if (v === ',' && opts.stopAtComma !== false) break;
        if (v === '=' && opts.stopAtEquals !== false) break;
        if (v === '=>' && !opts.allowArrow) break;
        if (v === '{' && opts.stopAtOpenBrace) {
          // In return types or interface/class headers, '{' starts the function/class body UNLESS preceded by a type continuation token
          var prevTok = i > startIdx ? tokens[i - 1] : null;
          if (prevTok && !TYPE_CONTINUATION_AFTER[prevTok.value] && prevTok.value !== '=>' && prevTok.value !== '|' && prevTok.value !== '&' && prevTok.value !== ':') {
            break;
          }
        }
        // Check if newline started a new statement when inside 'as Type' or type alias without semicolon
        if (i > startIdx && tok.newlineBefore) {
          var prev = tokens[i - 1];
          if (!TYPE_CONTINUATION_AFTER[prev.value] && !TYPE_CONTINUATION_BEFORE[v]) {
            break;
          }
        }
      }

      if (v === '(') parenDepth++;
      else if (v === ')') parenDepth--;
      else if (v === '{') braceDepth++;
      else if (v === '}') braceDepth--;
      else if (v === '[') bracketDepth++;
      else if (v === ']') bracketDepth--;
      else if (v === '<') angleDepth++;
      else if (v === '>') {
        if (angleDepth > 0) angleDepth--;
        else if (atTop) break;
      } else if (v === '>>' && angleDepth > 0) {
        angleDepth = Math.max(0, angleDepth - 2);
      }

      lastIdx = i;
      i++;
    }

    return lastIdx >= startIdx ? lastIdx : startIdx;
  }

  function looksLikeTypeArguments(tokens, openIdx, closeIdx) {
    if (closeIdx <= openIdx + 1) return false;
    for (var i = openIdx + 1; i < closeIdx; i++) {
      var tok = tokens[i];
      var v = tok.value;
      if (v === ';' || v === '==' || v === '===' || v === '!=' || v === '!==' ||
          v === '&&' || v === '||' || v === '+=' || v === '-=') {
        return false;
      }
    }
    var after = tokens[closeIdx + 1];
    if (!after) return false;
    return after.value === '(' || after.value === '`';
  }

  function isFunctionHeaderCloseParen(tokens, closeParenIdx) {
    // Checks if ')' at closeParenIdx closes a function/method/arrow parameter list.
    // Find matching '('
    var depth = 0;
    var openParenIdx = -1;
    for (var i = closeParenIdx; i >= 0; i--) {
      if (tokens[i].value === ')') depth++;
      else if (tokens[i].value === '(') {
        depth--;
        if (depth === 0) {
          openParenIdx = i;
          break;
        }
      }
    }
    if (openParenIdx < 0) return false;

    // Look after ')' (possibly after ': ReturnType') for '=>' or '{'
    var afterParen = tokens[closeParenIdx + 1];
    if (!afterParen) return false;

    // Check what precedes '('
    var beforeParen = openParenIdx > 0 ? tokens[openParenIdx - 1] : null;
    if (beforeParen && beforeParen.value === '>') {
      // Could be generic function foo<T>(...)
      for (var k = openParenIdx - 1; k >= 0; k--) {
        if (tokens[k].value === '<') {
          beforeParen = k > 0 ? tokens[k - 1] : null;
          break;
        }
      }
    }

    if (beforeParen && beforeParen.type === 'ident') {
      var kw = beforeParen.value;
      if (kw === 'if' || kw === 'for' || kw === 'while' || kw === 'switch' || kw === 'catch' || kw === 'with') {
        return false;
      }
      if (kw === 'function') return true;
      var beforeIdent = openParenIdx - 2 >= 0 ? tokens[openParenIdx - 2] : null;
      if (beforeIdent && beforeIdent.value === 'function') return true;
    }

    // If ': ReturnType' follows ')', scan past the return type and check if '=>' or '{' follows
    if (afterParen.value === ':') {
      var endType = scanTypeExpression(tokens, closeParenIdx + 2, {
        allowArrow: true,
        stopAtComma: true,
        stopAtEquals: true,
        stopAtOpenBrace: true
      });
      var nextAfterType = tokens[endType + 1];
      if (nextAfterType && (nextAfterType.value === '=>' || nextAfterType.value === '{' || nextAfterType.value === ';')) {
        return true;
      }
    }

    return afterParen.value === '=>';
  }

  function stripTypeScriptTypes(source) {
    var tokens = tokenize(source);
    var chars = makeCharArray(source);
    var n = tokens.length;

    // Track object literal / block / switch braces and ternary '?' depth
    var scopeStack = []; // 'block' | 'object' | 'class' | 'switch' | 'paren' | 'bracket'
    var ternaryDepth = 0;

    function currentScope() {
      return scopeStack.length > 0 ? scopeStack[scopeStack.length - 1] : 'block';
    }

    function isInsideParameterList(tokenIdx) {
      // Walk backward to the enclosing '('
      var depth = 0;
      var openIdx = -1;
      for (var k = tokenIdx; k >= 0; k--) {
        var v = tokens[k].value;
        if (v === ')' || v === ']' || v === '}') depth++;
        else if (v === '(' || v === '[' || v === '{') {
          if (depth === 0) {
            if (v === '(') openIdx = k;
            break;
          }
          depth--;
        }
      }
      if (openIdx < 0) return false;
      var closeIdx = findMatchingClose(tokens, openIdx, '(', ')');
      if (closeIdx < 0) return false;
      var afterClose = tokens[closeIdx + 1];
      if (afterClose && (afterClose.value === '=>' || afterClose.value === ':' || afterClose.value === '{')) {
        var beforeOpen = openIdx > 0 ? tokens[openIdx - 1] : null;
        if (beforeOpen && (beforeOpen.value === 'if' || beforeOpen.value === 'for' || beforeOpen.value === 'while' || beforeOpen.value === 'switch' || beforeOpen.value === 'catch')) {
          return false;
        }
        return true;
      }
      return false;
    }

    var i = 0;
    while (i < n) {
      var tok = tokens[i];
      var v = tok.value;

      // 1. 'declare ...' statement
      if (tok.type === 'ident' && v === 'declare' && (i === 0 || tokens[i - 1].value === 'export' || tok.newlineBefore || tokens[i - 1].value === ';' || tokens[i - 1].value === '{' || tokens[i - 1].value === '}')) {
        var declStart = (i > 0 && tokens[i - 1].value === 'export') ? tokens[i - 1].start : tok.start;
        var j = i + 1;
        var bDepth = 0;
        while (j < n) {
          if (tokens[j].value === '{') bDepth++;
          else if (tokens[j].value === '}') {
            bDepth--;
            if (bDepth === 0) { j++; break; }
          } else if (bDepth === 0 && tokens[j].value === ';') {
            j++;
            break;
          }
          j++;
        }
        var declEnd = j < n ? tokens[j - 1].end : source.length;
        blankRange(chars, declStart, declEnd);
        i = j;
        continue;
      }

      // 2. 'interface Name ... { ... }' (and 'export interface ...')
      if (tok.type === 'ident' && v === 'interface' && i + 1 < n && tokens[i + 1].type === 'ident' && !tokens[i + 1].newlineBefore) {
        var ifaceStart = (i > 0 && tokens[i - 1].value === 'export') ? tokens[i - 1].start : tok.start;
        var k = i + 1;
        while (k < n && tokens[k].value !== '{') k++;
        if (k < n) {
          var closeBrace = findMatchingClose(tokens, k, '{', '}');
          var ifaceEnd = closeBrace >= 0 ? tokens[closeBrace].end : source.length;
          blankRange(chars, ifaceStart, ifaceEnd);
          i = closeBrace >= 0 ? closeBrace + 1 : n;
          continue;
        }
      }

      // 3. 'type Name<...> = ...' or 'export type { ... }' or 'import type ...'
      if (tok.type === 'ident' && v === 'type') {
        var prev = i > 0 ? tokens[i - 1] : null;
        // 'import type ...'
        if (prev && prev.value === 'import') {
          var impStart = prev.start;
          var m = i + 1;
          while (m < n && tokens[m].value !== 'from' && tokens[m].value !== ';') m++;
          if (m < n && tokens[m].value === 'from') {
            m += 2; // 'from' and specifier
          }
          if (m < n && tokens[m].value === ';') m++;
          var impEnd = m <= n && m > 0 ? tokens[m - 1].end : source.length;
          blankRange(chars, impStart, impEnd);
          i = m;
          continue;
        }
        // 'export type { ... } [from "..."]'
        if (prev && prev.value === 'export' && i + 1 < n && tokens[i + 1].value === '{') {
          var expStart = prev.start;
          var closeExp = findMatchingClose(tokens, i + 1, '{', '}');
          var afterExp = closeExp >= 0 ? closeExp + 1 : i + 2;
          if (afterExp < n && tokens[afterExp].value === 'from') {
            afterExp += 2;
          }
          if (afterExp < n && tokens[afterExp].value === ';') afterExp++;
          var expEnd = afterExp > 0 && afterExp <= n ? tokens[afterExp - 1].end : source.length;
          blankRange(chars, expStart, expEnd);
          i = afterExp;
          continue;
        }
        // '[export] type Name<...> = TypeExpr;'
        if (i + 1 < n && tokens[i + 1].type === 'ident' && !tokens[i + 1].newlineBefore &&
            (!prev || prev.value === 'export' || prev.value === ';' || prev.value === '{' || prev.value === '}' || tok.newlineBefore)) {
          var tIdx = i + 2;
          if (tIdx < n && tokens[tIdx].value === '<') {
            var closeAng = findMatchingAngle(tokens, tIdx);
            if (closeAng >= 0) tIdx = closeAng + 1;
          }
          if (tIdx < n && tokens[tIdx].value === '=') {
            var aliasStart = (prev && prev.value === 'export') ? prev.start : tok.start;
            var endAlias = scanTypeExpression(tokens, tIdx + 1, {
              allowArrow: true,
              stopAtComma: false,
              stopAtEquals: false,
              stopAtOpenBrace: false
            });
            var nextIdx = endAlias + 1;
            if (nextIdx < n && tokens[nextIdx].value === ';') nextIdx++;
            var aliasEnd = tokens[nextIdx - 1].end;
            blankRange(chars, aliasStart, aliasEnd);
            i = nextIdx;
            continue;
          }
        }
      }

      // 4. Inline 'type' specifier inside import/export braces: import { type Foo, bar } from '...'
      if (tok.type === 'ident' && (v === 'import' || v === 'export')) {
        var bracePos = i + 1;
        if (bracePos < n && tokens[bracePos].value === '{') {
          var closeBr = findMatchingClose(tokens, bracePos, '{', '}');
          if (closeBr > bracePos) {
            var allTypeOnly = true;
            var hasSpecifiers = false;
            var p = bracePos + 1;
            while (p < closeBr) {
              hasSpecifiers = true;
              if (tokens[p].value === 'type' && p + 1 < closeBr && tokens[p + 1].type === 'ident') {
                var specStart = tokens[p].start;
                p += 2;
                if (p < closeBr && tokens[p].value === 'as' && p + 1 < closeBr) {
                  p += 2;
                }
                var specEnd = tokens[p - 1].end;
                if (p < closeBr && tokens[p].value === ',') {
                  specEnd = tokens[p].end;
                  p++;
                }
                blankRange(chars, specStart, specEnd);
              } else {
                allTypeOnly = false;
                while (p < closeBr && tokens[p].value !== ',') p++;
                if (p < closeBr && tokens[p].value === ',') p++;
              }
            }
            if (hasSpecifiers && allTypeOnly) {
              var afterCloseBr = closeBr + 1;
              if (afterCloseBr < n && tokens[afterCloseBr].value === 'from') {
                afterCloseBr += 2;
              }
              if (afterCloseBr < n && tokens[afterCloseBr].value === ';') afterCloseBr++;
              blankRange(chars, tok.start, tokens[afterCloseBr - 1].end);
              i = afterCloseBr;
              continue;
            }
          }
        }
      }

      // 5. 'enum Name { ... }' or 'const enum Name { ... }'
      if (tok.type === 'ident' && v === 'enum' && i + 1 < n && tokens[i + 1].type === 'ident') {
        var isConstEnum = (i > 0 && tokens[i - 1].value === 'const');
        var enumName = tokens[i + 1].value;
        var openEnumBrace = i + 2;
        if (openEnumBrace < n && tokens[openEnumBrace].value === '{') {
          var closeEnumBrace = findMatchingClose(tokens, openEnumBrace, '{', '}');
          if (closeEnumBrace > openEnumBrace) {
            // Parse enum members and replace on the same lines
            var members = [];
            var nextNumeric = 0;
            var cur = openEnumBrace + 1;
            while (cur < closeEnumBrace) {
              var mNameTok = tokens[cur];
              if (mNameTok.type === 'ident' || mNameTok.type === 'string') {
                var mName = mNameTok.value;
                cur++;
                if (cur < closeEnumBrace && tokens[cur].value === '=') {
                  cur++;
                  var valStart = tokens[cur].start;
                  while (cur < closeEnumBrace && tokens[cur].value !== ',') cur++;
                  var valEnd = tokens[cur - 1].end;
                  var valText = source.slice(valStart, valEnd).trim();
                  var parsedNum = Number(valText);
                  if (!isNaN(parsedNum)) {
                    nextNumeric = parsedNum + 1;
                  }
                  members.push(JSON.stringify(mName) + ':' + valText);
                } else {
                  members.push(JSON.stringify(mName) + ':' + String(nextNumeric));
                  nextNumeric++;
                }
              }
              if (cur < closeEnumBrace && tokens[cur].value === ',') cur++;
              else cur++;
            }
            var enumStart = isConstEnum ? tokens[i - 1].start : tok.start;
            var enumEnd = tokens[closeEnumBrace].end;
            var origSlice = source.slice(enumStart, enumEnd);
            var newlineCount = 0;
            for (var nc = 0; nc < origSlice.length; nc++) {
              if (origSlice[nc] === '\n') newlineCount++;
            }
            var replacement = 'const ' + enumName + '={' + members.join(',') + '};' + '\n'.repeat(newlineCount);
            blankRange(chars, enumStart, enumEnd);
            for (var rc = 0; rc < replacement.length; rc++) {
              chars[enumStart + rc] = replacement[rc];
            }
            i = closeEnumBrace + 1;
            continue;
          }
        }
      }

      // 6. Accessibility / modifier keywords: public, private, protected, readonly, override, abstract
      if (tok.type === 'ident' && (v === 'public' || v === 'private' || v === 'protected' || v === 'readonly' || v === 'override' || v === 'abstract')) {
        var nextTok = tokens[i + 1];
        if (nextTok && !nextTok.newlineBefore && (nextTok.type === 'ident' || nextTok.value === '[' || nextTok.value === '{')) {
          blankRange(chars, tok.start, tok.end);
          i++;
          continue;
        }
      }

      // 7. 'implements ...' on class declarations
      if (tok.type === 'ident' && v === 'implements') {
        var implEnd = i + 1;
        while (implEnd < n && tokens[implEnd].value !== '{') {
          implEnd++;
        }
        if (implEnd > i) {
          blankRange(chars, tok.start, tokens[implEnd - 1].end);
          i = implEnd;
          continue;
        }
      }

      // 8. Generic type parameters or call type arguments '<...>'
      if (v === '<') {
        var prevTok = i > 0 ? tokens[i - 1] : null;
        var closeAngle = findMatchingAngle(tokens, i);
        if (closeAngle > i) {
          var afterAngle = tokens[closeAngle + 1];
          // Case A: function foo<T>(...), class Foo<T> { ... }, method<T>(...)
          if (prevTok && (prevTok.type === 'ident' || prevTok.value === 'function') &&
              afterAngle && (afterAngle.value === '(' || afterAngle.value === '{' || afterAngle.value === 'extends' || afterAngle.value === 'implements')) {
            if (looksLikeTypeArguments(tokens, i, closeAngle) || afterAngle.value === '{' || afterAngle.value === 'extends' || afterAngle.value === 'implements') {
              blankRange(chars, tok.start, tokens[closeAngle].end);
              i = closeAngle + 1;
              continue;
            }
          }
          // Case B: generic arrow function <T>(x: T) => ...
          if (afterAngle && afterAngle.value === '(') {
            var matchParen = findMatchingClose(tokens, closeAngle + 1, '(', ')');
            if (matchParen > closeAngle && isFunctionHeaderCloseParen(tokens, matchParen)) {
              blankRange(chars, tok.start, tokens[closeAngle].end);
              i = closeAngle + 1;
              continue;
            }
          }
        }
      }

      // 9. Optional parameter/property '?' or definite assignment '!': e.g. x?: number, x? = 1, x?: number = 1, prop!: number
      if ((v === '?' || v === '!') && i > 0 && (tokens[i - 1].type === 'ident' || tokens[i - 1].value === '}' || tokens[i - 1].value === ']')) {
        var nextAfterQ = tokens[i + 1];
        if (nextAfterQ && nextAfterQ.value === ':') {
          var optTypeEnd = scanTypeExpression(tokens, i + 2, {
            allowArrow: true,
            stopAtComma: true,
            stopAtEquals: true,
            stopAtOpenBrace: true
          });
          blankRange(chars, tok.start, tokens[optTypeEnd].end);
          i = optTypeEnd + 1;
          continue;
        }
        if (v === '?' && nextAfterQ && (nextAfterQ.value === ',' || nextAfterQ.value === ')' || nextAfterQ.value === '=') && isInsideParameterList(i)) {
          blankRange(chars, tok.start, tok.end);
          i++;
          continue;
        }
      }

      // 10. Non-null assertion 'expr!'
      if (v === '!' && i > 0) {
        var prevForBang = tokens[i - 1];
        var nextForBang = tokens[i + 1];
        var canPrecededByValue = (prevForBang.type === 'ident' || prevForBang.type === 'number' || prevForBang.type === 'string' ||
                                  prevForBang.value === ')' || prevForBang.value === ']');
        var followedByPostfixOrEnd = !nextForBang || nextForBang.newlineBefore ||
          nextForBang.value === '.' || nextForBang.value === '?.' || nextForBang.value === '[' ||
          nextForBang.value === '(' || nextForBang.value === ';' || nextForBang.value === ',' ||
          nextForBang.value === ')' || nextForBang.value === ']' || nextForBang.value === '}' ||
          nextForBang.value === ':';
        if (canPrecededByValue && followedByPostfixOrEnd && prevForBang.value !== 'return' && prevForBang.value !== 'throw' && prevForBang.value !== 'case') {
          blankRange(chars, tok.start, tok.end);
          i++;
          continue;
        }
      }

      // 11. 'as Type' or 'satisfies Type'
      if (tok.type === 'ident' && (v === 'as' || v === 'satisfies') && !tok.newlineBefore && i > 0) {
        var prevBeforeAs = tokens[i - 1];
        // Make sure it's not 'import * as x' or 'import { a as b }' or 'export { a as b }'
        var isImportExportAs = (prevBeforeAs.value === '*') || (currentScope() === 'import_export_braces');
        if (!isImportExportAs) {
          var endAsType = scanTypeExpression(tokens, i + 1, {
            allowArrow: false,
            stopAtComma: true,
            stopAtEquals: true,
            stopAtOpenBrace: true
          });
          blankRange(chars, tok.start, tokens[endAsType].end);
          i = endAsType + 1;
          continue;
        }
      }

      // Track scopes for ':' disambiguation
      if (v === '{') {
        var prevB = i > 0 ? tokens[i - 1] : null;
        if (prevB && (prevB.value === 'import' || prevB.value === 'export')) {
          scopeStack.push('import_export_braces');
        } else if (prevB && prevB.value === ')' && i >= 2) {
          scopeStack.push('block');
        } else if (prevB && (prevB.value === '=' || prevB.value === ':' || prevB.value === '(' || prevB.value === ',' || prevB.value === '[' || prevB.value === 'return' || prevB.value === '=>')) {
          scopeStack.push('object');
        } else {
          scopeStack.push('block');
        }
        i++;
        continue;
      }
      if (v === '}') {
        scopeStack.pop();
        i++;
        continue;
      }
      if (v === '(') {
        scopeStack.push('paren');
        i++;
        continue;
      }
      if (v === ')') {
        scopeStack.pop();
        // Check if ': ReturnType' follows a function/method/arrow parameter list ')'
        if (i + 1 < n && tokens[i + 1].value === ':' && isFunctionHeaderCloseParen(tokens, i)) {
          var colonTok = tokens[i + 1];
          var retEnd = scanTypeExpression(tokens, i + 2, {
            allowArrow: false,
            stopAtComma: true,
            stopAtEquals: true,
            stopAtOpenBrace: true
          });
          blankRange(chars, colonTok.start, tokens[retEnd].end);
          i = retEnd + 1;
          continue;
        }
        i++;
        continue;
      }
      if (v === '[') {
        scopeStack.push('bracket');
        i++;
        continue;
      }
      if (v === ']') {
        scopeStack.pop();
        i++;
        continue;
      }

      if (v === '?') {
        ternaryDepth++;
        i++;
        continue;
      }

      // 12. Type annotations ': Type'
      if (v === ':') {
        if (ternaryDepth > 0) {
          ternaryDepth--;
          i++;
          continue;
        }
        var sc = currentScope();
        var prevC = i > 0 ? tokens[i - 1] : null;
        var prevPrevC = i > 1 ? tokens[i - 2] : null;
        if (prevC && prevC.value === 'default') {
          i++;
          continue;
        }
        // Check if this is 'case expr:'
        var isCaseColon = false;
        for (var back = i - 1; back >= 0; back--) {
          var bv = tokens[back].value;
          if (bv === 'case') { isCaseColon = true; break; }
          if (bv === ';' || bv === '{' || bv === '}' || bv === ':') break;
        }
        if (isCaseColon) {
          i++;
          continue;
        }
        // Inside an object literal, 'key: value' is a property, NOT a type annotation.
        if (sc === 'object') {
          i++;
          continue;
        }
        // Inside block or paren: check if preceded by variable declaration, parameter binding, or destructuring pattern
        var isTypeAnnot = false;
        if (sc === 'paren' && isInsideParameterList(i)) {
          isTypeAnnot = true;
        } else if (prevC && (prevC.type === 'ident' || prevC.value === '}' || prevC.value === ']')) {
          if (prevPrevC && (prevPrevC.value === 'const' || prevPrevC.value === 'let' || prevPrevC.value === 'var' || prevPrevC.value === ',' || prevPrevC.value === '(')) {
            isTypeAnnot = true;
          } else if (prevC.value === '}' || prevC.value === ']') {
            isTypeAnnot = true;
          } else if (sc === 'block' && prevPrevC && (prevPrevC.value === ';' || prevPrevC.value === '{' || prevPrevC.value === '}' || prevPrevC.value === 'public' || prevPrevC.value === 'private' || prevPrevC.value === 'protected' || prevPrevC.value === 'readonly')) {
            // Class property type annotation (as long as not a labeled loop)
            var nextAfterType = scanTypeExpression(tokens, i + 1, {
              allowArrow: true,
              stopAtComma: true,
              stopAtEquals: true,
              stopAtOpenBrace: true
            });
            var tokAfter = tokens[nextAfterType + 1];
            if (!tokAfter || tokAfter.value === ';' || tokAfter.value === '=' || tokAfter.newlineBefore) {
              if (tokens[i + 1] && tokens[i + 1].value !== 'for' && tokens[i + 1].value !== 'while' && tokens[i + 1].value !== 'do' && tokens[i + 1].value !== 'switch') {
                isTypeAnnot = true;
              }
            }
          }
        }

        if (isTypeAnnot) {
          var typeEnd = scanTypeExpression(tokens, i + 1, {
            allowArrow: true,
            stopAtComma: true,
            stopAtEquals: true,
            stopAtOpenBrace: true
          });
          blankRange(chars, tok.start, tokens[typeEnd].end);
          i = typeEnd + 1;
          continue;
        }
      }

      i++;
    }

    return chars.join('');
  }

  // Transforms ES module import/export syntax and injects loop tick checks while tracking per-line column adjustments.
  function transformESModulesAndLoops(jsSource) {
    var tokens = tokenize(jsSource);
    var n = tokens.length;
    var edits = []; // { start, end, text, line, origCol, delta }
    var exportedBindings = [];

    function addEdit(start, end, replacement, line, origCol) {
      edits.push({
        start: start,
        end: end,
        text: replacement,
        line: line,
        origCol: origCol,
        delta: replacement.length - (end - start)
      });
    }

    function preserveNewlines(originalSlice, replacementSingleLine) {
      var nlCount = 0;
      for (var c = 0; c < originalSlice.length; c++) {
        if (originalSlice[c] === '\n') nlCount++;
      }
      return replacementSingleLine + '\n'.repeat(nlCount);
    }

    var i = 0;
    while (i < n) {
      var tok = tokens[i];
      var v = tok.value;

      // 1. Loop tick injection for 'for (...)', 'while (...)', 'do'
      if (tok.type === 'ident' && (v === 'for' || v === 'while')) {
        var openP = i + 1;
        if (openP < n && tokens[openP].value === 'await') openP++;
        if (openP < n && tokens[openP].value === '(') {
          var closeP = findMatchingClose(tokens, openP, '(', ')');
          if (closeP > openP && closeP + 1 < n) {
            var bodyFirst = tokens[closeP + 1];
            if (bodyFirst.value === '{') {
              addEdit(bodyFirst.end, bodyFirst.end, '__made_tick();', bodyFirst.line, bodyFirst.col + 1);
            } else if (bodyFirst.value === ';') {
              addEdit(bodyFirst.start, bodyFirst.end, '{__made_tick();}', bodyFirst.line, bodyFirst.col);
            } else {
              addEdit(bodyFirst.start, bodyFirst.start, '(__made_tick(),0);', bodyFirst.line, bodyFirst.col);
            }
          }
        }
      } else if (tok.type === 'ident' && v === 'do') {
        var doBody = tokens[i + 1];
        if (doBody && doBody.value === '{') {
          addEdit(doBody.end, doBody.end, '__made_tick();', doBody.line, doBody.col + 1);
        }
      }

      // 2. ES Module 'import'
      if (tok.type === 'ident' && v === 'import') {
        var nextAfterImport = tokens[i + 1];
        // Ignore dynamic import(...)
        if (nextAfterImport && nextAfterImport.value !== '(' && nextAfterImport.value !== '.') {
          var impStart = tok.start;
          var impLine = tok.line;
          var impCol = tok.col;

          // Case A: import 'specifier';
          if (nextAfterImport.type === 'string') {
            var specLiteral = nextAfterImport.value;
            var endIdx = i + 2;
            if (endIdx < n && tokens[endIdx].value === ';') endIdx++;
            var endOff = tokens[endIdx - 1].end;
            var repA = '__made_require(' + specLiteral + ',' + nextAfterImport.line + ',' + nextAfterImport.col + ');';
            addEdit(impStart, endOff, preserveNewlines(jsSource.slice(impStart, endOff), repA), impLine, impCol);
            i = endIdx;
            continue;
          }

          // Scan to 'from'
          var fromIdx = i + 1;
          while (fromIdx < n && tokens[fromIdx].value !== 'from') {
            if (tokens[fromIdx].value === ';') break;
            fromIdx++;
          }
          if (fromIdx < n && tokens[fromIdx].value === 'from' && fromIdx + 1 < n && tokens[fromIdx + 1].type === 'string') {
            var modTok = tokens[fromIdx + 1];
            var modLit = modTok.value;
            var stmtEndIdx = fromIdx + 2;
            if (stmtEndIdx < n && tokens[stmtEndIdx].value === ';') stmtEndIdx++;
            var stmtEndOff = tokens[stmtEndIdx - 1].end;

            // Parse bindings between i+1 and fromIdx
            var defaultName = null;
            var namespaceName = null;
            var namedParts = [];
            var bIdx = i + 1;

            if (tokens[bIdx].type === 'ident') {
              defaultName = tokens[bIdx].value;
              bIdx++;
              if (bIdx < fromIdx && tokens[bIdx].value === ',') bIdx++;
            }
            if (bIdx < fromIdx && tokens[bIdx].value === '*') {
              if (bIdx + 2 < fromIdx && tokens[bIdx + 1].value === 'as' && tokens[bIdx + 2].type === 'ident') {
                namespaceName = tokens[bIdx + 2].value;
              }
            } else if (bIdx < fromIdx && tokens[bIdx].value === '{') {
              var closeImportBrace = findMatchingClose(tokens, bIdx, '{', '}');
              var k = bIdx + 1;
              while (k < closeImportBrace) {
                if (tokens[k].type === 'ident') {
                  var imported = tokens[k].value;
                  var local = imported;
                  k++;
                  if (k + 1 < closeImportBrace && tokens[k].value === 'as' && tokens[k + 1].type === 'ident') {
                    local = tokens[k + 1].value;
                    k += 2;
                  }
                  if (imported === local) {
                    namedParts.push(imported);
                  } else {
                    namedParts.push(imported + ': ' + local);
                  }
                }
                if (k < closeImportBrace && tokens[k].value === ',') k++;
                else k++;
              }
            }

            var reqCall = '__made_require(' + modLit + ',' + modTok.line + ',' + modTok.col + ')';
            var statements = [];
            if (namespaceName) {
              statements.push('const ' + namespaceName + ' = ' + reqCall + ';');
            } else if (defaultName && namedParts.length > 0) {
              var tmpVar = '__made_imp_' + impLine + '_' + impCol;
              statements.push('const ' + tmpVar + ' = ' + reqCall + ', ' + defaultName + ' = ' + tmpVar + '.default, {' + namedParts.join(', ') + '} = ' + tmpVar + ';');
            } else if (defaultName) {
              statements.push('const ' + defaultName + ' = ' + reqCall + '.default;');
            } else if (namedParts.length > 0) {
              statements.push('const {' + namedParts.join(', ') + '} = ' + reqCall + ';');
            } else {
              statements.push(reqCall + ';');
            }

            var repImport = preserveNewlines(jsSource.slice(impStart, stmtEndOff), statements.join(' '));
            addEdit(impStart, stmtEndOff, repImport, impLine, impCol);
            i = stmtEndIdx;
            continue;
          }
        }
      }

      // 3. ES Module 'export'
      if (tok.type === 'ident' && v === 'export') {
        var nextExp = tokens[i + 1];
        if (!nextExp) { i++; continue; }

        // Case A: export default ...
        if (nextExp.value === 'default') {
          var spanLen = nextExp.end - tok.start;
          // "__made_d.def =" is 14 chars; pad with spaces to exact length of "export default"
          var padCount = Math.max(0, spanLen - 14);
          var repDef = '__made_d.def =' + ' '.repeat(padCount);
          addEdit(tok.start, nextExp.end, repDef, tok.line, tok.col);
          i += 2;
          continue;
        }

        // Case B: export const / let / var / function / class
        if (nextExp.value === 'const' || nextExp.value === 'let' || nextExp.value === 'var') {
          // Blank 'export' with 6 spaces so column numbers on the declaration line are 100% unchanged!
          addEdit(tok.start, tok.end, '      ', tok.line, tok.col);
          // Collect declared binding names at top level of this declaration
          var dIdx = i + 2;
          var pDepth = 0, bDepth = 0, kDepth = 0;
          var expectingBinding = true;
          while (dIdx < n) {
            var dt = tokens[dIdx];
            var dv = dt.value;
            if (pDepth === 0 && bDepth === 0 && kDepth === 0) {
              if (expectingBinding && dt.type === 'ident') {
                exportedBindings.push({ local: dv, exported: dv });
                expectingBinding = false;
              } else if (dv === ',') {
                expectingBinding = true;
              } else if (dv === ';') {
                break;
              } else if (dt.newlineBefore && (dv === 'export' || dv === 'import' || dv === 'const' || dv === 'let' || dv === 'var' || dv === 'function' || dv === 'class' || dv === 'return')) {
                break;
              }
            }
            if (dv === '(') pDepth++;
            else if (dv === ')') pDepth--;
            else if (dv === '{') bDepth++;
            else if (dv === '}') bDepth--;
            else if (dv === '[') kDepth++;
            else if (dv === ']') kDepth--;
            dIdx++;
          }
          i += 2;
          continue;
        }

        if (nextExp.value === 'function' || nextExp.value === 'class' || (nextExp.value === 'async' && i + 2 < n && tokens[i + 2].value === 'function')) {
          addEdit(tok.start, tok.end, '      ', tok.line, tok.col);
          var fnNameIdx = nextExp.value === 'async' ? i + 3 : i + 2;
          if (fnNameIdx < n && tokens[fnNameIdx].value === '*') fnNameIdx++;
          if (fnNameIdx < n && tokens[fnNameIdx].type === 'ident') {
            var fnName = tokens[fnNameIdx].value;
            exportedBindings.push({ local: fnName, exported: fnName });
          }
          i += 2;
          continue;
        }

        // Case C: export { a, b as c } [from './mod']
        if (nextExp.value === '{') {
          var closeExpBrace = findMatchingClose(tokens, i + 1, '{', '}');
          if (closeExpBrace > i + 1) {
            var specs = [];
            var s = i + 2;
            while (s < closeExpBrace) {
              if (tokens[s].type === 'ident') {
                var locName = tokens[s].value;
                var expName = locName;
                s++;
                if (s + 1 < closeExpBrace && tokens[s].value === 'as' && tokens[s + 1].type === 'ident') {
                  expName = tokens[s + 1].value;
                  s += 2;
                }
                specs.push({ local: locName, exported: expName });
              }
              if (s < closeExpBrace && tokens[s].value === ',') s++;
              else s++;
            }
            var afterBr = closeExpBrace + 1;
            var reexportFrom = null;
            if (afterBr + 1 < n && tokens[afterBr].value === 'from' && tokens[afterBr + 1].type === 'string') {
              reexportFrom = tokens[afterBr + 1];
              afterBr += 2;
            }
            if (afterBr < n && tokens[afterBr].value === ';') afterBr++;
            var expEndOff = tokens[afterBr - 1].end;
            var repSpec = '';
            if (reexportFrom) {
              var reVar = '__made_re_' + tok.line;
              var assigns = specs.map(function (sp) {
                return '__made_exports[' + JSON.stringify(sp.exported) + '] = ' + reVar + '[' + JSON.stringify(sp.local) + '];';
              }).join(' ');
              repSpec = 'const ' + reVar + ' = __made_require(' + reexportFrom.value + ',' + reexportFrom.line + ',' + reexportFrom.col + '); ' + assigns;
            } else {
              repSpec = specs.map(function (sp) {
                return '__made_exports[' + JSON.stringify(sp.exported) + '] = ' + sp.local + ';';
              }).join(' ');
            }
            addEdit(tok.start, expEndOff, preserveNewlines(jsSource.slice(tok.start, expEndOff), repSpec), tok.line, tok.col);
            i = afterBr;
            continue;
          }
        }

        // Case D: export * from './mod'
        if (nextExp.value === '*' && i + 3 < n && tokens[i + 2].value === 'from' && tokens[i + 3].type === 'string') {
          var starMod = tokens[i + 3];
          var starEnd = i + 4;
          if (starEnd < n && tokens[starEnd].value === ';') starEnd++;
          var starEndOff = tokens[starEnd - 1].end;
          var repStar = 'Object.assign(__made_exports, __made_require(' + starMod.value + ',' + starMod.line + ',' + starMod.col + '));';
          addEdit(tok.start, starEndOff, preserveNewlines(jsSource.slice(tok.start, starEndOff), repStar), tok.line, tok.col);
          i = starEnd;
          continue;
        }
      }

      i++;
    }

    // Apply edits in reverse order of start offset
    edits.sort(function (a, b) { return b.start - a.start; });
    var out = jsSource;
    for (var e = 0; e < edits.length; e++) {
      var ed = edits[e];
      out = out.slice(0, ed.start) + ed.text + out.slice(ed.end);
    }

    // Build footer to assign exported bindings onto __made_exports
    var footerParts = [];
    for (var b = 0; b < exportedBindings.length; b++) {
      var bind = exportedBindings[b];
      footerParts.push('__made_exports[' + JSON.stringify(bind.exported) + '] = ' + bind.local + ';');
    }
    footerParts.push('if ("def" in __made_d) { __made_exports.default = __made_d.def; }');

    // Sort edits ascending by line & col for source mapping
    edits.sort(function (a, b) {
      if (a.line !== b.line) return a.line - b.line;
      return a.origCol - b.origCol;
    });

    return {
      code: out + '\n' + footerParts.join(' '),
      edits: edits
    };
  }

  global.__made_transformSource = function (source, isTypeScript) {
    var stripped = isTypeScript ? stripTypeScriptTypes(source) : source;
    return transformESModulesAndLoops(stripped);
  };
})(globalThis);
