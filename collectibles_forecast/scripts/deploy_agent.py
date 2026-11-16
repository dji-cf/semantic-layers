"""Create or update a Cortex Agent from a local spec JSON via the `snow` CLI.

Usage:
    python deploy_agent.py <spec_json> <DB.SCHEMA.AGENT> [--replace] [--display-name NAME] [--comment TEXT]

Without --replace an existing agent is left untouched (CREATE AGENT fails if it exists);
with --replace the LIVE spec is updated in place via ALTER AGENT ... MODIFY LIVE VERSION.
"""
import argparse
import json
import pathlib
import subprocess
import sys
import tempfile


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("spec_json")
    ap.add_argument("agent_fqn")
    ap.add_argument("--replace", action="store_true")
    ap.add_argument("--display-name", default=None)
    ap.add_argument("--comment", default=None)
    ap.add_argument("--connection", default="FANATICS_COLLECTIBLES_PROD")
    ap.add_argument("--role", default="POWER_ANALYST_ORACLE_PROD")
    args = ap.parse_args()

    spec = json.dumps(json.loads(pathlib.Path(args.spec_json).read_text(encoding="utf-8")), indent=2)
    if "$$" in spec:
        print("spec contains '$$'; cannot dollar-quote it.", file=sys.stderr)
        return 2

    def q(s: str) -> str:
        return "'" + s.replace("'", "''") + "'"

    if args.replace:
        body = f"ALTER AGENT {args.agent_fqn} MODIFY LIVE VERSION SET SPECIFICATION = $$\n{spec}\n$$;\n"
    else:
        body = f"CREATE AGENT {args.agent_fqn}\n"
        if args.comment:
            body += f"COMMENT = {q(args.comment)}\n"
        if args.display_name:
            body += f"PROFILE = {q(json.dumps({'display_name': args.display_name}))}\n"
        body += f"FROM SPECIFICATION $$\n{spec}\n$$;\n"
    sql = f"USE ROLE {args.role};\n{body}"

    with tempfile.NamedTemporaryFile("w", suffix=".sql", delete=False, encoding="utf-8") as f:
        f.write(sql)
        sql_path = f.name
    cmd = ["snow", "sql", "-c", args.connection, "--enable-templating", "NONE", "-f", sql_path]
    res = subprocess.run(cmd, capture_output=True, text=True, encoding="utf-8", errors="replace")
    out = res.stdout
    print(out[out.rfind("$$"):] if "$$" in out else out)
    if res.returncode != 0:
        print(res.stderr, file=sys.stderr)
    pathlib.Path(sql_path).unlink(missing_ok=True)
    return res.returncode


if __name__ == "__main__":
    sys.exit(main())
