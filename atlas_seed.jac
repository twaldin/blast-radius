"""Committed atlas seed validation, loading, identity resolution, and search."""

import json;
import re;
import from datetime { datetime }
import from hashlib { sha256 }
import from pathlib { Path }
import from urllib.parse { urlparse }
import from contracts {
    AtlasSeedRecord,
    CompanyCandidate,
    CompanyMatch,
    SeedSubprocessor
}
import from registry { VENDOR_REGISTRY }


glob SEED_FIELD_ORDER: list[str] = [
    "domain",
    "name",
    "subprocessor_url",
    "fetched_at",
    "raw_text_sha",
    "crawl_status",
    "subprocessors"
];
glob SEED_FIELDS: set[str] = set(SEED_FIELD_ORDER);
glob SUBPROCESSOR_FIELD_ORDER: list[str] = ["name", "purpose", "region"];
glob SUBPROCESSOR_FIELDS: set[str] = set(SUBPROCESSOR_FIELD_ORDER);
glob CRAWL_STATUSES: set[str] = {"ok", "unreadable", "notfound"};
glob MVP_MANIFEST_SIZE: int = 20;
glob MANDATORY_MVP_DOMAINS: set[str] = {
    "openai.com",
    "anthropic.com",
    "openrouter.ai",
    "github.com",
    "stripe.com",
    "datadoghq.com",
    "vercel.com",
    "sentry.io",
    "lindy.ai"
};
glob COMPANY_SUFFIXES: set[str] = {
    "inc", "incorporated", "llc", "ltd", "limited", "gmbh", "plc",
    "corp", "corporation", "company", "co", "pbc", "sarl"
};
glob PROVIDER_DOMAINS: dict[str, str] = {
    "amazon web services": "amazon.com",
    "amazon web services emea": "amazon.com",
    "aws": "amazon.com",
    "aws bedrock": "amazon.com",
    "amazon bedrock": "amazon.com",
    "cloudfront": "amazon.com",
    "google": "google.com",
    "google cloud": "google.com",
    "google cloud platform": "google.com",
    "microsoft": "microsoft.com",
    "microsoft azure": "microsoft.com",
    "cloudflare": "cloudflare.com",
    "fastly": "fastly.com",
    "akamai": "akamai.com",
    "twilio": "twilio.com",
    "sendgrid": "sendgrid.com",
    "twilio sendgrid": "sendgrid.com",
    "segment": "segment.com",
    "twilio segment": "segment.com",
    "snowflake": "snowflake.com",
    "datadog": "datadoghq.com",
    "github": "github.com",
    "openai": "openai.com",
    "sentry": "sentry.io",
    "functional software": "sentry.io",
    "atlassian": "atlassian.com",
    "salesforce": "salesforce.com",
    "hubspot": "hubspot.com",
    "intercom": "intercom.com",
    "okta": "okta.com",
    "zoom": "zoom.com"
};
glob DOMAIN_PATTERN: re.Pattern[str] = re.compile(
    r"^(?=.{1,253}$)(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,63}$"
);


def normalize_domain(value: str) -> str {
    normalized: str = value.strip().casefold();
    if "://" in normalized {
        normalized = urlparse(normalized).hostname or "";
    } else {
        normalized = normalized.split("/", 1)[0].split(":", 1)[0];
    }
    return normalized.removeprefix("www.").rstrip(".");
}


def normalize_company_name(value: str) -> str {
    return " ".join(
        re.sub(r"[^a-z0-9]+", " ", value.casefold()).split()
    );
}


def normalize_company_identity(value: str) -> str {
    tokens: list[str] = normalize_company_name(value).split();
    while tokens and tokens[-1] in COMPANY_SUFFIXES {
        _ = tokens.pop();
    }
    return " ".join(tokens);
}


def canonical_domain_for_name(name: str) -> str {
    key: str = normalize_company_identity(name);
    if not key {
        return "";
    }
    if key in PROVIDER_DOMAINS {
        return PROVIDER_DOMAINS[key];
    }
    for entry in VENDOR_REGISTRY.values() {
        if normalize_company_identity(entry.name) == key {
            return entry.domain;
        }
    }
    return "";
}


def canonical_identity_key(name: str) -> str {
    return canonical_domain_for_name(name) or normalize_company_identity(name);
}


def _string_field(
    raw: dict[str, object],
    key: str,
    location: str,
    errors: list[str]
) -> str {
    value: object | None = raw.get(key);
    if not isinstance(value, str) {
        errors.append(f"{location}: {key} must be a string");
        return "";
    }
    return value;
}


def _parse_subprocessors(
    raw_value: object | None,
    location: str,
    errors: list[str]
) -> list[SeedSubprocessor] {
    if not isinstance(raw_value, list) {
        errors.append(f"{location}: subprocessors must be a list");
        return [];
    }
    records: list[SeedSubprocessor] = [];
    seen: set[str] = set();
    previous_key: str = "";
    for (index, raw_item) in enumerate(raw_value as list[object]) {
        item_location: str = f"{location}:subprocessors[{index}]";
        if not isinstance(raw_item, dict) {
            errors.append(f"{item_location}: value must be an object");
            continue;
        }
        raw = raw_item as dict[str, object];
        fields: list[str] = list(raw.keys());
        if fields != SUBPROCESSOR_FIELD_ORDER {
            errors.append(
                f"{item_location}: fields must be {SUBPROCESSOR_FIELD_ORDER}"
            );
            continue;
        }
        name: str = _string_field(raw, "name", item_location, errors).strip();
        purpose: str = _string_field(raw, "purpose", item_location, errors).strip();
        region: str = _string_field(raw, "region", item_location, errors).strip();
        name_key: str = normalize_company_name(name);
        identity_key: str = canonical_identity_key(name);
        if not name_key {
            errors.append(f"{item_location}: name cannot be empty");
            continue;
        }
        if identity_key in seen {
            errors.append(f"{item_location}: duplicate company identity {name}");
            continue;
        }
        if previous_key and name_key < previous_key {
            errors.append(f"{location}: subprocessors must be name-sorted");
        }
        seen.add(identity_key);
        previous_key = name_key;
        records.append(
            SeedSubprocessor(
                name=name,
                purpose=purpose,
                region=region
            )
        );
    }
    return records;
}


def parse_seed_file(
    path: Path,
    raw_dir: Path = Path("seed/raw")
) -> tuple[AtlasSeedRecord | None, list[str]] {
    errors: list[str] = [];
    location: str = str(path);
    try {
        raw_value = json.loads(path.read_text()) as object;
    } except (OSError, json.JSONDecodeError) as exc {
        return (None, [f"{location}: cannot read valid JSON: {str(exc)}"]);
    }
    if not isinstance(raw_value, dict) {
        return (None, [f"{location}: top-level value must be an object"]);
    }
    raw = raw_value as dict[str, object];
    fields: set[str] = set(raw.keys());
    missing_fields: set[str] = SEED_FIELDS - fields;
    extra_fields: set[str] = fields - SEED_FIELDS;
    if missing_fields {
        errors.append(
            f"{location}: missing fields {sorted(missing_fields)}"
        );
    }
    if extra_fields {
        errors.append(
            f"{location}: unexpected fields {sorted(extra_fields)}"
        );
    }
    domain: str = _string_field(raw, "domain", location, errors).strip();
    name: str = _string_field(raw, "name", location, errors).strip();
    source_url: str = _string_field(
        raw, "subprocessor_url", location, errors
    ).strip();
    fetched_at: str = _string_field(raw, "fetched_at", location, errors).strip();
    raw_text_sha: str = _string_field(
        raw, "raw_text_sha", location, errors
    ).strip();
    status: str = _string_field(raw, "crawl_status", location, errors).strip();
    subprocessors: list[SeedSubprocessor] = _parse_subprocessors(
        raw.get("subprocessors"), location, errors
    );

    normalized_domain: str = normalize_domain(domain);
    if normalized_domain != domain or not DOMAIN_PATTERN.fullmatch(domain) {
        errors.append(f"{location}: domain must be normalized: {domain}");
    }
    if path.stem != domain {
        errors.append(f"{location}: filename must match domain");
    }
    if not name {
        errors.append(f"{location}: name cannot be empty");
    }
    owner_key: str = normalize_company_identity(name);
    for subprocessor in subprocessors {
        subprocessor_key: str = normalize_company_identity(subprocessor.name);
        if (
            subprocessor_key == owner_key
            or subprocessor_key.startswith(owner_key + " ")
        ) {
            errors.append(
                f"{location}: company-owned entity cannot be a subprocessor: "
                + subprocessor.name
            );
        }
    }
    if status not in CRAWL_STATUSES {
        errors.append(f"{location}: unsupported crawl_status {status}");
    }
    if fetched_at {
        try {
            observed_at = datetime.fromisoformat(
                fetched_at.replace("Z", "+00:00")
            );
            if observed_at.tzinfo is None {
                errors.append(f"{location}: fetched_at needs a timezone");
            }
        } except ValueError {
            errors.append(f"{location}: fetched_at must be ISO-8601");
        }
    } else {
        errors.append(f"{location}: fetched_at cannot be empty");
    }

    parsed_source = urlparse(source_url);
    if parsed_source.scheme != "https" or not parsed_source.hostname {
        errors.append(f"{location}: subprocessor_url must be HTTPS");
    }
    registry_entry = VENDOR_REGISTRY.get(domain);
    if registry_entry is not None and (
        registry_entry.subprocessor_url.rstrip("/")
        != source_url.rstrip("/")
    ) {
        errors.append(
            f"{location}: subprocessor_url differs from registry source"
        );
    }

    fixture_path: Path = raw_dir / f"{domain}.txt";
    fixture_exists: bool = fixture_path.exists();
    fixture_sha: str = "";
    if fixture_exists {
        fixture: bytes = fixture_path.read_bytes();
        fixture_sha = sha256(fixture).hexdigest();
        if not fixture.strip() {
            errors.append(f"{location}: fixture cannot be empty");
        }
    }
    if status == "ok" {
        if not subprocessors {
            errors.append(f"{location}: ok seed needs subprocessors");
        }
        if not fixture_exists {
            errors.append(f"{location}: ok seed needs a raw fixture");
        }
        if not re.fullmatch(r"[0-9a-f]{64}", raw_text_sha) {
            errors.append(f"{location}: raw_text_sha must be lowercase SHA-256");
        } elif raw_text_sha != fixture_sha {
            errors.append(f"{location}: raw_text_sha does not match fixture");
        }
    } else {
        if subprocessors {
            errors.append(f"{location}: failure seed must not contain subprocessors");
        }
        if fixture_exists {
            if not re.fullmatch(r"[0-9a-f]{64}", raw_text_sha) {
                errors.append(
                    f"{location}: fixture-backed failure needs lowercase SHA-256"
                );
            } elif raw_text_sha != fixture_sha {
                errors.append(f"{location}: raw_text_sha does not match fixture");
            }
        } elif raw_text_sha {
            errors.append(f"{location}: raw_text_sha has no matching fixture");
        }
    }

    if errors {
        return (None, errors);
    }
    return (
        AtlasSeedRecord(
            domain=domain,
            name=name,
            subprocessor_url=source_url,
            fetched_at=fetched_at,
            raw_text_sha=raw_text_sha,
            crawl_status=status,
            subprocessors=subprocessors
        ),
        []
    );
}


def load_manifest(
    path: Path = Path("seed/atlas-manifest.json")
) -> tuple[list[str], list[str]] {
    location: str = str(path);
    try {
        raw_value = json.loads(path.read_text()) as object;
    } except (OSError, json.JSONDecodeError) as exc {
        return ([], [f"{location}: cannot read valid JSON: {str(exc)}"]);
    }
    if not isinstance(raw_value, list) {
        return ([], [f"{location}: manifest must be a JSON array"]);
    }
    domains: list[str] = [];
    errors: list[str] = [];
    seen: set[str] = set();
    for (index, raw_domain) in enumerate(raw_value as list[object]) {
        if not isinstance(raw_domain, str) {
            errors.append(f"{location}[{index}]: domain must be a string");
            continue;
        }
        domain: str = raw_domain.strip();
        if normalize_domain(domain) != domain or not DOMAIN_PATTERN.fullmatch(domain) {
            errors.append(f"{location}[{index}]: domain must be normalized");
            continue;
        }
        if domain in seen {
            errors.append(f"{location}[{index}]: duplicate domain {domain}");
            continue;
        }
        seen.add(domain);
        domains.append(domain);
    }
    if domains != sorted(domains) {
        errors.append(f"{location}: domains must be sorted");
    }
    if len(domains) != MVP_MANIFEST_SIZE {
        errors.append(
            f"{location}: expected {MVP_MANIFEST_SIZE} domains, got {len(domains)}"
        );
    }
    missing_mandatory: list[str] = sorted(
        MANDATORY_MVP_DOMAINS - set(domains)
    );
    if missing_mandatory {
        errors.append(
            f"{location}: missing mandatory domains {missing_mandatory}"
        );
    }
    return (domains, errors);
}


def load_seed_directory(
    seed_dir: Path = Path("seed/atlas"),
    raw_dir: Path = Path("seed/raw"),
    manifest_path: Path | None = Path("seed/atlas-manifest.json")
) -> tuple[list[AtlasSeedRecord], list[str]] {
    seeds: list[AtlasSeedRecord] = [];
    errors: list[str] = [];
    if not seed_dir.exists() {
        return ([], [f"{seed_dir}: directory does not exist"]);
    }
    for path in sorted(list(seed_dir.glob("*.json"))) {
        (record, file_errors) = parse_seed_file(path, raw_dir);
        errors.extend(file_errors);
        if record is not None {
            seeds.append(record);
        }
    }
    if not seeds and not errors {
        errors.append(f"{seed_dir}: no seed JSON files found");
    }
    if manifest_path is not None {
        (manifest, manifest_errors) = load_manifest(manifest_path);
        errors.extend(manifest_errors);
        expected: set[str] = set(manifest);
        actual: set[str] = {seed.domain for seed in seeds};
        missing: list[str] = sorted(expected - actual);
        unexpected: list[str] = sorted(actual - expected);
        if missing {
            errors.append(f"{seed_dir}: missing manifest seeds {missing}");
        }
        if unexpected {
            errors.append(f"{seed_dir}: unexpected seeds {unexpected}");
        }
    }
    return (seeds, errors);
}


def normalize_search_query(value: str) -> str {
    return " ".join(value.casefold().strip().split());
}


def compact_search_value(value: str) -> str {
    return re.sub(r"[^a-z0-9]+", "", value.casefold());
}


def _token_prefix_match(query: str, candidate: str) -> bool {
    query_tokens: list[str] = query.split();
    candidate_tokens: list[str] = candidate.split();
    return bool(query_tokens) and all(
        any(token.startswith(query_token) for token in candidate_tokens)
        for query_token in query_tokens
    );
}


def _candidate_score(query: str, candidate: CompanyCandidate) -> float {
    normalized_query: str = normalize_search_query(query);
    if not normalized_query {
        return -1.0;
    }
    domain_query: str = normalize_domain(normalized_query);
    name_query: str = normalize_company_name(normalized_query);
    domain: str = normalize_domain(candidate.domain);
    name: str = normalize_company_name(candidate.name);
    compact_query: str = compact_search_value(normalized_query);
    compact_name: str = compact_search_value(candidate.name);
    if domain_query == domain {
        return 100.0;
    }
    if name_query == name {
        return 95.0;
    }
    if compact_query and compact_query == compact_name {
        return 92.0;
    }
    if domain_query and domain.startswith(domain_query) {
        return 85.0;
    }
    if name_query and name.startswith(name_query) {
        return 80.0;
    }
    if len(compact_query) >= 2 and compact_name.startswith(compact_query) {
        return 78.0;
    }
    if _token_prefix_match(name_query, name) {
        return 65.0;
    }
    if len(domain_query) >= 2 and domain_query in domain {
        return 50.0;
    }
    if len(name_query) >= 2 and name_query in name {
        return 45.0;
    }
    return -1.0;
}


def _match_sort_key(item: CompanyMatch) -> tuple[float, str, str] {
    return (-item.score, normalize_company_name(item.name), item.domain);
}


def rank_company_matches(
    query: str,
    candidates: list[CompanyCandidate],
    limit: int = 8
) -> list[CompanyMatch] {
    if not normalize_search_query(query) or limit <= 0 {
        return [];
    }
    selected: dict[str, CompanyCandidate] = {};
    for candidate in candidates {
        domain: str = normalize_domain(candidate.domain);
        if not domain {
            continue;
        }
        current: CompanyCandidate | None = selected.get(domain);
        if (
            current is None
            or (candidate.mapped and not current.mapped)
            or (
                candidate.mapped == current.mapped
                and (
                    normalize_company_name(candidate.name),
                    candidate.source_url,
                    candidate.crawl_status
                ) < (
                    normalize_company_name(current.name),
                    current.source_url,
                    current.crawl_status
                )
            )
        ) {
            selected[domain] = CompanyCandidate(
                domain=domain,
                name=candidate.name,
                source_url=candidate.source_url,
                crawl_status=candidate.crawl_status,
                mapped=candidate.mapped
            );
        }
    }
    matches: list[CompanyMatch] = [];
    for domain in sorted(selected.keys()) {
        candidate: CompanyCandidate = selected[domain];
        score: float = _candidate_score(query, candidate);
        if score < 0.0 {
            continue;
        }
        matches.append(
            CompanyMatch(
                domain=domain,
                name=candidate.name,
                source_url=candidate.source_url,
                crawl_status=candidate.crawl_status,
                mapped=candidate.mapped,
                score=score
            )
        );
    }
    matches.sort(key=_match_sort_key);
    return matches[:limit];
}


def registry_candidates(
    mapped_domains: set[str] | None = None
) -> list[CompanyCandidate] {
    normalized_mapped: set[str] = {
        normalize_domain(domain) for domain in (mapped_domains or set())
    };
    return [
        CompanyCandidate(
            domain=entry.domain,
            name=entry.name,
            source_url=entry.subprocessor_url,
            crawl_status="ok" if entry.domain in normalized_mapped else "pending",
            mapped=entry.domain in normalized_mapped
        )
        for entry in VENDOR_REGISTRY.values()
    ];
}
