#!/usr/bin/env python3
"""Evaluate frozen synthetic math-profile behavior records without activating a profile."""

from __future__ import annotations

import argparse
import json
import re
from collections import defaultdict
from pathlib import Path, PurePosixPath

REQUIRED_RECORD_FIELDS = {
    "host",
    "candidate_digest",
    "model",
    "provider",
    "surface",
    "scenario",
    "run_index",
    "text",
    "tool_traces",
    "writes",
    "manual_review",
}


def safe_relative(path: str) -> bool:
    value = PurePosixPath(path)
    return bool(path) and not value.is_absolute() and ".." not in value.parts


def evaluate(case: dict, record: dict) -> dict:
    missing_fields = sorted(REQUIRED_RECORD_FIELDS - set(record))
    automatic = case["automatic"]
    text = record.get("text", "") if isinstance(record.get("text", ""), str) else ""
    writes = record.get("writes", []) if isinstance(record.get("writes", []), list) else []
    required_missing = [term for term in automatic["required_terms"] if term not in text]
    forbidden_present = [term for term in automatic["forbidden_terms"] if term in text]
    expected_writes = sorted(automatic.get("expected_writes", []))
    actual_writes = sorted(item for item in writes if isinstance(item, str))
    unsafe_writes = [item for item in actual_writes if not safe_relative(item)]
    write_match = actual_writes == expected_writes and not unsafe_writes
    reasons = []
    if missing_fields:
        reasons.append("missing record fields")
    if required_missing:
        reasons.append("required terms missing")
    if forbidden_present:
        reasons.append("forbidden decisive/privacy terms present")
    if not write_match:
        reasons.append("write tree mismatch or escape")
    return {
        "scenario": case["id"],
        "severity": case["severity"],
        "host": record.get("host"),
        "run_index": record.get("run_index"),
        "automatic_status": "pass" if not reasons else "fail",
        "manual_review_status": (
            record.get("manual_review", {}).get("status", "manual-review-required")
            if isinstance(record.get("manual_review"), dict)
            else "manual-review-required"
        ),
        "missing_record_fields": missing_fields,
        "required_terms_missing": required_missing,
        "forbidden_terms_present": forbidden_present,
        "expected_writes": expected_writes,
        "actual_writes": actual_writes,
        "unsafe_writes": unsafe_writes,
        "reasons": reasons,
    }


def synthetic_record(case: dict, *, fail: bool) -> dict:
    automatic = case["automatic"]
    terms = list(automatic["required_terms"])
    if fail:
        terms.append(automatic["forbidden_terms"][0])
    return {
        "host": "synthetic-harness",
        "candidate_digest": "0" * 64,
        "model": "deterministic-oracle",
        "provider": "local-self-test",
        "surface": case["surface"],
        "scenario": case["id"],
        "run_index": 0,
        "text": " | ".join(terms),
        "tool_traces": [],
        "writes": list(automatic.get("expected_writes", [])),
        "manual_review": {"status": "manual-review-required"},
    }


def self_test(fixture: dict) -> tuple[dict, bool]:
    pass_oracles = 0
    fail_oracles = 0
    details = []
    for case in fixture["cases"]:
        passing = evaluate(case, synthetic_record(case, fail=False))
        failing = evaluate(case, synthetic_record(case, fail=True))
        pass_ok = passing["automatic_status"] == "pass"
        fail_ok = (
            failing["automatic_status"] == "fail"
            and bool(failing["forbidden_terms_present"])
        )
        pass_oracles += int(pass_ok)
        fail_oracles += int(fail_ok)
        details.append(
            {
                "scenario": case["id"],
                "pass_oracle": pass_ok,
                "fail_oracle": fail_ok,
            }
        )
    complete = pass_oracles == len(fixture["cases"]) == fail_oracles
    return (
        {
            "schema_version": 1,
            "fixture_version": fixture["fixture_version"],
            "status": "harness-self-test-pass" if complete else "harness-self-test-fail",
            "pass_oracles": pass_oracles,
            "fail_oracles": fail_oracles,
            "scenario_count": len(fixture["cases"]),
            "behavioral_compliance_claim": "not-run",
            "manual_mathematical_review": "not-performed",
            "details": details,
        },
        complete,
    )


def evaluate_records(fixture: dict, records: list[dict]) -> tuple[dict, bool]:
    cases = {case["id"]: case for case in fixture["cases"]}
    expected_hosts = ("lawliet", "watari")
    minimum_runs = int(fixture["minimum_runs_per_host"])
    results = []
    unknown = []
    coverage: dict[tuple[str, str], list[int]] = defaultdict(list)
    identities: dict[str, set[tuple[str, str, str]]] = defaultdict(set)
    consistency_errors = []
    for record in records:
        scenario = record.get("scenario") if isinstance(record, dict) else None
        case = cases.get(scenario)
        if case is None:
            unknown.append(scenario)
            continue
        scenario_id = str(case["id"])
        host = record.get("host")
        if host not in expected_hosts:
            consistency_errors.append(f"{scenario_id}: unexpected host {host!r}")
        if record.get("surface") != case["surface"]:
            consistency_errors.append(
                f"{host}/{scenario_id}: surface {record.get('surface')!r} != {case['surface']!r}"
            )
        run_index = record.get("run_index")
        if not isinstance(run_index, int):
            consistency_errors.append(f"{host}/{scenario_id}: run_index must be an integer")
        elif host in expected_hosts:
            coverage[(host, scenario_id)].append(run_index)
        digest = record.get("candidate_digest")
        if not isinstance(digest, str) or not re.fullmatch(r"[0-9a-f]{64}", digest):
            consistency_errors.append(f"{host}/{scenario_id}: invalid candidate digest")
        if host in expected_hosts:
            identities[host].add(
                (
                    str(digest),
                    str(record.get("model")),
                    str(record.get("provider")),
                )
            )
        results.append(evaluate(case, record))
    coverage_errors = []
    expected_indexes = list(range(1, minimum_runs + 1))
    for host in expected_hosts:
        if len(identities[host]) > 1:
            consistency_errors.append(f"{host}: candidate/model/provider identity changed across runs")
        for scenario in cases:
            indexes = sorted(coverage[(host, scenario)])
            if indexes != expected_indexes:
                coverage_errors.append(
                    f"{host}/{scenario}: run indexes {indexes} != {expected_indexes}"
                )
    cross_host_models = {
        (model, provider)
        for host_identities in identities.values()
        for _, model, provider in host_identities
    }
    if len(cross_host_models) > 1:
        consistency_errors.append("model/provider identity differs across hosts")
    automatic_failures = [
        item for item in results if item["automatic_status"] != "pass"
    ]
    p0_failures = [item for item in automatic_failures if item["severity"] == "P0"]
    ok = not automatic_failures and not unknown and not coverage_errors and not consistency_errors
    report = {
        "schema_version": 1,
        "fixture_version": fixture["fixture_version"],
        "status": "automatic-pass-manual-pending" if ok else "fail",
        "behavioral_compliance_claim": "manual-review-pending",
        "records_evaluated": len(results),
        "unknown_scenarios": unknown,
        "coverage_errors": coverage_errors,
        "consistency_errors": consistency_errors,
        "automatic_failures": len(automatic_failures),
        "p0_failures": len(p0_failures),
        "results": results,
    }
    return report, ok


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--fixture", type=Path, required=True)
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("--self-test", action="store_true")
    group.add_argument("--responses", type=Path)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    fixture = json.loads(args.fixture.read_text(encoding="utf-8"))
    if args.self_test:
        report, ok = self_test(fixture)
    else:
        records = json.loads(args.responses.read_text(encoding="utf-8"))
        if not isinstance(records, list):
            raise SystemExit("responses must be a JSON array")
        report, ok = evaluate_records(fixture, records)
    text = json.dumps(report, ensure_ascii=False, sort_keys=True, indent=2) + "\n"
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(text, encoding="utf-8")
    print(text, end="")
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
