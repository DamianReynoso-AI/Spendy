#!/usr/bin/env python3
"""Revisión aproximada de RNF-29 y RNF-30 (no reemplaza a un analizador).

- RNF-29: ninguna función o método de lib/ con más de 50 líneas ni con
  complejidad ciclomática mayor a 10. La complejidad se estima como
  1 + if + for + while + case + catch + && + || + ?? + ternarios (" ? ").
  Solo mide funciones de nivel superior y miembros de clase; las funciones
  anónimas cuentan dentro de la función que las contiene.
- RNF-30: ningún archivo de lib/ui/ importa lib/data/.

Uso: python3 tool/check_quality.py   (sale con código 1 si algo falla)
"""
import pathlib
import re
import sys

MAX_LINES = 50
MAX_COMPLEXITY = 10
ROOT = pathlib.Path(__file__).resolve().parent.parent
SIGNATURE_END = re.compile(r"\)\s*(async\*?|sync\*)?\s*$")
DECISIONS = re.compile(
    r"\bif\b|\bfor\b|\bwhile\b|\bcase\b|\bcatch\b|&&|\|\||\?\?|\s\?\s"
)


def strip_code(text):
    """Quita comentarios y el contenido de cadenas, conserva saltos."""
    out, i, n = [], 0, len(text)
    while i < n:
        two = text[i:i + 2]
        if two == "//":
            while i < n and text[i] != "\n":
                i += 1
            continue
        if two == "/*":
            end = text.find("*/", i + 2)
            end = n if end == -1 else end + 2
            out.append("\n" * text.count("\n", i, end))
            i = end
            continue
        if text[i] in "'\"":
            i = skip_string(text, i, out)
            continue
        out.append(text[i])
        i += 1
    return "".join(out)


def skip_string(text, i, out):
    quote = text[i:i + 3] if text[i:i + 3] in ("'''", '"""') else text[i]
    raw = i > 0 and text[i - 1] == "r"
    j = i + len(quote)
    while j < len(text) and not text.startswith(quote, j):
        if text[j] == "\\" and not raw:
            j += 1
        j += 1
    end = min(j + len(quote), len(text))
    out.append("''" + "\n" * text.count("\n", i, end))
    return end


def functions(code):
    """Devuelve (línea, nombre, líneas, cuerpo) de cada función miembro."""
    results, depth, class_depths, start, parens = [], 0, [], 0, 0
    i = 0
    while i < len(code):
        ch = code[i]
        if ch in "([":
            parens += 1
        elif ch in ")]":
            parens -= 1
        elif parens > 0:
            pass  # llaves de parámetros con nombre o valores por defecto
        elif ch == "{":
            head = code[start:i]
            member = depth == 0 or (class_depths and depth == class_depths[-1])
            if member and SIGNATURE_END.search(head):
                end = match_brace(code, i)
                results.append(make_result(code, start, i, end))
                i, start = end + 1, end + 1
                continue
            if re.search(r"\b(class|mixin|extension|enum)\b", head):
                class_depths.append(depth + 1)
            depth += 1
            start = i + 1
        elif ch == "}":
            if class_depths and class_depths[-1] == depth:
                class_depths.pop()
            depth -= 1
            start = i + 1
        elif ch == ";":
            arrow = code.rfind("=>", start, i)
            member = depth == 0 or (class_depths and depth == class_depths[-1])
            if member and arrow != -1:
                results.append(make_result(code, start, arrow, i))
            start = i + 1
        i += 1
    return results


def match_brace(code, i):
    depth = 0
    for j in range(i, len(code)):
        if code[j] == "{":
            depth += 1
        elif code[j] == "}":
            depth -= 1
            if depth == 0:
                return j
    return len(code) - 1


def make_result(code, start, body_start, end):
    head = code[start:body_start].strip()
    name_match = re.search(r"([A-Za-z_][\w.]*)\s*(<[^()]*>)?\s*\(", head)
    name = name_match.group(1) if name_match else head[:40]
    first_line = code.count("\n", 0, start + len(code[start:body_start]) -
                            len(code[start:body_start].lstrip())) + 1
    last_line = code.count("\n", 0, end) + 1
    return first_line, name, last_line - first_line + 1, code[body_start:end]


def main():
    problems = []
    for path in sorted((ROOT / "lib").rglob("*.dart")):
        rel = path.relative_to(ROOT)
        text = path.read_text(encoding="utf-8")
        if str(rel).startswith("lib/ui/") and re.search(
                r"import\s+['\"][^'\"]*data/", text):
            problems.append(f"{rel}: RNF-30, importa lib/data/")
        for line, name, length, body in functions(strip_code(text)):
            complexity = 1 + len(DECISIONS.findall(body))
            if length > MAX_LINES:
                problems.append(f"{rel}:{line} {name}: {length} líneas")
            if complexity > MAX_COMPLEXITY:
                problems.append(f"{rel}:{line} {name}: complejidad {complexity}")
    for problem in problems:
        print(problem)
    print(f"{len(problems)} problemas (máx. {MAX_LINES} líneas, "
          f"complejidad {MAX_COMPLEXITY}).")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
