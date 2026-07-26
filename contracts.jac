"""Shared value contracts across extraction, seeding, graph import, and search."""

obj DetectedVendor {
    has domain: str;
    has name: str;
    has method: str = "";      # dns | headers | scripts | manual
}

obj SubprocessorRecord {
    has name: str;
    has purpose: str = "";
    has hosting_region: str = "";
}
sem SubprocessorRecord.name = "The third-party processor's published legal or brand name.";
sem SubprocessorRecord.purpose = "The processing purpose stated in the filing, or an empty string when absent.";
sem SubprocessorRecord.hosting_region = "The processing or hosting region stated in the filing, or an empty string when absent.";

obj ResolvedSubprocessor {
    has canonical_name: str;
    has canonical_domain: str = "";
    has purpose: str = "";
    has region: str = "";
    has confidence: float = 1.0;
}

obj SeedSubprocessor {
    has name: str;
    has purpose: str = "";
    has region: str = "";
}

obj AtlasSeedRecord {
    has domain: str;
    has name: str;
    has subprocessor_url: str;
    has fetched_at: str;
    has raw_text_sha: str;
    has crawl_status: str;
    has subprocessors: list[SeedSubprocessor] = [];
}

obj CompanyCandidate {
    has domain: str;
    has name: str;
    has source_url: str = "";
    has crawl_status: str = "pending";
    has mapped: bool = False;
}

obj CompanyMatch {
    has domain: str;
    has name: str;
    has source_url: str = "";
    has crawl_status: str = "pending";
    has mapped: bool = False;
    has score: float = 0.0;
}

obj ProviderEvidence {
    has domain: str;
    has name: str;
    has soc2_status: str = "";
    has soc2_source_url: str = "";
    has downtime_hours: float | None = None;
    has downtime_period_start: str = "";
    has downtime_period_end: str = "";
    has downtime_source_urls: list[str] = [];
    has observed_at: str = "";
}

obj RiskHeadline {
    has biggest_risk: str;
    has biggest_suggestion: str;
}
