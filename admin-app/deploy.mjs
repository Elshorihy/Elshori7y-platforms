import { spawnSync } from "node:child_process";

const result = spawnSync(
  "wrangler",
  [
    "deploy",
    "--assets",
    "./dist",
    "--name",
    "elshori7y-admin",
    "--compatibility-date",
    "2026-09-15",
  ],
  { stdio: "inherit", shell: true }
);

process.exit(result.status ?? 1);
