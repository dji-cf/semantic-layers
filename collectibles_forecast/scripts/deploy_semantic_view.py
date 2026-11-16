"""Deploy a Cortex Analyst semantic-model YAML as a Snowflake SEMANTIC VIEW.

Usage:
    python deploy_semantic_view.py <yaml_path> [--verify-only] [--schema DB.SCHEMA] [--connection NAME]

Wraps SYSTEM$CREATE_SEMANTIC_VIEW_FROM_YAML and runs it through the `snow` CLI so the
YAML file in the repo stays the single source of truth.
"""
import argparse
import pathlib
import subprocess
import sys
import tempfile


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("yaml_path")
    ap.add_argument("--schema", default="ORACLE_DATA_PROD.SANDBOX")
    ap.add_argument("--connection", default="FANATICS_COLLECTIBLES_PROD")
    ap.add_argument("--role", default="POWER_ANALYST_ORACLE_PROD")
    ap.add_argument("--verify-only", action="store_true")
    args = ap.parse_args()

    body = pathlib.Path(args.yaml_path).read_text(encoding="utf-8")
    if "$$" in body:
        print("YAML contains '$$'; cannot dollar-quote it.", file=sys.stderr)
        return 2

    verify = ", TRUE" if args.verify_only else ""
    sql = (
        f"USE ROLE {args.role};\n"
        f"CALL SYSTEM$CREATE_SEMANTIC_VIEW_FROM_YAML('{args.schema}', $${body}$${verify});\n"
    )
    with tempfile.NamedTemporaryFile("w", suffix=".sql", delete=False, encoding="utf-8") as f:
        f.write(sql)
        sql_path = f.name

    cmd = ["snow", "sql", "-c", args.connection, "--enable-templating", "NONE", "-f", sql_path]
    res = subprocess.run(cmd, capture_output=True, text=True, encoding="utf-8", errors="replace")
    # snow echoes each statement; print only the result tables
    out = res.stdout
    print(out[out.rfind("$$"):] if "$$" in out else out)
    if res.returncode != 0:
        print(res.stderr, file=sys.stderr)
    pathlib.Path(sql_path).unlink(missing_ok=True)
    return res.returncode


if __name__ == "__main__":
    sys.exit(main())
