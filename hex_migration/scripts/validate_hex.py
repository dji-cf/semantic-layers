"""Validate Hex semantic model YAML files before loading them into Hex.

Usage:
    python scripts/validate_hex.py semantic/*.yml [--no-snowflake] [--connection NAME]

Checks, per file/document:
  1. Structure against Hex's published JSON Schema (scripts/hex_resource_schema.json, from hex-inc/hex-sl-utils).
  2. Semantics the schema can't see: id uniqueness across dims/measures/relations, >= 1 `unique: true`
     dimension, `of` / `filters` / ${ref} references resolve, filters point at boolean dimensions.
  3. Snowflake compile: every dimension expr_sql and every (expanded) measure is compiled against the model's
     base table with `SELECT ... LIMIT 0` through the `snow` CLI. Failing expressions are re-run one by one
     so the error names the culprit.
"""
import argparse
import json
import pathlib
import re
import subprocess
import sys

import jsonschema
import yaml

HERE = pathlib.Path(__file__).parent
REF = re.compile(r"\$\{([a-z_][a-z0-9_.]*)\}")
AGG = {"sum": "SUM", "avg": "AVG", "min": "MIN", "max": "MAX", "median": "MEDIAN", "count_distinct": "COUNT(DISTINCT",
       "stddev": "STDDEV", "stddev_pop": "STDDEV_POP", "variance": "VARIANCE", "variance_pop": "VAR_POP"}


def check_model(m, errs):
    dims = {d["id"]: d for d in m.get("dimensions", [])}
    meas = {x["id"]: x for x in m.get("measures", [])}
    rels = {r["id"] for r in m.get("relations", [])}
    ids = list(dims) + list(meas) + list(rels)
    for i in {i for i in ids if ids.count(i) > 1}:
        errs.append(f"duplicate id '{i}'")
    if not any(d.get("unique") for d in dims.values()):
        errs.append("no dimension has unique: true")

    def refs_ok(text, where, allow_measures):
        for r in REF.findall(text or ""):
            head = r.split(".")[0]
            if head in dims or head in rels or (allow_measures and head in meas):
                continue
            errs.append(f"{where}: unresolved ${{{r}}}")

    for d in dims.values():
        refs_ok(d.get("expr_sql"), f"dimension {d['id']}", False)
    for x in meas.values():
        w = f"measure {x['id']}"
        if "of" in x and isinstance(x["of"], str) and x["of"] not in dims:
            errs.append(f"{w}: of '{x['of']}' is not a dimension")
        if isinstance(x.get("of"), dict):
            refs_ok(x["of"].get("expr_sql"), w, False)
        for f in x.get("filters", []):
            if isinstance(f, str):
                if f not in dims:
                    errs.append(f"{w}: filter '{f}' is not a dimension")
                elif dims[f].get("type") != "boolean":
                    errs.append(f"{w}: filter '{f}' is not boolean")
            else:
                refs_ok(f.get("expr_sql"), w, False)
        refs_ok(x.get("func_sql"), w, True)
        if "func_calc" in x:
            for tok in set(re.findall(r"\b[a-z_][a-z0-9_]*\b", x["func_calc"])):
                if tok not in meas and tok not in dims and tok.upper() not in {"NULLIF", "IF", "ABS", "AND", "OR", "NOT", "NULL"}:
                    errs.append(f"{w}: func_calc token '{tok}' is not a measure/dimension (check)")
    return dims, meas


def dim_sql(d):
    return d.get("expr_sql") or d["id"].upper()


def expand(text, dims, meas, depth=0):
    if depth > 10:
        raise ValueError("measure reference cycle")

    def sub(mo):
        r = mo.group(1)
        if r in dims:
            return f"({expand(dim_sql(dims[r]), dims, meas, depth + 1)})"
        if r in meas:
            return f"({measure_sql(meas[r], dims, meas, depth + 1)})"
        return mo.group(0)
    return REF.sub(sub, text)


def measure_sql(x, dims, meas, depth=0):
    if "func_sql" in x:
        return expand(x["func_sql"], dims, meas, depth)
    if "func_calc" in x:
        return None  # Hex calc language; not compiled here
    f = x["func"]
    if f == "count" and "of" not in x:
        inner = "1"
    else:
        of = x["of"]
        inner = expand(of["expr_sql"] if isinstance(of, dict) else f"${{{of}}}", dims, meas, depth)
    conds = []
    for flt in x.get("filters", []):
        conds.append(expand(flt["expr_sql"] if isinstance(flt, dict) else f"${{{flt}}}", dims, meas, depth))
    if conds:
        inner = f"IFF({' AND '.join('(' + c + ')' for c in conds)}, {inner}, NULL)"
    if f == "count":
        return f"COUNT({inner})"
    if f == "sum_boolean":
        return f"COUNT_IF({inner})"
    agg = AGG[f]
    return f"{agg}({inner}))" if agg.endswith("(DISTINCT") else f"{agg}({inner})"


def run_sf(sql, conn):
    res = subprocess.run(["snow", "sql", "-c", conn, "--enable-templating", "NONE", "--format", "json", "-q", sql],
                         capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=180)
    return res.returncode == 0, (res.stdout + res.stderr)[-600:]


def compile_model(m, dims, meas, conn, errs):
    src = m.get("base_sql_table") or f"({m['base_sql_query']})"
    exprs = [(f"dimension {k}", expand(dim_sql(d), dims, meas)) for k, d in dims.items()]
    exprs += [(f"measure {k}", s) for k, x in meas.items() if (s := measure_sql(x, dims, meas))]
    aggs = [e for e in exprs if e[0].startswith("measure")]
    plain = [e for e in exprs if e[0].startswith("dimension")]
    batch = []
    if plain:
        batch.append(("dimensions", "SELECT " + ",\n ".join(f"{s} AS c{i}" for i, (_, s) in enumerate(plain)) + f" FROM {src} LIMIT 0", plain))
    if aggs:
        batch.append(("measures", "SELECT " + ",\n ".join(f"{s} AS c{i}" for i, (_, s) in enumerate(aggs)) + f" FROM {src} LIMIT 0", aggs))
    for _, sql, items in batch:
        ok, out = run_sf(sql, conn)
        if ok:
            continue
        for name, s in items:  # pinpoint
            ok1, out1 = run_sf(f"SELECT {s} FROM {src} LIMIT 0", conn)
            if not ok1:
                msg = re.search(r"(SQL compilation error.*|error.*)", out1, re.S | re.I)
                errs.append(f"{name}: Snowflake: {(msg.group(1) if msg else out1).strip()[:300]}")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("files", nargs="+")
    ap.add_argument("--no-snowflake", action="store_true")
    ap.add_argument("--connection", default="FANATICS_COLLECTIBLES_PROD")
    a = ap.parse_args()
    validator = jsonschema.Draft202012Validator(json.loads((HERE / "hex_resource_schema.json").read_text()))
    bad = 0
    for fn in a.files:
        for doc in yaml.safe_load_all(pathlib.Path(fn).read_text(encoding="utf-8")):
            if not doc:
                continue
            dims, meas = {}, {}
            errs = [f"schema: {e.json_path}: {e.message[-200:]}" for e in validator.iter_errors(doc)]
            if errs:
                be = jsonschema.exceptions.best_match(validator.iter_errors(doc))
                deep = sorted(be.context or [be], key=lambda e: -len(e.absolute_path))[:3]
                errs = [f"schema: {e.json_path}: {e.message[-200:]}" for e in deep]
            if doc.get("type", "model") == "model" and not errs:
                dims, meas = check_model(doc, errs)
                if not a.no_snowflake and not errs:
                    compile_model(doc, dims, meas, a.connection, errs)
                summary = f"{len(dims)} dims, {len(meas)} measures"
            else:
                summary = doc.get("type")
            print(f"{'OK  ' if not errs else 'FAIL'} {fn} :: {doc.get('id')} ({summary})")
            for e in errs:
                print("     -", e)
            bad += bool(errs)
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
